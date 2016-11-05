/**
	Implements WebSocket support and fallbacks for older browsers.

    Standards: $(LINK2 https://tools.ietf.org/html/rfc6455, RFC6455)
	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger
*/
module vibe.http.websockets;

///
unittest {
	void handleConn(scope WebSocket sock)
	{
		// simple echo server
		while (sock.connected) {
			auto msg = sock.receiveText();
			sock.send(msg);
		}
	}

	void startServer()
	{
		import vibe.http.router;
		auto router = new URLRouter;
		router.get("/ws", handleWebSockets(&handleConn));

		// Start HTTP server using listenHTTP()...
	}
}

alias WebSocketHandshakeDelegate = void delegate(scope WebSocket);

import vibe.core.core;
import vibe.core.log;
import vibe.core.net;
import vibe.stream.operations;
import vibe.http.server;
import vibe.http.client;
import vibe.core.connectionpool;
import vibe.utils.array;

import core.time;
import std.array;
import std.base64;
import std.conv;
import std.exception;
import std.bitmanip;
import std.digest.sha;
import std.string;
import std.functional;
import std.uuid;
import std.base64;
import std.digest.sha;
import vibe.crypto.cryptorand;

/// Exception thrown by $(D vibe.http.websockets).
class WebSocketException: Exception
{
	///
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		super(msg, file, line, next);
	}

	///
	this(string msg, Throwable next, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, next, file, line);
	}
}

/**
	Returns a WebSocket client object that is connected to the specified host.
*/
WebSocket connectWebSocket(URL url, HTTPClientSettings settings = defaultSettings)
{
	import std.typecons : Tuple, tuple;

	auto host = url.host;
	auto port = url.port;
	bool use_tls = (url.schema == "wss") ? true : false;

	if (port == 0)
		port = (use_tls) ? 443 : 80;

	static struct ConnInfo { string host; ushort port; bool useTLS; string proxyIP; ushort proxyPort; }
	static FixedRingBuffer!(Tuple!(ConnInfo, ConnectionPool!HTTPClient), 16) s_connections;
	auto   ckey = ConnInfo(host, port, use_tls, settings ? settings.proxyURL.host : null, settings ? settings.proxyURL.port : 0);

	ConnectionPool!HTTPClient pool;
	foreach (c; s_connections)
		if (c[0].host == host && c[0].port == port && c[0].useTLS == use_tls && (settings is null || (c[0].proxyIP == settings.proxyURL.host && c[0].proxyPort == settings.proxyURL.port)))
			pool = c[1];

	if (!pool)
	{
		logDebug("Create HTTP client pool %s:%s %s proxy %s:%d", host, port, use_tls, (settings) ? settings.proxyURL.host : string.init, (settings) ? settings.proxyURL.port : 0);
		pool = new ConnectionPool!HTTPClient({
			auto ret = new HTTPClient;
			ret.connect(host, port, use_tls, settings);
			return ret;
		});
		if (s_connections.full)
			s_connections.popFront();
		s_connections.put(tuple(ckey, pool));
	}

	auto rng = new SystemRNG;
	auto challengeKey = generateChallengeKey(rng);
	auto answerKey = computeAcceptKey(challengeKey);
	auto cl = pool.lockConnection();
	auto res = cl.request((scope req){
		req.requestURL = (url.localURI == "") ? "/" : url.localURI;
		req.method = HTTPMethod.GET;
		req.headers["Upgrade"] = "websocket";
		req.headers["Connection"] = "Upgrade";
		req.headers["Sec-WebSocket-Version"] = "13";
		req.headers["Sec-WebSocket-Key"] = challengeKey;
	});

	enforce(res.statusCode == HTTPStatus.switchingProtocols, "Server didn't accept the protocol upgrade request.");

	auto key = "sec-websocket-accept" in res.headers;
	enforce(key !is null, "Response is missing the Sec-WebSocket-Accept header.");
	enforce(*key == answerKey, "Response has wrong accept key");
	auto conn = res.switchProtocol("websocket");
	auto ws = new WebSocket(conn, null, rng);
	return ws;
}

