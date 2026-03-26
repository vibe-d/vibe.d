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
import std.typecons : Nullable, nullable;


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

		cfg.password = password;
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
				case "replicaset": cfg.replicaSet = value; break;
				case "readpreference": cfg.readPreference = parseReadPreference(value); break;
				case "localthresholdms": setLong(cfg.localThresholdMS); break;
				case "maxstalenessseconds": setLong(cfg.maxStalenessSeconds); break;
				case "readconcernlevel": cfg.readConcern = parseReadConcern(value); break;
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
				case "compressors":
					import std.algorithm : map, filter;
					import std.array : array;
					cfg.compressors = value.splitter(",")
						.map!(c => parseCompressor(c))
						.filter!(c => !c.isNull)
						.map!(c => c.get)
						.array;
					break;
				case "zlibcompressionlevel":
					long level;
					if (setLong(level)) {
						cfg.zlibCompressionLevel = cast(int) level;
					}
					break;
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

/// parseMongoDBUrl parses minimal localhost URL with all defaults
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
}

/// parseMongoDBUrl parses URL with username and password
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://fred:foobar@localhost"));
	assert(cfg.username == "fred");
	assert(cfg.digest == MongoClientSettings.makeDigest("fred", "foobar"));
	assert(cfg.hosts.length == 1);
	assert(cfg.database == "");
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);
}

/// parseMongoDBUrl parses URL with empty password and database
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://fred:@localhost/baz"));
	assert(cfg.username == "fred");
	assert(cfg.digest == MongoClientSettings.makeDigest("fred", ""));
	assert(cfg.database == "baz");
	assert(cfg.hosts.length == 1);
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);
}

/// parseMongoDBUrl parses multi-host URL with safe, w, wtimeoutMS, ssl options
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://host1,host2,host3/?safe=true&w=2&wtimeoutMS=2000&ssl=true&sslverifycertificate=false"));
	assert(cfg.username == "");
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
}

/// parseMongoDBUrl parses full URL with credentials, multi-host with ports, database, and all options
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg,
				"mongodb://fred:flinstone@host1.example.com,host2.other.example.com:27108,host3:"
				~ "27019/mydb?journal=true;fsync=true;connectTimeoutms=1500;sockettimeoutMs=1000;w=majority"));
	assert(cfg.username == "fred");
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
}

/// parseMongoDBUrl returns false for invalid URLs
unittest
{
	MongoClientSettings cfg;

	assert(!(parseMongoDBUrl(cfg, "localhost:27018")));
	assert(!(parseMongoDBUrl(cfg, "http://blah")));
	assert(!(parseMongoDBUrl(cfg, "mongodb://@localhost")));
	assert(!(parseMongoDBUrl(cfg, "mongodb://:thepass@localhost")));
	assert(!(parseMongoDBUrl(cfg, "mongodb://:badport/")));
}

/// parseMongoDBUrl parses URL with special characters in password
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://me:sl$ash/w0+rd@localhost"));
	assert(cfg.digest == MongoClientSettings.makeDigest("me", "sl$ash/w0+rd"));
	assert(cfg.hosts.length == 1);
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);
}

/// parseMongoDBUrl parses URL with special characters in password and database
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://me:sl$ash/w0+rd@localhost/mydb"));
	assert(cfg.digest == MongoClientSettings.makeDigest("me", "sl$ash/w0+rd"));
	assert(cfg.database == "mydb");
	assert(cfg.hosts.length == 1);
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);
}

/// parseMongoDBUrl parses authMechanism=SCRAM-SHA-1
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://user:pass@localhost/?authMechanism=SCRAM-SHA-1"));
	assert(cfg.authMechanism == MongoAuthMechanism.scramSHA1);
}

/// parseMongoDBUrl parses authMechanism=MONGODB-CR
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://user:pass@localhost/?authMechanism=MONGODB-CR"));
	assert(cfg.authMechanism == MongoAuthMechanism.mongoDBCR);
}

/// parseMongoDBUrl parses authMechanism=MONGODB-X509
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://user:pass@localhost/?authMechanism=MONGODB-X509"));
	assert(cfg.authMechanism == MongoAuthMechanism.mongoDBX509);
}

/// parseMongoDBUrl throws on invalid authMechanism
unittest
{
	import std.exception : assertThrown;

	MongoClientSettings cfg;

	assertThrown!Exception(parseMongoDBUrl(cfg, "mongodb://user:pass@localhost/?authMechanism=INVALID"));
}

