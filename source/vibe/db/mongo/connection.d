/**
	Low level mongodb protocol.

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.connection;

public import vibe.data.bson;

import vibe.core.log;
import vibe.core.net;
import vibe.db.mongo.settings;
import vibe.inet.webform;
import vibe.stream.tls;

import std.algorithm : map, splitter;
import std.array;
import std.range;
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
alias MongoErrorDescription = immutable(_MongoErrorDescription);

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
final class MongoConnection {
	import vibe.stream.wrapper : StreamOutputRange;

	private {
		MongoClientSettings m_settings;
		TCPConnection m_conn;
		Stream m_stream;
		ulong m_bytesRead;
		int m_msgid = 1;
		StreamOutputRange m_outRange;
	}

	enum ushort defaultPort = MongoClientSettings.defaultPort;

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
			m_conn.tcpNoDelay = true;
			if (m_settings.ssl) {
				auto ctx =  createTLSContext(TLSContextKind.client);
				if (!m_settings.sslverifycertificate) {
					ctx.peerValidationMode = TLSPeerValidationMode.none;
				}
				if (m_settings.sslPEMKeyFile) {
					ctx.useCertificateChainFile(m_settings.sslPEMKeyFile);
					ctx.usePrivateKeyFile(m_settings.sslPEMKeyFile);
				}
				if (m_settings.sslCAFile) {
					ctx.useTrustedCertificateFile(m_settings.sslCAFile);
				}

				m_stream = createTLSStream(m_conn, ctx, m_settings.hosts[0].name);
			}
			else {
				m_stream = m_conn;
			}
			m_outRange = StreamOutputRange(m_stream);
		}
		catch (Exception e) {
			throw new MongoDriverException(format("Failed to connect to MongoDB server at %s:%s.", m_settings.hosts[0].name, m_settings.hosts[0].port), __FILE__, __LINE__, e);
		}

		m_bytesRead = 0;
		if(m_settings.digest != string.init)
		{
			authenticate();
		}
		else if (m_settings.sslPEMKeyFile != null && m_settings.username != null)
		{
			certAuthenticate();
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
		send(OpCode.Update, -1, cast(int)0, collection_name, cast(int)flags, selector, update);
		if (m_settings.safe) checkForError(collection_name);
	}

	void insert(string collection_name, InsertFlags flags, Bson[] documents)
	{
		scope(failure) disconnect();
		foreach (d; documents) if (d["_id"].isNull()) d["_id"] = Bson(BsonObjectID.generate());
		send(OpCode.Insert, -1, cast(int)flags, collection_name, documents);
		if (m_settings.safe) checkForError(collection_name);
	}

	void query(T)(string collection_name, QueryFlags flags, int nskip, int nret, Bson query, Bson returnFieldSelector, scope ReplyDelegate on_msg, scope DocDelegate!T on_doc)
	{
		scope(failure) disconnect();
		flags |= m_settings.defQueryFlags;
		int id;
		if (returnFieldSelector.isNull)
			id = send(OpCode.Query, -1, cast(int)flags, collection_name, nskip, nret, query);
		else
			id = send(OpCode.Query, -1, cast(int)flags, collection_name, nskip, nret, query, returnFieldSelector);
		recvReply!T(id, on_msg, on_doc);
	}

	void getMore(T)(string collection_name, int nret, long cursor_id, scope ReplyDelegate on_msg, scope DocDelegate!T on_doc)
	{
		scope(failure) disconnect();
		auto id = send(OpCode.GetMore, -1, cast(int)0, collection_name, nret, cursor_id);
		recvReply!T(id, on_msg, on_doc);
	}

	void delete_(string collection_name, DeleteFlags flags, Bson selector)
	{
		scope(failure) disconnect();
		send(OpCode.Delete, -1, cast(int)0, collection_name, cast(int)flags, selector);
		if (m_settings.safe) checkForError(collection_name);
	}

	void killCursors(long[] cursors)
	{
		scope(failure) disconnect();
		send(OpCode.KillCursors, -1, cast(int)0, cast(int)cursors.length, cursors);
	}

	MongoErrorDescription getLastError(string db)
	{
		// Though higher level abstraction level by concept, this function
		// is implemented here to allow to check errors upon every request
		// on conncetion level.

		Bson command_and_options = Bson.emptyObject;
		command_and_options["getLastError"] = Bson(1.0);

		if(m_settings.w != m_settings.w.init)
			command_and_options["w"] = m_settings.w; // Already a Bson struct
		if(m_settings.wTimeoutMS != m_settings.wTimeoutMS.init)
			command_and_options["wtimeout"] = Bson(m_settings.wTimeoutMS);
		if(m_settings.journal)
			command_and_options["j"] = Bson(true);
		if(m_settings.fsync)
			command_and_options["fsync"] = Bson(true);

		_MongoErrorDescription ret;

		query!Bson(db ~ ".$cmd", QueryFlags.NoCursorTimeout | m_settings.defQueryFlags,
			0, -1, command_and_options, Bson(null),
			(cursor, flags, first_doc, num_docs) {
				logTrace("getLastEror(%s) flags: %s, cursor: %s, documents: %s", db, flags, cursor, num_docs);
				enforce(!(flags & ReplyFlags.QueryFailure),
					new MongoDriverException(format("MongoDB error: getLastError(%s) call failed.", db))
				);
				enforce(
					num_docs == 1,
					new MongoDriverException(format("getLastError(%s) returned %s documents instead of one.", db, num_docs))
				);
			},
			(idx, ref error) {
				try {
					ret = MongoErrorDescription(
						error.err.opt!string(""),
						error.code.opt!int(-1),
						error.connectionId.opt!int(-1),
						error.n.get!int(),
						error.ok.get!double()
					);
				} catch (Exception e) {
					throw new MongoDriverException(e.msg);
				}
			}
		);

		return ret;
	}

	/** Queries the server for all databases.

		Returns:
			An input range of $(D MongoDBInfo) values.
	*/
	auto listDatabases()
	{
		string cn = (m_settings.database == string.init ? "admin" : m_settings.database) ~ ".$cmd";

		auto cmd = Bson(["listDatabases":Bson(1)]);

		void on_msg(long cursor, ReplyFlags flags, int first_doc, int num_docs) {
			if ((flags & ReplyFlags.QueryFailure))
				throw new MongoDriverException("Calling listDatabases failed.");
		}

		MongoDBInfo toInfo(const(Bson) db_doc) {
			return MongoDBInfo(
				db_doc["name"].get!string,
				db_doc["sizeOnDisk"].get!double,
				db_doc["empty"].get!bool
			);
		}

		typeof((const(Bson)[]).init.map!toInfo) result;
		void on_doc(size_t idx, ref Bson doc) {
			if (doc["ok"].get!double != 1.0)
				throw new MongoAuthException("listDatabases failed.");

			result = doc["databases"].get!(const(Bson)[]).map!toInfo;
		}

		query!Bson(cn, QueryFlags.None, 0, -1, cmd, Bson(null), &on_msg, &on_doc);

		return result;
	}

	private int recvReply(T)(int reqid, scope ReplyDelegate on_msg, scope DocDelegate!T on_doc)
	{
		import std.traits;

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

		scope (exit) {
			if (m_bytesRead - bytes_read < msglen) {
				logWarn("MongoDB reply was longer than expected, skipping the rest: %d vs. %d", msglen, m_bytesRead - bytes_read);
				ubyte[] dst = new ubyte[msglen - cast(size_t)(m_bytesRead - bytes_read)];
				recv(dst);
			} else if (m_bytesRead - bytes_read > msglen) {
				logWarn("MongoDB reply was shorter than expected. Dropping connection.");
				disconnect();
				throw new MongoDriverException("MongoDB reply was too short for data.");
			}
		}

		on_msg(cursor, flags, start, numret);
		foreach (i; 0 .. cast(size_t)numret) {
			// TODO: directly deserialize from the wire
			static if (!hasIndirections!T && !is(T == Bson)) {
				ubyte[256] buf = void;
				auto bson = recvBson(buf);
			} else {
				auto bson = recvBson(null);
			}

			static if (is(T == Bson)) on_doc(i, bson);
			else {
				T doc = deserializeBson!T(bson);
				on_doc(i, doc);
			}
		}

		return resid;
	}

	private int send(ARGS...)(OpCode code, int response_to, ARGS args)
	{
		if( !connected() ) connect();
		int id = nextMessageId();
		sendValue(16 + sendLength(args));
		sendValue(id);
		sendValue(response_to);
		sendValue(cast(int)code);
		foreach (a; args) sendValue(a);
		m_outRange.flush();
		return id;
	}

	private void sendValue(T)(T value)
	{
		import std.traits;
		static if (is(T == int)) sendBytes(toBsonData(value));
		else static if (is(T == long)) sendBytes(toBsonData(value));
		else static if (is(T == Bson)) sendBytes(value.data);
		else static if (is(T == string)) {
			sendBytes(cast(ubyte[])value);
			sendBytes(cast(ubyte[])"\0");
		} else static if (isArray!T) {
			foreach (v; value)
				sendValue(v);
		} else static assert(false, "Unexpected type: "~T.stringof);
	}

	private void sendBytes(in ubyte[] data){ m_outRange.put(data); }

	private int recvInt() { ubyte[int.sizeof] ret; recv(ret); return fromBsonData!int(ret); }
	private long recvLong() { ubyte[long.sizeof] ret; recv(ret); return fromBsonData!long(ret); }
	private Bson recvBson(ubyte[] buf) {
		int len = recvInt();
		if (len > buf.length) buf = new ubyte[len];
		else buf = buf[0 .. len];
		buf[0 .. 4] = toBsonData(len)[];
		recv(buf[4 .. $]);
		return Bson(Bson.Type.Object, cast(immutable)buf);
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

	private void certAuthenticate()
	{
		Bson cmd = Bson.emptyObject;
		cmd["authenticate"] = Bson(1);
		cmd["mechanism"] = Bson("MONGODB-X509");
		cmd["user"] = Bson(m_settings.username);
		query!Bson("$external.$cmd", QueryFlags.None, 0, -1, cmd, Bson(null),
			(cursor, flags, first_doc, num_docs) {
				if ((flags & ReplyFlags.QueryFailure) || num_docs != 1)
					throw new MongoDriverException("Calling authenticate failed.");
			},
			(idx, ref doc) {
				if (doc["ok"].get!double != 1.0)
					throw new MongoAuthException("Authentication failed.");
			}
		);
	}

	private void authenticate()
	{
		string cn = (m_settings.database == string.init ? "admin" : m_settings.database) ~ ".$cmd";

		string nonce, key;

		auto cmd = Bson(["getnonce":Bson(1)]);
		query!Bson(cn, QueryFlags.None, 0, -1, cmd, Bson(null),
			(cursor, flags, first_doc, num_docs) {
				if ((flags & ReplyFlags.QueryFailure) || num_docs != 1)
					throw new MongoDriverException("Calling getNonce failed.");
			},
			(idx, ref doc) {
				if (doc["ok"].get!double != 1.0)
					throw new MongoDriverException("getNonce failed.");
				nonce = doc["nonce"].get!string;
				key = toLower(toHexString(md5Of(nonce ~ m_settings.username ~ m_settings.digest)).idup);
			}
		);

		cmd = Bson.emptyObject;
		cmd["authenticate"] = Bson(1);
		cmd["mechanism"] = Bson("MONGODB-CR");
		cmd["nonce"] = Bson(nonce);
		cmd["user"] = Bson(m_settings.username);
		cmd["key"] = Bson(key);
		query!Bson(cn, QueryFlags.None, 0, -1, cmd, Bson(null),
			(cursor, flags, first_doc, num_docs) {
				if ((flags & ReplyFlags.QueryFailure) || num_docs != 1)
					throw new MongoDriverException("Calling authenticate failed.");
			},
			(idx, ref doc) {
				if (doc["ok"].get!double != 1.0)
					throw new MongoAuthException("Authentication failed.");
			}
		);
	}
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

alias ReplyDelegate = void delegate(long cursor, ReplyFlags flags, int first_doc, int num_docs);
template DocDelegate(T) { alias DocDelegate = void delegate(size_t idx, ref T doc); }

enum UpdateFlags {
	none         = 0,    /// Normal update of a single document.
	upsert       = 1<<0, /// Creates a document if none exists.
	multiUpdate  = 1<<1, /// Updates all matching documents.

	None = none, /// Deprecated compatibility alias
	Upsert = upsert, /// Deprecated compatibility alias
	MultiUpdate = multiUpdate /// Deprecated compatibility alias
}

enum InsertFlags {
	none             = 0,    /// Normal insert.
	continueOnError  = 1<<0, /// For multiple inserted documents, continues inserting further documents after a failure.

	None = none, /// Deprecated compatibility alias
	ContinueOnError = continueOnError /// Deprecated compatibility alias
}

enum QueryFlags {
	none             = 0,    /// Normal query
	tailableCursor   = 1<<1, /// 
	slaveOk          = 1<<2, /// 
	oplogReplay      = 1<<3, /// 
	noCursorTimeout  = 1<<4, /// 
	awaitData        = 1<<5, /// 
	exhaust          = 1<<6, /// 
	partial          = 1<<7, /// 

	None = none, /// Deprecated compatibility alias
	TailableCursor = tailableCursor, /// Deprecated compatibility alias
	SlaveOk = slaveOk, /// Deprecated compatibility alias
	OplogReplay = oplogReplay, /// Deprecated compatibility alias
	NoCursorTimeout = noCursorTimeout, /// Deprecated compatibility alias
	AwaitData = awaitData, /// Deprecated compatibility alias
	Exhaust = exhaust, /// Deprecated compatibility alias
	Partial = partial /// Deprecated compatibility alias
}

enum DeleteFlags {
	none          = 0,
	singleRemove  = 1<<0,

	None = none, /// Deprecated compatibility alias
	SingleRemove = singleRemove /// Deprecated compatibility alias
}

enum ReplyFlags {
	none              = 0,
	cursorNotFound    = 1<<0,
	queryFailure      = 1<<1,
	shardConfigStale  = 1<<2,
	awaitCapable      = 1<<3,

	None = none, /// Deprecated compatibility alias
	CursorNotFound = cursorNotFound, /// Deprecated compatibility alias
	QueryFailure = queryFailure, /// Deprecated compatibility alias
	ShardConfigStale = shardConfigStale, /// Deprecated compatibility alias
	AwaitCapable = awaitCapable /// Deprecated compatibility alias
}

struct MongoDBInfo
{
	string name;
	double sizeOnDisk;
	bool empty;
}

private int sendLength(ARGS...)(ARGS args)
{
	import std.traits;
	static if (ARGS.length == 1) {
		alias T = ARGS[0];
		static if (is(T == string)) return cast(int)args[0].length + 1;
		else static if (is(T == int)) return 4;
		else static if (is(T == long)) return 8;
		else static if (is(T == Bson)) return cast(int)args[0].data.length;
		else static if (isArray!T) {
			int ret = 0;
			foreach (el; args[0]) ret += sendLength(el);
			return ret;
		} else static assert(false, "Unexpected type: "~T.stringof);
	}
	else if (ARGS.length == 0) return 0;
	else return sendLength(args[0 .. $/2]) + sendLength(args[$/2 .. $]);
}
