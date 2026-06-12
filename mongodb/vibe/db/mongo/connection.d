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
public import vibe.db.mongo.impl.wireversion;
public import vibe.db.mongo.impl.serverdescription;

import vibe.core.core : vibeVersionString;
import vibe.core.log;
import vibe.core.net;
import vibe.data.bson;
import vibe.db.mongo.flags;
import vibe.db.mongo.impl.compression;
import vibe.db.mongo.impl.clustertime;
import vibe.db.mongo.impl.wire;
import vibe.db.mongo.monitor : MongoServerErrorCode;
import vibe.db.mongo.impl.serverapi : applyServerApi;
import vibe.db.mongo.settings;
import vibe.db.mongo.topology;
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

	/// Server-reported error labels (e.g. "TransientTransactionError").
	string[] errorLabels;

	/// Server-reported error code as a MongoServerErrorCode (none when there is no error).
	MongoServerErrorCode code;

	/// Whether the given server error label is present.
	bool hasErrorLabel(string label) const
	{
		import std.algorithm : canFind;
		return errorLabels.canFind(label);
	}
}

/// A MongoException carries server error labels and reports a present one via hasErrorLabel.
unittest
{
	auto e = new MongoException("transient failure");
	e.errorLabels = ["TransientTransactionError"];
	assert(e.hasErrorLabel("TransientTransactionError") == true,
		"hasErrorLabel must return true for an attached label");
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

	this(string message, MongoServerErrorCode code, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		super(message, file, line, next);
		this.code = code;
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

	this(string message, MongoServerErrorCode code, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		super(message, file, line, next);
		this.code = code;
	}
}

/**
 * Thrown when the contacted mongo node is no longer primary (e.g. step down).
 *
 * Carries the server-reported error code (e.g. 10107).
 */
class MongoStepDownException : MongoDriverException
{
@safe:

	this(string message, MongoServerErrorCode code, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		super(message, file, line, next);
		this.code = code;
	}
}

unittest
{
	auto stepDown = new MongoStepDownException("not primary", MongoServerErrorCode.notWritablePrimary);
	assert(stepDown.code == MongoServerErrorCode.notWritablePrimary, "expected stored code notWritablePrimary");
	assert(cast(MongoDriverException)stepDown !is null,
		"MongoStepDownException must be catchable as MongoDriverException");
}

/**
 * Thrown when a connection-level (network) failure interrupts an operation,
 * e.g. a socket error or a dropped connection. Retryable for writes with
 * session support and for idempotent reads.
 */
class MongoNetworkException : MongoDriverException
{
@safe:

	this(string message, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		super(message, file, line, next);
	}
}

/// MongoNetworkException is a MongoDriverException subclass
unittest
{
	auto networkFailure = new MongoNetworkException("connection reset");
	assert(cast(MongoDriverException) networkFailure !is null,
		"MongoNetworkException must be catchable as a MongoDriverException");
}

/// MongoDriverException can carry a server error code
unittest
{
	assert(new MongoDriverException("x", MongoServerErrorCode.networkTimeout).code == MongoServerErrorCode.networkTimeout,
		"MongoDriverException(message, code) carries the code");
}

/// asNetworkError passes a MongoException through unchanged
unittest
{
	auto mongo = new MongoDriverException("boom");
	assert(asNetworkError(mongo) is mongo, "a MongoException must pass through unchanged");
}

/// asNetworkError wraps a non-Mongo exception as a MongoNetworkException
unittest
{
	auto raw = new Exception("socket reset");
	auto wrapped = cast(MongoNetworkException) asNetworkError(raw);
	assert(wrapped !is null, "a non-Mongo exception becomes a MongoNetworkException");
	assert(wrapped.next is raw, "the original exception is preserved as the cause");
}

/// Builds the exception for a non-ok command response: a `MongoStepDownException` for
/// stale-topology codes, otherwise the generic `FallbackException`. In both cases the
/// returned exception carries the server `code`.
Exception commandFailureException(FallbackException = MongoDriverException)(
	string message, MongoServerErrorCode code, string[] errorLabels = null) @safe
{
	import vibe.db.mongo.monitor : isStaleTopologyError;

	MongoException e;
	if (isStaleTopologyError(code))
		e = new MongoStepDownException(message, code);
	else
		e = new FallbackException(message, code);

	e.errorLabels = errorLabels;
	return e;
}

unittest
{
	auto e = commandFailureException("primary stepped down", MongoServerErrorCode.notWritablePrimary);
	assert(cast(MongoStepDownException) e !is null,
		"stale code notWritablePrimary must yield a MongoStepDownException");
	assert((cast(MongoStepDownException) e).code == MongoServerErrorCode.notWritablePrimary,
		"step-down exception must carry the server code notWritablePrimary");
}

unittest
{
	auto e = commandFailureException("duplicate key", MongoServerErrorCode.duplicateKey);
	assert(cast(MongoStepDownException) e is null,
		"a non-stale code must not be classified as a step-down");
	assert(cast(MongoDriverException) e !is null,
		"a non-stale command failure stays a generic MongoDriverException");
}

/// A non-stale command failure carries its server error code on the MongoException base.
unittest
{
	auto e = commandFailureException("network timeout", MongoServerErrorCode.networkTimeout);
	assert((cast(MongoException) e).code == MongoServerErrorCode.networkTimeout,
		"a non-stale command failure must carry its server error code");
}

/// commandFailureException attaches the server-reported error labels to the exception
unittest
{
	auto e = commandFailureException("transient failure", MongoServerErrorCode.duplicateKey,
		["TransientTransactionError"]);
	assert((cast(MongoException) e).hasErrorLabel("TransientTransactionError"),
		"commandFailureException must attach the reply's error labels so hasErrorLabel works");
}

/// Extracts the server-reported `errorLabels` array from a command reply
/// (e.g. ["TransientTransactionError"]); an empty array when none are present.
string[] parseErrorLabels(Bson reply) @safe
{
	return reply["errorLabels"].opt!(Bson[]).map!(b => b.get!string).array;
}

/// parseErrorLabels extracts the errorLabels array from a command reply
unittest
{
	auto reply = Bson(["errorLabels": Bson([Bson("TransientTransactionError"), Bson("RetryableWriteError")])]);
	assert(parseErrorLabels(reply) == ["TransientTransactionError", "RetryableWriteError"],
		"parseErrorLabels returns the reply's errorLabels in order");
}

/// parseErrorLabels yields an empty array for replies without a proper errorLabels array
unittest
{
	// absent field (a normal successful reply)
	assert(parseErrorLabels(Bson(["ok": Bson(1.0)])) == [],
		"a reply without errorLabels yields no labels");
	// present but not an array (malformed/hostile reply) must not throw
	assert(parseErrorLabels(Bson(["errorLabels": Bson("oops")])) == [],
		"a non-array errorLabels yields no labels rather than throwing");
}

/// Reads the server-reported error `code` from a command reply, defaulting to 0
/// (unknown) when the reply omits it.
MongoServerErrorCode serverErrorCode(Bson reply) @safe
{
	return cast(MongoServerErrorCode) reply["code"].opt!int(0);
}

/// serverErrorCode reads the reply's code, falling back to 0 when absent
unittest
{
	assert(serverErrorCode(Bson(["code": Bson(112)])) == cast(MongoServerErrorCode) 112,
		"serverErrorCode returns the reply's code");
	assert(serverErrorCode(Bson(["ok": Bson(1.0)])) == cast(MongoServerErrorCode) 0,
		"a reply without a code yields 0");
}

/// Whether to auto-infer MONGODB-X509 auth from the TLS/credential shape: a client
/// certificate (PEM key file) is configured but NO password (a password means SCRAM
/// was intended). Server-version capability is checked separately at the call site.
bool inferX509(MongoClientSettings settings) @safe
{
	return settings.sslPEMKeyFile != null
		&& settings.username.length > 0
		&& settings.password.length == 0
		&& settings.digest.length == 0;
}

/// inferX509 does not infer MONGODB-X509 when a password is present (SCRAM was intended)
unittest
{
	auto settings = new MongoClientSettings();
	settings.sslPEMKeyFile = "/etc/ssl/client.pem";
	settings.username = "appuser";
	settings.password = "s3cret";

	assert(!inferX509(settings),
		"X509 must not be inferred when a password is present — SCRAM was intended");
}

/// inferX509 does not infer MONGODB-X509 for a PEM-only TLS connection with no username (no auth)
unittest
{
	auto settings = new MongoClientSettings();
	settings.sslPEMKeyFile = "/etc/ssl/client.pem";
	// no username, no password — TLS client cert only

	assert(!inferX509(settings),
		"X509 must not be inferred from a PEM file alone (no username) — that's TLS-only, no auth");
}

/// inferX509 does not infer MONGODB-X509 when a SCRAM digest is present (SCRAM was intended)
unittest
{
	auto settings = new MongoClientSettings();
	settings.sslPEMKeyFile = "/etc/ssl/client.pem";
	settings.username = "appuser";
	settings.digest = "0123456789abcdef0123456789abcdef"; // pre-hashed SCRAM-SHA-1 credential, no plaintext password

	assert(!inferX509(settings),
		"X509 must not be inferred when a SCRAM digest is present — SCRAM was intended");
}

/// inferX509 infers MONGODB-X509 for the genuine cert-auth shape: PEM cert + username, no password/digest
unittest
{
	auto settings = new MongoClientSettings();
	settings.sslPEMKeyFile = "/etc/ssl/client.pem";
	settings.username = "CN=appuser,OU=clients"; // the certificate subject DN

	assert(inferX509(settings),
		"X509 is inferred for a PEM client cert plus a username with no password or digest");
}

/// Builds the command-failure exception from a non-ok reply: message from `errmsg`,
/// the server `code`, and the reply's `errorLabels` (so `hasErrorLabel` works).
Exception commandFailureFromReply(FallbackException = MongoDriverException)(
	Bson reply, string errorInfo, string errorFile, size_t errorLine) @safe
{
	return commandFailureException!FallbackException(
		formatCommandError("command failed: " ~ reply["errmsg"].opt!string("(no message)"), errorInfo, errorFile, errorLine),
		serverErrorCode(reply), parseErrorLabels(reply));
}

/// commandFailureFromReply builds the failure exception from a reply, carrying its error labels and code
unittest
{
	auto reply = Bson([
		"ok": Bson(0.0),
		"code": Bson(112),
		"errmsg": Bson("WriteConflict"),
		"errorLabels": Bson([Bson("TransientTransactionError")]),
	]);

	auto e = cast(MongoException) commandFailureFromReply(reply, "ctx", "file.d", 1);
	assert(e.hasErrorLabel("TransientTransactionError"),
		"the exception built from a failing reply carries the reply's error labels");
	assert(e.code == cast(MongoServerErrorCode) 112,
		"the exception built from a failing reply carries the server code");
}

/// Classifies a thrown exception from the wire exchange: a MongoException passes through
/// unchanged; any other (connection-level) exception becomes a retryable MongoNetworkException.
Exception asNetworkError(Exception e) @safe
{
	if (cast(MongoException) e !is null)
		return e;
	return new MongoNetworkException(e.msg, __FILE__, __LINE__, e);
}

/// Appends the originating command's call-site context to an error message so a
/// failure points back at the caller rather than this protocol module.
private string formatCommandError(string msg, string errorInfo, string errorFile, size_t errorLine) @safe
{
	return text(msg, " in ", errorInfo, " (", errorFile, ":", errorLine, ")");
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
		MongoHost m_connectedHost;
		/// Hook invoked with (host, error code) when a command fails.
		void delegate(MongoHost host, MongoServerErrorCode code) @safe nothrow m_onCommandError;
		/// Flag to prevent recursive connections when server closes connection while connecting
		bool m_allowReconnect;
		bool m_isAuthenticating;
		bool m_supportsOpMsg;
		Compressor m_negotiatedCompressor = Compressor.noop;
		/// Highest `$clusterTime` observed on a reply; gossiped back on every command
		/// for causal consistency. Null until the first cluster-time-bearing reply.
		Bson m_clusterTime = Bson(null);
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
	}

	/// Sets the hook called with (host, error code) on command failure.
	package void onCommandError(void delegate(MongoHost host, MongoServerErrorCode code) @safe nothrow handler)
	{
		m_onCommandError = handler;
	}

	void connectToHost(MongoHost host, bool doAuthenticate = true) {
		// Reset before the handshake so a reconnect's hello/speculative-auth is
		// never sent OP_COMPRESSED with the previous connection's stale codec;
		// compression only applies once it's re-negotiated below.
		m_negotiatedCompressor = Compressor.noop;
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

			m_conn = connectTCP(host.name, host.port, null, 0, connectTimeout);
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

				m_stream = createTLSStream(m_conn, ctx, host.name);
				isTLS = true;
			}
			else {
				m_stream = m_conn;
			}
			m_outRange = streamOutputRange(m_stream);
		}
		catch (Exception e) {
			throw new MongoNetworkException(format("Failed to connect to MongoDB server at %s:%s.", host.name, host.port), __FILE__, __LINE__, e);
		}

		scope (failure) disconnect();

		m_allowReconnect = false;
		scope (exit)
			m_allowReconnect = true;

		Bson handshake = Bson.emptyObject;
		// TODO: must use legacy handshake once we allow configuring a server API
		// version in the driver
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

		if (m_settings.loadBalanced)
			handshake["loadBalanced"] = Bson(true);

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

		import vibe.db.mongo.sasl;
		import vibe.db.mongo.saslprep : saslPrep;
		import std.digest.sha : SHA1, SHA256;

		ScramState!SHA256 speculativeScramSHA256;
		ScramState!SHA1 speculativeScramSHA1;
		string speculativePayload;
		bool speculatingScram = false;
		MongoAuthMechanism speculativeMechanism = MongoAuthMechanism.none;

		if (m_settings.username.length) {
			string authDb = m_settings.getAuthDatabase;
			handshake["saslSupportedMechs"] = Bson(authDb ~ "." ~ m_settings.username);

			if (m_settings.password.length) {
				speculativePayload = speculativeScramSHA256.createInitialRequest(m_settings.username);
				speculativeMechanism = MongoAuthMechanism.scramSHA256;
			} else if (m_settings.digest.length) {
				speculativePayload = speculativeScramSHA1.createInitialRequest(m_settings.username);
				speculativeMechanism = MongoAuthMechanism.scramSHA1;
			}

			if (speculativePayload.length) {
				string mechStr = speculativeMechanism == MongoAuthMechanism.scramSHA256
					? "SCRAM-SHA-256" : "SCRAM-SHA-1";

				auto specAuth = Bson.emptyObject;
				specAuth["saslStart"] = Bson(1);
				specAuth["mechanism"] = Bson(mechStr);
				specAuth["payload"] = Bson(BsonBinData(BsonBinData.Type.generic, speculativePayload.representation));
				specAuth["options"] = Bson(["skipEmptyExchange": Bson(true)]);

				handshake["speculativeAuthenticate"] = specAuth;
				speculatingScram = true;
			}
		}

		auto advertised = advertisedCompressorNames(m_settings.compressors);
		if (advertised.length > 0)
			handshake["compression"] = Bson(advertised.map!(name => Bson(name)).array);

		auto reply = runCommand!MongoAuthException("admin", handshake);
		m_description = deserializeBson!ServerDescription(reply);
		enforceLoadBalancedServiceId(m_settings.loadBalanced, m_description);

		if (m_description.satisfiesVersion(WireVersion.v36))
			m_supportsOpMsg = true;

		bool serverSupportsSHA256 = false;
		bool hasSaslSupportedMechs = false;
		auto saslMechs = reply.tryIndex("saslSupportedMechs");
		if (!saslMechs.isNull) {
			hasSaslSupportedMechs = true;
			foreach (mech; saslMechs.get.byValue) {
				if (mech.get!string == "SCRAM-SHA-256") {
					serverSupportsSHA256 = true;
					break;
				}
			}
		}

		Bson speculativeResult = Bson(null);
		auto specResultField = reply.tryIndex("speculativeAuthenticate");
		if (!specResultField.isNull)
			speculativeResult = specResultField.get;

		m_negotiatedCompressor = negotiateCompressor(
			m_settings.compressors, m_description.compression);

		m_bytesRead = 0;
		m_connectedHost = host;

		if (doAuthenticate) {
			auto authMechanism = m_settings.authMechanism;

			if (authMechanism == MongoAuthMechanism.none && inferX509(m_settings) && m_description.satisfiesVersion(WireVersion.v26))
				authMechanism = MongoAuthMechanism.mongoDBX509;

			if (authMechanism == MongoAuthMechanism.none && (m_settings.digest.length || m_settings.password.length))
			{
				if (serverSupportsSHA256 && m_settings.password.length)
					authMechanism = MongoAuthMechanism.scramSHA256;
				else if (!hasSaslSupportedMechs && m_description.satisfiesVersion(WireVersion.v40) && m_settings.password.length)
					authMechanism = MongoAuthMechanism.scramSHA256;
				else if (m_description.satisfiesVersion(WireVersion.v30))
					authMechanism = MongoAuthMechanism.scramSHA1;
				else
					authMechanism = MongoAuthMechanism.mongoDBCR;
			}

			enforce!MongoAuthException(authMechanism != MongoAuthMechanism.mongoDBCR || !m_description.satisfiesVersion(WireVersion.v40),
				"Trying to force MONGODB-CR authentication on a >=4.0 server not supported");

			enforce!MongoAuthException(authMechanism != MongoAuthMechanism.scramSHA1 || m_description.satisfiesVersion(WireVersion.v30),
				"Trying to force SCRAM-SHA-1 authentication on a <3.0 server not supported");

			enforce!MongoAuthException(authMechanism != MongoAuthMechanism.scramSHA256 || m_description.satisfiesVersion(WireVersion.v40),
				"Trying to force SCRAM-SHA-256 authentication on a <4.0 server not supported");

			enforce!MongoAuthException(authMechanism != MongoAuthMechanism.scramSHA256 || m_settings.password.length > 0,
				"SCRAM-SHA-256 requires the raw password, not just the MD5 digest");

			enforce!MongoAuthException(authMechanism != MongoAuthMechanism.mongoDBX509 || m_description.satisfiesVersion(WireVersion.v26),
				"Trying to force MONGODB-X509 authentication on a <2.6 server not supported");

			enforce!MongoAuthException(authMechanism != MongoAuthMechanism.mongoDBX509 || isTLS,
				"Trying to force MONGODB-X509 authentication, but didn't use ssl!");

			bool canUseSpeculative = speculatingScram
				&& speculativeMechanism == authMechanism
				&& speculativeResult != Bson(null);

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
				if (canUseSpeculative)
					scramAuthenticateContinue(speculativeScramSHA1, m_settings.digest, speculativeResult);
				else
					scramAuthenticate();
				break;
			case MongoAuthMechanism.scramSHA256:
				if (canUseSpeculative)
					scramAuthenticateContinue(speculativeScramSHA256, saslPrep(m_settings.password), speculativeResult);
				else
					scramSHA256Authenticate();
				break;
			case MongoAuthMechanism.mongoDBCR:
				authenticate();
				break;
			}

			logDiagnostic("Connected to: %s primary=%s secondary=%s", m_description.me, m_description.isPrimary, m_description.secondary);
		} else {
			logDiagnostic("Probed: %s primary=%s secondary=%s", m_description.me, m_description.isPrimary, m_description.secondary);
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

	/**
	 * Checks if the connection is alive by probing the socket for remote close.
	 *
	 * Unlike `connected`, which only checks local socket state, this detects
	 * when the remote end has sent a FIN (server shutdown, timeout, etc.).
	 */
	@property bool alive()
	{
		import core.time : Duration;

		if (!m_conn || !m_conn.connected)
			return false;

		auto status = m_conn.waitForDataEx(Duration.zero);
		// timeout (wouldBlock) means the socket is alive but no data pending, which is fine
		// dataAvailable means there's unread data, so the socket is also alive
		// noMoreData means the remote end closed the connection
		return status != typeof(status).noMoreData;
	}

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
	Bson runCommand(CommandFailException = MongoDriverException)(
		string database,
		Bson command,
		string errorInfo = __FUNCTION__,
		string errorFile = __FILE__,
		size_t errorLine = __LINE__
	)
	in(database.length, "runCommand requires a database argument")
	{
		return runCommandImpl!CommandFailException(
			database, command, true, errorInfo, errorFile, errorLine);
	}

	Bson runCommandUnchecked(CommandFailException = MongoDriverException)(
		string database,
		Bson command,
		string errorInfo = __FUNCTION__,
		string errorFile = __FILE__,
		size_t errorLine = __LINE__
	)
	in(database.length, "runCommand requires a database argument")
	{
		return runCommandImpl!CommandFailException(
			database, command, false, errorInfo, errorFile, errorLine);
	}

	private Bson runCommandImpl(CommandFailException)(
		string database,
		Bson command,
		bool testOk = true,
		string errorInfo = __FUNCTION__,
		string errorFile = __FILE__,
		size_t errorLine = __LINE__
	)
	in(database.length, "runCommand requires a database argument")
	{
		Bson ret;

		// Unlike the sibling cursor methods, disconnect() lives inside the send/recv
		// catch blocks rather than a method-top `scope (failure) disconnect();`. A wire
		// error desyncs the connection and must quarantine it, but the clean `ok != 1.0`
		// command-failure path below fully reads a healthy connection and must keep it.
		// A method-scoped guard would wrongly disconnect on that logical failure too.

		// When the Stable API (Versioned API) is configured, every command, including
		// the handshake hello, carries apiVersion (+ apiStrict / apiDeprecationErrors).
		command = applyServerApi(command, m_settings.serverApi);

		// Gossip the highest cluster time we've seen so the server advances causally.
		// No-op until the first reply carries a $clusterTime (e.g. on a standalone).
		command = gossipClusterTime(command, m_clusterTime);

		if (m_supportsOpMsg)
		{
			debug (VibeVerboseMongo)
				logDiagnostic("runCommand: [db=%s] %s", database, command);

			command["$db"] = Bson(database);

			try
			{
				auto id = sendMsg(-1, 0, command);
				Appender!(Bson[])[string] docs;
				recvMsg!true(id, (flags, root) @safe {
					ret = root;
				}, (scope ident, size) @safe {
					docs[ident.idup] = appender!(Bson[]);
				}, (scope ident, push) @safe {
					auto pd = ident in docs;
					enforce!MongoDriverException(!!pd, formatCommandError("Received data for unexpected identifier", errorInfo, errorFile, errorLine));
					pd.put(push);
				});

				foreach (ident, app; docs)
					ret[ident] = Bson(app.data);
			}
			catch (Exception e)
			{
				disconnect();
				throw asNetworkError(e);
			}
		}
		else
		{
			debug (VibeVerboseMongo)
				logDiagnostic("runCommand(legacy): [db=%s] %s", database, command);
			try
			{
				auto id = send(OpCode.Query, -1, 0, database ~ ".$cmd", 0, -1, command, Bson(null));
				recvReply!Bson(id,
					(cursor, flags, first_doc, num_docs) {
						logTrace("runCommand(%s) flags: %s, cursor: %s, documents: %s", database, flags, cursor, num_docs);
						enforce!MongoDriverException(!(flags & ReplyFlags.QueryFailure), formatCommandError("command query failed", errorInfo, errorFile, errorLine));
						enforce!MongoDriverException(num_docs == 1, formatCommandError("received more than one document in command response", errorInfo, errorFile, errorLine));
					},
					(idx, ref doc) {
						ret = doc;
					});
			}
			catch (Exception e)
			{
				disconnect();
				throw asNetworkError(e);
			}
		}

		// Observe the reply's $clusterTime even on command failure: a failed command
		// still gossips a valid cluster time the driver must track.
		m_clusterTime = laterClusterTime(m_clusterTime, ret["$clusterTime"]);

		if (testOk && ret["ok"].get!double != 1.0)
		{
			auto code = serverErrorCode(ret);
			if (m_onCommandError !is null)
				m_onCommandError(m_connectedHost, code);

			throw commandFailureFromReply!CommandFailException(ret, errorInfo, errorFile, errorLine);
		}

		return ret;
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
			Nullable!ReadPreference pref = Nullable!ReadPreference.init,
			Bson sessionContext = Bson.emptyObject,
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

			// A secondary keeps serving getMore only if each continuation re-sends $readPreference.
			if (!pref.isNull && pref.get != ReadPreference.primary)
				command["$readPreference"] = readPreferenceBson(pref.get);

			foreach (string key, value; sessionContext.byKeyValue)
				command[key] = value;

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
						formatCommandError("Invalid cursor handle.", errorInfo, errorFile, errorLine));
					enforce!MongoDriverException(!(flags & ReplyFlags.QueryFailure),
						formatCommandError("Query failed. Does the database exist?", errorInfo, errorFile, errorLine));

					on_header(cursor, full_name, num_docs);
				}, (size_t idx, ref T doc) {
					if (cast(int)idx == nextId) {
						on_doc(doc);
						nextId++;
						brokenId = nextId;
					} else {
						enforce!MongoDriverException(idx >= brokenId,
							formatCommandError("Got legacy document with same id after having already processed it!", errorInfo, errorFile, errorLine));
						enforce!MongoDriverException(idx < num_docs,
							formatCommandError("Received more documents than the database reported to us", errorInfo, errorFile, errorLine));

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
		scope (failure) disconnect();

		enforce!MongoDriverException(m_supportsOpMsg, formatCommandError("Database does not support required OP_MSG for new style queries", errorInfo, errorFile, errorLine));

		enum needsDup = hasIndirections!T || is(T == Bson);

		debug (VibeVerboseMongo)
			logDiagnostic("%s: %s", errorInfo, command);

		auto id = sendMsg(-1, 0, command);
		recvMsg!needsDup(id, (flags, scope root) @safe {
			if (root["ok"].get!double != 1.0)
			{
				auto failure = new MongoDriverException(
					formatCommandError("error response: " ~ root["errmsg"].opt!string("(no message)"), errorInfo, errorFile, errorLine),
					serverErrorCode(root));
				failure.errorLabels = parseErrorLabels(root);
				throw failure;
			}

			auto cursor = root["cursor"];
			if (cursor.type == Bson.Type.null_)
				throw new MongoDriverException(formatCommandError("no cursor in response: "
					~ root["errmsg"].opt!string("(no error message)"), errorInfo, errorFile, errorLine));
			auto batch = cursor[batchKey].get!(Bson[]);
			on_header(cursor["id"].get!long, cursor["ns"].get!string, batch.length);

			foreach (ref push; batch)
			{
				T doc = deserializeBson!T(push);
				on_doc(doc);
			}
		}, (scope ident, size) @safe {}, (scope ident, scope push) @safe {
			throw new MongoDriverException(formatCommandError("unexpected section type 1 in response", errorInfo, errorFile, errorLine));
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

	void killCursors(string collection, scope long[] cursors, Nullable!ReadPreference pref = Nullable!ReadPreference.init)
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
			if (!pref.isNull && pref.get != ReadPreference.primary)
				command["$readPreference"] = readPreferenceBson(pref.get);
			runCommand(parts[0], command);
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

		auto error = runCommandUnchecked(db, command_and_options);

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

		auto result = runCommand(cn, cmd)["databases"];

		return result.byValue.map!toInfo;
	}

	private int recvMsg(bool dupBson = true)(int reqid,
		scope MsgReplyDelegate!dupBson on_sec0,
		scope MsgSection1StartDelegate on_sec1_start,
		scope MsgSection1Delegate!dupBson on_sec1_doc)
	{
		import std.traits;

		auto packet_start_index = m_bytesRead;
		int msglen = recvInt();
		int resid = recvInt();
		int respto = recvInt();
		int opcode = recvInt();

		enforce!MongoDriverException(respto == reqid, "Reply is not for the expected message on a sequential connection!");

		if (opcode == OpCode.Compressed) {
			return recvCompressedMsg!dupBson(resid, msglen, packet_start_index,
				on_sec0, on_sec1_start, on_sec1_doc);
		}

		enforce!MongoDriverException(opcode == OpCode.Msg, "Got wrong reply type! (must be OP_MSG or OP_COMPRESSED)");

		uint flagBits = recvUInt();
		const bool hasCRC = checksumPresent(flagBits);

		// Sections occupy everything but the optional trailing CRC; stop before it so the
		// CRC's bytes are not read as a bogus payload-section type.
		const ulong sectionEnd = msglen - (hasCRC ? uint.sizeof : 0);

		bool gotSec0;
		while (m_bytesRead - packet_start_index < sectionEnd) {
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

		assert(packet_start_index + msglen == m_bytesRead,
			format!"Packet size mismatch! Expected %s bytes, but read %s."(
				msglen, m_bytesRead - packet_start_index));

		return resid;
	}

	private int recvCompressedMsg(bool dupBson)(
		int resid, int msglen, ulong packet_start_index,
		scope MsgReplyDelegate!dupBson on_sec0,
		scope MsgSection1StartDelegate on_sec1_start,
		scope MsgSection1Delegate!dupBson on_sec1_doc)
	{
		int originalOpcode = recvInt();
		enforce!MongoDriverException(originalOpcode == OpCode.Msg,
			"OP_COMPRESSED wraps unsupported opcode: " ~ originalOpcode.to!string);

		int uncompressedSize = recvInt();
		ubyte compressorId = recvUByte();

		int compressedSize = cast(int)(msglen - (m_bytesRead - packet_start_index));
		ubyte[] compressedPayload = new ubyte[compressedSize];
		recv(compressedPayload);

		auto compressor = compressorFromId(compressorId);
		ubyte[] decompressed = decompressData(compressor, compressedPayload, uncompressedSize);
		enforce!MongoDriverException(decompressed.length == uncompressedSize,
			"Decompressed size mismatch");

		parseOpMsgBody!dupBson(decompressed, on_sec0, on_sec1_start, on_sec1_doc);

		assert(packet_start_index + msglen == m_bytesRead,
			format!"Packet size mismatch! Expected %s bytes, but read %s."(
				msglen, m_bytesRead - packet_start_index));

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
		ensureConnected();

		int id = nextMessageId();
		sendHeader(16 + sendLength(args), id, response_to, code);
		foreach (a; args) sendValue(a);
		m_outRange.flush();

		return id;
	}

	private int sendMsg(int response_to, uint flagBits, Bson document)
	{
		ensureConnected();
		int id = nextMessageId();
		const bool hasCRC = checksumPresent(flagBits);
		assert(!hasCRC, "sending with CRC bits not yet implemented");

		bool shouldCompress = m_negotiatedCompressor != Compressor.noop
			&& !m_isAuthenticating;

		if (!shouldCompress) {
			sendHeader(21 + sendLength(document), id, response_to, OpCode.Msg);
			sendValue!uint(flagBits);
			sendValue!ubyte(0);
			sendValue(document);
			m_outRange.flush();
			return id;
		}

		auto docData = () @trusted { return cast(const(ubyte)[]) document.data; }();
		int uncompressedSize = cast(int)(4 + 1 + docData.length);

		ubyte[] uncompressedBody = new ubyte[uncompressedSize];
		uncompressedBody[0 .. 4] = toBsonData(flagBits)[];
		uncompressedBody[4] = 0;
		uncompressedBody[5 .. $] = docData[];

		auto compressedBody = compressData(
			m_negotiatedCompressor, uncompressedBody, m_settings.zlibCompressionLevel);

		int msgLen = cast(int)(16 + 4 + 4 + 1 + compressedBody.length);
		sendHeader(msgLen, id, response_to, OpCode.Compressed);
		sendValue!int(cast(int) OpCode.Msg);
		sendValue!int(uncompressedSize);
		sendValue!ubyte(cast(ubyte) m_negotiatedCompressor);
		sendBytes(compressedBody);
		m_outRange.flush();

		return id;
	}

	private void ensureConnected()
	{
		if (connected()) {
			return;
		}

		if (m_allowReconnect) {
			connectToHost(m_connectedHost);
			return;
		}

		throw m_isAuthenticating
			? new MongoAuthException("Connection got closed while authenticating")
			: new MongoDriverException("Connection got closed while connecting");
	}

	private void sendHeader(int messageLength, int id, int responseTo, OpCode code)
	{
		sendValue!int(messageLength);
		sendValue!int(id);
		sendValue!int(responseTo);
		sendValue!int(cast(int) code);
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
		// MONGODB-X509 authenticates against the "$external" database per the spec,
		// not the configured auth database (the identity lives in the certificate).
		runCommand!MongoAuthException("$external", cmd);
	}

	private void authenticate()
	{
		scope (failure) disconnect();

		string cn = m_settings.getAuthDatabase;

		auto cmd = Bson(["getnonce": Bson(1)]);
		auto result = runCommand!MongoAuthException(cn, cmd);
		string nonce = result["nonce"].get!string;
		string key = toLower(toHexString(md5Of(nonce ~ m_settings.username ~ m_settings.digest)).idup);

		cmd = Bson.emptyObject;
		cmd["authenticate"] = Bson(1);
		cmd["mechanism"] = Bson("MONGODB-CR");
		cmd["nonce"] = Bson(nonce);
		cmd["user"] = Bson(m_settings.username);
		cmd["key"] = Bson(key);
		runCommand!MongoAuthException(cn, cmd);
	}

	private void scramAuthenticate()
	{
		import std.digest.sha : SHA1;
		scramStartAuth!SHA1("SCRAM-SHA-1", m_settings.digest);
	}

	private void scramSHA256Authenticate()
	{
		import vibe.db.mongo.saslprep : saslPrep;
		import std.digest.sha : SHA256;
		scramStartAuth!SHA256("SCRAM-SHA-256", saslPrep(m_settings.password));
	}

	private void scramStartAuth(HashType)(string mechanism, string credential)
	{
		import vibe.db.mongo.sasl;

		string cn = m_settings.getAuthDatabase;

		ScramState!HashType state;
		string payload = state.createInitialRequest(m_settings.username);

		auto cmd = Bson.emptyObject;
		cmd["saslStart"] = Bson(1);
		cmd["mechanism"] = Bson(mechanism);
		cmd["payload"] = Bson(BsonBinData(BsonBinData.Type.generic, payload.representation));
		cmd["options"] = Bson(["skipEmptyExchange": Bson(true)]);

		auto doc = runCommand!MongoAuthException(cn, cmd);
		scramFinishAuth(state, credential, doc, cn);
	}

	private void scramAuthenticateContinue(ScramStateType)(ref ScramStateType state, string credential, Bson speculativeResult)
	{
		string cn = m_settings.getAuthDatabase;
		scramFinishAuth(state, credential, speculativeResult, cn);
	}

	private void scramFinishAuth(ScramStateType)(ref ScramStateType state, string credential, Bson doc, string cn)
	{
		string response = cast(string)doc["payload"].get!BsonBinData().rawData;
		Bson conversationId = doc["conversationId"];

		string payload = state.update(credential, response);
		auto cmd = Bson.emptyObject;
		cmd["saslContinue"] = Bson(1);
		cmd["conversationId"] = conversationId;
		cmd["payload"] = Bson(BsonBinData(BsonBinData.Type.generic, payload.representation));

		doc = runCommand!MongoAuthException(cn, cmd);
		response = cast(string)doc["payload"].get!BsonBinData().rawData;

		payload = state.finalize(response);

		auto doneField = doc.tryIndex("done");
		if (!doneField.isNull && doneField.get.get!bool)
			return;

		cmd = Bson.emptyObject;
		cmd["saslContinue"] = Bson(1);
		cmd["conversationId"] = conversationId;
		cmd["payload"] = Bson(BsonBinData(BsonBinData.Type.generic, payload.representation));
		runCommand!MongoAuthException(cn, cmd);
	}
}


alias GetMoreHeaderDelegate = void delegate(long id, string ns, size_t count) @safe;
alias GetMoreDocumentDelegate(T) = void delegate(ref T document) @safe;

struct MongoDBInfo
{
	string name;
	double sizeOnDisk;
	bool empty;
}


/**
 * Probes a MongoDB host by performing a hello handshake without authentication.
 *
 * Creates a temporary connection, sends the hello command, measures round-trip
 * time, and returns the resulting ServerDescription. Used by MongoClient for
 * topology discovery without consuming a pool connection.
 */
package ServerDescription probeServer(MongoClientSettings settings, MongoHost host) @safe
{
	import std.datetime.stopwatch : StopWatch;

	StopWatch sw;
	sw.start();

	auto conn = new MongoConnection(settings);
	scope (exit) {
		conn.disconnect();
		() @trusted { destroy(conn); } ();
	}

	conn.connectToHost(host, false);

	sw.stop();

	auto desc = conn.m_description;
	desc.roundTripTime = sw.peek.total!"usecs" / 1_000_000.0f;

	import core.time : MonoTime;
	auto now = MonoTime.currTime;
	desc.lastUpdateTimeUsecs = now.ticks * 1_000_000 / MonoTime.ticksPerSecond;

	return desc;
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

	static if(os.endian == os.Endian.bigEndian)
		string endian = "bigEndian";
	else static if(os.endian == os.Endian.littleEndian)
		string endian = "littleEndian";

	return arch ~ endian;
}

private static immutable hostArchitecture = getHostArchitecture;

