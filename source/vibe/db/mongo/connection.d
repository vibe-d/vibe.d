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

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.regex;
import std.string;

/**
	Provides low-level mongodb protocol access.

	Note that a MongoConnection my only be used from one fiber/thread at a time.
*/
class MongoConnection : EventedObject {
	private {
		MongoClientSettings config;
		TcpConnection m_conn;
		ulong m_bytesRead;
		int m_msgid = 1;
	}

	this(string server, ushort port = 27017)
	{
		config = new MongoClientSettings();
		config.hosts ~= new MongoHost(server, port);
	}
	
	this(MongoClientSettings cfg)
	{
		config = cfg;
		
		// Now let's check for features that are not yet supported.
		if(config.hosts.length > 1)
			logWarn("Multiple mongodb hosts are not yet supported. Using first one: {}:{}",
				config.hosts[0].name, config.hosts[0].port);
		if(config.username != "")
			logWarn("MongoDB username is not yet supported. Ignoring username: {}", config.username);
		if(config.password != "")
			logWarn("MongoDB password is not yet supported. Ignoring password.");
		if(config.database != "")
			logWarn("MongoDB database is not yet supported. Ignoring database value: {}", config.database);
	}

	// changes the ownership of this connection
	override void acquire()
	{
		if( m_conn && m_conn.connected ) m_conn.acquire();
		else connect();
	}

	override void release()
	{
		if( m_conn && m_conn.connected )
			m_conn.release();
	}

	override bool isOwner() { return m_conn ? m_conn.isOwner() : true; }

	void connect()
	{
		/* 
		 * TODO: Connect to one of the specified hosts taking into consideration
		 * options such as connect timeouts and so on.
		 */
		m_conn = connectTcp(config.hosts[0].name, config.hosts[0].port);
		m_bytesRead = 0;
	}

	void disconnect()
	{
		if( m_conn ){
			if( m_conn.connected ) m_conn.close();
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
		msg.addInt(flags | config.defQueryFlags);
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

/**
 * Parses the given string as a mongodb URL. Url must be in the form documented at
 * http://www.mongodb.org/display/DOCS/Connections which is:
 * 
 * mongodb://[username:password@]host1[:port1][,host2[:port2],...[,hostN[:portN]]][/[database][?options]]
 *
 * Returns true if the URL was successfully parsed. Returns false if the URL can not be parsed.
 * If the URL is successfully parsed the MongoConfig struct will contain the parsed data. 
 * If the URL is not successfully parsed the information in the MongoConfig struct may be 
 * incomplete and should not be used. 
 */
bool parseMongoDBUrl(out MongoClientSettings cfg, string url)
{
	cfg = new MongoClientSettings();
	
	string tmpUrl = url[0..$]; // Slice of the url (not a copy)
	
	if(!startsWith(tmpUrl, "mongodb://"))
	{
		return false;
	}

	// Reslice to get rid of 'mongodb://'
    tmpUrl = tmpUrl[10..$];
		
	auto slashIndex = countUntil(tmpUrl, "/");
	if( slashIndex == -1 ) slashIndex = tmpUrl.length; 
	auto authIndex = tmpUrl[0 .. slashIndex].countUntil('@');
	sizediff_t hostIndex = 0; // Start of the host portion of the URL.
		
	// Parse out the username and optional password. 
	if( authIndex != -1 )
	{
		// Set the host start to after the '@'
		hostIndex = authIndex + 1;
		
		auto colonIndex = tmpUrl[0..authIndex].countUntil(':');
		if(colonIndex != -1)
		{
			cfg.username = tmpUrl[0..colonIndex];
			cfg.password = tmpUrl[colonIndex + 1 .. authIndex];
		} else {
			cfg.username = tmpUrl[0..authIndex];
		}
			
		// Make sure the username is not empty. If it is then the parse failed. 
		if(cfg.username.length == 0)
		{ 
			return false;
		}
	}
		
	// Parse the hosts section. 
	try 
	{
		auto hostPortEntries = splitter(tmpUrl[hostIndex..slashIndex], ",");
		foreach(entry; hostPortEntries)
		{
			auto hostPort = splitter(entry, ":");
			string host = hostPort.front;
			hostPort.popFront();
			ushort port = 27017; // default port
			if(!hostPort.empty)
			{ 
				port = to!ushort(hostPort.front);
			}
			
			cfg.hosts ~= new MongoHost(host, port);
		}
	} catch ( Exception e) {
		return  false; // Probably failed converting the port to ushort.
	}		
		
	// If we couldn't parse a host we failed.
	if(cfg.hosts.length == 0)
	{
		return false;
	}
	
	if(slashIndex == tmpUrl.length)
	{
		// We're done parsing. 
		return true;
	}
	
	auto queryIndex = tmpUrl[slashIndex..$].countUntil("?");
	if(queryIndex == -1){
		// No query string. Remaining string is the database
		queryIndex = tmpUrl.length;  
	} else {
		queryIndex += slashIndex;
	}
	
	cfg.database = tmpUrl[slashIndex+1..queryIndex];
	if(queryIndex != tmpUrl.length)
	{
		// Parse options if any. They may be separated by ';' or '&'
		auto optionRegex = ctRegex!(`(?P<option>[^=&;]+=[^=&;]+)(?:[&;])?`, "g");
		auto optionMatch = match(tmpUrl[queryIndex+1..$], optionRegex);
		foreach(c; optionMatch)
		{
			auto optionString = c["option"];
			auto separatorIndex = countUntil(optionString, "="); 
			// Per the mongo docs the option names are case insensitive. 
			auto option = optionString[0 .. separatorIndex].toLower();
			auto value = optionString[(separatorIndex+1) .. $];
			switch(option)
			{	
				case "slaveok":
					try 
					{
					 	auto setting = to!bool(value);
						if(setting)	cfg.defQueryFlags |= QueryFlags.SlaveOk;				
					} catch (Exception e) {
						logError("Value for slaveOk must be true or false but was {}", value);
					}
				break;	
				
				case "replicaset":	
				case "safe":
				case "w":
				case "wtimeoutms":
				case "fsync":
				case "journal":
				case "connecttimeoutms":					
				case "sockettimeoutms":
					logWarn("MongoDB option {} not yet implemented.", option);
				break;
					
				// Catch-all				
				default:
					logWarn("Unknown MongoDB option {}", option);
			}
			
			// Store the options in string format in case we want them later.
			cfg.options[option] = value;
		}	
	}
	
	return true;
}

/* Test for parseMongoDBUrl */
unittest 
{
	MongoClientSettings cfg;
	
	assert(parseMongoDBUrl(cfg, "mongodb://localhost"));
	assert(cfg.hosts.length == 1);
	assert(cfg.database == "");
	assert(cfg.options.length == 0);
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);
	
	cfg = MongoClientSettings.init;	
	assert(parseMongoDBUrl(cfg, "mongodb://fred:foobar@localhost"));
	assert(cfg.username == "fred");
	assert(cfg.password == "foobar");
	assert(cfg.hosts.length == 1);
	assert(cfg.database == "");
	assert(cfg.options.length == 0);
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);
	
	cfg = MongoClientSettings.init;	
	assert(parseMongoDBUrl(cfg, "mongodb://fred:@localhost/baz"));
	assert(cfg.username == "fred");
	assert(cfg.password == "");
	assert(cfg.database == "baz");
	assert(cfg.hosts.length == 1);
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);
	assert(cfg.options.length == 0);
	assert(cfg.defQueryFlags == QueryFlags.None);
	
