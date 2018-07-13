/**
	MongoDB client connection settings.

	Copyright: © 2012-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.settings;

import vibe.core.log;
import vibe.data.bson;
import vibe.db.mongo.flags : QueryFlags;
import vibe.inet.webform;

import std.conv : to;
static if (__VERSION__ >= 2076)
	import std.digest : toHexString;
else
	import std.digest.digest : toHexString;
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

	string tmpUrl = url[0..$]; // Slice of the url (not a copy)

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
				logDiagnostic("MongoDB option %s not yet implemented.", option);
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
				case "authmechanism": cfg.authMechanism = parseAuthMechanism(value); break;
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

enum MongoAuthMechanism
{
	none,
	scramSHA1,
	mongoDBCR,
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

class MongoClientSettings
{
	enum ushort defaultPort = 27017;

	string username;
	string digest;
	uint maxConnections = uint.max;
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
	string sslPEMKeyFile;
	string sslCAFile;
	MongoAuthMechanism authMechanism;

	static string makeDigest(string username, string password)
	@safe {
		return md5Of(username ~ ":mongo:" ~ password).toHexString().idup.toLower();
	}
}

struct MongoHost
{
	string name;
	ushort port;
}
