/**
	HTTP/2 implementation
	Copyright: © 2015 RejectedSoftware e.K., GlobecSys Inc
	Authors: Sönke Ludwig, Etienne Cimon
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.http.internal.http2;

import vibe.core.core;
import vibe.core.stream;
import vibe.core.driver;
import vibe.utils.memory;
import vibe.utils.dictionarylist;
import vibe.inet.message;
import vibe.inet.url;
import vibe.http.status;
import vibe.http.common;
import vibe.utils.array;
import vibe.stream.memory;
import vibe.stream.wrapper;
//import vibe.core.log;

import libhttp2.types;
import libhttp2.connector;
import libhttp2.session;
import libhttp2.buffers;
import libhttp2.frame;
import libhttp2.constants;
import libhttp2.helpers;

import memutils.circularbuffer;
import memutils.vector;
import memutils.utils;

import std.base64;
import std.datetime;
import std.conv : to;
import std.exception;
import std.format;

alias B64 = Base64Impl!('-', '_', Base64.NoPadding);

alias HTTP2RequestHandler = void delegate(HTTP2Stream stream);


struct PingData
{
	long sent;
	SysTime* recv;
	ManualEvent cb;
}


/// If TLS is used in the underlying connection, this value is set to LockMemory, however
/// it will be reset to None on the first read attempt if the user does not 
/// call HTTP2Stream.MemoryLevel with a value different than None before reading data.
enum SafetyLevel {
	// Let the memory pool hold the data until it is overwritten by other chunks (fastest, insecure)
	None,
	// Zeroize the data after it is moved in read operations (slower, safer)
	ZeroizeBuffers,
	// Attempts to lock buffers to virtual memory, avoiding a dump to disk. (slowest, safest)
	LockMemory
}

final class HTTP2Stream : ConnectionStream
{
	@property bool isOpener() const { return m_opener; }
	@property bool headersWritten() const { return m_headersWritten; }
	private {
		// state
		int m_stream_id = -1; // -1 if fresh client request. >0 and always defined on server streams
		@property int streamId() { return m_stream_id; }

		HTTP2Session m_session;
		bool m_opener; // used to determine if we should close the session and redirect
		bool m_connected;
		bool m_active; // iff the headers were all received

		bool m_paused; // the session r/w loops will pause, but may or may not be paused because of this stream
		bool m_unpaused;

		bool m_headersWritten;
		bool m_push; // this stream was initialized as a push promise. This is a push response
		bool m_safety_level_changed;
		int m_maxFrameSize; // The buffers also allocate their additional storage at these intervals

		PrioritySpec m_priSpec;
		SafetyLevel m_safety_level;
		ubyte m_priority = 0;

		// i/o operations
		Incoming m_rx;
		Outgoing m_tx;

		string toString() {
			import std.array;
			Appender!string app;
			app ~= "Session is server: " ~ m_session.isServer.to!string ~ "\n";
			app ~= "Connected session: " ~ m_session.connected.to!string ~ "\n";
			app ~= "Connected stream: " ~ m_connected.to!string ~ "\n";
			app ~= "Stream ID: " ~ m_stream_id.to!string ~ "\n";
			app ~= "Active: " ~ m_active.to!string ~ "\n";
			app ~= "Paused: " ~ m_paused.to!string ~ "\n";
			app ~= "Push: " ~ m_push.to!string ~ "\n";
			app ~= "SafetyLevelChanged: " ~ m_safety_level_changed.to!string ~ "\n";
			app ~= "maxFrameSize: " ~ m_maxFrameSize.to!string ~ "\n";
			app ~= "priSpec: " ~ m_priSpec.to!string ~ "\n";
			app ~= "SafetyLevel: " ~ m_safety_level.to!string ~ "\n\n";

			app ~= m_rx.toString();
			app ~= "\n\n";
			app ~= m_tx.toString();

			return app.data;
		}

		struct Incoming {
			Buffers bufs;
			Task owner;
			ManualEvent signal;
			bool dataSignalRaised;
			bool waitingData;
			bool waitingHeaders;
			bool waitingStreamExit;
			bool close;
			PrioritySpec prispec;
			FrameError error;
			Exception ex;
			Vector!HeaderField headers;

			void free() {
				if (bufs) {
					bufs.free();
					Mem.free(bufs);
				}

				if (!headers.empty) { // for inbound headers, we had to allocate...
					foreach(HeaderField hf; headers[])
						hf.free();
					headers.clear();
				}
				//if (signal) destroy(signal);
			}

			void notifyData() { if (waitingData && !dataSignalRaised) { dataSignalRaised=true; signal.emit(); } }
			void notifyHeaders() { if (waitingHeaders && !dataSignalRaised) { dataSignalRaised=true; signal.emit(); } }

			void notifyAll() {
				if (waitingData || waitingHeaders || waitingStreamExit)
				{
					if (!dataSignalRaised)
					{
						dataSignalRaised = true;
						signal.emit();
					}
				}
			}

			string toString() {
				import std.array;
				Appender!string app;
				app ~= "Incoming: \n";
				app ~= "Buffered: " ~ bufs.length.to!string ~ "\n";
				app ~= "dataSignalRaised: " ~ dataSignalRaised.to!string ~ "\n";
				app ~= "waitingData: " ~ waitingData.to!string ~ "\n";
				app ~= "waitingHeaders: " ~ waitingHeaders.to!string  ~ "\n";
				app ~= "waitingStreamExit: " ~ waitingStreamExit.to!string ~ "\n";
				app ~= "close: " ~ close.to!string ~ "\n";
				app ~= "prispec: " ~ prispec.to!string ~ "\n";
				app ~= "error: " ~ error.to!string ~ "\n";
				app ~= "ex: " ~ (ex?ex.to!string:"") ~ "\n";
				app ~= "Headers: " ~ headers[].to!string ~ "\n";
				return app.data;
			}
		}

		struct Outgoing {
			Buffers bufs;
			int queued;
			int queued_len;
			Task owner;
			ManualEvent signal;
			bool waitingData;
			bool dataSignalRaised;
			bool dirty;
			bool halfClosed; // On finalize(), the application must be finished with the request/response. submitRequest or submitResponse can then be used on this stream.
			bool deferred;
			bool finalized;
			bool close;
			FrameError error;

			PrioritySpec priSpec;

			uint windowUpdate;
			uint windowUpdatePaused;

			HeaderField[] headers;

			
			string toString() {
				import std.array;
				Appender!string app;
				app ~= "Outgoing: \n";
				app ~= "Buffered: " ~ bufs.length.to!string ~ "\n";
				app ~= "queued: " ~ queued.to!string ~ "\n";
				app ~= "queued_len: " ~ queued_len.to!string ~ "\n";
				app ~= "waitingData: " ~ waitingData.to!string ~ "\n";
				app ~= "dataSignalRaised: " ~ dataSignalRaised.to!string ~ "\n";
				app ~= "dirty: " ~ dirty.to!string ~ "\n";
				app ~= "halfClosed: " ~ halfClosed.to!string  ~ "\n";
				app ~= "close: " ~ close.to!string ~ "\n";
				app ~= "error: " ~ error.to!string ~ "\n";
				app ~= "prispec: " ~ priSpec.to!string ~ "\n";
				app ~= "windowUpdate: " ~ windowUpdate.to!string ~ "\n";
				app ~= "windowUpdatePaused: " ~ windowUpdatePaused.to!string ~ "\n";
				app ~= "Headers: " ~ headers.to!string ~ "\n";
				return app.data;
			}

			void free() {
				if (bufs) {
					bufs.free();
					Mem.free(bufs);
					bufs = null;
				}
				freeHeaders();
				//if (signal) destroy(signal);
				dirty = false;
			}

			void freeHeaders() {
				import vibe.utils.dictionarylist : icmp2;
				if (headers) { // When the headers are outbound, strings are references only except cookies
					foreach (HeaderField hf; headers) {
						if (icmp2(hf.name, "Cookie") == 0) Mem.free(hf.value);
						if (hf.name == ":status") Mem.free(hf.value);
						if (icmp2(hf.name, "Set-Cookie") == 0) Mem.free(hf.value);
						if (icmp2(hf.name, "HTTP2-Settings") == 0) Mem.free(hf.value);
					}
					Mem.free(headers);
				}
			}

			void notify() {
				if (!dataSignalRaised && waitingData)
				{
					dataSignalRaised = true;
					signal.emit();
				}
			}
		}

		@property void streamId(int stream_id) {
			if (stream_id == 1) m_opener = true;
			int old_stream_id = m_stream_id;
			m_stream_id = stream_id;

			if (stream_id > 0) 
				m_session.m_totConnected++;
			else if (old_stream_id > 0 && stream_id <= 0) {
				m_session.m_totConnected--;
				// schedule a pending (dirty) stream initialization
				if (!m_session.m_closing && !m_session.m_tx.pending.empty) {
					m_session.m_tx.dirty ~= m_session.m_tx.pending.front();
					m_session.m_tx.pending.popFront();
					m_session.m_tx.notify();
				}
				// Check if the session was closing, waiting for this stream to stop.
				if (m_session.m_closing && m_session.m_totConnected <= 0)
					m_session.m_tx.notify();
			}
		}
	}

	/// Get the last error. For push it will be FramError.CANCEL if the remote end hasn't enabled it.
	@property FrameError error() { return m_rx.error; }

	package void initialize(HTTP2Session sess)
	{
		m_session = sess;
		if (!m_session.isServer)
			m_connected = true;
		allocateBuffers(m_session.m_defaultChunkSize);
	}

	this() {
		m_rx.signal = getEventDriver.createManualEvent();
		m_tx.signal = getEventDriver.createManualEvent();
	}

	this(HTTP2Session sess, int stream_id, int chunk_size = 16*1024, bool push = false)
	in { assert(sess !is null && stream_id != 0); }
	body {
		logDebug("Stream ctor");
		m_session = sess;
		m_rx.signal = getEventDriver.createManualEvent();
		m_tx.signal = getEventDriver.createManualEvent();

		assert(m_session.m_tcpConn);
		streamId = stream_id;
		if (!m_session.isServer)
			m_connected = true;

		allocateBuffers(chunk_size);
	}

	~this()
	{
		onClose();
		m_rx.free();
	}

	/// Set the memory safety to > None to secure memory operations for the active stream.
	/// This may be important if you wish to add a layer of security for sensitive 
	/// data (password or private information) to counter possible memory attacks.
	/// 
	/// Note: Higher safety levels may slow down the application quite a bit.
	/// The buffers will not adapt to new safety levels while they contain data.
	@property void memorySafety(SafetyLevel sl) { 
		m_safety_level = sl; 
		m_safety_level_changed = true;
	}

	/// Read client request headers into supplied structures. The session must be opened as a server
	void readHeader(out string schema, out string host, out ushort port, out string path, out HTTPMethod method, out InetHeaderMap header, Allocator alloc = defaultAllocator())
	in { assert(m_session.isServer); }
	body
	{
		import vibe.utils.dictionarylist : icmp2;
		acquireReader();
		scope(exit) releaseReader();

		while (!m_active)
		{
			m_rx.waitingHeaders = true;
			m_rx.dataSignalRaised = false;
			m_rx.signal.wait();
			m_rx.dataSignalRaised = false;
			m_rx.waitingHeaders = false;
			processExceptions();
		}
		
		assert(m_active, "Stream is not active, but headers were received.");
		import vibe.utils.memory : allocArray;

		foreach (HeaderField hf; m_rx.headers) {
			if (hf.name == ":path") 
				path = hf.value;
			else if (hf.name == ":scheme")
				schema = hf.value;
			else if (hf.name == ":method")
				method = httpMethodFromString(hf.value);
			else if ((icmp2(hf.name, "host") == 0 && !host) || hf.name == ":authority") {
				import std.algorithm : countUntil;
				int idx = cast(int)hf.value.countUntil(":");
				if (idx == -1)
					host = hf.value;
				else {
					import std.conv : parse;
					host = hf.value[0 .. idx];
					auto chunk = hf.value[idx + 1 .. $];
					port = to!ushort(chunk);
				}
				header.addField("Host", hf.value);
			}
			else
				header.addField(hf.name, hf.value);
		}
		


	}

	/// Read server response headers into supplied structures. The session must be opened as a client
	void readHeader(out int status_code, out InetHeaderMap header, Allocator alloc = defaultAllocator())
	in { assert(!m_session.isServer); }
	body {
		acquireReader();
		scope(exit) releaseReader();

		while (!m_active)
		{
			m_rx.waitingHeaders = true;
			logDebug("Waiting for response headers");
			m_rx.dataSignalRaised = false;
			m_rx.signal.wait();
			m_rx.dataSignalRaised = false;
			m_rx.waitingHeaders = false;
			processExceptions();
		}
		assert(m_active, "Stream is not active, but headers were received.");
		import vibe.utils.memory : allocArray;

		foreach (HeaderField hf; m_rx.headers) {
			import std.conv : parse;
			if (hf.name == ":status")
				status_code = hf.value.parse!int;
			else if (hf.name == ":authority")
				header.addField("Host", hf.value);
			else
				header.addField(hf.name, hf.value);
		}


	}

	/// Queue server response headers, sent when responding to a client. The session must be opened as a server.
	void writeHeader(in HTTPStatus status, const ref InetHeaderMap header, ref Cookie[string] cookies)
	in { assert(m_session.isServer); }
	body {
		import vibe.utils.dictionarylist : icmp2;
		acquireWriter();
		scope(exit) releaseWriter();
		scope(success) m_headersWritten = true;
		int len = cast(int)( 1 /*:status*/ + header.length + cookies.length );
		HeaderField[] headers = Mem.alloc!(HeaderField[])(len);
		scope(failure) {
			foreach (hf; headers)
			{
				if (hf.name == ":status") Mem.free(hf.value);
				if (icmp2(hf.name, "Set-Cookie") == 0) Mem.free(hf.value);
			}
			Mem.free(headers);
		}
		char[] status_str = Mem.alloc!(char[])(3);
		import std.c.stdio : sprintf;
		sprintf(status_str.ptr, "%d\0", cast(int)status);
		size_t i;
		// write status code
		headers[i++] = HeaderField(":status", cast(string) status_str);

		// write headers
		foreach (string name, const ref string value; header) 
		{
			if (icmp2(name, "Host") == 0)
				headers[i++] = HeaderField(":authority", value);
			else
				headers[i++] = HeaderField(name, value);

		}

		MemoryOutputStream memstream = FreeListObjectAlloc!MemoryOutputStream.alloc(manualAllocator());
		StreamOutputRange dst = StreamOutputRange(memstream);
		scope(exit) {
			destroy(dst);
			memstream.reset(AppenderResetMode.freeData);
			FreeListObjectAlloc!MemoryOutputStream.free(memstream);
		}
		// write set-cookie headers
		foreach (name, Cookie cookie; cookies)
		{
			import vibe.utils.array : AllocAppender, AppenderResetMode;
			cookie.writeString(&dst, cast(string) name);
			dst.flush();
			char[] cookie_val = cast(char[]) Mem.copy(memstream.data);
			memstream.reset();
			headers[i++] = HeaderField("Set-Cookie", cast(string) cookie_val);
		}

		//commit
		m_tx.headers = headers;
		
		assert(len == i);
		dirty();
	}

	/// Queue client request headers, sent when requesting data from a server. The session must be opened as a client.
	void writeHeader(in string path, in string scheme, in HTTPMethod method, const ref InetHeaderMap header, in CookieStore cookie_jar, bool concatenate_cookies)
	in { assert(!m_session.isServer); }
	body {
		import vibe.utils.dictionarylist : icmp2;
		acquireWriter();
		scope(exit) releaseWriter();
		scope(success) m_headersWritten = true;

		immutable string[] methods = ["GET","HEAD","PUT","POST","PATCH","DELETE","OPTIONS","TRACE","CONNECT","COPY","LOCK","MKCOL","MOVE","PROPFIND","PROPPATCH","UNLOCK"];

		Vector!(char[]) cookie_arr;
		char[] cookie_concat;
		scope(failure) {
			foreach (char[] cookie; cookie_arr)
				Mem.free(cookie);
			if (cookie_concat)
				Mem.free(cookie_concat);
		}

		void cookieSinkIndividually(string[] cookies) {
			foreach (c; cookies) {
				char[] cookie = Mem.alloc!(char[])(c.length);
				cookie[] = cast(char[])c[];
				cookie_arr ~= cookie;
			}
		}
		void cookieSinkConcatenate(string cookies) {
			cookie_concat = Mem.alloc!(char[])(cookies.length);
			cookie_concat[] = cast(char[])cookies[];
		}

		string authority = header.get("Host", null);
		if (!authority)
			throw new Exception("Cannot write headers, Host was not present");

		if (cookie_jar) {
			if (concatenate_cookies)
				cookie_jar.get(authority, path, scheme == "https", &cookieSinkConcatenate);
			else
				cookie_jar.get(authority, path, scheme == "https", &cookieSinkIndividually);
		}
		logDebug("Cookie jar got ", cookie_arr.length, " concat: ", cookie_concat.length);
		int len = cast(int)( 2 /* :scheme :path */ + 1 /* :method */ + header.length + cookie_arr.length + (cookie_jar && cookie_concat?1:0) ) /* one per field for indexing */;
		HeaderField[] headers = Mem.alloc!(HeaderField[])(len);
		scope(failure) {
			Mem.free(headers);
		}
		size_t i;
		// write method, scheme, path pseudo-headers
		headers[i++] = HeaderField(":method", methods[method]);
		headers[i++] = HeaderField(":scheme", scheme);
		headers[i++] = HeaderField(":path", path);
		headers[i++] = HeaderField(":authority", authority);

		bool wrote_cookie;

		// write headers
		foreach (string name, const ref string value; header) 
		{
			if (icmp2(name, "Host") == 0) continue;
			if (cookie_jar && icmp2(name, "Cookie") == 0 && concatenate_cookies && value.length > 0) {
				char[] cookie_tmp = Mem.alloc!(char[])(value.length + cookie_concat.length + 2);
				cookie_tmp[0 .. value.length] = cast(char[])value[0 .. $];
				cookie_tmp[value.length .. value.length + 2] = "; ";
				cookie_tmp[value.length + 2 .. $] = cookie_concat[0 .. $];
				Mem.free(cookie_concat);
				cookie_concat = cookie_tmp;
			} else if (icmp2(name, "Cookie") == 0) {
				if (value.length > 0) {
					char[] cookie_val = Mem.alloc!(char[])(value.length);
					cookie_val[] = cast(char[]) value;
					cookie_arr ~= cookie_val;
					headers[i++] = HeaderField("Cookie", cast(string) cookie_val);	
				} else len--;
			}
			else headers[i++] = HeaderField(name, value);
		}

		// write cookies, individually by default to use indexing
		if (cookie_jar) {
			if (concatenate_cookies)
				headers[i++] = HeaderField("Cookie", cast(string) cookie_concat);
			else if (!wrote_cookie) foreach (char[] cookie; cookie_arr[])
				headers[i++] = HeaderField("Cookie", cast(string) cookie);
		}

		//commit
		m_tx.headers = headers;
		logDebug(m_tx.headers.to!string); 
		assert(len == i);

		dirty();
	}

	/// Send headers expected by a client in a request. The session must be opened as a server
	/// A stream that mimics a client request will be opened after this frame is sent
	/// Note: cookies must be in the headers already
	/// Untested.
	void pushPromise(in URL url, in HTTPMethod method, const ref InetHeaderMap header)
	in { assert(m_session.isServer); }
	body {
		acquireWriter();
		scope(exit) releaseWriter();

		HTTP2Stream stream = new HTTP2Stream;
		stream.initialize(m_session);
		stream.m_push = true;
		stream.setParent(this, false);
		// cookies must be in the headers already
		stream.writeHeader(url.localURI, url.schema, method, header, null, false); 
	}

	/// can produce multiple concurrent requests by calling it with using multiple tasks simultaneously
	Duration ping() {
		Duration latency;

		ManualEvent cb = getEventDriver().createManualEvent();
		scope(exit) destroy(cb);
		SysTime start = Clock.currTime();
		long sent = start.stdTime();
		SysTime recv;

		PingData data = PingData(sent, &recv, cb);
		logDebug("send ping data"); 
		m_session.ping(data);
		logDebug("wait");
		cb.wait();

		latency = recv - start;

		return latency;
	}

	/// Queue a priority change, a protocol bias will use this to alter the quality of this stream's connection
	void setPriority(ubyte i)
	in { assert(i != 0, "Priority cannot be zero"); }
	body
	{
		acquireWriter();
		scope(exit) releaseWriter();

		m_priority = i;
		dirty();
	}

	/// Stop transfer through this stream until unpaused. Untested.
	void pause() { m_paused = true; }
	/// Resume transfer through this stream. Untested.
	void unpaused() { m_session.get().consumeStream(streamId, m_tx.windowUpdatePaused); m_session.m_tx.notify(); m_unpaused = true; }

	/// The parent stream will not close if this stream is active, and this stream
	/// will automatically close if the parent stream dies. 
	/// This is useful to settle the lifetime of Tasks actively working together.
	/// 
	/// Params:
	///   parent = The stream that this stream depends on
	///   exclusive = true causes children of parent to depend on this stream
	void setParent(HTTP2Stream parent, bool exclusive) 
	{
		acquireWriter();
		scope(exit) releaseWriter();

		m_tx.priSpec = m_priSpec;
		m_tx.priSpec.stream_id = parent.m_stream_id;
		m_tx.priSpec.exclusive = exclusive;

		dirty();
	}

	/// Queue an increase in window size to help saturate the bandwidth.
	void increaseWindowSize(uint window_size)
	{
		acquireWriter();
		scope(exit) releaseWriter();

		m_tx.windowUpdate += window_size;
		dirty();
	}

	private @property HTTP2Session session() {		
		return m_session;
	}

	@property bool connected() const { return m_connected && m_session.get() && !m_rx.close && !m_tx.close; }
	
	@property bool dataAvailableForRead(){
		logDebug("HTTP2: data available for read");
		acquireReader();
		scope(exit) releaseReader();
		return m_rx.bufs.length > 0;
	}

	@property bool empty() { 
		return leastSize == 0; }
	
	@property ulong leastSize()
	{
		logDebug("HTTP/2: Leastsize");
		acquireReader();
		scope(exit) releaseReader();
		
		while( m_rx.bufs.length == 0 )
		{
			if (!connected)
				return 0;
			m_rx.waitingData = true;
			m_rx.dataSignalRaised = false;
			m_rx.signal.wait();
			m_rx.dataSignalRaised = false;
			m_rx.waitingData = false;
		}
		return m_rx.bufs.length;
	}

	void close(FrameError error) {
		if (m_session.isServer && m_tx.finalized) return;
		if (!m_session.connected) return;
		// This could be called by a keep-alive timer. In this case we must forcefully free the read lock
		if (m_rx.owner !is Task.init && m_rx.owner != Task.getThis())
		{
			m_rx.owner.interrupt();
			yield();
		}
		acquireReader();
		scope(exit) releaseReader();
		m_tx.halfClosed = true; // attempts an atomic response in some cases
		m_tx.close = true;
		m_tx.error = error;
		dirty();

		while (m_stream_id > 0 && !m_rx.close) {
			m_rx.waitingStreamExit = true;
			m_rx.dataSignalRaised = false;
			m_rx.signal.wait();
			m_rx.dataSignalRaised = false;
			m_rx.waitingStreamExit = false;
		}

		onClose();
	}

	void close()
	{
		close(FrameError.NO_ERROR);
	}
	
	bool waitForData(Duration timeout = 0.seconds) 
	{
		logDebug("HTTP2: wait for data");
		acquireReader();
		scope(exit) releaseReader();

		if (m_rx.bufs.length == 0) {
			checkConnected();
			assert(!m_rx.waitingData, "Another task is waiting already.");
			m_rx.waitingData = true;
			m_rx.dataSignalRaised = false;
			m_rx.signal.wait(timeout, m_rx.signal.emitCount);
			m_rx.dataSignalRaised = false;
			m_rx.waitingData = false;
		}

		if (m_rx.bufs.length == 0)
			return false; // timeout exceeded

		return true;
	}

	/// avoid allocation but provides only some of the data.
	const(ubyte)[] peekSome()
	{
		acquireReader();
		scope(exit) releaseReader();
		
		if (m_rx.bufs.length > 0) 
			return m_rx.bufs.head.buf[];
		
		return null;
	}

	// this function will allocate to peek on the entire buffers
	const(ubyte)[] peek() {

		// we must block if dst is not filled
		logDebug("HTTP/2: Peek"); 
		acquireReader();
		scope(exit) releaseReader();

		ubyte[] ub = new ubyte[](m_rx.bufs.length);
		if (m_rx.bufs.length > 0) {
			ubyte[] tmp = ub;
			with(m_rx.bufs) for(Chain ci = head; ci; ci = ci.next)
			{
				tmp[0 .. ci.buf.length] = ci.buf[];
				if (tmp.length > ci.buf.length)
					tmp = tmp[ci.buf.length .. $];
				else break;
			}
			return cast(const(ubyte)[]) ub;
		}

		return null;
	}
	
	void read(ubyte[] dst)
	{
		// we must block if dst is not filled
		logDebug("HTTP/2: Read, dst len: ", dst.length); 
		assert(dst !is null);
		acquireReader();
		scope(exit) releaseReader();
		Buffers bufs = m_rx.bufs;
		ubyte[] ub = dst;
		
		while(ub.length > 0)
		{
			ubyte[] payload = bufs.removeOne(ub);

			if (ub.length > payload.length) {
				if (m_paused)
				{
					m_session.get().consumeConnection(payload.length);
					m_tx.windowUpdatePaused += payload.length;
				}
				else if (connected) {
					m_session.get().consume(streamId, payload.length);
					m_session.m_tx.notify();
				} else if (m_session.get()) {
					m_session.get().consumeConnection(payload.length);
					break;
				}
				ub = ub[payload.length .. $];

				if (ub.length > 0 && bufs.length == 0) { // we should wait for more data...
					enforce(connected);
					m_rx.waitingData = true;
					m_rx.dataSignalRaised = false;
					logDebug("HTTP/2: Waiting for more data in read()");
					m_rx.signal.wait();
					m_rx.dataSignalRaised = false;
					m_rx.waitingData = false;
				}
			}
			else if (connected) {
				m_session.get().consume(streamId, payload.length); // notify remote of local buffer size change
				m_session.m_tx.notify();
				break;
			}
			else if (m_session.get()) {
				m_session.get().consumeConnection(payload.length);
				break;
			}

			processExceptions();
		
		}

		//logDebug("Finished reading with ", bufs.length, " bytes left in the buffers, data: ", dst);

		// we can read again
		if (m_session.m_rx.paused)
			m_session.m_rx.signal.emit();
		
	}
	
	void write(in ubyte[] src)
	{
		acquireWriter();
		scope(exit) releaseWriter();
		const(ubyte)[] ub = cast()src;

		while (ub.length > 0)
		{
			size_t to_send = min(m_tx.bufs.available, ub.length);
			ErrorCode rv = m_tx.bufs.add(cast(string) ub[0 .. to_send]);
			enforce(rv >= 0, "Error adding data to buffer");
			if (to_send == ub.length) break;
			ub = ub[to_send .. $];
			dirty();
			m_tx.waitingData = true;
			assert(m_tx.signal);
			m_tx.dataSignalRaised = false;
			m_tx.signal.wait();
			m_tx.dataSignalRaised = false;
			m_tx.waitingData = false;
			processExceptions();
			checkConnected();
		}

		dirty();
	}

	void flush()
	{
		if (!m_tx.bufs || m_tx.bufs.length == 0) return;
		acquireWriter();
		scope(exit) releaseWriter();
		// enforce dirty?
		dirty();
		yield(); // will flush the buffers on the next run of the event loop
		
	}

	/// Calling finalize on a stream that has never yielded will half-close it and allow a full atomic request or response
	void finalize()
	{
		acquireWriter();
		scope(exit) releaseWriter();
		halfClose();
		if (!m_session.isServer) {
			yield();
		}
		else {
			while (!m_tx.finalized) {
				m_rx.waitingStreamExit = true;
				m_rx.dataSignalRaised = false;
				m_rx.signal.wait();
				m_rx.dataSignalRaised = false;
				m_rx.waitingStreamExit = false;
			}
		}
		processExceptions();

	}
	
	void write(InputStream stream, ulong nbytes = 0)
	{
		writeDefault(stream, nbytes);
	}