	cfg = MongoClientSettings.init;		
	assert(parseMongoDBUrl(cfg, "mongodb://host1,host2,host3/?safe=true&w=2&wtimeoutMS=2000&slaveOk=false"));
	assert(cfg.username == "");
	assert(cfg.password == "");
	assert(cfg.database == "");
	assert(cfg.hosts.length == 3);
	assert(cfg.hosts[0].name == "host1");
	assert(cfg.hosts[0].port == 27017);
	assert(cfg.hosts[1].name == "host2");
	assert(cfg.hosts[1].port == 27017);
	assert(cfg.hosts[2].name == "host3");
	assert(cfg.hosts[2].port == 27017);
	assert(cfg.options.length == 3);
	assert(cfg.options["safe"] == "true");
	assert(cfg.options["w"] == "2");
	assert(cfg.options["wtimeoutms"] == "2000");
	assert(cfg.options["slaveok"] == "false");
	assert(cfg.defQueryFlags == QueryFlags.None);
	
	cfg = MongoClientSettings.init;		
	assert(parseMongoDBUrl(cfg, 
		"mongodb://fred:flinstone@host1.example.com,host2.other.example.com:27108,host3:"
		"27019/mydb?safe=true;w=2;wtimeoutMS=2000;slaveok=true"));
	assert(cfg.username == "fred");
	assert(cfg.password == "flinstone");
	assert(cfg.database == "mydb");
	assert(cfg.hosts.length == 3);
	assert(cfg.hosts[0].name == "host1.example.com");
	assert(cfg.hosts[0].port == 27017);
	assert(cfg.hosts[1].name == "host2.other.example.com");
	assert(cfg.hosts[1].port == 27108);
	assert(cfg.hosts[2].name == "host3");
	assert(cfg.hosts[2].port == 27019);
	assert(cfg.options.length == 3);
	assert(cfg.options["safe"] == "true");
	assert(cfg.options["w"] == "2");
	assert(cfg.options["wtimeoutms"] == "2000");
	assert(cfg.options["slaveok"] == "true");
	assert(cfg.defQueryFlags & QueryFlags.SlaveOk);
	
	// Invalid URLs - these should fail to parse
	cfg = MongoClientSettings.init;		
	assert(! (parseMongoDBUrl(cfg, "localhost:27018")));
	assert(! (parseMongoDBUrl(cfg, "http://blah")));
	assert(! (parseMongoDBUrl(cfg, "mongodb://@localhost")));
	assert(! (parseMongoDBUrl(cfg, "mongodb://:thepass@localhost")));
	assert(! (parseMongoDBUrl(cfg, "mongodb://:badport/")));
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

class MongoClientSettings
{
	string username;
	string password;
	MongoHost[] hosts;
	string database;
	string[string] options;
	QueryFlags defQueryFlags = QueryFlags.None;
}

class MongoHost
{
	string name;
	ushort port;
	
	this(string hostName, ushort mongoPort)
	{
		name = hostName;
		port = mongoPort;
	}
}