/// ditto
void connectWebSocket(URL url, scope void delegate(scope WebSocket sock) del, HTTPClientSettings settings = defaultSettings)
{
	bool use_tls = (url.schema == "wss") ? true : false;
	url.schema = use_tls ? "https" : "http";

	scope rng = new SystemRNG;
	auto challengeKey = generateChallengeKey(rng);
	auto answerKey = computeAcceptKey(challengeKey);

	requestHTTP(url,
		(scope req) {
			req.method = HTTPMethod.GET;
			req.headers["Upgrade"] = "websocket";
			req.headers["Connection"] = "Upgrade";
			req.headers["Sec-WebSocket-Version"] = "13";
			req.headers["Sec-WebSocket-Key"] = challengeKey;
		},
		(scope res) {
			enforce(res.statusCode == HTTPStatus.switchingProtocols, "Server didn't accept the protocol upgrade request.");
			auto key = "sec-websocket-accept" in res.headers;
			enforce(key !is null, "Response is missing the Sec-WebSocket-Accept header.");
			enforce(*key == answerKey, "Response has wrong accept key");
			res.switchProtocol("websocket", (conn) {
				scope ws = new WebSocket(conn, null, rng);
				del(ws);
			});
		}
	);
}

/**
	Establishes a web socket conection and passes it to the $(D on_handshake) delegate.
*/
void handleWebSocket(scope WebSocketHandshakeDelegate on_handshake, scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	auto pUpgrade = "Upgrade" in req.headers;
	auto pConnection = "Connection" in req.headers;
	auto pKey = "Sec-WebSocket-Key" in req.headers;
	//auto pProtocol = "Sec-WebSocket-Protocol" in req.headers;
	auto pVersion = "Sec-WebSocket-Version" in req.headers;

	auto isUpgrade = false;

	if( pConnection ) {
		auto connectionTypes = split(*pConnection, ",");
		foreach( t ; connectionTypes ) {
			if( t.strip().toLower() == "upgrade" ) {
				isUpgrade = true;
				break;
			}
		}
	}

	string req_error;
	if (!isUpgrade) req_error = "WebSocket endpoint only accepts \"Connection: upgrade\" requests.";
	else if (!pUpgrade || icmp(*pUpgrade, "websocket") != 0) req_error = "WebSocket endpoint requires \"Upgrade: websocket\" header.";
	else if (!pVersion || *pVersion != "13") req_error = "Only version 13 of the WebSocket protocol is supported.";
	else if (!pKey) req_error = "Missing \"Sec-WebSocket-Key\" header.";

	if (req_error.length) {
		logDebug("Browser sent invalid WebSocket request: %s", req_error);
		res.statusCode = HTTPStatus.badRequest;
		res.writeBody(req_error);
		return;
	}

	auto accept = cast(string)Base64.encode(sha1Of(*pKey ~ s_webSocketGuid));
	res.headers["Sec-WebSocket-Accept"] = accept;
	res.headers["Connection"] = "Upgrade";
	ConnectionStream conn = res.switchProtocol("websocket");

	WebSocket socket = new WebSocket(conn, req, null);
	try {
		on_handshake(socket);
	} catch (Exception e) {
		logDiagnostic("WebSocket handler failed: %s", e.msg);
	}
	socket.close();
}

/**
	Returns a HTTP request handler that establishes web socket conections.
*/
HTTPServerRequestDelegateS handleWebSockets(void function(scope WebSocket) on_handshake)
{
	return handleWebSockets(toDelegate(on_handshake));
}
/// ditto
HTTPServerRequestDelegateS handleWebSockets(WebSocketHandshakeDelegate on_handshake)
{
	void callback(scope HTTPServerRequest req, scope HTTPServerResponse res)
	{
		auto pUpgrade = "Upgrade" in req.headers;
		auto pConnection = "Connection" in req.headers;
		auto pKey = "Sec-WebSocket-Key" in req.headers;
		//auto pProtocol = "Sec-WebSocket-Protocol" in req.headers;
		auto pVersion = "Sec-WebSocket-Version" in req.headers;

		auto isUpgrade = false;

		if( pConnection ) {
			auto connectionTypes = split(*pConnection, ",");
			foreach( t ; connectionTypes ) {
				if( t.strip().toLower() == "upgrade" ) {
					isUpgrade = true;
					break;
				}
			}
		}
		if( !(isUpgrade &&
			  pUpgrade && icmp(*pUpgrade, "websocket") == 0 &&
			  pKey &&
			  pVersion && *pVersion == "13") )
		{
			logDebug("Browser sent invalid WebSocket request.");
			res.statusCode = HTTPStatus.badRequest;
			res.writeVoidBody();
			return;
		}

		auto accept = cast(string)Base64.encode(sha1Of(*pKey ~ s_webSocketGuid));
		res.headers["Sec-WebSocket-Accept"] = accept;
		res.headers["Connection"] = "Upgrade";
		res.switchProtocol("websocket", (scope conn) {
			// TODO: put back 'scope' once it is actually enforced by DMD
			/*scope*/ auto socket = new WebSocket(conn, req, null);
			try on_handshake(socket);
			catch (Exception e) {
				logDiagnostic("WebSocket handler failed: %s", e.msg);
			} catch (Throwable th) {
				// pretend to have sent a closing frame so that any further sends will fail
				socket.m_sentCloseFrame = true;
				throw th;
			}
			socket.close();
		});
	}
	return &callback;
}


