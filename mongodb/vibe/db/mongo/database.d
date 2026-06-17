/**
	MongoDatabase class representing common database for group of collections.

	Technically it is very special collection with common query functions
	disabled and some service commands provided.

	Copyright: © 2012-2014 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.database;

import vibe.db.mongo.client;
import vibe.db.mongo.collection;
import vibe.db.mongo.settings : ReadConcern, ReadPreference, readPreferenceBson;
import vibe.db.mongo.impl.retryablewrites : isRetryableWriteCommand, applyRetryableWrite;
import vibe.db.mongo.impl.serversession : ServerSession, MongoClientSession, inActiveTransaction;
import vibe.db.mongo.connection : MongoNetworkException;
import vibe.data.bson;

import core.time;
import std.typecons : Nullable;

/** Represents a single database accessible through a given MongoClient.
*/
struct MongoDatabase
{
@safe:

	private {
		string m_name;
		MongoClient m_client;
		ReadConcern m_readConcern;
	}

	//@disable this();

	this(MongoClient client, string name)
	{
		import std.algorithm;

		assert(client !is null);
		m_client = client;
		m_readConcern = client.readConcern;

		assert(
				!canFind(name, '.'),
				"Compound collection path provided to MongoDatabase constructor instead of single database name"
		  );
		m_name = name;
	}

	/// The name of this database
	@property string name()
	{
		return m_name;
	}

	/// The client which represents the connection to the database server
	@property MongoClient client()
	{
		return m_client;
	}

	/// The read concern for this database, inherited from the client unless overridden.
	ReadConcern readConcern() const
	{
		return m_readConcern;
	}

	/// Returns a copy of this database with the given read concern.
	MongoDatabase withReadConcern(ReadConcern rc)
	{
		auto db = this;
		db.m_readConcern = rc;
		return db;
	}

	/** Accesses the collections of this database.

		Returns: The collection with the given name
	*/
	MongoCollection opIndex(string name)
	{
		return MongoCollection(this, name);
	}

	/** Retrieves the last error code (if any) from the database server.

		Exact object format is not documented. MongoErrorDescription signature will be
		updated upon any issues. Note that this method will execute a query to service
		collection and thus is far from being "free".

		Returns: struct storing data from MongoDB db.getLastErrorObj() object
 	*/
	MongoErrorDescription getLastError()
	{
		return m_client.lockConnection().getLastError(m_name);
	}

	/** Returns recent log messages for this database from the database server.

		See $(LINK http://www.mongodb.org/display/DOCS/getLog+Command).

	 	Params:
	 		mask = "global" or "rs" or "startupWarnings". Refer to official MongoDB docs.

	 	Returns: Bson document with recent log messages from MongoDB service.
 	 */
	Bson getLog(string mask)
	{
		static struct CMD {
			string getLog;
		}
		CMD cmd;
		cmd.getLog = mask;
		return runCommandChecked(cmd);
	}

	/** Performs a filesystem/disk sync of the database on the server.

		This method can only be called on the admin database.

		See $(LINK http://www.mongodb.org/display/DOCS/fsync+Command)

		Returns: check documentation
 	 */
	Bson fsync(bool async = false)
	{
		static struct CMD {
			int fsync = 1;
			bool async;
		}
		CMD cmd;
		cmd.async = async;
		return runCommandChecked(cmd);
	}

	deprecated("use runCommandChecked or runCommandUnchecked instead")
	Bson runCommand(T)(T command_and_options,
		string errorInfo = __FUNCTION__, string errorFile = __FILE__, size_t errorLine = __LINE__)
	{
		return runCommandUnchecked(command_and_options, errorInfo, errorFile, errorLine);
	}

	/// Runs a command with an explicit per-query read preference, overriding the client default.
	Bson runCommand(T)(T command_and_options, ReadPreference readPreference,
		string errorInfo = __FUNCTION__, string errorFile = __FILE__, size_t errorLine = __LINE__)
	{
		return runCommandChecked!T(command_and_options, errorInfo, errorFile, errorLine,
			false, Nullable!ReadPreference(readPreference));
	}

