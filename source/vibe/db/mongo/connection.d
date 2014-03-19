/**
	Low level mongodb protocol.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.connection;

public import vibe.data.bson;

import vibe.core.log;
import vibe.core.net;
import vibe.inet.webform;
import vibe.stream.ssl;

import std.algorithm : splitter;
import std.array;
import std.conv;
import std.exception;
import std.string;
import std.digest.md;


private struct _MongoErrorDescription
{
	string message;
	int code;
	int connectionId;
	int n;
	double ok;
}

/**
 * D POD representation of Mongo error object.
 *
 * For successful queries "code" is negative.
 * Can be used also to check how many documents where updated upon
 * a successful query via "n" field.
 */
alias immutable(_MongoErrorDescription) MongoErrorDescription;

/**
 * Root class for vibe.d Mongo driver exception hierarchy.
 */
class MongoException : Exception
{
	this(string message, string file = __FILE__, int line = __LINE__, Throwable next = null)
	{
		super(message, file, line, next);
	}
}

/**
 * Generic class for all exception related to unhandled driver problems.
 *
 * I.e.: protocol mismatch or unexpected mongo service behavior.
 */
class MongoDriverException : MongoException
{
	this(string message, string file = __FILE__, int line = __LINE__, Throwable next = null)
	{
		super(message, file, line, next);
	}
}

/**
 * Wrapper class for all inner mongo collection manipulation errors.
 *
 * It does not indicate problem with vibe.d driver itself. Most frequently this
 * one is thrown when MongoConnection is in checked mode and getLastError() has something interesting.
 */
class MongoDBException : MongoException
{
	MongoErrorDescription description;
	alias description this;

	this(MongoErrorDescription description, string file = __FILE__,
			int line = __LINE__, Throwable next = null)
	{
		super(description.message, file, line, next);
		this.description = description;
	}
}

/**
 * Generic class for all exceptions related to authentication problems.
 *
 * I.e.: unsupported mechanisms or wrong credentials.
 */
class MongoAuthException : MongoException
{
	this(string message, string file = __FILE__, int line = __LINE__, Throwable next = null)
	{
		super(message, file, line, next);
	}
}

/**
  [internal] Provides low-level mongodb protocol access.

  It is not intended for direct usage. Please use vibe.db.mongo.db and vibe.db.mongo.collection modules for your code.
  Note that a MongoConnection may only be used from one fiber/thread at a time.
 */
class MongoConnection {
	private {
		MongoClientSettings m_settings;
		TCPConnection m_conn;
		Stream m_stream;
		ulong m_bytesRead;
		int m_msgid = 1;
	}

	enum defaultPort = 27017;

	/// Simplified constructor overload, with no m_settings
	this(string server, ushort port = defaultPort)
	{
		m_settings = new MongoClientSettings();
		m_settings.hosts ~= MongoHost(server, port);
	}

	this(MongoClientSettings cfg)
	{
		m_settings = cfg;

		// Now let's check for features that are not yet supported.
		if(m_settings.hosts.length > 1)
			logWarn("Multiple mongodb hosts are not yet supported. Using first one: %s:%s",
					m_settings.hosts[0].name, m_settings.hosts[0].port);
	}

	void connect()
	{
		/*
		 * TODO: Connect to one of the specified hosts taking into consideration
		 * options such as connect timeouts and so on.
		 */
		try {
			m_conn = connectTCP(m_settings.hosts[0].name, m_settings.hosts[0].port);
			if (m_settings.ssl) {
				auto ctx =  new SSLContext(SSLContextKind.client);
				if (!m_settings.sslverifycertificate) {
					ctx.peerValidationMode = SSLPeerValidationMode.none;
				}
				
				m_stream = new SSLStream(m_conn, ctx);
			}
			else {
				m_stream = m_conn;
			}
		}
		catch (Exception e) {
			throw new MongoDriverException(format("Failed to connect to MongoDB server at %s:%s.", m_settings.hosts[0].name, m_settings.hosts[0].port), __FILE__, __LINE__, e);
		}

		m_bytesRead = 0;
		if(m_settings.digest != string.init)
		{
			authenticate();
		}
	}