private:

	void checkSafetyLevel() {
		if (!m_safety_level_changed) return;

		void checkBufs(ref Buffers bufs) {
			if (bufs.length == 0) {
				if ((m_safety_level & SafetyLevel.LockMemory) != 0 && !bufs.use_secure_mem) {
					bufs.free();
					Buffers old = bufs;
					bufs = Mem.alloc!Buffers(old.chunk_length, old.max_chunk, 1, 0, true, false);
					Mem.free(old);
				}
				else if ((m_safety_level & SafetyLevel.LockMemory) == 0 && bufs.use_secure_mem)
				{ // switch from Secure to Insecure
					bufs.free();
					Buffers old = bufs;
					bufs = Mem.alloc!Buffers(old.chunk_length, old.max_chunk, 1, 0, false, false);
					Mem.free(old);
				}
				
				if (m_safety_level & SafetyLevel.ZeroizeBuffers)
					bufs.zeroize_on_free = true;
				else bufs.zeroize_on_free = false;
				
				m_safety_level_changed = false;
			}
		}
		checkBufs(m_tx.bufs);
		checkBufs(m_rx.bufs);
	}

	void readPushResponse(HTTP2Stream push_response)
	{
		import std.algorithm : swap;
		.swap(m_rx.bufs, push_response.m_rx.bufs);
		.swap(m_rx.headers, push_response.m_rx.headers);
		.swap(m_stream_id, push_response.m_stream_id);
		m_session.get().setStreamUserData(push_response.m_stream_id, cast(void*) this);
		m_rx.dataSignalRaised = true;
		m_rx.signal.emit();
		push_response.close(); // it is now the client stream
		m_connected = true;
		m_active = true;
		logDebug("Destroy stream: ", push_response.streamId);
		push_response.destroy();
	}

	/// optimization used when the request or response data are completely buffered
	/// stream will be marked half-closed (Shutdown.WR or Shutdown.RD)
	void halfClose() {
		m_tx.halfClosed = true;
		dirty();
	}

	/// don't yield here, we want to coalesce data segments as much as possible
	/// the write event loop sends as soon as its Task is resumed
	void dirty() {
		if (m_tx.dirty)
			return;
		
		if (m_priority != m_priSpec.weight)
			m_tx.priSpec.weight = m_priority;

		m_tx.dirty = true;
		enforce(m_session.m_tcpConn !is null);
		m_session.m_tx.schedule(this);
	}

	void acquireReader() { 
		logDebug("HTTP2 Reader Acquired");
		if (Task.getThis() == Task()) {
			logDebug("Reading without task");
			return;
		}
		assert(!m_rx.waitingData && !m_rx.waitingHeaders && !m_rx.waitingStreamExit, "Another task is waiting.");
		assert(!m_rx.owner || m_rx.owner == Task.getThis()); 
		m_rx.owner = Task.getThis();
		processExceptions();
		checkSafetyLevel();
	}
	
	void releaseReader() { 
		logDebug("HTTP2 Reader Released");
		if (Task.getThis() == Task()) return;
		assert(m_rx.owner == Task.getThis());
		m_rx.owner = Task();
	}
		
	void acquireWriter() { 
		if (Task.getThis() == Task()) return;
		assert(!m_tx.waitingData, "Another task is waiting.");
		assert(m_tx.owner == Task() || m_tx.owner == Task.getThis());
		m_tx.owner = Task.getThis();

		processExceptions();
		checkConnected();
		checkSafetyLevel();
	}
	
	void releaseWriter() { 
		if (Task.getThis() == Task()) return;
		assert(m_tx.owner == Task.getThis()); 
		m_tx.owner = Task();
	}

	void checkConnected() {

		scope(failure)
			onClose();
		if (m_session) {
			if (m_session.m_rx.ex) {
				throw m_session.m_rx.ex;
			}
			enforceEx!StreamExitException(!m_session.m_rx.error, "This stream has ended with GoAway error: " ~ m_session.m_rx.error.to!string);
		}

		enforceEx!StreamExitException(connected && !m_rx.close, "The remote endpoint has closed this HTTP/2 stream.");
		enforceEx!StreamExitException(!m_tx.halfClosed, "Cannot write on a finalized stream");

	}

	void processExceptions() {
		scope(failure) onClose();

		if (m_rx.ex)
			throw m_rx.ex;
		if (m_rx.error)
			throw new Exception("This stream has ended with error: " ~ m_rx.error.to!string);
		if (m_rx.prispec != PrioritySpec.init) {
			m_priority = cast(ubyte)m_rx.prispec.weight;
			m_rx.prispec = PrioritySpec.init;
		}

	}

	void notifyClose(FrameError error_code = FrameError.NO_ERROR) {
		m_rx.close = true;
		streamId = -1;
		// in case of an error, we let the reading fail
		if (error_code != FrameError.NO_ERROR) {
			m_rx.error = error_code;
			m_tx.notify();
		}
		
		m_rx.notifyAll();
		onClose();
	}

	void onClose() {
		m_connected = false;
		if (m_session && m_session.m_tcpConn) {
			if (m_session.m_closing && !m_session.m_tx.dataSignalRaised) {
				m_session.m_tx.dataSignalRaised = true;
				if (m_session.m_tx.signal)
					m_session.m_tx.signal.emit();
			}
			streamId = -1;
		} else m_stream_id = -1;
		m_tx.free();
	}

	// This function retrieves the length of the next write and calls Connector.writeData when ready
	int dataProvider(ubyte[] dst, ref DataFlags data_flags)
	{
		if (!m_rx.bufs)
			return ErrorCode.CALLBACK_FAILURE;
		// this function may be called many times for a single send operation		
		Buffers bufs = m_tx.bufs;
		int wlen;
		if (bufs.length > 0) {
			data_flags |= DataFlags.NO_COPY; // dst is unused
			Buffers.Chain c;
			int i;
			// find the next buffer scheduled to be sent
			for(c = bufs.head; i++ < m_tx.queued; c = c.next)
				continue;
			if (i == 1)
				assert(c == bufs.head);

			bool remove_one = dst.length >= c.buf.length;
			wlen = min(cast(int) dst.length, cast(int) c.buf.length);

			if (wlen == 0) {
				m_tx.notify();
				if (m_tx.halfClosed) {
					dirty();
					m_tx.finalized = true;
					data_flags |= DataFlags.EOF;
					return 0;
				}
				m_tx.deferred = true;
				return ErrorCode.DEFERRED;
			}
			// make sure this buffer is not going to enlarge while it is queued
			if (bufs.head is bufs.cur)
				bufs.advance();

			if (remove_one)
				// move queue for next send
				m_tx.queued++;

			m_tx.queued_len += wlen;
		}
		
		if (bufs.length == 0 || (m_tx.halfClosed && m_tx.bufs.length - wlen == 0))
		{
			dirty();
			m_tx.finalized = true;
			data_flags |= DataFlags.EOF;
		}
		return wlen;
	}

	void allocateBuffers(int chunk_size) {
		int remote_chunk_size = m_session.get().getRemoteSettings(Setting.MAX_FRAME_SIZE);
		int remote_window_size = m_session.get().getRemoteSettings(Setting.INITIAL_WINDOW_SIZE);
		int local_window_size = m_session.m_defaultStreamWindowSize;
		m_maxFrameSize = min(chunk_size, remote_chunk_size);
		m_rx.bufs = Mem.alloc!Buffers(m_maxFrameSize, local_window_size/m_maxFrameSize+1, 1, 0, m_session.m_tlsStream?true:false, false);
		m_tx.bufs = Mem.alloc!Buffers(m_maxFrameSize, remote_window_size/m_maxFrameSize+1, 1, 0, m_session.m_tlsStream?true:false, false);
		// once read is called, the buffers will adjust to the user's desired memory safety level.
		m_safety_level_changed = m_session.m_tlsStream?true:false;
	}
}