	/** Generic means to run commands on the database.

		See $(LINK http://www.mongodb.org/display/DOCS/Commands) for a list
		of possible values for command_and_options.

		Note that some commands return a cursor instead of a single document.
		In this case, use `runListCommand` instead of `runCommandChecked` or
		`runCommandUnchecked` to be able to properly iterate over the results.

		Usually commands respond with a `double ok` field in them, the `Checked`
		version of this function checks that they equal to `1.0`. The `Unchecked`
		version of this function does not check that parameter.

		With cursor functions on `runListCommand` the error checking is well
		defined.

		Params:
			command_and_options = Bson object containing the command to be executed
				as well as the command parameters as fields

		Returns: The raw response of the MongoDB server
	*/
	Bson runCommandChecked(T, ExceptionT = MongoDriverException)(
		T command_and_options,
		string errorInfo = __FUNCTION__,
		string errorFile = __FILE__,
		size_t errorLine = __LINE__,
		bool toPrimary = false,
		Nullable!ReadPreference readPreference = Nullable!ReadPreference.init
	)
	{
		Bson cmd = toCommandBson(command_and_options);
		auto conn = resolveCommandConnection(toPrimary, cmd, readPreference);
		return conn.runCommand!ExceptionT(
			m_name, cmd, errorInfo, errorFile, errorLine);
	}

	/// ditto, but always sends to the primary (for write operations).
	Bson runWriteCommandChecked(T, ExceptionT = MongoDriverException)(
		T command_and_options,
		MongoClientSession* session = null,
		string errorInfo = __FUNCTION__,
		string errorFile = __FILE__,
		size_t errorLine = __LINE__
	)
	{
		Bson cmd = toCommandBson(command_and_options);
		if (inActiveTransaction(session))
			return runSessionWrite!ExceptionT(cmd, *session, errorInfo, errorFile, errorLine, true);
		return runWriteWithRetry!ExceptionT(cmd, errorInfo, errorFile, errorLine, true);
	}

	/// ditto
	Bson runCommandUnchecked(T, ExceptionT = MongoDriverException)(
		T command_and_options,
		string errorInfo = __FUNCTION__,
		string errorFile = __FILE__,
		size_t errorLine = __LINE__,
		bool toPrimary = false,
		Nullable!ReadPreference readPreference = Nullable!ReadPreference.init
	)
	{
		Bson cmd = toCommandBson(command_and_options);
		auto conn = resolveCommandConnection(toPrimary, cmd, readPreference);
		return conn.runCommandUnchecked!ExceptionT(
			m_name, cmd, errorInfo, errorFile, errorLine);
	}

	/// ditto, but always sends to the primary (for write operations).
	Bson runWriteCommandUnchecked(T, ExceptionT = MongoDriverException)(
		T command_and_options,
		string errorInfo = __FUNCTION__,
		string errorFile = __FILE__,
		size_t errorLine = __LINE__
	)
	{
		Bson cmd = toCommandBson(command_and_options);
		return runWriteWithRetry!ExceptionT(cmd, errorInfo, errorFile, errorLine, false);
	}

	/// Runs a write that belongs to an explicit session's active transaction: stamps the
	/// session's transaction context onto the command and sends it to the primary once,
	/// bypassing the implicit retryable-write path.
	private Bson runSessionWrite(ExceptionT)(
		Bson cmd, ref MongoClientSession session, string errorInfo, string errorFile, size_t errorLine, bool checked)
	{
		Bson prepared = session.applyToCommand(cmd);
		auto conn = m_client.lockConnectionToPrimary();
		return checked
			? conn.runCommand!ExceptionT(m_name, prepared, errorInfo, errorFile, errorLine)
			: conn.runCommandUnchecked!ExceptionT(m_name, prepared, errorInfo, errorFile, errorLine);
	}