/**
 * Represents a single _WebSocket connection.
 *
 * ---
 * shared static this ()
 * {
 *   runTask(() => connectToWS());
 * }
 *
 * void connectToWS ()
 * {
 *   auto ws_url = URL("wss://websockets.example.com/websocket/auth_token");
 *   auto ws = connectWebSocket(ws_url);
 *   logInfo("WebSocket connected");
 *
 *   while (ws.waitForData())
 *   {
 *     auto txt = ws.receiveText;
 *     logInfo("Received: %s", txt);
 *   }
 *   logFatal("Connection lost!");
 * }
 * ---
 */
final class WebSocket {
	private {
		ConnectionStream m_conn;
		bool m_sentCloseFrame = false;
		IncomingWebSocketMessage m_nextMessage = null;
		const HTTPServerRequest m_request;
		Task m_reader;
		InterruptibleTaskMutex m_readMutex, m_writeMutex;
		InterruptibleTaskCondition m_readCondition;
		Timer m_pingTimer;
		uint m_lastPingIndex;
		bool m_pongReceived;
		bool m_pongSkipped;
        SystemRNG m_rng;
	}

	/**
	 * Private constructor, called from `connectWebSocket`.
	 *
	 * Params:
	 *	 conn = Underlying connection string
	 *	 request = HTTP request used to establish the connection
	 *	 rng = Source of entropy to use.  If null, assume we're a server socket
	 */
	private this(ConnectionStream conn, in HTTPServerRequest request,
				 SystemRNG rng)
	{
		m_conn = conn;
		m_request = request;
		assert(m_conn);
		m_rng = rng;
		m_writeMutex = new InterruptibleTaskMutex;
		m_readMutex = new InterruptibleTaskMutex;
		m_readCondition = new InterruptibleTaskCondition(m_readMutex);
		m_readMutex.performLocked!({
			m_reader = runTask(&startReader);
			if (request !is null && request.serverSettings.webSocketPingInterval != Duration.zero) {
				m_pingTimer = setTimer(request.serverSettings.webSocketPingInterval, &sendPing, true);
				m_pongReceived = true;
			}
		});
	}

	/**
		Determines if the WebSocket connection is still alive and ready for sending.

		Note that for determining the ready state for $(EM reading), you need
		to use $(D waitForData) instead, because both methods can return
		different values while a disconnect is in proress.

		See_also: $(D waitForData)
	*/
	@property bool connected() { return m_conn.connected && !m_sentCloseFrame; }

	/**
		The HTTP request that established the web socket connection.
	*/
	@property const(HTTPServerRequest) request() const { return m_request; }

	/**
		Checks if data is readily available for read.
	*/
	@property bool dataAvailableForRead() { return m_conn.dataAvailableForRead || m_nextMessage !is null; }

	/** Waits until either a message arrives or until the connection is closed.

		This function can be used in a read loop to cleanly determine when to stop reading.
	*/
	bool waitForData()
	{
		if (m_nextMessage) return true;

		m_readMutex.performLocked!({
			while (connected && m_nextMessage is null)
				m_readCondition.wait();
		});
		return m_nextMessage !is null;
	}

	/// ditto
	bool waitForData(Duration timeout)
	{
		import std.datetime;

		if (m_nextMessage) return true;

		immutable limit_time = Clock.currTime(UTC()) + timeout;

		m_readMutex.performLocked!({
			while (connected && m_nextMessage is null && timeout > 0.seconds) {
				m_readCondition.wait(timeout);
				timeout = limit_time - Clock.currTime(UTC());
			}
		});
		return m_nextMessage !is null;
	}

