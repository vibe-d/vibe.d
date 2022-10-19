/**
	MongoDB client connection settings.

	Copyright: © 2012-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.settings;

import vibe.core.log;
import vibe.data.bson;
deprecated import vibe.db.mongo.flags : QueryFlags;
import vibe.inet.webform;

import core.time;
import std.conv : to;
import std.digest : toHexString;
import std.digest.md : md5Of;
import std.algorithm : splitter, startsWith;
import std.string : icmp, indexOf, toLower;


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
@safe {
	import std.exception : enforce;

	cfg = new MongoClientSettings();

	string tmpUrl = url[0..$]; // Slice of the URL (not a copy)

	if( !startsWith(tmpUrl, "mongodb://") )
	{
		return false;
	}

	// Reslice to get rid of 'mongodb://'
	tmpUrl = tmpUrl[10..$];

	auto authIndex = tmpUrl.indexOf('@');
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

	auto slashIndex = tmpUrl[hostIndex..$].indexOf("/");
	if( slashIndex == -1 ) slashIndex = tmpUrl.length;
	else slashIndex += hostIndex;

	// Parse the hosts section.
	try
	{
		foreach(entry; splitter(tmpUrl[hostIndex..slashIndex], ","))
		{
			auto hostPort = splitter(entry, ":");
			string host = hostPort.front;
			hostPort.popFront();
			ushort port = MongoClientSettings.defaultPort;
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
		foreach (option, value; options.byKeyValue) {
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

			bool setMsecs(ref Duration dst)
			{
				try {
					dst = to!long(value).msecs;
					return true;
				} catch( Exception e ){
					logError("Value for '%s' must be an integer but was '%s'.", option, value);
					return false;
				}
			}

			void warnNotImplemented()
			{
				logDiagnostic("MongoDB option %s not yet implemented.", option);
			}

			switch( option.toLower() ){
				import std.string : split;

				default: logWarn("Unknown MongoDB option %s", option); break;
				case "appname": cfg.appName = value; break;
				case "replicaset": cfg.replicaSet = value; warnNotImplemented(); break;
				case "safe": setBool(cfg.safe); break;
				case "fsync": setBool(cfg.fsync); break;
				case "journal": setBool(cfg.journal); break;
				case "connecttimeoutms": setMsecs(cfg.connectTimeout); break;
				case "sockettimeoutms": setMsecs(cfg.socketTimeout); break;
				case "tls": setBool(cfg.ssl); break;
				case "ssl": setBool(cfg.ssl); break;
				case "sslverifycertificate": setBool(cfg.sslverifycertificate); break;
				case "authmechanism": cfg.authMechanism = parseAuthMechanism(value); break;
				case "authmechanismproperties": cfg.authMechanismProperties = value.split(","); warnNotImplemented(); break;
				case "authsource": cfg.authSource = value; break;
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
	assert(cfg.replicaSet == "");
	assert(cfg.safe == false);
	assert(cfg.w == Bson.init);
	assert(cfg.wTimeoutMS == long.init);
	assert(cfg.fsync == false);
	assert(cfg.journal == false);
	assert(cfg.connectTimeoutMS == 10_000);
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
	assert(parseMongoDBUrl(cfg, "mongodb://host1,host2,host3/?safe=true&w=2&wtimeoutMS=2000&ssl=true&sslverifycertificate=false"));
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
	assert(cfg.ssl == true);
	assert(cfg.sslverifycertificate == false);

	cfg = MongoClientSettings.init;
	assert(parseMongoDBUrl(cfg,
				"mongodb://fred:flinstone@host1.example.com,host2.other.example.com:27108,host3:"
				~ "27019/mydb?journal=true;fsync=true;connectTimeoutms=1500;sockettimeoutMs=1000;w=majority"));
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

	assert(parseMongoDBUrl(cfg, "mongodb://me:sl$ash/w0+rd@localhost"));
	assert(cfg.digest == MongoClientSettings.makeDigest("me", "sl$ash/w0+rd"));
	assert(cfg.hosts.length == 1);
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);
	assert(parseMongoDBUrl(cfg, "mongodb://me:sl$ash/w0+rd@localhost/mydb"));
	assert(cfg.digest == MongoClientSettings.makeDigest("me", "sl$ash/w0+rd"));
	assert(cfg.database == "mydb");
	assert(cfg.hosts.length == 1);
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);
}

/**
 * Describes a vibe.d supported authentication mechanism to use on client
 * connection to a MongoDB server.
 */
enum MongoAuthMechanism
{
	/**
	 * Use no auth mechanism. If a digest or ssl certificate is given this
	 * defaults to trying the recommend auth mechanisms depending on server
	 * version and input parameters.
	 */
	none,