	/// Runs a write command on the primary, retrying once after a primary
	/// step-down. Retryable writes (per `isRetryableWriteCommand`, when
	/// `retryWrites` is enabled) carry an `lsid`/`txnNumber` so the server
	/// deduplicates the retried write; the retry re-discovers the topology and
	/// re-locks the freshly elected primary before resending the same command.
	private Bson runWriteWithRetry(ExceptionT)(
		Bson cmd, string errorInfo, string errorFile, size_t errorLine, bool checked)
	{
		return withImplicitSession!Bson(cmd, (preparedCmd, sessionSupport) @safe {
			return retryOnceOnRetryableError!Bson(
				() @safe {
					auto conn = m_client.lockConnectionToPrimary();
					auto reply = checked
						? conn.runCommand!ExceptionT(m_name, preparedCmd, errorInfo, errorFile, errorLine)
						: conn.runCommandUnchecked!ExceptionT(m_name, preparedCmd, errorInfo, errorFile, errorLine);
					// An ok:1 reply can still carry a transient writeConcernError; surface a
					// retryable one as a throw so the retry path re-sends the deduplicated write.
					enforceWriteConcernRetry(reply, sessionSupport);
					return reply;
				},
				RetryPolicy(false, sessionSupport),
				() @safe { m_client.refreshTopology(); });
		});
	}

	/// Runs `body` with an implicit server session attached when `cmd` is a retryable write:
	/// acquires a session, stamps the retryable-write fields onto the command, and releases the
	/// session on exit. `body` receives the (possibly stamped) command and whether session support is active.
	private T withImplicitSession(T)(Bson cmd, scope T delegate(Bson preparedCmd, bool sessionSupport) @safe body)
	{
		const retryable = m_client.retryWrites && m_client.supportsRetryableWrites()
			&& isRetryableWriteCommand(cmd);
		ServerSession session;
		if (retryable)
		{
			session = m_client.acquireServerSession();
			cmd = applyRetryableWrite(cmd, session.lsid, session.nextTransactionNumber());
		}
		scope (exit)
			if (retryable)
				m_client.releaseServerSession(session);

		try
			return body(cmd, retryable);
		catch (MongoNetworkException e)
		{
			// A network error tainted the session (the txnNumber may have reached the
			// server); mark it dirty so release discards it rather than recycling its
			// lsid for the next operation. Per the Driver Sessions spec.
			if (retryable)
				session.markDirty();
			throw e;
		}
	}

	/// ditto
	MongoCursor!R runListCommand(R = Bson, T)(T command_and_options, int batchSize = 0,
		Duration getMoreMaxTime = Duration.max,
		Nullable!ReadPreference readPreference = Nullable!ReadPreference.init)
	{
		Bson cmd = toCommandBson(command_and_options);
		cmd["$db"] = Bson(m_name);

		auto pref = readPreference.isNull ? m_client.readPreference : readPreference.get;
		if (pref != ReadPreference.primary)
			cmd["$readPreference"] = readPreferenceBson(pref, m_client.readPreferenceTags);

		return MongoCursor!R(m_client, cmd, batchSize, getMoreMaxTime, Nullable!ReadPreference(pref));
	}

	/// Normalizes a command argument into its Bson wire form: Bson passes through,
	/// anything else is serialized.
	private static Bson toCommandBson(T)(T command_and_options)
	{
		static if (is(T : Bson))
			return command_and_options;
		else
			return command_and_options.serializeToBson;
	}

	/// Writes lock the primary; reads lock by effective preference and inject `$readPreference`.
	// TODO(causal-consistency): explicit sessions and retryable writes already carry an lsid,
	// and multi-document transactions are fully wired (cursors pin the session across getMore).
	// What remains is IMPLICIT sessions: attaching an lsid (applySession from impl.serversession)
	// to EVERY command automatically — reads and non-retryable writes alike — for causal
	// consistency, checking one out of the pool and returning it after.
	private auto resolveCommandConnection(bool toPrimary, ref Bson cmd, Nullable!ReadPreference readPreference)
	{
		if (toPrimary)
			return m_client.lockConnectionToPrimary();

		auto pref = readPreference.isNull ? m_client.readPreference : readPreference.get;
		if (pref != ReadPreference.primary)
			cmd["$readPreference"] = readPreferenceBson(pref, m_client.readPreferenceTags);

		return m_client.lockConnection(pref);
	}
}