	/**
		Sends a text message.

		On the JavaScript side, the text will be available as message.data (type string).
		Throws: WebSocketException if the connection is closed.
	*/
	void send(scope const(char)[] data)
	{
		send((scope message){ message.write(cast(const ubyte[])data); });
	}

	/**
		Sends a binary message.

		On the JavaScript side, the text will be available as message.data (type Blob).
		Throws: WebSocketException if the connection is closed.
	*/
	void send(ubyte[] data)
	{
		send((scope message){ message.write(data); }, FrameOpcode.binary);
	}

	/**
		Sends a message using an output stream.
		Throws: WebSocketException if the connection is closed.
	*/
	void send(scope void delegate(scope OutgoingWebSocketMessage) sender, FrameOpcode frameOpcode = FrameOpcode.text)
	{
		m_writeMutex.performLocked!({
			enforceEx!WebSocketException(!m_sentCloseFrame, "WebSocket connection already actively closed.");
			scope message = new OutgoingWebSocketMessage(m_conn, frameOpcode, m_rng);
			scope(exit) message.finalize();
			sender(message);
		});
	}

	/**
		Actively closes the connection.

		Params:
			code = Numeric code indicating a termination reason.
			reason = Message describing why the connection was terminated.
	*/
	void close(short code = 0, scope const(char)[] reason = "")
	{
		//control frame payloads are limited to 125 bytes
		assert(reason.length <= 123);

		if (connected) {
			m_writeMutex.performLocked!({
				m_sentCloseFrame = true;
				Frame frame;
				frame.opcode = FrameOpcode.close;
				if(code != 0)
					frame.payload = std.bitmanip.nativeToBigEndian(code) ~ cast(const ubyte[])reason;
				frame.fin = true;
				frame.writeFrame(m_conn, m_rng);
			});
		}
		if (m_pingTimer) m_pingTimer.stop();
		if (Task.getThis() != m_reader) m_reader.join();
	}

	/**
		Receives a new message and returns its contents as a newly allocated data array.

		Params:
			strict = If set, ensures the exact frame type (text/binary) is received and throws an execption otherwise.
		Throws: WebSocketException if the connection is closed or
			if $(D strict == true) and the frame received is not the right type
	*/
	ubyte[] receiveBinary(bool strict = true)
	{
		ubyte[] ret;
		receive((scope message){
			enforceEx!WebSocketException(!strict || message.frameOpcode == FrameOpcode.binary,
				"Expected a binary message, got "~message.frameOpcode.to!string());
			ret = message.readAll();
		});
		return ret;
	}
	/// ditto
	string receiveText(bool strict = true)
	{
		string ret;
		receive((scope message){
			enforceEx!WebSocketException(!strict || message.frameOpcode == FrameOpcode.text,
				"Expected a text message, got "~message.frameOpcode.to!string());
			ret = message.readAllUTF8();
		});
		return ret;
	}

	/**
		Receives a new message using an InputStream.
		Throws: WebSocketException if the connection is closed.
	*/
	void receive(scope void delegate(scope IncomingWebSocketMessage) receiver)
	{
		m_readMutex.performLocked!({
			while (!m_nextMessage) {
				enforceEx!WebSocketException(connected, "Connection closed while reading message.");
				m_readCondition.wait();
			}
			receiver(m_nextMessage);
			m_nextMessage = null;
			m_readCondition.notifyAll();
		});
	}