	/**
	 * Use SCRAM-SHA-1 as defined in [RFC 5802](http://tools.ietf.org/html/rfc5802)
	 *
	 * This is the default when a password is provided. In the future other
	 * scram algorithms may be implemented and selectable through these values.
	 *
	 * MongoDB: 3.0–
	 */
	scramSHA1,

	/**
	 * Forces login through the legacy MONGODB-CR authentication mechanism. This
	 * mechanism is a nonce and MD5 based system.
	 *
	 * MongoDB: 1.4–4.0 (deprecated 3.0)
	 */
	mongoDBCR,

	/**
	 * Use an X.509 certificate to authenticate. Only works if digest is set to
	 * null or empty string in the MongoClientSettings.
	 *
	 * MongoDB: 2.6–
	 */
	mongoDBX509
}

private MongoAuthMechanism parseAuthMechanism(string str)
@safe {
	switch (str) {
		case "SCRAM-SHA-1": return MongoAuthMechanism.scramSHA1;
		case "MONGODB-CR": return MongoAuthMechanism.mongoDBCR;
		case "MONGODB-X509": return MongoAuthMechanism.mongoDBX509;
		default: throw new Exception("Auth mechanism \"" ~ str ~ "\" not supported");
	}
}

/**
 * See_Also: $(LINK https://docs.mongodb.com/manual/reference/connection-string/#connections-connection-options)
 */
class MongoClientSettings
{
	/// Gets the default port used for MongoDB connections
	enum ushort defaultPort = 27017;

	/**
	 * If set to non-empty string, use this username to try to authenticate with
	 * to the database. Only has an effect if digest or sslPEMKeyFile is set too
	 *
	 * Use $(LREF authenticatePassword) or $(LREF authenticateSSL) to
	 * automatically fill this.
	 */
	string username;

	/**
	 * The password hashed as MongoDB digest as returned by $(LREF makeDigest).
	 *
	 * **DISCOURAGED** to fill this manually as future authentication mechanisms
	 * may use other digest algorithms.
	 *
	 * Use $(LREF authenticatePassword) to automatically fill this.
	 */
	string digest;

	/**
	 * Amount of maximum simultaneous connections to have open at the same time.
	 *
	 * Every MongoDB call may allocate a new connection if no previous ones are
	 * available and there is no connection associated with the calling Fiber.
	 */
	uint maxConnections = uint.max;

	/**
	 * MongoDB hosts to try to connect to.
	 *
	 * Bugs: currently only a connection to the first host is attempted, more
	 * hosts are simply ignored.
	 */
	MongoHost[] hosts;

	/**
	 * Default auth database to operate on, otherwise operating on special
	 * "admin" database for all MongoDB authentication commands.
	 */
	string database;

	deprecated("unused since at least before v3.6") QueryFlags defQueryFlags = QueryFlags.None;

	/**
	 * Specifies the name of the replica set, if the mongod is a member of a
	 * replica set.
	 *
	 * Bugs: Not yet implemented
	 */
	string replicaSet;

	/**
	 * Automatically check for errors when operating on collections and throw a
	 * $(REF MongoDBException, vibe,db,mongo,connection) in case of errors.
	 *
	 * Automatically set if either:
	 * * the "w" (write concern) parameter is set
	 * * the "wTimeoutMS" parameter is set
	 * * journal is true
	 */
	bool safe;

	/**
	 * Requests acknowledgment that write operations have propagated to a
	 * specified number of mongod instances (number) or to mongod instances with
	 * specified tags (string) or "majority" for calculated majority.
	 *
	 * See_Also: write concern [w Option](https://docs.mongodb.com/manual/reference/write-concern/#wc-w).
	 */
	Bson w; // Either a number or the string 'majority'

	/**
	 * Time limit for the w option to prevent write operations from blocking
	 * indefinitely.
	 *
	 * See_Also: $(LREF w)
	 */
	long wTimeoutMS;

	// undocumented feature in no documentation of >=MongoDB 2.2 ?!
	bool fsync;

	/**
	 * Requests acknowledgment that write operations have been written to the
	 * [on-disk journal](https://docs.mongodb.com/manual/core/journaling/).
	 *
	 * See_Also: write concern [j Option](https://docs.mongodb.com/manual/reference/write-concern/#wc-j).
	 */
	bool journal;

	/**
	 * The time to attempt a connection before timing out.
	 */
	Duration connectTimeout = 10.seconds;

	/// ditto
	long connectTimeoutMS() const @property
	@safe {
		return connectTimeout.total!"msecs";
	}