struct HTTP2Settings {
	bool enablePush;
	int connectionWindowSize = INITIAL_CONNECTION_WINDOW_SIZE;
	int streamWindowSize = INITIAL_WINDOW_SIZE;
	int chunkSize = 1024*16; // max frame size
	int maxConcurrentStreams = INITIAL_MAX_CONCURRENT_STREAMS; // should be set to 100
	uint maxHeadersListSize = int.max;

	private ubyte[] toSettingsPayload() {
		Setting[] iva = Mem.alloc!(Setting[])(5);
		iva[0].id = Setting.INITIAL_WINDOW_SIZE;
		iva[0].value = connectionWindowSize;
		iva[1].id = Setting.MAX_CONCURRENT_STREAMS;
		iva[1].value = maxConcurrentStreams;
		iva[2].id = Setting.MAX_FRAME_SIZE;
		iva[2].value = chunkSize;
		iva[3].id = Setting.ENABLE_PUSH;
		iva[3].value = enablePush;
		iva[4].id = Setting.MAX_HEADER_LIST_SIZE;
		iva[4].value = maxHeadersListSize;
		
		Settings settings = Settings(FrameFlags.NONE, iva);
		import libhttp2.constants : FRAME_HDLEN;
		Buffers bufs = Mem.alloc!Buffers(2048, 1, FRAME_HDLEN + 1);
		scope(exit) Mem.free(bufs);
		ErrorCode rv = settings.pack(bufs);
		if (rv != 0)
			throw new Exception("Could not pack settings: " ~ libhttp2.types.toString(rv));
		return Mem.copy(bufs.cur.buf[][FRAME_HDLEN .. $]);
	}