/// parseMongoDBUrl parses authSource overriding database for getAuthDatabase
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://user:pass@localhost/mydb?authSource=admin"));
	assert(cfg.authSource == "admin");
	assert(cfg.getAuthDatabase() == "admin");
}

/// parseMongoDBUrl parses appName option
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?appName=myApp"));
	assert(cfg.appName == "myApp");
}

/// parseMongoDBUrl parses replicaSet option
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?replicaSet=rs0"));
	assert(cfg.replicaSet == "rs0");
}

/// parseMongoDBUrl parses readPreference option
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?readPreference=secondaryPreferred"));
	assert(cfg.readPreference == ReadPreference.secondaryPreferred);
}

/// parseMongoDBUrl parses readPreference=primary (default)
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?readPreference=primary"));
	assert(cfg.readPreference == ReadPreference.primary);
}

/// parseMongoDBUrl parses readPreference combined with replicaSet
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?replicaSet=rs0&readPreference=nearest"));
	assert(cfg.replicaSet == "rs0");
	assert(cfg.readPreference == ReadPreference.nearest);
}

/// parseMongoDBUrl parses localThresholdMS option
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?localThresholdMS=25"));
	assert(cfg.localThresholdMS == 25);
}

/// parseMongoDBUrl uses default localThresholdMS of 15
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/"));
	assert(cfg.localThresholdMS == 15);
}

/// parseMongoDBUrl parses maxStalenessSeconds option
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?maxStalenessSeconds=120"));
	assert(cfg.maxStalenessSeconds == 120);
}

/// parseMongoDBUrl uses default maxStalenessSeconds of -1
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/"));
	assert(cfg.maxStalenessSeconds == -1);
}

/// parseMongoDBUrl parses readConcernLevel option
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?readConcernLevel=majority"));
	assert(cfg.readConcern.level == "majority");
}

/// parseMongoDBUrl defaults readConcern to empty
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost"));
	assert(cfg.readConcern.level == "");
}

/// parseMongoDBUrl parses tls=true as ssl alias
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?tls=true"));
	assert(cfg.ssl == true);
}

/// parseMongoDBUrl parses tls=false as ssl alias
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?tls=false"));
	assert(cfg.ssl == false);
}

/// parseMongoDBUrl parses connectTimeoutMS
unittest
{
	import core.time : msecs;

	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?connectTimeoutMS=5000"));
	assert(cfg.connectTimeout == 5000.msecs);
	assert(cfg.connectTimeoutMS == 5000);
}

/// parseMongoDBUrl parses socketTimeoutMS
unittest
{
	import core.time : msecs;

	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?socketTimeoutMS=3000"));
	assert(cfg.socketTimeout == 3000.msecs);
	assert(cfg.socketTimeoutMS == 3000);
}

/// parseMongoDBUrl parses w=1 as integer write concern
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?w=1"));
	assert(cfg.w == Bson(1L));
}

/// parseMongoDBUrl parses w=majority as string write concern
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?w=majority"));
	assert(cfg.w == Bson("majority"));
}

/// parseMongoDBUrl sets safe=true when journal=true
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?journal=true"));
	assert(cfg.journal == true);
	assert(cfg.safe == true);
}

/// parseMongoDBUrl sets safe=true when fsync=true
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?fsync=true"));
	assert(cfg.fsync == true);
	assert(cfg.safe == true);
}

/// parseMongoDBUrl parses sslverifycertificate=false
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?sslverifycertificate=false"));
	assert(cfg.sslverifycertificate == false);
}

/// parseMongoDBUrl parses multiple combined options
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?appName=test&replicaSet=rs1&ssl=true&authSource=admin"));
	assert(cfg.appName == "test");
	assert(cfg.replicaSet == "rs1");
	assert(cfg.ssl == true);
	assert(cfg.authSource == "admin");
}

/// parseMongoDBUrl parses URL with database and no options
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/mydb"));
	assert(cfg.database == "mydb");
	assert(cfg.hosts[0].name == "localhost");
	assert(cfg.hosts[0].port == 27017);
}

/// parseMongoDBUrl parses URL with database and trailing empty query string
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/mydb?"));
	assert(cfg.database == "mydb");
}

/// parseMongoDBUrl parses URL with no database but with options
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?safe=true"));
	assert(cfg.database == "");
	assert(cfg.safe == true);
}

/// parseMongoDBUrl parses explicit non-default port
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost:27018"));
	assert(cfg.hosts[0].port == 27018);
}

/// parseMongoDBUrl parses minimum valid port 1
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost:1"));
	assert(cfg.hosts[0].port == 1);
}

