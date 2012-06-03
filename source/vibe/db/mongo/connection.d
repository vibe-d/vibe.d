/**
	Low level mongodb protocol.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.connection;

public import vibe.data.bson;

import vibe.core.log;
import vibe.core.tcp;

import std.array;
import std.exception;


/**
	Provides low-level mongodb protocol access.

	Note that a MongoConnection my only be used from one fiber/thread at a time.
*/
class MongoConnection : EventedObject {
	private {
		string m_host;
		ushort m_port;
		TcpConnection m_conn;
		ulong m_bytesRead;
		int m_msgid = 1;
	}

	this(string server, ushort port = 27017)
	{
		m_host = server;
		m_port = port;
	}

	// changes the ownership of this connection
	override void acquire() { if( m_conn ) m_conn.acquire(); }
	override void release() { if( m_conn ) m_conn.release(); }
	override bool isOwner() { return m_conn ? m_conn.isOwner() : true; }

	void connect()
	{
		m_conn = connectTcp(m_host, m_port);
		m_bytesRead = 0;
	}

	void disconnect()
	{
		if( m_conn ){
			m_conn.close();
			m_conn = null;
		}
	}

	@property bool connected() const { return m_conn && m_conn.connected; }

	void update(string collection_name, UpdateFlags flags, Bson selector, Bson update)
	{
		scope(failure) disconnect();
		scope msg = new Message(OpCode.Update);
		msg.addInt(0);
		msg.addCString(collection_name);
		msg.addInt(flags);
		msg.addBSON(selector);
		msg.addBSON(update);
		send(msg);
	}

	void insert(string collection_name, InsertFlags flags, Bson[] documents)
	{
		scope(failure) disconnect();
		scope msg = new Message(OpCode.Insert);
		msg.addInt(flags);
		msg.addCString(collection_name);
		foreach( d; documents ){
			if( d["_id"].isNull() ) d["_id"] = Bson(BsonObjectID.generate());
			msg.addBSON(d);
		}
		send(msg);
	}

	Reply query(string collection_name, QueryFlags flags, int nskip, int nret, Bson query, Bson returnFieldSelector = Bson(null))
	{
		scope(failure) disconnect();
		scope msg = new Message(OpCode.Query);
		msg.addInt(flags);
		msg.addCString(collection_name);
		msg.addInt(nskip);
		msg.addInt(nret);
		msg.addBSON(query);
		if( returnFieldSelector.type != Bson.Type.Null )
			msg.addBSON(returnFieldSelector);
		return call(msg);
	}

	Reply getMore(string collection_name, int nret, long cursor_id)
	{
		scope(failure) disconnect();
		scope msg = new Message(OpCode.GetMore);
		msg.addInt(0);
		msg.addCString(collection_name);
		msg.addInt(nret);
		msg.addLong(cursor_id);
		return call(msg);
	}

	void delete_(string collection_name, DeleteFlags flags, Bson selector)
	{
		scope(failure) disconnect();
		scope msg = new Message(OpCode.Delete);
		msg.addInt(0);
		msg.addCString(collection_name);
		msg.addInt(flags);
		msg.addBSON(selector);
		send(msg);
	}

	void killCursors(long[] cursors)
	{
		scope(failure) disconnect();
		scope msg = new Message(OpCode.KillCursors);
		msg.addInt(0);
		msg.addInt(cast(int)cursors.length);
		foreach( c; cursors )
			msg.addLong(c);
		send(msg);
	}