	/// Serializes this for client HTTP2-Settings header data. 
	string toBase64Settings() {
		ubyte[] buf = toSettingsPayload();
		scope(exit) Mem.free(buf);
		char[] enc_buf = Mem.alloc!(char[])(B64.encodeLength(buf.length));
		scope(exit) Mem.free(enc_buf);
		return B64.encode(buf, enc_buf).idup;
	}

}

final class HTTP2Session
{
	static ulong total_sessions_running;

	import vibe.stream.tls : TLSStream;
	Session m_session; // libhttp2 implementation
	TCPConnection m_tcpConn;
	TLSStream m_tlsStream;
	HTTP2RequestHandler m_requestHandler;
	HTTP2Connector m_connector;
	Vector!HTTP2Stream m_pushResponses;
	Vector!PingData m_pong;
	int m_defaultStreamWindowSize;
	int m_defaultChunkSize;
	int m_totConnected;
	uint m_maxConcurrency;
	bool m_closing;
	bool m_forcedClose;
	bool m_server;
	bool m_gotPreface;
	bool m_paused;
	bool m_aborted;
	bool m_resume;
	void delegate(ref HTTP2Settings) m_settingsUpdater;

	Duration m_readTimeout = 10.minutes; // max inactivity waiting for any data
	Duration m_writeTimeout = 10.minutes; // max internal inactivity writing data
	Duration m_pauseTimeout = 10.minutes; // max local pause duration

	ReadLoop m_rx;
	WriteLoop m_tx;

	@property bool isServer() { return m_server; }
	@property bool connected() { return m_tx.owner != Task() && m_tcpConn && m_tcpConn.connected() && !m_rx.closed && !m_tx.closed && m_gotPreface; }
	@property string httpVersion() { if (m_tlsStream) return "h2"; else return "h2c"; }
	@property ConnectionStream topStream() { return m_tlsStream ? cast(ConnectionStream) m_tlsStream : cast(ConnectionStream) m_tcpConn; }

	/// Sets the max amount of time we wait for data. You can use ping to avoid reaching the timeout
	void setReadTimeout(Duration timeout) { m_readTimeout = timeout; }
	void setWriteTimeout(Duration timeout) { m_writeTimeout = timeout; }
	void setPauseTimeout(Duration timeout) { m_pauseTimeout = timeout; }

	private inout(Session) get() inout { return m_session; }