	private void startReader()
	{
		m_readMutex.performLocked!({}); //Wait until initialization
		scope (exit) m_readCondition.notifyAll();
		try {
			while (!m_conn.empty) {
				assert(!m_nextMessage);
				if (m_pingTimer) {
					if (m_pongSkipped) {
						logDebug("Pong not received, closing connection");
						m_writeMutex.performLocked!({
							m_conn.close();
						});
						return;
					}
					if (!m_conn.waitForData(request.serverSettings.webSocketPingInterval))
						continue;
				}
				scope msg = new IncomingWebSocketMessage(m_conn, m_rng);
				if (msg.frameOpcode == FrameOpcode.pong) {
					enforce(msg.peek().length == uint.sizeof, "Pong payload has wrong length");
					enforce(m_lastPingIndex == littleEndianToNative!uint(msg.peek()[0..uint.sizeof]), "Pong payload has wrong value");
					m_pongReceived = true;
					continue;
				}
				if(msg.frameOpcode == FrameOpcode.close) {
					logDebug("Got closing frame (%s)", m_sentCloseFrame);
					if(!m_sentCloseFrame) close();
					logDebug("Terminating connection (%s)", m_sentCloseFrame);
					m_conn.close();
					return;
				}
				m_readMutex.performLocked!({
					m_nextMessage = msg;
					m_readCondition.notifyAll();
					while (m_nextMessage) m_readCondition.wait();
				});
			}
		} catch (Exception e) {
			logDiagnostic("Error while reading websocket message: %s", e.msg);
			logDiagnostic("Closing connection.");
		}
		m_conn.close();
	}

	private void sendPing() {
		if (!m_pongReceived) {
			logDebug("Pong skipped");
			m_pongSkipped = true;
			m_pingTimer.stop();
			return;
		}
		m_writeMutex.performLocked!({
			m_pongReceived = false;
			Frame ping;
			ping.opcode = FrameOpcode.ping;
			ping.fin = true;
			ping.payload = nativeToLittleEndian(++m_lastPingIndex);
			ping.writeFrame(m_conn, m_rng);
			logDebug("Ping sent");
		});
	}
}

/**
	Represents a single outgoing _WebSocket message as an OutputStream.
*/
final class OutgoingWebSocketMessage : OutputStream {
	private {
        SystemRNG m_rng;
		Stream m_conn;
		FrameOpcode m_frameOpcode;
		Appender!(ubyte[]) m_buffer;
		bool m_finalized = false;
	}

	this( Stream conn, FrameOpcode frameOpcode, SystemRNG rng )
	{
		assert(conn !is null);
		m_conn = conn;
		m_frameOpcode = frameOpcode;
        m_rng = rng;
	}

	void write(in ubyte[] bytes)
	{
		assert(!m_finalized);
		m_buffer.put(bytes);
	}

	void flush()
	{
		assert(!m_finalized);
		Frame frame;
		frame.opcode = m_frameOpcode;
		frame.fin = false;
		frame.payload = m_buffer.data;
		frame.writeFrame(m_conn, m_rng);
		m_buffer.clear();
		m_conn.flush();
	}

	void finalize()
	{
		if (m_finalized) return;
		m_finalized = true;

		Frame frame;
		frame.fin = true;
		frame.opcode = m_frameOpcode;
		frame.payload = m_buffer.data;
		frame.writeFrame(m_conn, m_rng);
		m_buffer.clear();
		m_conn.flush();
	}

	void write(InputStream stream, ulong nbytes = 0)
	{
		writeDefault(stream, nbytes);
	}
}


/**
	Represents a single incoming _WebSocket message as an InputStream.
*/
final class IncomingWebSocketMessage : InputStream {
	private {
        SystemRNG m_rng;
		Stream m_conn;
		Frame m_currentFrame;
	}

	this(Stream conn, SystemRNG rng)
	{
		assert(conn !is null);
		m_conn = conn;
        m_rng = rng;
        readFrame();
	}

	@property bool empty() const { return m_currentFrame.payload.length == 0; }

	@property ulong leastSize() const { return m_currentFrame.payload.length; }

	@property bool dataAvailableForRead() { return true; }

	/// The frame type for this nessage;
	@property FrameOpcode frameOpcode() const { return m_currentFrame.opcode; }

	const(ubyte)[] peek() { return m_currentFrame.payload; }

	void read(ubyte[] dst)
	{
		while( dst.length > 0 ) {
			enforceEx!WebSocketException( !empty , "cannot read from empty stream");
			enforceEx!WebSocketException( leastSize > 0, "no data available" );

			import std.algorithm : min;
			auto sz = cast(size_t)min(leastSize, dst.length);
			dst[0 .. sz] = m_currentFrame.payload[0 .. sz];
			dst = dst[sz .. $];
			m_currentFrame.payload = m_currentFrame.payload[sz .. $];

			if( leastSize == 0 && !m_currentFrame.fin ) m_currentFrame = Frame.readFrame(m_conn);
		}
	}