	/// ditto
	void connectTimeoutMS(long ms) @property
	@safe {
		connectTimeout = ms.msecs;
	}

	/**
	 * The time to attempt a send or receive on a socket before the attempt
	 * times out.
	 *
	 * Bugs: Not implemented for sending
	 */
	Duration socketTimeout = Duration.zero;

	/// ditto
	long socketTimeoutMS() const @property
	@safe {
		return socketTimeout.total!"msecs";
	}

	/// ditto
	void socketTimeoutMS(long ms) @property
	@safe {
		socketTimeout = ms.msecs;
	}

	/**
	 * Enables or disables TLS/SSL for the connection.
	 */
	bool ssl;

	/**
	 * Can be set to false to disable TLS peer validation to allow self signed
	 * certificates.
	 *
	 * This mode is discouraged and should ONLY be used in development.
	 */
	bool sslverifycertificate = true;

	/**
	 * Path to a certificate with private key and certificate chain to connect
	 * with.
	 */
	string sslPEMKeyFile;

	/**
	 * Path to a certificate authority file for verifying the remote
	 * certificate.
	 */
	string sslCAFile;

	/** 
	 * Specify the database name associated with the user's credentials. If
	 * `authSource` is unspecified, `authSource` defaults to the `defaultauthdb`
	 * specified in the connection string. If `defaultauthdb` is unspecified,
	 * then `authSource` defaults to `admin`.
	 *
	 * The `PLAIN` (LDAP), `GSSAPI` (Kerberos), and `MONGODB-AWS` (IAM)
	 * authentication mechanisms require that `authSource` be set to `$external`,
	 * as these mechanisms delegate credential storage to external services.
	 *
	 * Ignored if no username is provided.
	 */
	string authSource;

	/**
	 * Use the given authentication mechanism when connecting to the server. If
	 * unsupported by the server, throw a MongoAuthException.
	 *
	 * If set to none, but digest or sslPEMKeyFile are set, this automatically
	 * determines a suitable authentication mechanism based on server version.
	 */
	MongoAuthMechanism authMechanism;

	/** 
	 * Specify properties for the specified authMechanism as a comma-separated
	 * list of colon-separated key-value pairs.
	 *
	 * Currently none are used by the vibe.d Mongo driver.
	 */
	string[] authMechanismProperties;

	/**
	 * Application name for the connection information when connected.
	 *
	 * The application name is printed to the mongod logs upon establishing the
	 * connection. It is also recorded in the slow query logs and profile
	 * collections.
	 */
	string appName;

	/**
	 * Generates a digest string which can be used for authentication by setting
	 * the username and digest members.
	 *
	 * Use $(LREF authenticate) to automatically configure username and digest.
	 */
	static pure string makeDigest(string username, string password)
	@safe {
		return md5Of(username ~ ":mongo:" ~ password).toHexString().idup.toLower();
	}

	/**
	 * Sets the username and the digest string in this MongoClientSettings
	 * instance.
	 */
	void authenticatePassword(string username, string password)
	@safe {
		this.username = username;
		this.digest = MongoClientSettings.makeDigest(username, password);
	}

	/**
	 * Sets ssl, the username, the PEM key file and the trusted CA file in this
	 * MongoClientSettings instance.
	 *
	 * Params:
	 *   username = The username as provided in the cert file like
	 *   `"C=IS,ST=Reykjavik,L=Reykjavik,O=MongoDB,OU=Drivers,CN=client"`.
	 *
	 *   The username can be blank if connecting to MongoDB 3.4 or above.
	 *
	 *   sslPEMKeyFile = Path to a certificate with private key and certificate
	 *   chain to connect with.
	 *
	 *   sslCAFile = Optional path to a trusted certificate authority file for
	 *   verifying the remote certificate.
	 */
	void authenticateSSL(string username, string sslPEMKeyFile, string sslCAFile = null)
	@safe {
		this.ssl = true;
		this.digest = null;
		this.username = username;
		this.sslPEMKeyFile = sslPEMKeyFile;
		this.sslCAFile = sslCAFile;
	}

	/** 
	 * Resolves the database to run authentication commands on.
	 * (authSource if set, otherwise the URI's database if set, otherwise "admin")
	 */
	string getAuthDatabase()
	@safe @nogc nothrow pure const return {
		if (authSource.length)
			return authSource;
		else if (database.length)
			return database;
		else
			return "admin";
	}
}

/// Describes a host we might be able to connect to
struct MongoHost
{
	/// The host name or IP address of the remote MongoDB server.
	string name;
	/// The port of the MongoDB server. See `MongoClientSettings.defaultPort`.
	ushort port;
}