	struct ReadLoop {
		ManualEvent signal;
		Exception ex;
		FrameError error;
		Task owner;
		ubyte[] buffer;
		bool paused;
		bool closed;
	}

	struct WriteLoop {
		CircularBuffer!HTTP2Stream pending; // Streams queued for initialization because maxConcurrentStreams was hit
		Vector!HTTP2Stream dirty; // Streams for which HTTP2Stream.m_tx is dirty, the write loop will flush them
		ManualEvent signal;
		Task owner;
		bool paused;
		bool dataSignalRaised;
		bool closed;

		bool opBinaryRight(string op)(HTTP2Stream needle)
			if (op == "in")
		{
			foreach(HTTP2Stream stream; dirty) {
				if (stream is needle)
					return true;
			}
			return false;
		}

		void schedule(HTTP2Stream stream) {
			if (stream !in this)
				dirty ~= stream;
			notify();
		}

		void notify() {
			if (!dataSignalRaised) {
				dataSignalRaised = true;
				if (signal) signal.emit();
			}
		}
	}

	/// Starts the session assuming the client and server both fully support the implementation protocol
	this(bool is_server, HTTP2RequestHandler handler, TCPConnection conn, TLSStream tls, HTTP2Settings local_settings, void delegate(ref HTTP2Settings) on_remote_settings = null)
	{
		m_server = is_server;
		m_requestHandler = handler;
		m_tcpConn = conn;
		m_tlsStream = tls;
		m_defaultStreamWindowSize = local_settings.streamWindowSize;
		m_defaultChunkSize = local_settings.chunkSize;
		m_settingsUpdater = on_remote_settings;
		m_maxConcurrency = local_settings.maxConcurrentStreams;
		m_rx.signal = getEventDriver.createManualEvent();
		m_tx.signal = getEventDriver.createManualEvent();
		m_connector = Mem.alloc!HTTP2Connector(this);

		Options options;
		options.setNoAutoWindowUpdate(true); // we will send them when reading the buffers, it's safer
		options.setRecvClientPreface(true);
		options.setPeerMaxConcurrentStreams(local_settings.maxConcurrentStreams); // safer value
		if (!is_server)
			topStream.write("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n");
		m_session = Mem.alloc!Session(is_server, m_connector, options);
		update(local_settings);
		if (tls)
			m_rx.buffer = SecureMem.alloc!(ubyte[])(local_settings.connectionWindowSize);
		else
			m_rx.buffer = Mem.alloc!(ubyte[])(local_settings.connectionWindowSize);

	}

	/// Starts a server "HTTP/2 over cleartext" session requested from a client with the HTTP/1.1 upgrade mechanism
	this(HTTP2RequestHandler handler, TCPConnection conn, string remote_settings_base64, HTTP2Settings local_settings = HTTP2Settings.init, void delegate(ref HTTP2Settings) on_remote_settings = null)
	{
		
		m_server = true;
		m_tcpConn = conn;
		m_requestHandler = handler;
		m_defaultStreamWindowSize = local_settings.streamWindowSize;
		m_defaultChunkSize = local_settings.chunkSize;
		m_connector = Mem.alloc!HTTP2Connector(this);
		m_settingsUpdater = on_remote_settings;
		m_maxConcurrency = local_settings.maxConcurrentStreams;
		m_rx.signal = getEventDriver.createManualEvent();
		m_tx.signal = getEventDriver.createManualEvent();

		Options options;
		options.setNoAutoWindowUpdate(true); // we will send them when reading the buffers, it's safer
		options.setRecvClientPreface(false);
		options.setPeerMaxConcurrentStreams(local_settings.maxConcurrentStreams); // safer value
		m_session = Mem.alloc!Session(m_server, m_connector, options);
		
		HTTP2Stream stream = new HTTP2Stream(this, 1, m_defaultChunkSize);
		stream.m_connected = true;
		stream.m_active = true;
		ubyte[] raw_buf = Mem.alloc!(ubyte[])(B64.decodeLength(remote_settings_base64.length));
		scope(exit) Mem.free(raw_buf);
		ubyte[] settings = B64.decode(remote_settings_base64, raw_buf);
		ErrorCode rv = m_session.upgrade(settings, cast(void*)stream); // starts the stream
		if (rv != 0)
			throw new Exception("Error upgrading server: " ~ libhttp2.types.toString(rv));
		// server preface
		update(local_settings);
		m_rx.buffer = Mem.alloc!(ubyte[])(local_settings.connectionWindowSize);
	}
	

	/// Starts a client "HTTP/2 over cleartext" session using upgrade mechanism and returns the stream in parameter
	/// The `run()` method must be run after the initial HTTP/1.1 headers are sent with the base64 encoded HTTP2Settings.
	/// If called from a server, a new Task will be opened to process the stream ID #1
	this(TCPConnection conn, out HTTP2Stream stream, HTTP2Settings local_settings = HTTP2Settings.init, void delegate(ref HTTP2Settings) on_remote_settings = null)
	{
		m_server = false;
		m_tcpConn = conn;
		m_defaultStreamWindowSize = local_settings.streamWindowSize;
		m_defaultChunkSize = local_settings.chunkSize;
		m_connector = Mem.alloc!HTTP2Connector(this);
		m_settingsUpdater = on_remote_settings;
		m_maxConcurrency = local_settings.maxConcurrentStreams;
		m_rx.signal = getEventDriver.createManualEvent();
		m_tx.signal = getEventDriver.createManualEvent();

		Options options;
		options.setNoAutoWindowUpdate(true); // we will send them when reading the buffers, it's safer
		options.setRecvClientPreface(true);
		options.setPeerMaxConcurrentStreams(local_settings.maxConcurrentStreams); // safer value
		m_session = Mem.alloc!Session(m_server, m_connector, options);
		
		stream = new HTTP2Stream(this, 1);

		ubyte[] settings = local_settings.toSettingsPayload();
		scope(exit) Mem.free(settings);
		ErrorCode rv = m_session.upgrade(settings, cast(void*)stream); // starts the stream
		if (rv != 0)
			throw new Exception("Client HTTP/2 upgrade failed: " ~ libhttp2.types.toString(rv));
		m_rx.buffer = Mem.alloc!(ubyte[])(local_settings.connectionWindowSize);
	}

	// Used exclusively by the server to send an initial response
	HTTP2Stream getUpgradeStream()
	in { assert(isServer);}
	body {
		HTTP2Stream upgrade_stream = cast(HTTP2Stream) m_session.getStreamUserData(1);
		logDebug("Get upgrade stream: ", cast(void*)upgrade_stream);
		return upgrade_stream;
	}

	HTTP2Stream startRequest()
	{
		enforce(!m_closing && m_tcpConn);
		return new HTTP2Stream(this, -1, m_defaultChunkSize);
	}

	/// Blocking event loop that runs this session and handles new streams
	/// Returns when stop() is called.
	void run(bool is_upgrade = false)
	in { assert(!is_upgrade || (is_upgrade && !m_tlsStream), "Aborting is only available when a client was initially waiting for an h2c upgrade"); }
	body {
		total_sessions_running++;
		scope(exit) {
			total_sessions_running--;
			onClose();
		}
		Task reader = runTask(&readLoop, is_upgrade);
		writeLoop(is_upgrade);
		reader.interrupt();
	}

	/// Used when trying upgrade from HTTP/1.1 and the remote peer doesn't support HTTP/2
	void abort(HTTP2Stream stream) 
	in { assert(!m_tlsStream, "Aborting is only available when a client was initially waiting for an h2c upgrade"); }
	body {
		m_aborted = true;
		m_closing = true;
		stream.onClose();
		if (!m_tx.dataSignalRaised) {
			m_tx.dataSignalRaised = true;
			m_tx.signal.emit();
		}
		m_rx.signal.emit();
	}

	/// Used when an upgrade from HTTP/1.1 is confirmed. Will resume the read loop
	void resume()
	in { assert(!m_tlsStream, "Resuming is only available when a client was initially waiting for an h2c upgrade. Use unpause to unpause"); }
	body  {
		m_resume = true;
		m_rx.signal.emit();
		m_tx.signal.emit();
		yield(); // start the loops and send the settings
	}

	void pause() {
		m_paused = true;
	}

	void unpause() {
		m_paused = false;
		if (!m_tx.dataSignalRaised) {
			m_tx.dataSignalRaised = true;
			m_tx.signal.emit();
		}
		m_rx.signal.emit();
	}

	/// Stop the session gracefully, waiting for existing streams to close by themselves and refusing new instances
	/// Must be a server to use this.
	void stop() 
	{
		assert(isServer, "Use stop(error) to shutdown client connections");
		m_tx.notify();
		if (m_closing) return;
		ErrorCode rv = submitShutdownNotice(m_session);
		if (rv != ErrorCode.OK)
			throw new Exception("Error sending shutdown notice: " ~ rv.to!string);
	}

	// Stop the connection forcefully with an error
	void stop(string error) {
		stop(FrameError.INTERNAL_ERROR, error);
	}

	/// Stop the connection with or without an error, forcing every stream to close if any is open
	/// Clients can use this with FrameError.NO_ERROR for "graceful" close if no streams are active
	void stop(FrameError error, string reason = "")
	{
		m_forcedClose = true;
		m_tx.notify();
		if (m_closing) return;
		m_closing = true;
		ErrorCode rv = submitGoAway(m_session, 0, error, reason);
		if (rv != ErrorCode.OK)
			throw new Exception("Error sending GoAway: " ~ rv.to!string);
	}

	void update(HTTP2Settings settings)
	{
		Setting[] iva = Mem.alloc!(Setting[])(5);
		scope(exit) 
			Mem.free(iva);
		with(settings) {
			iva[0].id = Setting.INITIAL_WINDOW_SIZE;
			iva[0].value = connectionWindowSize;
			iva[1].id = Setting.MAX_CONCURRENT_STREAMS;
			iva[1].value = maxConcurrentStreams;
			iva[2].id = Setting.MAX_FRAME_SIZE;
			iva[2].value = chunkSize;
			iva[3].id = Setting.ENABLE_PUSH;
			iva[3].value = enablePush;
			iva[4].id = Setting.MAX_HEADER_LIST_SIZE;
			iva[4].value = maxHeadersListSize;
			m_maxConcurrency = settings.maxConcurrentStreams;
		}
		ErrorCode rv = submitSettings(m_session, iva);
		if (rv != ErrorCode.OK) 
			throw new Exception("Could not update settings: " ~ rv.to!string);
	}