	private Reply recvReply(int reqid)
	{

		auto bytes_read = m_bytesRead;
		int msglen = recvInt();
		int resid = recvInt();
		int respto = recvInt();
		int opcode = recvInt();

		enforce(respto == reqid, "Reply is not for the expected message on a sequential connection!");
		enforce(opcode == OpCode.Reply, "Got a non-'Reply' reply!");

		auto flags = cast(ReplyFlags)recvInt();
		long cursor = recvLong();
		int start = recvInt();
		int numret = recvInt();
		auto docs = new Bson[numret];
		foreach( i; 0 .. numret )
			docs[i] = recvBson();

		if( m_bytesRead - bytes_read < msglen ){
			logWarn("MongoDB reply was longer than expected, skipping the rest: %d vs. %d", msglen, m_bytesRead - bytes_read);
			ubyte[] dst = new ubyte[msglen - cast(size_t)(m_bytesRead - bytes_read)];
			recv(dst);
		} else if( m_bytesRead - bytes_read > msglen ){
			logWarn("MongoDB reply was shorter than expected. Dropping connection.");
			disconnect();
			throw new Exception("MongoDB reply was too short for data.");
		}

		auto msg = new Reply;
		msg.cursor = cursor;
		msg.flags = flags;
		msg.firstDocument = start;
		msg.documents = docs;
		return msg;
	}


	private Reply call(Message req)
	{
		auto id = send(req);
		auto res = recvReply(id);
		return res;
	}

	private int send(Message req, int response_to = -1)
	{
		if( !connected() ) connect();
		int id = nextMessageId();
		sendInt(16 + cast(int)req.m_data.data.length);
		sendInt(id);
		sendInt(response_to);
		sendInt(req.m_opCode);
		send(req.m_data.data);
		m_conn.flush();
		return id;
	}

	private void sendInt(int v) { send(toBsonData(v)); }
	private void sendLong(long v) { send(toBsonData(v)); }
	private void send(in ubyte[] data){ m_conn.write(data, false); }

	private int recvInt() { ubyte[int.sizeof] ret; recv(ret); return fromBsonData!int(ret); }
	private long recvLong() { ubyte[long.sizeof] ret; recv(ret); return fromBsonData!long(ret); }
	private Bson recvBson() {
		int len = recvInt();
		auto bson = new ubyte[len-4];
		recv(bson);
		return Bson(Bson.Type.Object, cast(immutable)(toBsonData(len) ~ bson));
	}
	private void recv(ubyte[] dst) { enforce(m_conn); m_conn.read(dst); m_bytesRead += dst.length; }

	private int nextMessageId() { return m_msgid++; }
}


/// private
private enum OpCode : int {
	Reply        = 1, // sent only by DB
	Msg          = 1000,
	Update       = 2001,
	Insert       = 2002,
	Reserved1    = 2003,
	Query        = 2004,
	GetMore      = 2005,
	Delete       = 2006,
	KillCursors  = 2007
}

enum UpdateFlags {
	None         = 0,
	Upsert       = 1<<0,
	MultiUpdate  = 1<<1
}

enum InsertFlags {
	None             = 0,
	ContinueOnError  = 1<<0
}

enum QueryFlags {
	None             = 0,
	TailableCursor   = 1<<1,
	SlaveOk          = 1<<2,
	OplogReplay      = 1<<3,
	NoCursorTimeout  = 1<<4,
	AwaitData        = 1<<5,
	Exhaust          = 1<<6,
	Partial          = 1<<7
}

enum DeleteFlags {
	None          = 0,
	SingleRemove  = 1<<0,
}

enum ReplyFlags {
	None              = 0,
	CursorNotFound    = 1<<0,
	QueryFailure      = 1<<1,
	ShardConfigStale  = 1<<2,
	AwaitCapable      = 1<<3
}

class Reply {
	long cursor;
	ReplyFlags flags;
	int firstDocument;
	Bson[] documents;
}

private class Message {
	private {
		OpCode m_opCode;
		Appender!(ubyte[]) m_data;
	}

	this(OpCode code)
	{
		m_opCode = code;
		m_data = appender!(ubyte[])();
	}

	void addInt(int v) { m_data.put(toBsonData(v)); }
	void addLong(long v) { m_data.put(toBsonData(v)); }
	void addCString(string v) { m_data.put(cast(bdata_t)v); m_data.put(cast(ubyte)0); }
	void addBSON(Bson v) { m_data.put(v.data); }
}