	private void readFrame() {
		Frame frame;
		do {
			frame = Frame.readFrame(m_conn);
			switch(frame.opcode) {
				case FrameOpcode.continuation:
				case FrameOpcode.text:
				case FrameOpcode.binary:
				case FrameOpcode.close:
				case FrameOpcode.pong:
					m_currentFrame = frame;
					break;
				case FrameOpcode.ping:
					Frame pong;
					pong.opcode = FrameOpcode.pong;
					pong.fin = true;
					pong.payload = frame.payload;

					pong.writeFrame(m_conn, m_rng);
					break;
				default:
					throw new WebSocketException("unknown frame opcode");
			}
		} while( frame.opcode == FrameOpcode.ping );
	}
}


private immutable s_webSocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

/**
 * The Opcode is 4 bytes, as defined in Section 5.2
 *
 * Values are defined in section 11.8
 * Currently only 6 values are defined, however the opcode is defined as
 * taking 4 bytes.
 */
enum FrameOpcode : uint {
	continuation = 0x0,
	text = 0x1,
	binary = 0x2,
	close = 0x8,
	ping = 0x9,
	pong = 0xA
}


struct Frame {
	bool fin;
	FrameOpcode opcode;
	ubyte[] payload;

	void writeFrame(OutputStream stream, SystemRNG sys_rng)
	{
		import vibe.stream.wrapper;

		auto rng = StreamOutputRange(stream);

        ubyte[4] buff;
		ubyte firstByte = cast(ubyte)opcode;
		if (fin) firstByte |= 0x80;
		rng.put(firstByte);

		auto b1 = 0;
		if (sys_rng) {
			b1 = 0x80;
		}

		if( payload.length < 126 ) {
			rng.put(std.bitmanip.nativeToBigEndian(cast(ubyte)(b1 | payload.length)));
		} else if( payload.length <= 65536 ) {
            buff[0] = cast(ubyte) (b1 | 126);
			rng.put(buff[0 .. 1]);
			rng.put(std.bitmanip.nativeToBigEndian(cast(ushort)payload.length));
		} else {
            buff[0] = cast(ubyte) (b1 | 127);
			rng.put(buff[0 .. 1]);
			rng.put(std.bitmanip.nativeToBigEndian(payload.length));
		}

		if (sys_rng) {
            sys_rng.read(buff);
			rng.put(buff);
			for (size_t i = 0; i < payload.length; i++) {
				payload[i] ^= buff[i % 4];
			}
			rng.put(payload);
		}else {
			rng.put(payload);
		}
		rng.flush();
		stream.flush();
	}

	static Frame readFrame(InputStream stream)
	{
		Frame frame;
		ubyte[2] data2;
		ubyte[8] data8;
		stream.read(data2);
		//enforceEx!WebSocketException( (data[0] & 0x70) != 0, "reserved bits must be unset" );
		frame.fin = (data2[0] & 0x80) == 0x80;
		bool masked = (data2[1] & 0x80) == 0x80;
		frame.opcode = cast(FrameOpcode)(data2[0] & 0xf);

		logDebug("Read frame: %s %s", frame.opcode, frame.fin);
		//parsing length
		ulong length = data2[1] & 0x7f;
		if( length == 126 ) {
			stream.read(data2);
			length = bigEndianToNative!ushort(data2);
		} else if( length == 127 ) {
			stream.read(data8);
			length = bigEndianToNative!ulong(data8);
		}

		//masking key
		ubyte[4] maskingKey;
		if( masked ) stream.read(maskingKey);

		//payload
		enforceEx!WebSocketException(length <= size_t.max);
		frame.payload = new ubyte[cast(size_t)length];
		stream.read(frame.payload);

		//de-masking
		for( size_t i = 0; i < length; ++i ) {
			frame.payload[i] = frame.payload[i] ^ maskingKey[i % 4];
		}

		return frame;
	}
}

/**
 * Generate a challenge key for the protocol upgrade phase.
 */
private string generateChallengeKey(scope SystemRNG rng)
{
	ubyte[16] buffer;
	rng.read(buffer);
	return Base64.encode(buffer);
}

private string computeAcceptKey(string challengekey)
{
	immutable(ubyte)[] b = challengekey.representation;
	immutable(ubyte)[] a = s_webSocketGuid.representation;
	SHA1 hash;
	hash.start();
	hash.put(b);
	hash.put(a);
	auto result = Base64.encode(hash.finish());
	return to!(string)(result);
}