	void ping(PingData req)
	{
		m_session.submitPing(*cast(ubyte[8]*)&req.sent);
		m_pong ~= req;
		m_tx.notify();
	}

	@property void onSettings(void delegate(ref HTTP2Settings) del)
	{
		m_settingsUpdater = del;
	}
	// todo: Use an external PUSH_PROMISE handler rather than intercepting them through new requests

private:

	void removeInactivePushPromise(Duration sleepdur, HTTP2Stream push_promise)
	{
		sleep(sleepdur);
		if (!push_promise.m_connected)
			removePushResponse(push_promise, true);
	}

	void removePushResponse(HTTP2Stream push_response, bool close = false) {
		foreach(i, HTTP2Stream stream; m_pushResponses[]) {
			if (stream.m_stream_id == push_response.m_stream_id)
			{
				Vector!HTTP2Stream tmp = m_pushResponses[][0 .. i];
				tmp ~= m_pushResponses[][i+1 .. $];
				m_pushResponses.clear();
				m_pushResponses = tmp;
				return;
			}
		}
	}

	HTTP2Stream popPushResponse(HTTP2Stream stream)
	{
		foreach (HTTP2Stream push_response; m_pushResponses)
		{
			if (pushcmp(push_response.m_rx.headers[], stream.m_tx.headers[]))
			{
				removePushResponse(push_response);
				return push_response;
			}
		}
		return null;
	}

	// The remote endpoint is gone
	void remoteStop(FrameError error, string reason) {
		logDebug("HTTP/2: GoAway received: ", error, " reason: ", reason);
		m_closing = true;
		m_forcedClose = true;
		if (reason) 
			m_rx.ex = new Exception("GoAway received: " ~ error.to!string ~ " reason: "  ~ reason);
		m_rx.error = error;
		m_tx.closed = true;
		m_tx.notify();
	}

	// When push promise is goes through at `onFrameSent`, this is called with already created HTTP2Stream
	void handleRequest(HTTP2Stream stream)
	{
		stream.m_push = false; // not relevant anymore
		runTask({ m_requestHandler(stream); });
	}

	void handleRequest(int stream_id)
	{
		assert(!m_closing, "A new request is being handled while the session is trying to close");
		logDebug("Handling new HTTP/2 request ID: ", stream_id);
		HTTP2Stream stream = new HTTP2Stream(this, stream_id, m_defaultChunkSize);
		stream.m_connected = true;
		ErrorCode ret = m_session.setStreamUserData(stream_id, cast(void*)stream);
		assert(ret == ErrorCode.OK);
		runTask({ m_requestHandler(stream); });
	}

	void onPushPromise(int stream_id)
	in { assert(!isServer); }
	body {
		logDebug("Got push promise on stream ", stream_id); 
		HTTP2Stream stream;
		foreach (HTTP2Stream el; m_pushResponses[])
		{
			if (el.streamId == stream_id)
			{
				stream = el;
				break;
			}
		}

		if (!stream) {
			stream = new HTTP2Stream(this, stream_id, m_defaultChunkSize, true);
			stream.m_active = true;
			stream.m_connected = false; // we will mark it connected once a client reads it
			runTask(&removeInactivePushPromise, 10.seconds, stream);
			m_pushResponses ~= stream;
		}
		else if (!stream.m_push && stream.m_connected)
			stream.m_rx.ex = new Exception("An existing stream ID was used for a push promise.");
	}

	void onClose() {
		m_tcpConn = null;
		foreach(HTTP2Stream stream; m_pushResponses) {
			if (stream.m_connected) {
				stream.m_rx.notifyAll();
				stream.m_tx.notify();
				stream.onClose();
			}
		}
		m_pushResponses.clear();
		foreach(HTTP2Stream stream; m_tx.dirty) {
			if (stream.m_connected) {
				stream.m_rx.notifyAll();
				stream.m_tx.notify();
				stream.onClose();
			}
		}
		if (m_session) m_session.free();
		if (m_connector) Mem.free(m_connector);
		if (m_session) Mem.free(m_session);
		if (m_rx.buffer && m_tlsStream) SecureMem.free(m_rx.buffer);
		else if (m_rx.buffer) Mem.free(m_rx.buffer);
		m_tlsStream = null;
		m_requestHandler = null;
		destroy(m_tx);
		destroy(m_rx);
		m_tx.closed = true;
		m_rx.closed = true;
	}

	void pong(long sent) 
	{
		logDebug("Got pong");
		foreach (i, PingData ping; m_pong[])
		{
			if (ping.sent == sent) {
				*ping.recv = Clock.currTime();

				// should resume the task on the next run of the event loop
				ping.cb.emit(); 
				
				if (m_pong.length == 1) {
					m_pong.clear();
					break;
				}
				
				Vector!PingData tmp = Vector!PingData(m_pong[][0 .. i]);
				
				if (m_pong.length-1 == i) {
					m_pong = tmp.move();
					break;
				}
				
				tmp ~= m_pong[][i .. $];
				m_pong = tmp.move();
				
				break;
			}
		}

	}

	// Task-blocking read event loop
	void readLoop(bool wait_read)
	{
		m_rx.closed = false;
		scope(exit) {
			m_closing = true;
			m_rx.closed = true;
			m_tx.notify();
		}
		assert(m_rx.owner == Task());
		m_rx.owner = Task.getThis();
		scope(exit) m_rx.owner = Task();

		// HTTP/1.1 upgrade mechanism
		while (wait_read && !m_resume && !m_aborted) {
			logDebug("HTTP/2: ReadLoop Waiting for upgrade");
			m_rx.signal.wait(); // triggered in abort() or continue()
			if (m_closing) {
				return;
			}
		}
		logDebug("HTTP/2: Starting ReadLoop");
		size_t offset;
		ConnectionStream stream = topStream();
		try while((!m_closing || m_totConnected > 0) && (stream.dataAvailableForRead() || stream.waitForData(m_readTimeout))) 
		{
			ubyte[] buf;

			// fill the buffer:
			if (!m_tlsStream) {
				/*if (auto conn = cast(Buffered) m_tcpConn)
					buf = conn.readChunk(m_rx.buffer[offset .. $]);
				else {*/
					size_t len = std.algorithm.min(m_tcpConn.leastSize(), m_rx.buffer.length - offset);
					if (len > 0)
						buf = m_rx.buffer[offset .. offset + len];
					m_tcpConn.read(buf);
				//}
			}
			else {
				/*if (auto conn = cast(Buffered) m_tlsStream)
					buf = conn.readChunk(m_rx.buffer[offset .. $]);
				else {*/
					buf = null;
					// 1 byte read to trigger retrieval of TCP data within the TLS stream
					buf = m_rx.buffer[offset .. offset + 1];
					m_tlsStream.read(buf);
					// receive the rest if any available
					size_t len = std.algorithm.min(m_tlsStream.dataAvailableForRead(), m_rx.buffer.length - offset);
					if (len > 0)
						buf = m_rx.buffer[offset + 1 .. offset + 1 + len];
					m_tlsStream.read(buf);

				//}
			}

			if (buf.length == 0 && connected)
				throw new TimeoutException("The connection has received no data for " ~ m_readTimeout.to!string);
			else if (buf.length == 0) break;
			assert(offset + buf.length < m_rx.buffer.length, "Buffer size is sane");
			// re-adjust buf to span the entire buffer in case previous read data was looped around
			buf = m_rx.buffer.ptr[0 .. offset + buf.length];

			// drain the buffer:
			int rv;
			// if memRecv can't drain it all we try to pause for stream reads until 
			// everything is processed correctly. We also prevent forever loops by keeping an eye on rv
			do {
				rv = m_session.memRecv(buf);
				if (m_forcedClose) break;
				//logDebug("Buffer length was: ", buf.length);
				if (rv == ErrorCode.PAUSE)
				{
					m_rx.paused = true;
					logDebug("HTTP/2: Waiting for pause");
					m_rx.signal.wait(m_pauseTimeout, m_rx.signal.emitCount); // wait for data or unpause
					m_rx.paused = false;
				}
				else if (rv == ErrorCode.BAD_PREFACE)
					throw new Exception("Bad client preface detected");
				else if (rv < 0)
					throw new Exception("Error in ReadLoop: " ~ libhttp2.types.toString(cast(ErrorCode)rv));
				else if (rv == buf.length) // we received it all
					break;
				if (rv > 0) buf = buf[rv .. $];
			} while (rv != 0); // we haven't received it all, buf we haven't received nothing either

			// handle data we can't seem to be able to drain until more comes in
			if (rv > 0 && buf.length - rv > 0) {
				import std.c.string : memmove;
				memmove(m_rx.buffer.ptr, buf.ptr + rv, buf.length - rv);
				offset = buf.length - rv;
			}
			else offset = 0;

			// The read triggered new writes that can't occur without this event
			if (m_session.wantWrite())
				m_tx.notify();
		}
		catch (Exception e) {
			m_rx.closed = true;
			// This is part of the clean connection closure API, we close TCP/TLS and resume the task through an exception.
			if (!m_closing)
				remoteStop(FrameError.NO_ERROR, e.msg);
		}
		
	}