/// parseMongoDBUrl parses maximum valid port 65535
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost:65535"));
	assert(cfg.hosts[0].port == 65535);
}

/// parseMongoDBUrl parses port 0
unittest
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost:0"));
	assert(cfg.hosts[0].port == 0);
}

/// parseMongoDBUrl returns false for port exceeding ushort range
unittest
{
	MongoClientSettings cfg;

	assert(!parseMongoDBUrl(cfg, "mongodb://localhost:65536"));
}

/// parseMongoDBUrl returns false for non-numeric port
unittest
{
	MongoClientSettings cfg;

	assert(!parseMongoDBUrl(cfg, "mongodb://localhost:abc"));
}

/// getAuthDatabase returns authSource when set
unittest
{
	auto cfg = new MongoClientSettings();
	cfg.authSource = "external";
	cfg.database = "mydb";
	assert(cfg.getAuthDatabase() == "external");
}

/// getAuthDatabase returns database when authSource is empty
unittest
{
	auto cfg = new MongoClientSettings();
	cfg.database = "mydb";
	assert(cfg.getAuthDatabase() == "mydb");
}

/// getAuthDatabase returns "admin" when both authSource and database are empty
unittest
{
	auto cfg = new MongoClientSettings();
	assert(cfg.getAuthDatabase() == "admin");
}

/// makeDigest produces deterministic output for same inputs
unittest
{
	assert(MongoClientSettings.makeDigest("user", "pass") ==
	       MongoClientSettings.makeDigest("user", "pass"));
}

/// makeDigest produces different output for different passwords
unittest
{
	assert(MongoClientSettings.makeDigest("user", "pass1") !=
	       MongoClientSettings.makeDigest("user", "pass2"));
}

/// makeDigest produces different output for different usernames
unittest
{
	assert(MongoClientSettings.makeDigest("user1", "pass") !=
	       MongoClientSettings.makeDigest("user2", "pass"));
}

/// connectTimeoutMS defaults to 10000 and round-trips through Duration
unittest
{
	import core.time : msecs, seconds;

	auto cfg = new MongoClientSettings();

	assert(cfg.connectTimeoutMS == 10_000);
	assert(cfg.connectTimeout == 10.seconds);

	cfg.connectTimeoutMS = 2500;
	assert(cfg.connectTimeout == 2500.msecs);
	assert(cfg.connectTimeoutMS == 2500);

	cfg.connectTimeout = 7.seconds;
	assert(cfg.connectTimeoutMS == 7000);
}

/// socketTimeoutMS defaults to 0 and round-trips through Duration
unittest
{
	import core.time : msecs;

	auto cfg = new MongoClientSettings();

	assert(cfg.socketTimeoutMS == 0);

	cfg.socketTimeoutMS = 5000;
	assert(cfg.socketTimeout == 5000.msecs);
	assert(cfg.socketTimeoutMS == 5000);
}

/// authenticatePassword sets username and digest
unittest
{
	auto cfg = new MongoClientSettings();

	cfg.authenticatePassword("fred", "secret");
	assert(cfg.username == "fred");
	assert(cfg.digest == MongoClientSettings.makeDigest("fred", "secret"));
}

/// authenticateSSL sets ssl, username, PEM key file, and CA file
unittest
{
	auto cfg = new MongoClientSettings();

	cfg.authenticateSSL("CN=client", "/path/to/cert.pem", "/path/to/ca.pem");
	assert(cfg.ssl == true);
	assert(cfg.username == "CN=client");
	assert(cfg.digest is null);
	assert(cfg.sslPEMKeyFile == "/path/to/cert.pem");
	assert(cfg.sslCAFile == "/path/to/ca.pem");
}

/// authenticateSSL without CA file sets sslCAFile to null
unittest
{
	auto cfg = new MongoClientSettings();

	cfg.authenticateSSL("CN=client2", "/path/to/cert2.pem");
	assert(cfg.sslCAFile is null);
}

/// parseMongoDBUrl parses single compressor option
unittest
{
	MongoClientSettings cfg;
	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?compressors=zlib"));
	assert(cfg.compressors == [Compressor.zlib]);
}

/// parseMongoDBUrl parses multiple compressors preserving order
unittest
{
	MongoClientSettings cfg;
	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?compressors=snappy,zlib,zstd"));
	assert(cfg.compressors == [Compressor.snappy, Compressor.zlib, Compressor.zstd]);
}

/// parseMongoDBUrl parses compressors together with zlibCompressionLevel
unittest
{
	MongoClientSettings cfg;
	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?compressors=zlib&zlibCompressionLevel=6"));
	assert(cfg.compressors == [Compressor.zlib]);
	assert(cfg.zlibCompressionLevel == 6);
}