	void disconnect()
	{
		if (m_stream) {
			m_stream.finalize();
			m_stream = null;
		}

		if (m_conn) {
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
		if(m_settings.safe)
		{
			checkForError(collection_name);
		}
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

		if(m_settings.safe)
		{
			checkForError(collection_name);
		}
	}

	Reply query(string collection_name, QueryFlags flags, int nskip, int nret, Bson query, Bson returnFieldSelector = Bson(null))
	{
		scope(failure) disconnect();
		scope msg = new Message(OpCode.Query);
		msg.addInt(flags | m_settings.defQueryFlags);
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
		if(m_settings.safe)
		{
			checkForError(collection_name);
		}
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

	MongoErrorDescription getLastError(string db)
	{
		// Though higher level abstraction level by concept, this function
		// is implemented here to allow to check errors upon every request
		// on conncetion level.

		Bson[string] command_and_options = [ "getLastError": Bson(1.0) ];

		if(m_settings.w != m_settings.w.init)
			command_and_options["w"] = m_settings.w; // Already a Bson struct
		if(m_settings.wTimeoutMS != m_settings.wTimeoutMS.init)
			command_and_options["wtimeout"] = Bson(m_settings.wTimeoutMS);
		if(m_settings.journal)
			command_and_options["j"] = Bson(true);
		if(m_settings.fsync)
			command_and_options["fsync"] = Bson(true);

		Reply reply = query(db ~ ".$cmd", QueryFlags.NoCursorTimeout | m_settings.defQueryFlags,
				0, -1, serializeToBson(command_and_options));

		logTrace(
				"getLastEror(%s)\n\tResult flags: %s\n\tCursor: %s\n\tDocument count: %s",
				db,
				reply.flags,
				reply.cursor,
				reply.documents.length
				);

		enforce(
			!(reply.flags & ReplyFlags.QueryFailure),
			new MongoDriverException(format(
				"MongoDB error: getLastError(%s) call failed.",
				db
			))
		);

		enforce(
			reply.documents.length == 1,
			new MongoDriverException(format(
				"getLastError(%s) returned %s documents instead of one.",
				db,
				to!string(reply.documents.length)
			))
		);

		auto error = reply.documents[0];

		try
		{
			return MongoErrorDescription(
				error.err.opt!string(""),
				error.code.opt!int(-1),
				error.connectionId.get!int(),
				error.n.get!int(),
				error.ok.get!double()
			);
		}
		catch (Exception e)
		{
			throw new MongoDriverException(e.msg);
		}
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
			throw new MongoDriverException("MongoDB reply was too short for data.");
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
		m_stream.flush();
		return id;
	}

	private void sendInt(int v) { send(toBsonData(v)); }
	private void sendLong(long v) { send(toBsonData(v)); }
	private void send(in ubyte[] data){ m_stream.write(data); }

	private int recvInt() { ubyte[int.sizeof] ret; recv(ret); return fromBsonData!int(ret); }
	private long recvLong() { ubyte[long.sizeof] ret; recv(ret); return fromBsonData!long(ret); }
	private Bson recvBson() {
		int len = recvInt();
		auto bson = new ubyte[len-4];
		recv(bson);
		return Bson(Bson.Type.Object, cast(immutable)(toBsonData(len) ~ bson));
	}
	private void recv(ubyte[] dst) { enforce(m_stream); m_stream.read(dst); m_bytesRead += dst.length; }

	private int nextMessageId() { return m_msgid++; }

	private void checkForError(string collection_name)
	{
		auto coll = collection_name.split(".")[0];
		auto err = getLastError(coll);

		enforce(
			err.code < 0,
			new MongoDBException(err)
		);
	}

	private void authenticate()
	{
		Reply rep;
		Bson cmd, doc;
		string cn = (m_settings.database == string.init ? "admin" : m_settings.database) ~ ".$cmd";

		cmd = Bson(["getnonce":Bson(1)]);
		rep = query(cn, QueryFlags.None, 0, -1, cmd);
		if ((rep.flags & ReplyFlags.QueryFailure) || rep.documents.length != 1)
		{
			throw new MongoDriverException("Calling getNonce failed.");
		}
		doc = rep.documents[0];
		if (doc["ok"].get!double != 1.0)
		{
			throw new MongoDriverException("getNonce failed.");
		}
		string nonce = doc["nonce"].get!string;
		string key = toLower(toHexString(md5Of(nonce ~ m_settings.username ~ m_settings.digest)).idup);
		cmd = Bson.EmptyObject;
		cmd["authenticate"] = Bson(1);
		cmd["nonce"] = Bson(nonce);
		cmd["user"] = Bson(m_settings.username);
		cmd["key"] = Bson(key);
		rep = query(cn, QueryFlags.None, 0, -1, cmd);
		if ((rep.flags & ReplyFlags.QueryFailure) || rep.documents.length != 1)
		{
			throw new MongoDriverException("Calling authenticate failed.");
		}
		doc = rep.documents[0];
		if (doc["ok"].get!double != 1.0)
		{
			throw new MongoAuthException("Authentication failed.");
		}
	}
}

/**
 * Parses the given string as a mongodb URL. The URL must be in the form documented at
 * $(LINK http://www.mongodb.org/display/DOCS/Connections) which is:
 *
 * mongodb://[username:password@]host1[:port1][,host2[:port2],...[,hostN[:portN]]][/[database][?options]]
 *
 * Returns: true if the URL was successfully parsed. False if the URL can not be parsed.
 *
 * If the URL is successfully parsed the MongoClientSettings instance will contain the parsed config.
 * If the URL is not successfully parsed the information in the MongoClientSettings instance may be
 * incomplete and should not be used.
 */
bool parseMongoDBUrl(out MongoClientSettings cfg, string url)
{
	cfg = new MongoClientSettings();

	string tmpUrl = url[0..$]; // Slice of the url (not a copy)

	if( !startsWith(tmpUrl, "mongodb://") )
	{
		return false;
	}

	// Reslice to get rid of 'mongodb://'
	tmpUrl = tmpUrl[10..$];

	auto slashIndex = tmpUrl.indexOf("/");
	if( slashIndex == -1 ) slashIndex = tmpUrl.length;
	auto authIndex = tmpUrl[0 .. slashIndex].indexOf('@');
	sizediff_t hostIndex = 0; // Start of the host portion of the URL.

	// Parse out the username and optional password.
	if( authIndex != -1 )
	{
		// Set the host start to after the '@'
		hostIndex = authIndex + 1;
		string password;

		auto colonIndex = tmpUrl[0..authIndex].indexOf(':');
		if(colonIndex != -1)
		{
			cfg.username = tmpUrl[0..colonIndex];
			password = tmpUrl[colonIndex + 1 .. authIndex];
		} else {
			cfg.username = tmpUrl[0..authIndex];
		}

		// Make sure the username is not empty. If it is then the parse failed.
		if(cfg.username.length == 0)
		{
			return false;
		}

		cfg.digest = MongoClientSettings.makeDigest(cfg.username, password);
	}

	// Parse the hosts section.
	try
	{
		foreach(entry; splitter(tmpUrl[hostIndex..slashIndex], ","))
		{
			auto hostPort = splitter(entry, ":");
			string host = hostPort.front;
			hostPort.popFront();
			ushort port = MongoConnection.defaultPort;
			if (!hostPort.empty) {
				port = to!ushort(hostPort.front);
				hostPort.popFront();
			}
			enforce(hostPort.empty, "Host specifications are expected to be of the form \"HOST:PORT,HOST:PORT,...\".");
			cfg.hosts ~= MongoHost(host, port);
		}
	} catch (Exception e) {
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

	auto queryIndex = tmpUrl[slashIndex..$].indexOf("?");
	if(queryIndex == -1){
		// No query string. Remaining string is the database
		queryIndex = tmpUrl.length;
	} else {
		queryIndex += slashIndex;
	}

	cfg.database = tmpUrl[slashIndex+1..queryIndex];
	if(queryIndex != tmpUrl.length)
	{
		FormFields options;
		parseURLEncodedForm(tmpUrl[queryIndex+1 .. $], options);
		foreach (option, value; options) {
			bool setBool(ref bool dst)
			{
				try {
					dst = to!bool(value);
					return true;
				} catch( Exception e ){
					logError("Value for '%s' must be 'true' or 'false' but was '%s'.", option, value);
					return false;
				}
			}

			bool setLong(ref long dst)
			{
				try {
					dst = to!long(value);
					return true;
				} catch( Exception e ){
					logError("Value for '%s' must be an integer but was '%s'.", option, value);
					return false;
				}
			}

			void warnNotImplemented()
			{
				logWarn("MongoDB option %s not yet implemented.", option);
			}

			switch( option.toLower() ){
				default: logWarn("Unknown MongoDB option %s", option); break;
				case "slaveok": bool v; if( setBool(v) && v ) cfg.defQueryFlags |= QueryFlags.SlaveOk; break;
				case "replicaset": cfg.replicaSet = value; warnNotImplemented(); break;
				case "safe": setBool(cfg.safe); break;
				case "fsync": setBool(cfg.fsync); break;
				case "journal": setBool(cfg.journal); break;
				case "connecttimeoutms": setLong(cfg.connectTimeoutMS); warnNotImplemented(); break;
				case "sockettimeoutms": setLong(cfg.socketTimeoutMS); warnNotImplemented(); break;
				case "ssl": setBool(cfg.ssl); break;
				case "sslverifycertificate": setBool(cfg.sslverifycertificate); break;
				case "wtimeoutms": setLong(cfg.wTimeoutMS); break;
				case "w":
					try {
						if(icmp(value, "majority") == 0){
							cfg.w = Bson("majority");
						} else {
							cfg.w = Bson(to!long(value));
						}
					} catch (Exception e) {
						logError("Invalid w value: [%s] Should be an integer number or 'majority'", value);
					}
				break;
			}
		}

		/* Some m_settings imply safe. If they are set, set safe to true regardless
		 * of what it was set to in the URL string
		 */
		if( (cfg.w != Bson.init) || (cfg.wTimeoutMS != long.init) ||
				cfg.journal 	 || cfg.fsync )
		{
			cfg.safe = true;
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
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);
	assert(cfg.defQueryFlags == QueryFlags.None);
	assert(cfg.replicaSet == "");
	assert(cfg.safe == false);
	assert(cfg.w == Bson.init);
	assert(cfg.wTimeoutMS == long.init);
	assert(cfg.fsync == false);
	assert(cfg.journal == false);
	assert(cfg.connectTimeoutMS == long.init);
	assert(cfg.socketTimeoutMS == long.init);
	assert(cfg.ssl == bool.init);
	assert(cfg.sslverifycertificate == true);

	cfg = MongoClientSettings.init;
	assert(parseMongoDBUrl(cfg, "mongodb://fred:foobar@localhost"));
	assert(cfg.username == "fred");
	//assert(cfg.password == "foobar");
	assert(cfg.digest == MongoClientSettings.makeDigest("fred", "foobar"));
	assert(cfg.hosts.length == 1);
	assert(cfg.database == "");
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);

	cfg = MongoClientSettings.init;
	assert(parseMongoDBUrl(cfg, "mongodb://fred:@localhost/baz"));
	assert(cfg.username == "fred");
	//assert(cfg.password == "");
	assert(cfg.digest == MongoClientSettings.makeDigest("fred", ""));
	assert(cfg.database == "baz");
	assert(cfg.hosts.length == 1);
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);

	cfg = MongoClientSettings.init;
	assert(parseMongoDBUrl(cfg, "mongodb://host1,host2,host3/?safe=true&w=2&wtimeoutMS=2000&slaveOk=true&ssl=true&sslverifycertificate=false"));
	assert(cfg.username == "");
	//assert(cfg.password == "");
	assert(cfg.digest == "");
	assert(cfg.database == "");
	assert(cfg.hosts.length == 3);
	assert(cfg.hosts[0].name == "host1");
	assert(cfg.hosts[0].port == 27017);
	assert(cfg.hosts[1].name == "host2");
	assert(cfg.hosts[1].port == 27017);
	assert(cfg.hosts[2].name == "host3");
	assert(cfg.hosts[2].port == 27017);
	assert(cfg.safe == true);
	assert(cfg.w == Bson(2L));
	assert(cfg.wTimeoutMS == 2000);
	assert(cfg.defQueryFlags == QueryFlags.SlaveOk);
	assert(cfg.ssl == true);
	assert(cfg.sslverifycertificate == false);

	cfg = MongoClientSettings.init;
	assert(parseMongoDBUrl(cfg,
				"mongodb://fred:flinstone@host1.example.com,host2.other.example.com:27108,host3:"
				"27019/mydb?journal=true;fsync=true;connectTimeoutms=1500;sockettimeoutMs=1000;w=majority"));
	assert(cfg.username == "fred");
	//assert(cfg.password == "flinstone");
	assert(cfg.digest == MongoClientSettings.makeDigest("fred", "flinstone"));
	assert(cfg.database == "mydb");
	assert(cfg.hosts.length == 3);
	assert(cfg.hosts[0].name == "host1.example.com");
	assert(cfg.hosts[0].port == 27017);
	assert(cfg.hosts[1].name == "host2.other.example.com");
	assert(cfg.hosts[1].port == 27108);
	assert(cfg.hosts[2].name == "host3");
	assert(cfg.hosts[2].port == 27019);
	assert(cfg.fsync == true);
	assert(cfg.journal == true);
	assert(cfg.connectTimeoutMS == 1500);
	assert(cfg.socketTimeoutMS == 1000);
	assert(cfg.w == Bson("majority"));
	assert(cfg.safe == true);

	// Invalid URLs - these should fail to parse
	cfg = MongoClientSettings.init;
	assert(! (parseMongoDBUrl(cfg, "localhost:27018")));
	assert(! (parseMongoDBUrl(cfg, "http://blah")));
	assert(! (parseMongoDBUrl(cfg, "mongodb://@localhost")));
	assert(! (parseMongoDBUrl(cfg, "mongodb://:thepass@localhost")));
	assert(! (parseMongoDBUrl(cfg, "mongodb://:badport/")));
}

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

/// [internal]
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

/// [internal]
class MongoClientSettings
{
	string username;
	string digest;
	MongoHost[] hosts;
	string database;
	QueryFlags defQueryFlags = QueryFlags.None;
	string replicaSet;
	bool safe;
	Bson w; // Either a number or the string 'majority'
	long wTimeoutMS;
	bool fsync;
	bool journal;
	long connectTimeoutMS;
	long socketTimeoutMS;
	bool ssl;
	bool sslverifycertificate = true;

	static string makeDigest(string username, string password)
	{
		return md5Of(username ~ ":mongo:" ~ password).toHexString().idup.toLower();
	}
}

private struct MongoHost
{
	string name;
	ushort port;
}
