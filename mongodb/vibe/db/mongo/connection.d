/**
	Low level mongodb protocol.

	Copyright: © 2012-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.connection;

// /// prints ALL modern OP_MSG queries and legacy runCommand invocations to logDiagnostic
// debug = VibeVerboseMongo;

public import vibe.data.bson;

import vibe.core.core : vibeVersionString;
import vibe.core.log;
import vibe.core.net;
import vibe.data.bson;
import vibe.db.mongo.flags;
import vibe.db.mongo.settings;
import vibe.inet.webform;
import vibe.stream.tls;

import std.algorithm : findSplit, map, splitter;
import std.array;
import std.conv;
import std.digest.md;
import std.exception;
import std.range;
import std.string;
import std.traits : hasIndirections;
import std.typecons;

import core.time;

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
deprecated("Check for MongoException instead - the modern write commands now throw MongoBulkWriteException on error")
class MongoDBException : MongoException
{
@safe:

	MongoErrorDescription description;

	this(MongoErrorDescription description, string file = __FILE__,
			size_t line = __LINE__, Throwable next = null)
	{
		super(description.message, file, line, next);
		this.description = description;
	}

	// NOTE: .message is a @future member of Throwable
	deprecated("Use .msg instead.") alias message = msg;
	@property int code() const nothrow { return description.code; };
	@property int connectionId() const nothrow { return description.connectionId; };
	@property int n() const nothrow { return description.n; };
	@property double ok() const nothrow { return description.ok; };
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
		bool m_supportsOpMsg;
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
			import core.time : Duration, msecs;

			auto connectTimeout = m_settings.connectTimeoutMS.msecs;
			if (m_settings.connectTimeoutMS == 0)
				connectTimeout = Duration.max;

			m_conn = connectTCP(m_settings.hosts[0].name, m_settings.hosts[0].port, null, 0, connectTimeout);
			m_conn.tcpNoDelay = true;
			if (m_settings.socketTimeout != Duration.zero)
				m_conn.readTimeout = m_settings.socketTimeout;
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

		scope (failure) disconnect();

		m_allowReconnect = false;
		scope (exit)
			m_allowReconnect = true;

		Bson handshake = Bson.emptyObject;
		static assert(!is(typeof(m_settings.loadBalanced)), "loadBalanced was added to the API, set legacy if it's true here!");
		// TODO: must use legacy handshake if m_settings.loadBalanced is true
		// and also once we allow configuring a server API version in the driver
		// (https://github.com/mongodb/specifications/blob/master/source/versioned-api/versioned-api.rst)
		m_supportsOpMsg = false;
		bool legacyHandshake = false;
		if (legacyHandshake)
		{
			handshake["isMaster"] = Bson(1);
			handshake["helloOk"] = Bson(1);
		}
		else
		{
			handshake["hello"] = Bson(1);
			m_supportsOpMsg = true;
		}

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

		auto reply = runCommand!(Bson, MongoAuthException)("admin", handshake);
		m_description = deserializeBson!ServerDescription(reply);

		if (m_description.satisfiesVersion(WireVersion.v36))
			m_supportsOpMsg = true;

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

	deprecated("Non-functional since MongoDB 5.1") void update(string collection_name, UpdateFlags flags, Bson selector, Bson update)
	{
		scope(failure) disconnect();
		send(OpCode.Update, -1, cast(int)0, collection_name, cast(int)flags, selector, update);
		if (m_settings.safe) checkForError(collection_name);
	}

	deprecated("Non-functional since MongoDB 5.1") void insert(string collection_name, InsertFlags flags, Bson[] documents)
	{
		scope(failure) disconnect();
		foreach (d; documents) if (d["_id"].isNull()) d["_id"] = Bson(BsonObjectID.generate());
		send(OpCode.Insert, -1, cast(int)flags, collection_name, documents);
		if (m_settings.safe) checkForError(collection_name);
	}

	deprecated("Non-functional since MongoDB 5.1: use `find` to query collections instead - instead of `$cmd` use `runCommand` to send commands - use listIndexes and listCollections instead of `<database>.system.indexes` and `<database>.system.namsepsaces`")
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

	/**
		Runs the given Bson command (Bson object with the first entry in the map
		being the command name) on the given database.

		Using `runCommand` checks that the command completed successfully by
		checking that `result["ok"].get!double == 1.0`. Throws the
		`CommandFailException` on failure.

		Using `runCommandUnchecked` will return the result as-is. Developers may
		check the `result["ok"]` value themselves. (It's a double that needs to
		be compared with 1.0 by default)

		Throws:
			- `CommandFailException` (template argument) only in the
				`runCommand` overload, when the command response is not ok.
			- `MongoDriverException` when internal protocol errors occur.
	*/
	Bson runCommand(T, CommandFailException = MongoDriverException)(
		string database,
		Bson command,
		string errorInfo = __FUNCTION__,
		string errorFile = __FILE__,
		size_t errorLine = __LINE__
	)
	in(database.length, "runCommand requires a database argument")
	{
		return runCommandImpl!(T, CommandFailException)(
			database, command, true, errorInfo, errorFile, errorLine);
	}

	Bson runCommandUnchecked(T, CommandFailException = MongoDriverException)(
		string database,
		Bson command,
		string errorInfo = __FUNCTION__,
		string errorFile = __FILE__,
		size_t errorLine = __LINE__
	)
	in(database.length, "runCommand requires a database argument")
	{
		return runCommandImpl!(T, CommandFailException)(
			database, command, false, errorInfo, errorFile, errorLine);
	}

	private Bson runCommandImpl(T, CommandFailException)(
		string database,
		Bson command,
		bool testOk = true,
		string errorInfo = __FUNCTION__,
		string errorFile = __FILE__,
		size_t errorLine = __LINE__
	)
	in(database.length, "runCommand requires a database argument")
	{
		import std.array;

		string formatErrorInfo(string msg) @safe
		{
			return text(msg, " in ", errorInfo, " (", errorFile, ":", errorLine, ")");
		}

		Bson ret;

		if (m_supportsOpMsg)
		{
			debug (VibeVerboseMongo)
				logDiagnostic("runCommand: [db=%s] %s", database, command);

			command["$db"] = Bson(database);

			auto id = sendMsg(-1, 0, command);
			Appender!(Bson[])[string] docs;
			recvMsg!true(id, (flags, root) @safe {
				ret = root;
			}, (scope ident, size) @safe {
				docs[ident.idup] = appender!(Bson[]);
			}, (scope ident, push) @safe {
				auto pd = ident in docs;
				assert(!!pd, "Received data for unexpected identifier");
				pd.put(push);
			});

			foreach (ident, app; docs)
				ret[ident] = Bson(app.data);
		}
		else
		{
			debug (VibeVerboseMongo)
				logDiagnostic("runCommand(legacy): [db=%s] %s", database, command);
			auto id = send(OpCode.Query, -1, 0, database ~ ".$cmd", 0, -1, command, Bson(null));
			recvReply!T(id,
				(cursor, flags, first_doc, num_docs) {
					logTrace("runCommand(%s) flags: %s, cursor: %s, documents: %s", database, flags, cursor, num_docs);
					enforce!MongoDriverException(!(flags & ReplyFlags.QueryFailure), formatErrorInfo("command query failed"));
					enforce!MongoDriverException(num_docs == 1, formatErrorInfo("received more than one document in command response"));
				},
				(idx, ref doc) {
					ret = doc;
				});
		}

		if (testOk && ret["ok"].get!double != 1.0)
			throw new CommandFailException(formatErrorInfo("command failed: "
				~ ret["errmsg"].opt!string("(no message)")));

		static if (is(T == Bson)) return ret;
		else {
			T doc = deserializeBson!T(bson);
			return doc;
		}
	}

	template getMore(T)
	{
		deprecated("use the modern overload instead")
		void getMore(string collection_name, int nret, long cursor_id, scope ReplyDelegate on_msg, scope DocDelegate!T on_doc)
		{
			scope(failure) disconnect();
			auto parts = collection_name.findSplit(".");
			auto id = send(OpCode.GetMore, -1, cast(int)0, parts[0], parts[2], nret, cursor_id);
			recvReply!T(id, on_msg, on_doc);
		}

		/**
		* Modern (MongoDB 3.2+ compatible) getMore implementation using the getMore
		* command and OP_MSG. (if supported)
		*
		* Falls back to compatibility for older MongoDB versions, but those are not
		* officially supported anymore.
		*
		* Upgrade_notes:
		* - error checking is now done inside this function
		* - document index is no longer sent, instead the callback is called sequentially
		*
		* Throws: $(LREF MongoDriverException) in case the command fails.
		*/
		void getMore(long cursor_id, string database, string collection_name, long nret,
			scope GetMoreHeaderDelegate on_header,
			scope GetMoreDocumentDelegate!T on_doc,
			Duration timeout = Duration.max,
			string errorInfo = __FUNCTION__, string errorFile = __FILE__, size_t errorLine = __LINE__)
		{
			Bson command = Bson.emptyObject;
			command["getMore"] = Bson(cursor_id);
			command["$db"] = Bson(database);
			command["collection"] = Bson(collection_name);
			if (nret > 0)
				command["batchSize"] = Bson(nret);
			if (timeout != Duration.max && timeout.total!"msecs" < int.max)
				command["maxTimeMS"] = Bson(cast(int)timeout.total!"msecs");

			string formatErrorInfo(string msg) @safe
			{
				return text(msg, " in ", errorInfo, " (", errorFile, ":", errorLine, ")");
			}

			scope (failure) disconnect();

			if (m_supportsOpMsg)
			{
				startFind!T(command, on_header, on_doc, "nextBatch", errorInfo ~ " (getMore)", errorFile, errorLine);
			}
			else
			{
				debug (VibeVerboseMongo)
					logDiagnostic("getMore(legacy): [db=%s] collection=%s, cursor=%s, nret=%s", database, collection_name, cursor_id, nret);

				int brokenId = 0;
				int nextId = 0;
				int num_docs;
				// array to store out-of-order items, to push them into the callback properly
				T[] compatibilitySort;
				string full_name = database ~ '.' ~ collection_name;
				auto id = send(OpCode.GetMore, -1, cast(int)0, full_name, nret, cursor_id);
				recvReply!T(id, (long cursor, ReplyFlags flags, int first_doc, int num_docs)
				{
					enforce!MongoDriverException(!(flags & ReplyFlags.CursorNotFound),
						formatErrorInfo("Invalid cursor handle."));
					enforce!MongoDriverException(!(flags & ReplyFlags.QueryFailure),
						formatErrorInfo("Query failed. Does the database exist?"));

					on_header(cursor, full_name, num_docs);
				}, (size_t idx, ref T doc) {
					if (cast(int)idx == nextId) {
						on_doc(doc);
						nextId++;
						brokenId = nextId;
					} else {
						enforce!MongoDriverException(idx >= brokenId,
							formatErrorInfo("Got legacy document with same id after having already processed it!"));
						enforce!MongoDriverException(idx < num_docs,
							formatErrorInfo("Received more documents than the database reported to us"));

						size_t arrayIndex = cast(int)idx - brokenId;
						if (!compatibilitySort.length)
							compatibilitySort.length = num_docs - brokenId;
						compatibilitySort[arrayIndex] = doc;
					}
				});

				foreach (doc; compatibilitySort)
					on_doc(doc);
			}
		}
	}

	/// Forwards the `find` command passed in to the database, handles the
	/// callbacks like with getMore. This exists for easier integration with
	/// MongoCursor!T.
	package void startFind(T)(Bson command,
		scope GetMoreHeaderDelegate on_header,
		scope GetMoreDocumentDelegate!T on_doc,
		string batchKey = "firstBatch",
		string errorInfo = __FUNCTION__, string errorFile = __FILE__, size_t errorLine = __LINE__)
	{
		string formatErrorInfo(string msg) @safe
		{
			return text(msg, " in ", errorInfo, " (", errorFile, ":", errorLine, ")");
		}

		scope (failure) disconnect();

		enforce!MongoDriverException(m_supportsOpMsg, formatErrorInfo("Database does not support required OP_MSG for new style queries"));

		enum needsDup = hasIndirections!T || is(T == Bson);

		debug (VibeVerboseMongo)
			logDiagnostic("%s: %s", errorInfo, command);

		auto id = sendMsg(-1, 0, command);
		recvMsg!needsDup(id, (flags, scope root) @safe {
			if (root["ok"].get!double != 1.0)
				throw new MongoDriverException(formatErrorInfo("error response: "
					~ root["errmsg"].opt!string("(no message)")));

			auto cursor = root["cursor"];
			if (cursor.type == Bson.Type.null_)
				throw new MongoDriverException(formatErrorInfo("no cursor in response: "
					~ root["errmsg"].opt!string("(no error message)")));
			auto batch = cursor[batchKey].get!(Bson[]);
			on_header(cursor["id"].get!long, cursor["ns"].get!string, batch.length);

			foreach (ref push; batch)
			{
				T doc = deserializeBson!T(push);
				on_doc(doc);
			}
		}, (scope ident, size) @safe {}, (scope ident, scope push) @safe {
			throw new MongoDriverException(formatErrorInfo("unexpected section type 1 in response"));
		});
	}

	deprecated("Non-functional since MongoDB 5.1") void delete_(string collection_name, DeleteFlags flags, Bson selector)
	{
		scope(failure) disconnect();
		send(OpCode.Delete, -1, cast(int)0, collection_name, cast(int)flags, selector);
		if (m_settings.safe) checkForError(collection_name);
	}

	deprecated("Non-functional since MongoDB 5.1, use the overload taking the collection as well")
	void killCursors(scope long[] cursors)
	{
		scope(failure) disconnect();
		send(OpCode.KillCursors, -1, cast(int)0, cast(int)cursors.length, cursors);
	}

	void killCursors(string collection, scope long[] cursors)
	{
		scope(failure) disconnect();
		// TODO: could add special case to runCommand to not return anything
		if (m_supportsOpMsg)
		{
			Bson command = Bson.emptyObject;
			auto parts = collection.findSplit(".");
			if (!parts[2].length)
				throw new MongoDriverException(
					"Attempted to call killCursors with non-fully-qualified collection name: '"
					~ collection ~ "'");
			command["killCursors"] = Bson(parts[2]);
			command["cursors"] = () @trusted { return cursors; } ().serializeToBson; // NOTE: "escaping" scope here
			runCommand!Bson(parts[0], command);
		}
		else
		{
			send(OpCode.KillCursors, -1, cast(int)0, cast(int)cursors.length, cursors);
		}
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

		auto error = runCommandUnchecked!Bson(db, command_and_options);

		try {
			ret = MongoErrorDescription(
				error["errmsg"].opt!string(error["err"].opt!string("")),
				error["code"].opt!int(-1),
				error["connectionId"].opt!int(-1),
				error["n"].opt!int(-1),
				error["ok"].get!double()
			);
		} catch (Exception e) {
			throw new MongoDriverException(e.msg);
		}

		return ret;
	}

	/** Queries the server for all databases.

		Returns:
			An input range of $(D MongoDBInfo) values.
	*/
	auto listDatabases()
	{
		string cn = m_settings.database == string.init ? "admin" : m_settings.database;

		auto cmd = Bson(["listDatabases":Bson(1)]);

		static MongoDBInfo toInfo(const(Bson) db_doc) {
			return MongoDBInfo(
				db_doc["name"].get!string,
				// double on MongoDB < 5.0, long afterwards
				db_doc["sizeOnDisk"].to!double,
				db_doc["empty"].get!bool
			);
		}

		auto result = runCommand!Bson(cn, cmd)["databases"];

		return result.byValue.map!toInfo;
	}

	private int recvMsg(bool dupBson = true)(int reqid,
		scope MsgReplyDelegate!dupBson on_sec0,
		scope MsgSection1StartDelegate on_sec1_start,
		scope MsgSection1Delegate!dupBson on_sec1_doc)
	{
		import std.traits;

		auto bytes_read = m_bytesRead;
		int msglen = recvInt();
		int resid = recvInt();
		int respto = recvInt();
		int opcode = recvInt();

		enforce!MongoDriverException(respto == reqid, "Reply is not for the expected message on a sequential connection!");
		enforce!MongoDriverException(opcode == OpCode.Msg, "Got wrong reply type! (must be OP_MSG)");

		uint flagBits = recvUInt();
		const bool hasCRC = (flagBits & (1 << 16)) != 0;

		int sectionLength = cast(int)(msglen - 4 * int.sizeof - flagBits.sizeof);
		if (hasCRC)
			sectionLength -= uint.sizeof; // CRC present

		bool gotSec0;
		while (m_bytesRead - bytes_read < sectionLength) {
			// TODO: directly deserialize from the wire
			static if (!dupBson) {
				ubyte[256] buf = void;
				ubyte[] bufsl = buf;
			}

			ubyte payloadType = recvUByte();
			switch (payloadType) {
				case 0:
					gotSec0 = true;
					static if (dupBson)
						auto data = recvBsonDup();
					else
						scope data = (() @trusted => recvBson(bufsl))();

					debug (VibeVerboseMongo)
						logDiagnostic("recvData: sec0[flags=%x]: %s", flagBits, data);
					on_sec0(flagBits, data);
					break;
				case 1:
					if (!gotSec0)
						throw new MongoDriverException("Got OP_MSG section 1 before section 0, which is not supported by vibe.d");

					auto section_bytes_read = m_bytesRead;
					int size = recvInt();
					auto identifier = recvCString();
					on_sec1_start(identifier, size);
					while (m_bytesRead - section_bytes_read < size) {
						static if (dupBson)
							auto data = recvBsonDup();
						else
							scope data = (() @trusted => recvBson(bufsl))();

						debug (VibeVerboseMongo)
							logDiagnostic("recvData: sec1[%s]: %s", identifier, data);

						on_sec1_doc(identifier, data);
					}
					break;
				default:
					throw new MongoDriverException("Received unexpected payload section type " ~ payloadType.to!string);
			}
		}

		if (hasCRC)
		{
			uint crc = recvUInt();
			// TODO: validate CRC
			logDiagnostic("recvData: crc=%s (discarded)", crc);
		}

		assert(bytes_read + msglen == m_bytesRead,
			format!"Packet size mismatch! Expected %s bytes, but read %s."(
				msglen, m_bytesRead - bytes_read));

		return resid;
	}

	private int recvReply(T)(int reqid, scope ReplyDelegate on_msg, scope DocDelegate!T on_doc)
	{
		auto bytes_read = m_bytesRead;
		int msglen = recvInt();
		int resid = recvInt();
		int respto = recvInt();
		int opcode = recvInt();

		enforce!MongoDriverException(respto == reqid, "Reply is not for the expected message on a sequential connection!");
		enforce!MongoDriverException(opcode == OpCode.Reply, "Got a non-'Reply' reply!");

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

	private int send(ARGS...)(OpCode code, int response_to, scope ARGS args)
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

	private int sendMsg(int response_to, uint flagBits, Bson document)
	{
		if( !connected() ) {
			if (m_allowReconnect) connect();
			else if (m_isAuthenticating) throw new MongoAuthException("Connection got closed while authenticating");
			else throw new MongoDriverException("Connection got closed while connecting");
		}
		int id = nextMessageId();
		// sendValue!int to make sure we don't accidentally send other types after arithmetic operations/changing types
		sendValue!int(21 + sendLength(document));
		sendValue!int(id);
		sendValue!int(response_to);
		sendValue!int(cast(int)OpCode.Msg);
		sendValue!uint(flagBits);
		const bool hasCRC = (flagBits & (1 << 16)) != 0;
		assert(!hasCRC, "sending with CRC bits not yet implemented");
		sendValue!ubyte(0);
		sendValue(document);
		m_outRange.flush();
		return id;
	}

	private void sendValue(T)(scope T value)
	{
		import std.traits;
		static if (is(T == ubyte)) m_outRange.put(value);
		else static if (is(T == int) || is(T == uint)) sendBytes(toBsonData(value));
		else static if (is(T == long)) sendBytes(toBsonData(value));
		else static if (is(T == Bson)) sendBytes(() @trusted { return value.data; } ());
		else static if (is(T == string)) {
			sendBytes(cast(const(ubyte)[])value);
			sendBytes(cast(const(ubyte)[])"\0");
		} else static if (isArray!T) {
			foreach (v; value)
				sendValue(v);
		} else static assert(false, "Unexpected type: "~T.stringof);
	}

	private void sendBytes(scope const(ubyte)[] data){ m_outRange.put(data); }

	private T recvInteger(T)() { ubyte[T.sizeof] ret; recv(ret); return fromBsonData!T(ret); }
	private alias recvUByte = recvInteger!ubyte;
	private alias recvInt = recvInteger!int;
	private alias recvUInt = recvInteger!uint;
	private alias recvLong = recvInteger!long;
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
		return Bson(Bson.Type.object, cast(immutable)dst);
	}
	private Bson recvBsonDup()
	@trusted {
		ubyte[4] size;
		recv(size[]);
		ubyte[] dst = new ubyte[fromBsonData!uint(size)];
		dst[0 .. 4] = size;
		recv(dst[4 .. $]);
		return Bson(Bson.Type.object, cast(immutable)dst);
	}
	private void recv(scope ubyte[] dst) { enforce(m_stream); m_stream.read(dst); m_bytesRead += dst.length; }
	private const(char)[] recvCString()
	{
		auto buf = new ubyte[32];
		ptrdiff_t i = -1;
		do
		{
			i++;
			if (i == buf.length) buf.length *= 2;
			recv(buf[i .. i + 1]);
		} while (buf[i] != 0);
		return cast(const(char)[])buf[0 .. i];
	}

	private int nextMessageId() { return m_msgid++; }

	deprecated private void checkForError(string collection_name)
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
		runCommand!(Bson, MongoAuthException)(m_settings.getAuthDatabase, cmd);
	}

	private void authenticate()
	{
		scope (failure) disconnect();

		string cn = m_settings.getAuthDatabase;

		auto cmd = Bson(["getnonce": Bson(1)]);
		auto result = runCommand!(Bson, MongoAuthException)(cn, cmd);
		string nonce = result["nonce"].get!string;
		string key = toLower(toHexString(md5Of(nonce ~ m_settings.username ~ m_settings.digest)).idup);

		cmd = Bson.emptyObject;
		cmd["authenticate"] = Bson(1);
		cmd["mechanism"] = Bson("MONGODB-CR");
		cmd["nonce"] = Bson(nonce);
		cmd["user"] = Bson(m_settings.username);
		cmd["key"] = Bson(key);
		runCommand!(Bson, MongoAuthException)(cn, cmd);
	}

	private void scramAuthenticate()
	{
		import vibe.db.mongo.sasl;

		string cn = m_settings.getAuthDatabase;

		ScramState state;
		string payload = state.createInitialRequest(m_settings.username);

		auto cmd = Bson.emptyObject;
		cmd["saslStart"] = Bson(1);
		cmd["mechanism"] = Bson("SCRAM-SHA-1");
		cmd["payload"] = Bson(BsonBinData(BsonBinData.Type.generic, payload.representation));

		auto doc = runCommand!(Bson, MongoAuthException)(cn, cmd);
		string response = cast(string)doc["payload"].get!BsonBinData().rawData;
		Bson conversationId = doc["conversationId"];

		payload = state.update(m_settings.digest, response);
		cmd = Bson.emptyObject;
		cmd["saslContinue"] = Bson(1);
		cmd["conversationId"] = conversationId;
		cmd["payload"] = Bson(BsonBinData(BsonBinData.Type.generic, payload.representation));

		doc = runCommand!(Bson, MongoAuthException)(cn, cmd);
		response = cast(string)doc["payload"].get!BsonBinData().rawData;

		payload = state.finalize(response);
		cmd = Bson.emptyObject;
		cmd["saslContinue"] = Bson(1);
		cmd["conversationId"] = conversationId;
		cmd["payload"] = Bson(BsonBinData(BsonBinData.Type.generic, payload.representation));
		runCommand!(Bson, MongoAuthException)(cn, cmd);
	}
}