	// Task-blocking write event loop
	void writeLoop(bool wait_write = false)
	{
		logDebug("HTTP/2: Starting write loop");
		m_tx.closed = false;
		scope(exit) {
			m_closing = true;
			m_tx.closed = true;
		}
		assert(m_tx.owner == Task());
		m_tx.owner = Task.getThis();
		scope(exit) m_tx.owner = Task();

		// HTTP/1.1 upgrade mechanism
		while (wait_write && !m_resume && !m_aborted) {
			logDebug("HTTP/2: ReadLoop Waiting for upgrade");
			m_tx.signal.wait(); // triggered in abort() or continue()
			if (m_closing) {
				return;
			}
		}

		// write is more simple, the sendWrite() and send() Connector callbacks are called and 
		// they block in the underlying stream until everything is sent.

		// We can loop until all streams are closed when session is closing
		while(!m_closing || m_totConnected > 0) {
			logDebug("Write loop: closing? ", m_closing, " Total connected: ", m_totConnected); 
			if (m_closing && !m_tx.pending.empty) {
				foreach (HTTP2Stream stream; m_tx.pending) {
					stream.m_tx.dirty = false;
					stream.m_rx.ex = new StreamExitException("The session was closed before the stream could initialize");
					stream.m_rx.notifyAll();
					stream.m_tx.notify();
				}
			}
			logDebug("HTTP/2: Processing dirty streams"); 
			processDirtyStreams();

			ErrorCode rv = m_session.send();
			if (m_forcedClose) break;
			if (rv == ErrorCode.PAUSE) {
				m_tx.paused = true;
				if (!m_tx.dataSignalRaised) {
					logDebug("HTTP/2: Pausing write loop!");
					m_tx.signal.wait(m_pauseTimeout, m_tx.signal.emitCount);
				}
				m_tx.dataSignalRaised = false;
				m_tx.paused = false;

				if (m_rx.paused)
					m_rx.signal.emit(); // make sure receiver also wakes up
			}
			else if (rv != ErrorCode.OK) {
				throw new Exception(libhttp2.types.toString(rv));
			}

			if (!m_tx.dataSignalRaised)
				m_tx.signal.wait(m_writeTimeout, m_tx.signal.emitCount); // triggers when dirty streams are available
			m_tx.dataSignalRaised = false;
		}

	}

	void processDirtyStreams()
	{
		// fixme: Is this the best way to implement connection-level pausing?
		if (m_paused) return;

		scope(exit) {
			logDebug("HTTP/2: Processed dirty streams");
			m_tx.dirty.clear();
		}
		foreach (HTTP2Stream stream; m_tx.dirty)
		{
			if (stream.m_tx.bufs) with (stream.m_tx) 
			{
				bool close_processed;
				bool headers_processed;
				bool prispec_processed;
				bool data_processed;

				logDebug("Stream information: ", stream.toString()); 
				if (!dirty) continue;
				if (finalized && isServer) close = true;
				if (stream.m_rx.close)
				{ // stream was closed remotely, no need to try and transmit something
					if (bufs) bufs.reset();
					dirty = false;
					continue;
				}

				if (close && stream.m_stream_id <= 0) {
					// a canceled request perhaps
					stream.notifyClose();
					bufs.reset();
					dirty = false;
					continue;
				}

				if (error) {
					submitRstStream(m_session, stream.m_stream_id, error);
					stream.notifyClose(error);
					dirty = false;
					continue;
				}

				if (windowUpdate > 0) {
					submitWindowUpdate(m_session, stream.streamId, windowUpdate);
				}

				// This stream needs to send a header, in which case it may send additional information and coalesce to optimize
				if (headers) {

					// Push promise must be sent by a server only
					if (isServer && stream.m_push) {
					
						// Make sure remote stream is accepting it
						if (!m_session.getRemoteSettings(Setting.ENABLE_PUSH))
						{
							freeHeaders();
							stream.m_rx.error = FrameError.CANCEL; // we cancel the push request
							dirty = false;
							continue;
						}
						// push promise being sent
						assert(stream.m_stream_id == -1);
						prispec_processed = true;
						if (m_session.isOutgoingConcurrentStreamsMax())
						{
							m_tx.pending.put(stream);
							continue; // try again later
						}
						logDebug("HTTP/2: Submit push promise id ", stream.m_priSpec.stream_id);
						int rv = submitPushPromise(m_session, stream.m_priSpec.stream_id, headers, cast(void*)stream);
						if (rv < 0) {
							HTTP2Stream parent = cast(HTTP2Stream)m_session.getStreamUserData(stream.m_priSpec.stream_id);
							parent.m_rx.ex = new Exception("Push promise failed: " ~ libhttp2.types.toString(cast(ErrorCode)rv));
						}
						else stream.streamId = rv;
					}
					// finalized stream with headers. The request/response can be sent all at once here
					else if (halfClosed) 
					{
						if (isServer) {
							// handle full server response
							ErrorCode rv = submitResponse(m_session, stream.m_stream_id, headers, &stream.dataProvider);
							logDebug("HTTP/2: Submit response id ", stream.m_stream_id);
							data_processed = true;
							if (rv != ErrorCode.OK)
								stream.m_rx.ex = new Exception("Error while submitting response: " ~ libhttp2.types.toString(rv));
						}
						else {
							if (stream.m_push) {
								// client push are illegal, it's worth catching it here rather than in libhttp2
								stream.m_rx.ex = new Exception("Push Promise being sent by client stream... and with no headers.");
							}
							else {
								// handle full client request
								assert(stream.m_stream_id == -1, "Stream was started. " ~ stream.toString());
								if (m_session.isOutgoingConcurrentStreamsMax())
								{
									m_tx.pending.put(stream);
									continue; // try again later
								}
								prispec_processed = true;
								int stream_id = submitRequest(m_session, stream.m_tx.priSpec, headers, (bufs.length>0)?&stream.dataProvider:null, cast(void*)stream);
								logDebug("HTTP/2: Submit request id ", stream_id);
								data_processed = true;
								if (stream_id < 0) {
									stream.m_rx.ex = new Exception("Error while submitting request: " ~ libhttp2.types.toString(cast(ErrorCode)stream_id));
									throw new Exception("Error while submitting request: " ~ libhttp2.types.toString(cast(ErrorCode)stream_id));
								}
								stream.streamId = stream_id; // client stream initiated!
							}
						}

					}
					// Regular stream headers, we send them
					else 
					{
						FrameFlags fflags = FrameFlags.END_HEADERS;

						if (close && bufs.length == 0) {
							fflags |= FrameFlags.END_STREAM;
						}
						if (priSpec != PrioritySpec.init)
						{
							stream.m_priSpec = priSpec;
							priSpec = PrioritySpec.init;
						}

						// This shouldn't happen...
						if (!isServer && stream.m_push) {
							stream.m_rx.ex = new Exception("Push Promise being sent by client stream... and with no headers.");
						// header request/response/push-response
						} else {
							bool was_push;
							// Clients: Is possible that we received this request as a push response?
							if (!isServer) {
								// To verify, we "pop" the push response that corresponds to this stream's headers, or null if none
								if (HTTP2Stream push_stream = popPushResponse(stream)) {
									assert(!isServer);
									stream.readPushResponse(push_stream);
									was_push = true;

								}
							}
							// header request/response
							if (!was_push) 
							{ 
								if (close) close_processed = true;
								prispec_processed = true;
								if (m_session.isOutgoingConcurrentStreamsMax())
								{
									m_tx.pending.put(stream);
									continue; // try again later
								}
								int rv = submitHeaders(m_session, fflags, stream.m_stream_id, stream.m_priSpec, headers, cast(void*)stream);
								if (rv < 0)
									stream.m_rx.ex = new Exception("Error submitting headers: " ~ libhttp2.types.toString(cast(ErrorCode)rv));
								logDebug("HTTP/2: Submit headers request id ", rv);
								// clients can use the return type as a new stream ID
								if (!isServer)
									stream.streamId = rv; // client stream initiated!
							}
						}
					}

					// all strings stored in the headers are destroyed
					freeHeaders();
					headers = null;

					headers_processed = true;
				}

				// Send the data if it wasn't done earlier
				if ((!data_processed && !finalized && halfClosed && stream.m_connected && stream.m_stream_id > 0) || 
					(!data_processed && stream.m_connected && stream.m_stream_id > 0 && bufs.length > 0 && ((isServer && stream.m_active) || !isServer)))
				{
					if (halfClosed)
						stream.m_rx.notifyAll();
					FrameFlags fflags;
					if (close) {
						close_processed = true;
						fflags = FrameFlags.END_STREAM;
					}

					logDebug("HTTP/2: Submit data id ", stream.m_stream_id);
					ErrorCode rv = submitData(m_session, fflags, stream.m_stream_id, &stream.dataProvider);
					if (rv == ErrorCode.DATA_EXIST) {
						close_processed = false;
						deferred = false;
						rv = m_session.resumeData(stream.m_stream_id);
					}
					else if (rv != ErrorCode.OK) {
						close_processed = false;
						stream.m_rx.ex = new Exception("Could not send Data: " ~ rv.to!string);
					}

					data_processed = true;
				}

				// This stream was closed and we didn't "submit" this info earlier
				if (close && !close_processed) 
				{
					bufs.reset();
					logDebug("HTTP/2: Submit rst stream id ", stream.m_stream_id);
					ErrorCode rv = submitRstStream(m_session, stream.m_stream_id, FrameError.NO_ERROR);
					if (rv != ErrorCode.OK)
						stream.m_rx.ex = new Exception("Could not send RstStream: " ~ rv.to!string);

					stream.notifyClose(error);

				}

				// The stream has a new priority weight or inheritance scheme and we didn't "submit" this info earlier
				if (priSpec != PrioritySpec.init && !prispec_processed)
				{
					prispec_processed = true;
					stream.m_priSpec = priSpec;
					priSpec = PrioritySpec.init;
					logDebug("HTTP/2: Submit priority id ", stream.m_stream_id);
					ErrorCode rv = submitPriority(m_session, stream.m_stream_id, stream.m_priSpec);
					if (rv != ErrorCode.OK)
						stream.m_rx.ex = new Exception("Could not send Priority Spec: " ~ rv.to!string);
				}

				dirty = false;
			}

		}
	}
}

private final class HTTP2Connector : Connector {
	HTTP2Session m_session;
	HTTP2Stream m_stream;
	int m_stream_id;

	bool m_expectPushPromise;
	bool m_expectHeaderFields;

	this(HTTP2Session session) {
		m_session = session;
	}

	HTTP2Stream getStream(int stream_id) {
		logDebug("HTTP/2: Get stream: ", stream_id);
		if (stream_id == 0)
			return null;

		if (m_stream_id == stream_id)
			return m_stream;
		m_stream = cast(HTTP2Stream) m_session.get().getStreamUserData(stream_id);
		if (m_stream)
			m_stream_id = stream_id;
		else m_stream_id = 0;
		return m_stream;
	}

override:
	