/// parseMongoDBUrl silently skips unknown compressors
unittest
{
	MongoClientSettings cfg;
	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?compressors=bogus,zlib"));
	assert(cfg.compressors == [Compressor.zlib]);
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
	 * Use SCRAM-SHA-256 as defined in [RFC 7677](http://tools.ietf.org/html/rfc7677)
	 *
	 * Preferred over SCRAM-SHA-1 when supported by the server. Uses the raw
	 * password (with SASLprep) instead of the MD5 digest.
	 *
	 * MongoDB: 4.0–
	 */
	scramSHA256,

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
		case "SCRAM-SHA-256": return MongoAuthMechanism.scramSHA256;
		case "MONGODB-CR": return MongoAuthMechanism.mongoDBCR;
		case "MONGODB-X509": return MongoAuthMechanism.mongoDBX509;
		default: throw new Exception("Auth mechanism \"" ~ str ~ "\" not supported");
	}
}

/**
  Specifies a level of isolation for read operations. For example, you can use read concern to only
  read data that has propagated to a majority of nodes in a replica set.

  See_Also: $(LINK https://docs.mongodb.com/manual/reference/read-concern/)
 */
struct ReadConcern {
	///
	enum Level : string {
		/// This is the default read concern level.
		local = "local",
		/// This is the default for reads against secondaries when afterClusterTime and "level" are unspecified.
		/// The query returns the instance's most recent data.
		available = "available",
		/// Available for replica sets that use WiredTiger storage engine.
		majority = "majority",
		/// Available for read operations on the primary only.
		linearizable = "linearizable",
		/// Available for read operations within multi-document transactions.
		snapshot = "snapshot"
	}

	/// The level of the read concern.
	string level;
}

/**
 * Determines which replica set members are acceptable for read operations.
 *
 * See_Also: $(LINK https://www.mongodb.com/docs/manual/core/read-preference/)
 */
enum ReadPreference
{
	/** Route all reads to the primary. This is the default. */
	primary,

	/** Read from the primary if available, otherwise a secondary. */
	primaryPreferred,

	/** Route all reads to secondaries. */
	secondary,

	/** Read from a secondary if available, otherwise the primary. */
	secondaryPreferred,

	/** Read from the member with the lowest network latency. */
	nearest,
}

private ReadConcern parseReadConcern(string str)
@safe {
	import std.traits : EnumMembers;
	switch (str) {
		default:
			throw new Exception("Read concern level \"" ~ str ~ "\" not supported");
		static foreach (level; EnumMembers!(ReadConcern.Level))
			case level:
				return ReadConcern(level);
	}
}

private ReadPreference parseReadPreference(string str)
@safe {
	switch (str) {
		case "primary": return ReadPreference.primary;
		case "primaryPreferred": return ReadPreference.primaryPreferred;
		case "secondary": return ReadPreference.secondary;
		case "secondaryPreferred": return ReadPreference.secondaryPreferred;
		case "nearest": return ReadPreference.nearest;
		default: throw new Exception("Read preference \"" ~ str ~ "\" not supported");
	}
}

/**
 * Compression algorithm identifier for OP_COMPRESSED wire protocol messages.
 *
 * See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/mongodb-wire-protocol/#op_compressed)
 */
enum Compressor : ubyte {
	noop   = 0,
	snappy = 1,
	zlib   = 2,
	zstd   = 3,
}

string compressorName(Compressor c)
@safe pure nothrow {
	final switch (c) {
		case Compressor.noop:   return "noop";
		case Compressor.snappy: return "snappy";
		case Compressor.zlib:   return "zlib";
		case Compressor.zstd:   return "zstd";
	}
}