private enum OpCode : int {
	Reply        = 1, // sent only by DB
	Update       = 2001,
	Insert       = 2002,
	Reserved1    = 2003,
	Query        = 2004,
	GetMore      = 2005,
	Delete       = 2006,
	KillCursors  = 2007,

	Compressed   = 2012,
	Msg          = 2013,
}

private alias ReplyDelegate = void delegate(long cursor, ReplyFlags flags, int first_doc, int num_docs) @safe;
private template DocDelegate(T) { alias DocDelegate = void delegate(size_t idx, ref T doc) @safe; }

private alias MsgReplyDelegate(bool dupBson : true) = void delegate(uint flags, Bson document) @safe;
private alias MsgReplyDelegate(bool dupBson : false) = void delegate(uint flags, scope Bson document) @safe;
private alias MsgSection1StartDelegate = void delegate(scope const(char)[] identifier, int size) @safe;
private alias MsgSection1Delegate(bool dupBson : true) = void delegate(scope const(char)[] identifier, Bson document) @safe;
private alias MsgSection1Delegate(bool dupBson : false) = void delegate(scope const(char)[] identifier, scope Bson document) @safe;

alias GetMoreHeaderDelegate = void delegate(long id, string ns, size_t count) @safe;
alias GetMoreDocumentDelegate(T) = void delegate(ref T document) @safe;

struct MongoDBInfo
{
	string name;
	double sizeOnDisk;
	bool empty;
}

private int sendLength(ARGS...)(scope ARGS args)
{
	import std.traits;
	static if (ARGS.length == 1) {
		alias T = ARGS[0];
		static if (is(T == string)) return cast(int)args[0].length + 1;
		else static if (is(T == int)) return 4;
		else static if (is(T == long)) return 8;
		else static if (is(T == Bson)) return cast(int)() @trusted { return args[0].data.length; } ();
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
	int minWireVersion, maxWireVersion;
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
	old = 0,
	v26 = 1,
	v26_2 = 2,
	v30 = 3,
	v32 = 4,
	v34 = 5,
	v36 = 6,
	v40 = 7,
	v42 = 8,
	v44 = 9,
	v49 = 12,
	v50 = 13,
	v51 = 14,
	v52 = 15,
	v53 = 16,
	v60 = 17
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