	bool onStreamExit(int stream_id, FrameError error_code)
	{
		HTTP2Stream stream = getStream(stream_id);
		logDebug("HTTP/2: onStreamExit"); 
		stream.notifyClose(error_code);
		return true;
	}

	bool onFrame(in Frame frame)
	{
		HTTP2Stream stream = getStream(frame.hd.stream_id);

		if (stream && (frame.hd.flags & FrameFlags.END_HEADERS) != 0) {
			assert(m_expectHeaderFields, "Did not expect header fields when we got END_HEADERS flag");
			m_expectHeaderFields = false;
			// headers are complete
			stream.m_active = true;
			stream.m_rx.notifyHeaders();
		}

		if (frame.hd.type == FrameType.GOAWAY)
		{
			m_session.remoteStop(frame.goaway.error_code, frame.goaway.opaque_data);
		}

		if (frame.hd.type == FrameType.SETTINGS)
		{
			m_session.m_gotPreface = true; // this usually means the connection preface is received, for clients and servers
			if (m_session.m_settingsUpdater)
			{
				logDebug("HTTP/2: Calling settings updater");
				import std.algorithm : min;
				HTTP2Settings remote_settings;
				remote_settings.enablePush = m_session.get().getRemoteSettings(Setting.ENABLE_PUSH) > 0;
				// todo: Do we use the min, or the remote value?
				remote_settings.maxConcurrentStreams = min(m_session.m_maxConcurrency, m_session.get().getRemoteSettings(Setting.MAX_CONCURRENT_STREAMS));
				remote_settings.maxHeadersListSize = m_session.get().getRemoteSettings(Setting.MAX_HEADER_LIST_SIZE);
				remote_settings.chunkSize = m_session.get().getRemoteSettings(Setting.MAX_FRAME_SIZE);
				remote_settings.streamWindowSize = m_session.get().getRemoteSettings(Setting.INITIAL_WINDOW_SIZE);
				remote_settings.connectionWindowSize = m_session.get().getRemoteWindowSize();
				//logDebug("HTTP/2: Remote settings: ", remote_settings.to!string);
				m_session.m_settingsUpdater(remote_settings);
			}
		}

		if (stream && frame.hd.type == FrameType.PRIORITY)
		{
			stream.m_rx.prispec = frame.priority.pri_spec;
			stream.m_rx.notifyData();
		}

		if (frame.hd.type == FrameType.PING)
		{
			logDebug("Ping frame type receive");
			long sent = *cast(long*)&frame.ping.opaque_data;
			m_session.pong(sent);
		}

		if (frame.hd.type == FrameType.WINDOW_UPDATE)
		{
			if (stream) {
				stream.m_tx.notify();
			}
		}

		return true;
	}
	
	bool onFrameHeader(in FrameHeader hd)
	{
		HTTP2Stream stream = getStream(hd.stream_id);

		if (hd.type == FrameType.PUSH_PROMISE)
			m_session.onPushPromise(hd.stream_id);
		logDebug("HTTP/2: On frame header stream: ", hd.stream_id); 
		if (stream && stream.m_paused && stream.m_unpaused && !stream.m_rx.close && !stream.m_tx.close)
		{
			// resume stream
			stream.m_paused = false;
			stream.m_unpaused = false;
			
			// if data was pending, process it
			if (stream.m_tx.dirty) {
				m_session.m_tx.schedule(stream);
			}

		}
		return true;
	}
	
	bool onHeaders(in Frame frame)
	{
		m_expectHeaderFields = true;
		if (frame.hd.type == FrameType.HEADERS) {
			m_expectPushPromise = false;
			if (frame.headers.cat == HeadersCategory.REQUEST)
				m_session.handleRequest(frame.hd.stream_id);

		}
		else if (frame.hd.type == FrameType.PUSH_PROMISE)
		{
			// this should be a client...
			m_expectPushPromise = true;
		}
		return true;
	}
	
	bool onHeaderField(in Frame frame, HeaderField hf, ref bool pause, ref bool rst_stream)
	{
		assert(m_expectHeaderFields, "Did not expect header fields when we got one");

		HTTP2Stream stream = getStream(frame.hd.stream_id);
		assert(stream, "Could not find stream");
		HeaderField hf_copy;
		hf_copy.name = cast(string)Mem.copy(hf.name);
		hf_copy.value = cast(string)Mem.copy(hf.value);
		stream.m_rx.headers ~= hf_copy;
		logDebug("Got response header: ", hf_copy); 
		return true;
	}
	
	bool onDataChunk(FrameFlags flags, int stream_id, in ubyte[] data, ref bool pause)
	{
		HTTP2Stream stream = getStream(stream_id);
		Buffers bufs = stream.m_rx.bufs;
		if (!bufs) {
			m_session.get().consumeConnection(data.length);
			return false; // the stream errored out...
		}
		if (stream.m_paused)
			pause = true;

		if (ErrorCode.BUFFER_ERROR == bufs.add(cast(string)data)) {
			m_session.get().consumeConnection(data.length);
			stream.m_rx.ex = new Exception("Remote peer didn't respect WINDOW SIZE");
			return false; // protocol error, peer didn't respect WINDOW SIZE
		}
		stream.m_rx.notifyData();

		return true;
	}
	
	bool onInvalidFrame(in Frame frame, FrameError error_code)
	{
		logDebug("HTTP/2 onInvalidFrame: ", error_code.to!string);
		HTTP2Stream stream = getStream(frame.hd.stream_id);
		stream.notifyClose(error_code);
		return true;
	}
	
	bool onFrameFailure(in Frame frame, ErrorCode error_code)
	{
		HTTP2Stream stream = getStream(frame.hd.stream_id);
		auto exception = new Exception("Frame Failure detected. ErrorCode: " ~ error_code.to!string);
		stream.m_rx.ex = exception;
		stream.notifyClose();
		return true;
	}
	
	bool onFrameReady(in Frame frame)
	{
		return true;
	}
	
	bool onFrameSent(in Frame frame)
	{
		if (frame.hd.type == FrameType.PUSH_PROMISE) {
			HTTP2Stream stream = getStream(frame.hd.stream_id);
			m_session.handleRequest(stream);
		}
		else if (frame.hd.type == FrameType.GOAWAY)
		{
			m_session.m_closing = true;
			// maybe all streams are already closed
			if (m_session.m_rx.paused)
				m_session.m_rx.signal.emit();
			m_session.m_tx.notify();
		}

		// When sending new local settings manually, it is important to keep the local copy up-to-date
		else if (frame.hd.type == FrameType.SETTINGS)
		{
			ErrorCode rv = m_session.m_session.updateLocalSettings(frame.settings.iva);
			if (rv != ErrorCode.OK) {
				m_session.m_rx.ex = new Exception("Could not update local settings: " ~ rv.to!string);
			}
		}
		return true;
	}
	
	int selectPaddingLength(in Frame frame, int max_payloadlen)
	{
		return frame.hd.length;
	}

	int maxFrameSize(FrameType frame_type, int stream_id, int session_remote_window_size, int stream_remote_window_size, uint remote_max_frame_size)
	{
		HTTP2Stream stream = getStream(stream_id);

		return min(stream.m_maxFrameSize, session_remote_window_size, stream_remote_window_size, remote_max_frame_size);
	}

	ErrorCode writeData(in Frame frame, ubyte[] framehd, uint length)
	{
		HTTP2Stream stream = getStream(frame.hd.stream_id);
		Buffer* buf = &stream.m_tx.bufs.head.buf;

		// write the header
		write(framehd); 
		// tag for pad
		if (frame.data.padlen > 0) {
			ubyte[1] padlen;
			padlen[0] = cast(ubyte)(frame.data.padlen - 1);
			write(padlen[0 .. 1]);
		}
		//logDebug("WRITING DATA: ", buf.pos[0 .. length]);
		// write the data directly from buffers (NO_COPY)
		write(buf.pos[0 .. length]);
		// deschedule the buffer and free the memory
		if (buf.length == length) {
			stream.m_tx.bufs.removeOne();
			stream.m_tx.queued--;
		}
		else buf.pos += length;
		stream.m_tx.queued_len -= length;
		stream.m_tx.notify();
		// add padding bytes
		if (frame.data.padlen > 1) {
			ubyte[] ub = Mem.alloc!(ubyte[])(frame.data.padlen - 1);
			scope(exit) Mem.free(ub);
			write(ub);
		}

		return ErrorCode.OK;
	}

	int write(in ubyte[] data) 
	{
		ConnectionStream stream = m_session.topStream;
		stream.write(data);
		//logDebug("Write: ", cast(string) data);
		return cast(int)data.length;
	}
	
	int read(ubyte[] data) 
	{  
		assert(false, "The read callback should not have been called, because Session.memRecv() is being used directly!");
	}
}

/**
	Thrown when the remote endpoint has cause the stream to exit prematurely
*/
class StreamExitException : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) @safe pure nothrow
	{
		super("The Stream Went Away: " ~ msg, file, line, next);
	}
}

/**
	Thrown when the read loop has received no data for an amount of time defined by the Session timeout value
*/
class TimeoutException : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) @safe pure nothrow
	{
		super("The Connection Went Away: " ~ msg, file, line, next);
	}
}

private:
HeaderField find(HeaderField[] hfa, string name) {
	foreach (HeaderField hf; hfa) {
		if (hf.name == name)
			return hf;
	}
	return HeaderField.init;
}

// returns true if the headers of a are push equivalent to headers of request
bool pushcmp(HeaderField[] req, HeaderField[] push)
{
	// todo: Check for deflate/gzip?
	return (isCacheable(req) && req.find(":path").value == push.find(":path").value
		&& req.find(":method").value == push.find(":method").value
		&& req.find(":scheme").value == push.find(":scheme").value);

}

bool isCacheable(HeaderField[] hfa) {
	bool has_nostore = hfa.find("Pragma").value == "no-cache";
	bool has_authorization = hfa.find("Authorization").value !is null;
	auto method = hfa.find(":method").value;
	bool is_method_cacheable =  method == "GET" || method == "POST" || method == "HEAD";
	return !has_nostore && !has_authorization && is_method_cacheable;
}