private Nullable!Compressor parseCompressor(const(char)[] name)
@safe {
	import std.string : strip;

	switch (strip(name)) {
		case "noop":   return nullable(Compressor.noop);
		case "snappy": return nullable(Compressor.snappy);
		case "zlib":   return nullable(Compressor.zlib);
		case "zstd":   return nullable(Compressor.zstd);
		default:
			logWarn("Unknown compressor: %s", name);
			return Nullable!Compressor.init;
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
	 * The raw password, needed for SCRAM-SHA-256 which does not use the MD5
	 * digest. Stored alongside digest for backward compatibility.
	 *
	 * Use $(LREF authenticatePassword) to automatically fill this.
	 */
	string password;

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
	 * When connecting to a replica set, each host is tried in order. If a
	 * secondary is reached, the driver follows the reported primary.
	 */
	MongoHost[] hosts;

	/**
	 * Default auth database to operate on, otherwise operating on special
	 * "admin" database for all MongoDB authentication commands.
	 */
	string database;

	/**
	 * Specifies the name of the replica set, if the mongod is a member of a
	 * replica set. When set, the driver validates that any connected server
	 * belongs to this replica set and discovers the primary through
	 * secondary-to-primary chasing.
	 */
	string replicaSet;

	/**
	 * Specifies the read preference mode for this connection.
	 *
	 * See_Also: $(LINK https://www.mongodb.com/docs/manual/core/read-preference/)
	 */
	ReadPreference readPreference;

	/**
	 * Upper bound on the acceptable latency window for nearest server selection.
	 * Servers within (fastest RTT + localThresholdMS) are eligible.
	 * Default: 15ms per MongoDB spec.
	 *
	 * See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/connection-string/#urioption.localThresholdMS)
	 */
	long localThresholdMS = 15;

	/**
	 * Maximum replication lag (in seconds) for a secondary to be eligible.
	 * -1 means no max staleness check. Minimum allowed value is 90 seconds.
	 *
	 * See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/connection-string/#urioption.maxStalenessSeconds)
	 */
	long maxStalenessSeconds = -1;

	/**
	 * Specifies the default read concern level for read operations.
	 *
	 * See_Also: $(LINK https://docs.mongodb.com/manual/reference/read-concern/)
	 */
	ReadConcern readConcern;

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
	 * Ordered list of compression algorithms the client is willing to use.
	 * The server picks the first one it supports.
	 *
	 * See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/connection-string/#urioption.compressors)
	 */
	Compressor[] compressors;

	/**
	 * Compression level for zlib (1-9). -1 means default (level 6).
	 */
	int zlibCompressionLevel = -1;

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
		this.password = password;
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

	bool opEquals(const MongoHost other) const @safe @nogc pure nothrow
	{
		return name == other.name && port == other.port;
	}
}

/**
 * Parses a "host:port" string into a MongoHost. Returns MongoHost.init if
 * the string cannot be parsed.
 */
MongoHost parseHostPort(string hostPort) @safe pure nothrow
{
	import std.string : indexOf;
	import std.conv : to;

	if (!hostPort.length)
		return MongoHost.init;

	auto colonIdx = hostPort.indexOf(':');
	if (colonIdx <= 0 || colonIdx >= cast(ptrdiff_t)(hostPort.length - 1))
		return MongoHost.init;

	try {
		return MongoHost(
			hostPort[0 .. colonIdx],
			hostPort[colonIdx + 1 .. $].to!ushort
		);
	} catch (Exception) {
		return MongoHost.init;
	}
}

/// parseHostPort parses valid host:port string
@safe pure nothrow unittest
{
	auto host = parseHostPort("mongo1.example.com:27017");
	assert(host.name == "mongo1.example.com");
	assert(host.port == 27017);
}

/// parseHostPort parses non-default port
@safe pure nothrow unittest
{
	auto host = parseHostPort("10.0.0.1:27018");
	assert(host.name == "10.0.0.1");
	assert(host.port == 27018);
}

/// parseHostPort returns init for empty string
@safe pure nothrow unittest
{
	assert(parseHostPort("") == MongoHost.init);
}

/// parseHostPort returns init for host without port
@safe pure nothrow unittest
{
	assert(parseHostPort("localhost") == MongoHost.init);
}

/// parseHostPort returns init for host with colon but no port
@safe pure nothrow unittest
{
	assert(parseHostPort("localhost:") == MongoHost.init);
}

/// parseHostPort returns init for colon-only string
@safe pure nothrow unittest
{
	assert(parseHostPort(":27017") == MongoHost.init);
}

/// parseHostPort returns init for non-numeric port
@safe pure nothrow unittest
{
	assert(parseHostPort("localhost:abc") == MongoHost.init);
}

/// parseHostPort returns init for port exceeding ushort range
@safe pure nothrow unittest
{
	assert(parseHostPort("localhost:99999") == MongoHost.init);
}

/// MongoHost equality compares both name and port
@safe pure nothrow @nogc unittest
{
	assert(MongoHost("a", 1) == MongoHost("a", 1));
	assert(MongoHost("a", 1) != MongoHost("a", 2));
	assert(MongoHost("a", 1) != MongoHost("b", 1));
}

/// MongoHost.init has empty name and port 0
@safe pure nothrow @nogc unittest
{
	auto h = MongoHost.init;
	assert(h.name == "");
	assert(h.port == 0);
}
