/**
	Implements WebSocket support and fallbacks for older browsers.

	Examples:
	---
	void handleConn(WebSocket sock)
	{
		// simple echo server
		while( sock.connected ){
			auto msg = sock.receive();
			sock.send(msg);
		}
	}

	static this {
		auto router = new UrlRouter;
		router.get("/websocket", handleWebSockets(&handleConn))
		
		// Start HTTP server...
	}
	---

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger
*/
module vibe.http.websockets;

import vibe.core.log;
import vibe.core.net;
import vibe.crypto.sha1;
import vibe.stream.operations;
import vibe.http.server;

import std.conv;
import std.array;
import std.bitmanip;
import std.string;
import std.base64;
import std.exception;

private immutable s_webSocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

enum FrameOpcode {
	Continuation = 0x0,
	Text = 0x1,
	Binary = 0x2,
	Close = 0x8,
	Ping = 0x9,
	Pong = 0xA
}


struct Frame {
	bool fin;
	FrameOpcode opcode;
	ubyte[] payload;


	void writeFrame(OutputStream stream) {
		ubyte firstByte = cast(ubyte)opcode;
		if (fin) firstByte |= 0x80;
		stream.write([firstByte], false);

		if( payload.length < 126 ) {
			stream.write(nativeToBigEndian(cast(ubyte)payload.length), false);
		} else if( payload.length <= 65536 ) {
			stream.write(cast(ubyte[])[126], false);
			stream.write(nativeToBigEndian(cast(ushort)payload.length), false);
		} else {
			stream.write(cast(ubyte[])[127], false);
			stream.write(nativeToBigEndian(payload.length), false);
		}
		stream.write(payload);
	}

	static Frame readFrame(InputStream stream) {
		Frame frame;
		ubyte[2] data2;
		ubyte[8] data8;
		stream.read(data2);
		//enforce( (data[0] & 0x70) != 0, "reserved bits must be unset" );
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
		enforce(length <= size_t.max);
		frame.payload = new ubyte[cast(size_t)length];
		stream.read(frame.payload);

		//de-masking
		for( size_t i = 0; i < length; ++i ) {
			frame.payload[i] = frame.payload[i] ^ maskingKey[i % 4];
		}

		return frame;
	}

}




class OutgoingWebSocketMessage : OutputStream {
	private {
		Stream m_conn;
		FrameOpcode m_frameOpcode;
		Appender!(ubyte[]) m_buffer;
	}

	this( Stream conn, FrameOpcode frameOpcode ) {
		assert(conn !is null);
		m_conn = conn;
		m_frameOpcode = frameOpcode;
	}

	void write(in ubyte[] bytes, bool do_flush = true) {
		m_buffer.put(bytes);
		if( do_flush ) flush();
	}
	void flush() {
		Frame frame;
		frame.opcode = m_frameOpcode;
		frame.fin = true;
		frame.payload = m_buffer.data;
		frame.writeFrame(m_conn);
		m_buffer.clear();
	}
	void finalize() {
		Frame frame;
		frame.fin = true;
		frame.opcode = m_frameOpcode;
		frame.payload = m_buffer.data;
		frame.writeFrame(m_conn);
		m_buffer.clear();
	}
	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true) {
		writeDefault(stream, nbytes, do_flush);
	}

}

class IncommingWebSocketMessage : InputStream {
	private {
		Stream m_conn;
		Frame m_currentFrame;
	}

	this(Stream conn)
	{
		assert(conn !is null);
		m_conn = conn;
		readFrame();
	}

	@property bool empty() const { return m_currentFrame.payload.length == 0; }

	@property ulong leastSize() const { return m_currentFrame.payload.length; }

	@property bool dataAvailableForRead() { return true; }

	@property FrameOpcode frameOpcode() { return m_currentFrame.opcode; }

	const(ubyte)[] peek() { return m_currentFrame.payload; }

	void read(ubyte[] dst)
	{
		while( dst.length > 0 ) {
			enforce( !empty , "cannot read from empty stream");
			enforce( leastSize > 0, "no data available" );

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
				case FrameOpcode.Continuation:
				case FrameOpcode.Text:
				case FrameOpcode.Binary:
				case FrameOpcode.Close:
					m_currentFrame = frame;
					break;
				case FrameOpcode.Ping:
					frame.opcode = FrameOpcode.Pong;
					frame.writeFrame(m_conn);
					break;
				default:
					throw new Exception("unknown frame opcode");
			}
		} while( frame.opcode == FrameOpcode.Ping );
	}
}

class WebSocket {
	private {
		TcpConnection m_conn;
		bool m_sentCloseFrame = false;
		IncommingWebSocketMessage m_nextMessage = null;
	}

	this(Stream conn)
	{
		m_conn = cast(TcpConnection)conn;
		assert(m_conn);
	}

	@property bool connected() {
		if(m_nextMessage is null && m_conn.dataAvailableForRead()){
			m_nextMessage = new IncommingWebSocketMessage(m_conn);
			if(m_nextMessage.frameOpcode == FrameOpcode.Close) {
				if(!m_sentCloseFrame) close();
				m_conn.close();
				return false;
			}
		}
		return m_conn.connected && !m_sentCloseFrame;
	}
	@property bool dataAvailableForRead() { return m_conn.dataAvailableForRead || m_nextMessage !is null; }

	void send(string data)
	{
		send( (message) { message.write(cast(ubyte[])data); });
	}
	void send(ubyte[] data)
	{
		send( (message) { message.write(data); }, FrameOpcode.Binary );
	}
	void send(void delegate(OutgoingWebSocketMessage) sender, FrameOpcode frameOpcode = FrameOpcode.Text) {
		if(m_sentCloseFrame) { throw new Exception("closed connection"); }
		auto message = new OutgoingWebSocketMessage(m_conn, frameOpcode);
		sender(message);
	}
	void close() {
		Frame frame;
		frame.opcode = FrameOpcode.Close;
		frame.fin = true;
		frame.writeFrame(m_conn);
		m_sentCloseFrame = true;
	}

	ubyte[] receive() {
		ubyte[] ret;
		receive( (message) {
			ret = message.readAll();
		});
		return ret;
	}

	void receive(void delegate(IncommingWebSocketMessage) receiver) {
		if(m_nextMessage is null && connected() == false) { throw new Exception("closed connection"); }
		receiver(m_nextMessage);
		m_nextMessage = null;
	}
}

HttpServerRequestDelegate handleWebSockets(void delegate(WebSocket) onHandshake)
{
	void callback(HttpServerRequest req, HttpServerResponse res)
	{
		auto pUpgrade = "Upgrade" in req.headers;
		auto pConnection = "Connection" in req.headers;
		auto pKey = "Sec-WebSocket-Key" in req.headers;
		auto pOrigin = "Origin" in req.headers;
		auto pProtocol = "Sec-WebSocket-Protocol" in req.headers;
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
			  pOrigin &&
			  pUpgrade && *pUpgrade == "websocket" && 
			  pKey &&
			  pVersion && *pVersion == "13") )
		{
			res.statusCode = HttpStatus.BadRequest;
			res.writeVoidBody();
			return;
		}

		auto accept = cast(string)Base64.encode(sha1(*pKey ~ s_webSocketGuid));
		res.headers["Sec-WebSocket-Accept"] = accept;
		res.headers["Connection"] = "Upgrade";
		Stream conn = res.switchProtocol("websocket");

		auto socket = new WebSocket(conn);
		onHandshake(socket);
	}
	return &callback;
}
