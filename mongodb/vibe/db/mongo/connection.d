/**
	Low level mongodb protocol.

	Copyright: © 2012-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.connection;

public import vibe.data.bson;

import vibe.core.core : vibeVersionString;
import vibe.core.log;
import vibe.core.net;
import vibe.db.mongo.settings;
import vibe.db.mongo.flags;
import vibe.inet.webform;
import vibe.stream.tls;

import std.algorithm : map, splitter;
import std.array;
import std.conv;
import std.digest.md;
import std.exception;
import std.range;
import std.string;
import std.typecons;


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
@safe:

	this(string message, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
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
@safe:

	this(string message, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
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
@safe:

	MongoErrorDescription description;
	alias description this;

	this(MongoErrorDescription description, string file = __FILE__,
			size_t line = __LINE__, Throwable next = null)
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
@safe:

	this(string message, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
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
@safe:

	import vibe.stream.wrapper /* : StreamOutputRange, streamOutputRange */;
	import vibe.internal.interfaceproxy;
	import vibe.core.stream : InputStream, Stream;

	private {
		MongoClientSettings m_settings;
		TCPConnection m_conn;
		InterfaceProxy!Stream m_stream;
		ulong m_bytesRead;
		int m_msgid = 1;
		StreamOutputRange!(InterfaceProxy!Stream) m_outRange;
		ServerDescription m_description;
		/// Flag to prevent recursive connections when server closes connection while connecting
		bool m_allowReconnect;
		bool m_isAuthenticating;
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
		bool isTLS;

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
				isTLS = true;
			}
			else {
				m_stream = m_conn;
			}
			m_outRange = streamOutputRange(m_stream);
		}
		catch (Exception e) {
			throw new MongoDriverException(format("Failed to connect to MongoDB server at %s:%s.", m_settings.hosts[0].name, m_settings.hosts[0].port), __FILE__, __LINE__, e);
		}

		m_allowReconnect = false;
		scope (exit)
			m_allowReconnect = true;

		Bson handshake = Bson.emptyObject;
		handshake["isMaster"] = Bson(1);

		import os = std.system;
		import compiler = std.compiler;
		string platform = compiler.name ~ " "
			~ compiler.version_major.to!string ~ "." ~ compiler.version_minor.to!string;
		// TODO: add support for os.version

		handshake["client"] = Bson([
			"driver": Bson(["name": Bson("vibe.db.mongo"), "version": Bson(vibeVersionString)]),
			"os": Bson(["type": Bson(os.os.to!string), "architecture": Bson(hostArchitecture)]),
			"platform": Bson(platform)
		]);

		if (m_settings.appName.length) {
			enforce!MongoAuthException(m_settings.appName.length <= 128,
				"The application name may not be larger than 128 bytes");
			handshake["client"]["application"] = Bson(["name": Bson(m_settings.appName)]);
		}

		query!Bson("$external.$cmd", QueryFlags.none, 0, -1, handshake, Bson(null),
			(cursor, flags, first_doc, num_docs) {
				enforce!MongoDriverException(!(flags & ReplyFlags.QueryFailure) && num_docs == 1,
					"Authentication handshake failed.");
			},
			(idx, ref doc) {
				enforce!MongoAuthException(doc["ok"].get!double == 1.0, "Authentication failed.");
				m_description = deserializeBson!ServerDescription(doc);
			});

		m_bytesRead = 0;
		auto authMechanism = m_settings.authMechanism;
		if (authMechanism == MongoAuthMechanism.none)
		{
			if (m_settings.sslPEMKeyFile != null && m_description.satisfiesVersion(WireVersion.v26))
			{
				authMechanism = MongoAuthMechanism.mongoDBX509;
			}
			else if (m_settings.digest.length)
			{
				// SCRAM-SHA-1 default since 3.0, otherwise use legacy authentication
				if (m_description.satisfiesVersion(WireVersion.v30))
					authMechanism = MongoAuthMechanism.scramSHA1;
				else
					authMechanism = MongoAuthMechanism.mongoDBCR;
			}
		}

		if (authMechanism == MongoAuthMechanism.mongoDBCR && m_description.satisfiesVersion(WireVersion.v40))
			throw new MongoAuthException("Trying to force MONGODB-CR authentication on a >=4.0 server not supported");

		if (authMechanism == MongoAuthMechanism.scramSHA1 && !m_description.satisfiesVersion(WireVersion.v30))
			throw new MongoAuthException("Trying to force SCRAM-SHA-1 authentication on a <3.0 server not supported");

		if (authMechanism == MongoAuthMechanism.mongoDBX509 && !m_description.satisfiesVersion(WireVersion.v26))
			throw new MongoAuthException("Trying to force MONGODB-X509 authentication on a <2.6 server not supported");

		if (authMechanism == MongoAuthMechanism.mongoDBX509 && !isTLS)
			throw new MongoAuthException("Trying to force MONGODB-X509 authentication, but didn't use ssl!");

		m_isAuthenticating = true;
		scope (exit)
			m_isAuthenticating = false;
		final switch (authMechanism)
		{
		case MongoAuthMechanism.none:
			break;
		case MongoAuthMechanism.mongoDBX509:
			certAuthenticate();
			break;
		case MongoAuthMechanism.scramSHA1:
			scramAuthenticate();
			break;
		case MongoAuthMechanism.mongoDBCR:
			authenticate();
			break;
		}
	}

	void disconnect()
	{
		if (m_conn) {
			if (m_stream && m_conn.connected) {
				m_outRange.flush();

				m_stream.finalize();
				m_stream = InterfaceProxy!Stream.init;
			}

			m_conn.close();
			m_conn = TCPConnection.init;
		}

		m_outRange.drop();
	}

	@property bool connected() const { return m_conn && m_conn.connected; }

	@property const(ServerDescription) description() const { return m_description; }

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
		// on connection level.

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
						error["err"].opt!string(""),
						error["code"].opt!int(-1),
						error["connectionId"].opt!int(-1),
						error["n"].get!int(),
						error["ok"].get!double()
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

		static MongoDBInfo toInfo(const(Bson) db_doc) {
			return MongoDBInfo(
				db_doc["name"].get!string,
				db_doc["sizeOnDisk"].get!double,
				db_doc["empty"].get!bool
			);
		}

		Bson result;
		void on_doc(size_t idx, ref Bson doc) {
			if (doc["ok"].get!double != 1.0)
				throw new MongoAuthException("listDatabases failed.");

			result = doc["databases"];
		}

		query!Bson(cn, QueryFlags.None, 0, -1, cmd, Bson(null), &on_msg, &on_doc);

		return result.byValue.map!toInfo;
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
		static if (hasIndirections!T || is(T == Bson))
			auto buf = new ubyte[msglen - cast(size_t)(m_bytesRead - bytes_read)];
		foreach (i; 0 .. cast(size_t)numret) {
			// TODO: directly deserialize from the wire
			static if (!hasIndirections!T && !is(T == Bson)) {
				ubyte[256] buf = void;
				ubyte[] bufsl = buf;
				auto bson = () @trusted { return recvBson(bufsl); } ();
			} else {
				auto bson = () @trusted { return recvBson(buf); } ();
			}

			// logDebugV("Received mongo response on %s:%s: %s", reqid, i, bson);

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
		if( !connected() ) {
			if (m_allowReconnect) connect();
			else if (m_isAuthenticating) throw new MongoAuthException("Connection got closed while authenticating");
			else throw new MongoDriverException("Connection got closed while connecting");
		}
		int id = nextMessageId();
		// sendValue!int to make sure we don't accidentally send other types after arithmetic operations/changing types
		sendValue!int(16 + sendLength(args));
		sendValue!int(id);
		sendValue!int(response_to);
		sendValue!int(cast(int)code);
		foreach (a; args) sendValue(a);
		m_outRange.flush();
		// logDebugV("Sent mongo opcode %s (id %s) in response to %s with args %s", code, id, response_to, tuple(args));
		return id;
	}

	private void sendValue(T)(T value)
	{
		import std.traits;
		static if (is(T == int)) sendBytes(toBsonData(value));
		else static if (is(T == long)) sendBytes(toBsonData(value));
		else static if (is(T == Bson)) sendBytes(value.data);
		else static if (is(T == string)) {
			sendBytes(cast(const(ubyte)[])value);
			sendBytes(cast(const(ubyte)[])"\0");
		} else static if (isArray!T) {
			foreach (v; value)
				sendValue(v);
		} else static assert(false, "Unexpected type: "~T.stringof);
	}

	private void sendBytes(in ubyte[] data){ m_outRange.put(data); }

	private int recvInt() { ubyte[int.sizeof] ret; recv(ret); return fromBsonData!int(ret); }
	private long recvLong() { ubyte[long.sizeof] ret; recv(ret); return fromBsonData!long(ret); }
	private Bson recvBson(ref ubyte[] buf)
	@system {
		int len = recvInt();
		ubyte[] dst;
		if (len > buf.length) dst = new ubyte[len];
		else {
			dst = buf[0 .. len];
			buf = buf[len .. $];
		}
		dst[0 .. 4] = toBsonData(len)[];
		recv(dst[4 .. $]);
		return Bson(Bson.Type.Object, cast(immutable)dst);
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
		if (m_description.satisfiesVersion(WireVersion.v34))
		{
			if (m_settings.username.length)
				cmd["user"] = Bson(m_settings.username);
		}
		else
		{
			if (!m_settings.username.length)
				throw new MongoAuthException("No username provided but connected to MongoDB server <=3.2 not supporting this");

			cmd["user"] = Bson(m_settings.username);
		}
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

	private void scramAuthenticate()
	{
		import vibe.db.mongo.sasl;
		string cn = (m_settings.database == string.init ? "admin" : m_settings.database) ~ ".$cmd";

		ScramState state;
		string payload = state.createInitialRequest(m_settings.username);

		auto cmd = Bson.emptyObject;
		cmd["saslStart"] = Bson(1);
		cmd["mechanism"] = Bson("SCRAM-SHA-1");
		cmd["payload"] = Bson(BsonBinData(BsonBinData.Type.generic, payload.representation));
		string response;
		Bson conversationId;
		query!Bson(cn, QueryFlags.None, 0, -1, cmd, Bson(null),
			(cursor, flags, first_doc, num_docs) {
				if ((flags & ReplyFlags.QueryFailure) || num_docs != 1)
					throw new MongoDriverException("SASL start failed.");
			},
			(idx, ref doc) {
				if (doc["ok"].get!double != 1.0)
					throw new MongoAuthException("Authentication failed.");
				response = cast(string)doc["payload"].get!BsonBinData().rawData;
				conversationId = doc["conversationId"];
			});
		payload = state.update(m_settings.digest, response);
		cmd = Bson.emptyObject;
		cmd["saslContinue"] = Bson(1);
		cmd["conversationId"] = conversationId;
		cmd["payload"] = Bson(BsonBinData(BsonBinData.Type.generic, payload.representation));
		query!Bson(cn, QueryFlags.None, 0, -1, cmd, Bson(null),
			(cursor, flags, first_doc, num_docs) {
				if ((flags & ReplyFlags.QueryFailure) || num_docs != 1)
					throw new MongoDriverException("SASL continue failed.");
			},
			(idx, ref doc) {
				if (doc["ok"].get!double != 1.0)
					throw new MongoAuthException("Authentication failed.");
				response = cast(string)doc["payload"].get!BsonBinData().rawData;
			});

		payload = state.finalize(response);
		cmd = Bson.emptyObject;
		cmd["saslContinue"] = Bson(1);
		cmd["conversationId"] = conversationId;
		cmd["payload"] = Bson(BsonBinData(BsonBinData.Type.generic, payload.representation));
		query!Bson(cn, QueryFlags.None, 0, -1, cmd, Bson(null),
			(cursor, flags, first_doc, num_docs) {
				if ((flags & ReplyFlags.QueryFailure) || num_docs != 1)
					throw new MongoDriverException("SASL finish failed.");
			},
			(idx, ref doc) {
				if (doc["ok"].get!double != 1.0)
					throw new MongoAuthException("Authentication failed.");
			});
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

alias ReplyDelegate = void delegate(long cursor, ReplyFlags flags, int first_doc, int num_docs) @safe;
template DocDelegate(T) { alias DocDelegate = void delegate(size_t idx, ref T doc) @safe; }

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

struct ServerDescription
{
	enum ServerType
	{
		unknown,
		standalone,
		mongos,
		possiblePrimary,
		RSPrimary,
		RSSecondary,
		RSArbiter,
		RSOther,
		RSGhost
	}

@optional:
	string address;
	string error;
	float roundTripTime = 0;
	Nullable!BsonDate lastWriteDate;
	Nullable!BsonObjectID opTime;
	ServerType type = ServerType.unknown;
	WireVersion minWireVersion, maxWireVersion;
	string me;
	string[] hosts, passives, arbiters;
	string[string] tags;
	string setName;
	Nullable!int setVersion;
	Nullable!BsonObjectID electionId;
	string primary;
	string lastUpdateTime = "infinity ago";
	Nullable!int logicalSessionTimeoutMinutes;

	bool satisfiesVersion(WireVersion wireVersion) @safe const @nogc pure nothrow
	{
		return maxWireVersion >= wireVersion;
	}
}

enum WireVersion : int
{
	old,
	v26,
	v26_2,
	v30,
	v32,
	v34,
	v36,
	v40,
	v42
}

private string getHostArchitecture()
{
	import os = std.system;

	version (X86_64)
		string arch = "x86_64 ";
	else version (X86)
		string arch = "x86 ";
	else version (AArch64)
		string arch = "aarch64 ";
	else version (ARM_HardFloat)
		string arch = "armhf ";
	else version (ARM)
		string arch = "arm ";
	else version (PPC64)
		string arch = "ppc64 ";
	else version (PPC)
		string arch = "ppc ";
	else
		string arch = "unknown ";

	return arch ~ os.endian.to!string;
}

private static immutable hostArchitecture = getHostArchitecture;
