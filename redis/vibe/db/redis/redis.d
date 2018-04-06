/**
	Redis database client implementation.

	Copyright: © 2012-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger, Sönke Ludwig, Michael Eisendle, Etienne Cimon
*/
module vibe.db.redis.redis;

public import vibe.core.net;

import vibe.core.connectionpool;
import vibe.core.core;
import vibe.core.log;
import vibe.inet.url;
import vibe.internal.allocator;
import vibe.internal.freelistref;
import vibe.stream.operations;
import std.conv;
import std.exception;
import std.format;
import std.range : isInputRange, isOutputRange;
import std.string;
import std.traits;
import std.typecons : Nullable;
import std.utf;

@safe:


/**
	Returns a RedisClient that can be used to communicate to the specified database server.
*/
RedisClient connectRedis(string host, ushort port = RedisClient.defaultPort)
{
	return new RedisClient(host, port);
}

/**
	Returns a Redis database connection instance corresponding to the given URL.

	The URL must be of the format "redis://server[:port]/dbnum".

	Authentication:
		Authenticated connections are supported by using a URL connection string
		such as "redis://password@host".

	Examples:
		---
		// connecting with default settings:
		auto redisDB = connectRedisDB("redis://127.0.0.1");
		---

		---
		// connecting using the URL form with custom settings
		auto redisDB = connectRedisDB("redis://password:myremotehost/3?maxmemory=10000000");
		---

	Params:
		url = Redis URI scheme for a Redis database instance
		host_or_url = Can either be a host name, in which case the default port will be used, or a URL with the redis:// scheme.

	Returns:
		A new RedisDatabase instance that can be used to access the database.

	See_also: $(LINK2 https://www.iana.org/assignments/uri-schemes/prov/redis, Redis URI scheme)
*/
RedisDatabase connectRedisDB(URL url)
{
	auto cli = connectRedis(url.host, url.port != 0 ? url.port : RedisClient.defaultPort);

	if (!url.queryString.empty)
	{
		import vibe.inet.webform : FormFields, parseURLEncodedForm;
		auto query = FormFields.init;
		parseURLEncodedForm(url.queryString, query);
		foreach (param, val; query.byKeyValue)
		{
			switch (param)
			{
				/**
				The password to use for the Redis AUTH command comes from either the
				password portion of the "userinfo" URI field or the value from the
				key-value pair from the "query" URI field with the key "password".
				If both the password portion of the "userinfo" URI field and a
				"query" URI field key-value pair with the key "password" are present,
				the semantics for what password to use for authentication are not
				well-defined.  Such situations therefore ought to be avoided.
				*/
				case "password":
					if (!url.password.empty)
						cli.auth(val);
					break;
				default:
					throw new Exception(`Redis config parameter "` ~ param ~ `" isn't supported`);
			}
		}
	}

	/*
	Redis' current optional authentication mechanism does not employ a
	username, but this might change in the future
	*/
	if (!url.password.empty)
		cli.auth(url.password);

	long databaseIndex;
	if (url.localURI.length >= 2)
		databaseIndex = url.pathString[1 .. $].to!long;

	return cli.getDatabase(databaseIndex);
}

/**
	A redis client with connection pooling.
*/
final class RedisClient {
	private {
		ConnectionPool!RedisConnection m_connections;
		string m_authPassword;
		string m_version;
		long m_selectedDB;
	}

	enum defaultPort = 6379;

	this(string host = "127.0.0.1", ushort port = defaultPort)
	{
		m_connections = new ConnectionPool!RedisConnection({
			return new RedisConnection(host, port);
		});
	}

	/// Returns Redis version
	@property string redisVersion()
	{
		if(m_version == "")
		{
			import std.string;
			auto info = info();
			auto lines = info.splitLines();
			if (lines.length > 1) {
				foreach (string line; lines) {
					auto lineParams = line.split(":");
					if (lineParams.length > 1 && lineParams[0] == "redis_version") {
						m_version = lineParams[1];
						break;
					}
				}
			}
		}

		return m_version;
	}

	/** Returns a handle to the given database.
	*/
	RedisDatabase getDatabase(long index) { return RedisDatabase(this, index); }

	/** Creates a RedisSubscriber instance for launching a pubsub listener
	*/
	RedisSubscriber createSubscriber() {
		return RedisSubscriber(this);
	}

	/*
		Connection
	*/

	/// Authenticate to the server
	void auth(string password) { m_authPassword = password; }
	/// Echo the given string
	T echo(T, U)(U data) if(isValidRedisValueReturn!T && isValidRedisValueType!U) { return request!T("ECHO", data); }
	/// Ping the server
	void ping() { request("PING"); }
	/// Close the connection
	void quit() { request("QUIT"); }

	/*
		Server
	*/

	//TODO: BGREWRITEAOF
	//TODO: BGSAVE

	/// Get the value of a configuration parameter
	T getConfig(T)(string parameter) if(isValidRedisValueReturn!T) { return request!T("CONFIG", "GET", parameter); }
	/// Set a configuration parameter to the given value
	void setConfig(T)(string parameter, T value) if(isValidRedisValueType!T) { request("CONFIG", "SET", parameter, value); }
	/// Reset the stats returned by INFO
	void configResetStat() { request("CONFIG", "RESETSTAT"); }

	//TOOD: Debug Object
	//TODO: Debug Segfault

	/** Deletes all keys from all databases.

		See_also: $(LINK2 http://redis.io/commands/flushall, FLUSHALL)
	*/
	void deleteAll() { request("FLUSHALL"); }

	/// Get information and statistics about the server
	string info() { return request!string("INFO"); }
	/// Get the UNIX time stamp of the last successful save to disk
	long lastSave() { return request!long("LASTSAVE"); }
	//TODO monitor
	/// Synchronously save the dataset to disk
	void save() { request("SAVE"); }
	/// Synchronously save the dataset to disk and then shut down the server
	void shutdown() { request("SHUTDOWN"); }
	/// Make the server a slave of another instance, or promote it as master
	void slaveOf(string host, ushort port) { request("SLAVEOF", host, port); }

	//TODO slowlog
	//TODO sync

	private T request(T = void, ARGS...)(string command, scope ARGS args)
	{
		return requestDB!(T, ARGS)(m_selectedDB, command, args);
	}

	private T requestDB(T, ARGS...)(long db, string command, scope ARGS args)
	{
		auto conn = m_connections.lockConnection();
		conn.setAuth(m_authPassword);
		conn.setDB(db);
		version (RedisDebug) {
			import std.conv;
			string debugargs = command;
			foreach (i, A; ARGS) debugargs ~= ", " ~ args[i].to!string;
		}

		static if (is(T == void)) {
			version (RedisDebug) logDebug("Redis request: %s => void", debugargs);
			_request!void(conn, command, args);
		} else static if (!isInstanceOf!(RedisReply, T)) {
			auto ret = _request!T(conn, command, args);
			version (RedisDebug) logDebug("Redis request: %s => %s", debugargs, ret.to!string);
			return ret;
		} else {
			auto ret = _request!T(conn, command, args);
			version (RedisDebug) logDebug("Redis request: %s => RedisReply", debugargs);
			return ret;
		}
	}
}


/**
	Accesses the contents of a Redis database
*/
struct RedisDatabase {
	private {
		RedisClient m_client;
		long m_index;
	}

	private this(RedisClient client, long index)
	{
		m_client = client;
		m_index = index;
	}

	/** The Redis client with which the database is accessed.
	*/
	@property inout(RedisClient) client() inout { return m_client; }

	/** Index of the database.
	*/
	@property long index() const { return m_index; }

	/** Deletes all keys of the database.

		See_also: $(LINK2 http://redis.io/commands/flushdb, FLUSHDB)
	*/
	void deleteAll() { request!void("FLUSHDB"); }
	/// Delete a key
	long del(scope string[] keys...) { return request!long("DEL", keys); }
	/// Determine if a key exists
	bool exists(string key) { return request!bool("EXISTS", key); }
	/// Set a key's time to live in seconds
	bool expire(string key, long seconds) { return request!bool("EXPIRE", key, seconds); }
	/// Set a key's time to live with D notation. E.g. $(D 5.minutes) for 60 * 5 seconds.
	bool expire(string key, Duration timeout) { return request!bool("PEXPIRE", key, timeout.total!"msecs"); }
	/// Set the expiration for a key as a UNIX timestamp
	bool expireAt(string key, long timestamp) { return request!bool("EXPIREAT", key, timestamp); }
	/// Find all keys matching the given glob-style pattern (Supported wildcards: *, ?, [ABC])
	RedisReply!T keys(T = string)(string pattern) if(isValidRedisValueType!T) { return request!(RedisReply!T)("KEYS", pattern); }
	/// Move a key to another database
	bool move(string key, long db) { return request!bool("MOVE", key, db); }
	/// Remove the expiration from a key
	bool persist(string key) { return request!bool("PERSIST", key); }
	//TODO: object
	/// Return a random key from the keyspace
	string randomKey() { return request!string("RANDOMKEY"); }
	/// Rename a key
	void rename(string key, string newkey) { request("RENAME", key, newkey); }
	/// Rename a key, only if the new key does not exist
	bool renameNX(string key, string newkey) { return request!bool("RENAMENX", key, newkey); }
	//TODO sort
	/// Get the time to live for a key
	long ttl(string key) { return request!long("TTL", key); }
	/// Get the time to live for a key in milliseconds
	long pttl(string key) { return request!long("PTTL", key); }
	/// Determine the type stored at key (string, list, set, zset and hash.)
	string type(string key) { return request!string("TYPE", key); }

	/*
		String Commands
	*/

	/// Append a value to a key
	long append(T)(string key, T suffix) if(isValidRedisValueType!T) { return request!long("APPEND", key, suffix); }
	/// Decrement the integer value of a key by one
	long decr(string key, long value = 1) { return value == 1 ? request!long("DECR", key) : request!long("DECRBY", key, value); }
	/// Get the value of a key
	T get(T = string)(string key) if(isValidRedisValueReturn!T) { return request!T("GET", key); }
	/// Returns the bit value at offset in the string value stored at key
	bool getBit(string key, long offset) { return request!bool("GETBIT", key, offset); }
	/// Get a substring of the string stored at a key
	T getRange(T = string)(string key, long start, long end) if(isValidRedisValueReturn!T) { return request!T("GETRANGE", key, start, end); }
	/// Set the string value of a key and return its old value
	T getSet(T = string, U)(string key, U value) if(isValidRedisValueReturn!T && isValidRedisValueType!U) { return request!T("GETSET", key, value); }
	/// Increment the integer value of a key
	long incr(string key, long value = 1) { return value == 1 ? request!long("INCR", key) : request!long("INCRBY", key, value); }
	/// Increment the real number value of a key
	long incr(string key, double value) { return request!long("INCRBYFLOAT", key, value); }
	/// Get the values of all the given keys
	RedisReply!T mget(T = string)(string[] keys) if(isValidRedisValueType!T) { return request!(RedisReply!T)("MGET", keys); }

	/// Set multiple keys to multiple values
	void mset(ARGS...)(ARGS args)
	{
		static assert(ARGS.length % 2 == 0 && ARGS.length >= 2, "Arguments to mset must be pairs of key/value");
		foreach (i, T; ARGS ) static assert(i % 2 != 0 || is(T == string), "Keys must be strings.");
		request("MSET", args);
	}

	/// Set multiple keys to multiple values, only if none of the keys exist
	bool msetNX(ARGS...)(ARGS args) {
		static assert(ARGS.length % 2 == 0 && ARGS.length >= 2, "Arguments to mset must be pairs of key/value");
		foreach (i, T; ARGS ) static assert(i % 2 != 0 || is(T == string), "Keys must be strings.");
		return request!bool("MSETEX", args);
	}

	/// Set the string value of a key
	void set(T)(string key, T value) if(isValidRedisValueType!T) { request("SET", key, value); }
	/// Set the value of a key, only if the key does not exist
	bool setNX(T)(string key, T value) if(isValidRedisValueType!T) { return request!bool("SETNX", key, value); }
	/// Set the value of a key, only if the key already exists
	bool setXX(T)(string key, T value) if(isValidRedisValueType!T) { return "OK" == request!string("SET", key, value, "XX"); }
	/// Set the value of a key, only if the key does not exist, and also set the specified expire time using D notation, e.g. $(D 5.minutes) for 5 minutes.
	bool setNX(T)(string key, T value, Duration expire_time) if(isValidRedisValueType!T) { return "OK" == request!string("SET", key, value, "PX", expire_time.total!"msecs", "NX"); }
	/// Set the value of a key, only if the key already exists, and also set the specified expire time using D notation, e.g. $(D 5.minutes) for 5 minutes.
	bool setXX(T)(string key, T value, Duration expire_time) if(isValidRedisValueType!T) { return "OK" == request!string("SET", key, value, "PX", expire_time.total!"msecs", "XX"); }
	/// Sets or clears the bit at offset in the string value stored at key
	bool setBit(string key, long offset, bool value) { return request!bool("SETBIT", key, offset, value ? "1" : "0"); }
	/// Set the value and expiration of a key
	void setEX(T)(string key, long seconds, T value) if(isValidRedisValueType!T) { request("SETEX", key, seconds, value); }
	/// Overwrite part of a string at key starting at the specified offset
	long setRange(T)(string key, long offset, T value) if(isValidRedisValueType!T) { return request!long("SETRANGE", key, offset, value); }
	/// Get the length of the value stored in a key
	long strlen(string key) { return request!long("STRLEN", key); }

	/*
		Hashes
	*/
	/// Delete one or more hash fields
	long hdel(string key, scope string[] fields...) { return request!long("HDEL", key, fields); }
	/// Determine if a hash field exists
	bool hexists(string key, string field) { return request!bool("HEXISTS", key, field); }
	/// Set multiple hash fields to multiple values
	void hset(T)(string key, string field, T value) if(isValidRedisValueType!T) { request("HSET", key, field, value); }
	/// Set the value of a hash field, only if the field does not exist
	bool hsetNX(T)(string key, string field, T value) if(isValidRedisValueType!T) { return request!bool("HSETNX", key, field, value); }
	/// Get the value of a hash field.
	T hget(T = string)(string key, string field) if(isValidRedisValueReturn!T) { return request!T("HGET", key, field); }
	/// Get all the fields and values in a hash
	RedisReply!T hgetAll(T = string)(string key) if(isValidRedisValueType!T) { return request!(RedisReply!T)("HGETALL", key); }
	/// Increment the integer value of a hash field
	long hincr(string key, string field, long value=1) { return request!long("HINCRBY", key, field, value); }
	/// Increment the real number value of a hash field
	long hincr(string key, string field, double value) { return request!long("HINCRBYFLOAT", key, field, value); }
	/// Get all the fields in a hash
	RedisReply!T hkeys(T = string)(string key) if(isValidRedisValueType!T) { return request!(RedisReply!T)("HKEYS", key); }
	/// Get the number of fields in a hash
	long hlen(string key) { return request!long("HLEN", key); }
	/// Get the values of all the given hash fields
	RedisReply!T hmget(T = string)(string key, scope string[] fields...) if(isValidRedisValueType!T) { return request!(RedisReply!T)("HMGET", key, fields); }
	/// Set multiple hash fields to multiple values
	void hmset(ARGS...)(string key, ARGS args) { request("HMSET", key, args); }

	/// Get all the values in a hash
	RedisReply!T hvals(T = string)(string key) if(isValidRedisValueType!T) { return request!(RedisReply!T)("HVALS", key); }

	/*
		Lists
	*/
	/// Get an element from a list by its index
	T lindex(T = string)(string key, long index) if(isValidRedisValueReturn!T) { return request!T("LINDEX", key, index); }
	/// Insert value in the list stored at key before the reference value pivot.
	long linsertBefore(T1, T2)(string key, T1 pivot, T2 value) if(isValidRedisValueType!T1 && isValidRedisValueType!T2) { return request!long("LINSERT", key, "BEFORE", pivot, value); }
	/// Insert value in the list stored at key after the reference value pivot.
	long linsertAfter(T1, T2)(string key, T1 pivot, T2 value) if(isValidRedisValueType!T1 && isValidRedisValueType!T2) { return request!long("LINSERT", key, "AFTER", pivot, value); }
	/// Returns the length of the list stored at key. If key does not exist, it is interpreted as an empty list and 0 is returned.
	long llen(string key) { return request!long("LLEN", key); }
	/// Insert all the specified values at the head of the list stored at key.
	long lpush(ARGS...)(string key, ARGS args) { return request!long("LPUSH", key, args); }
	/// Inserts value at the head of the list stored at key, only if key already exists and holds a list.
	long lpushX(T)(string key, T value) if(isValidRedisValueType!T) { return request!long("LPUSHX", key, value); }
	/// Insert all the specified values at the tail of the list stored at key.
	long rpush(ARGS...)(string key, ARGS args) { return request!long("RPUSH", key, args); }
	/// Inserts value at the tail of the list stored at key, only if key already exists and holds a list.
	long rpushX(T)(string key, T value) if(isValidRedisValueType!T) { return request!long("RPUSHX", key, value); }
	/// Returns the specified elements of the list stored at key.
	RedisReply!T lrange(T = string)(string key, long start, long stop) { return request!(RedisReply!T)("LRANGE",  key, start, stop); }
	/// Removes the first count occurrences of elements equal to value from the list stored at key.
	long lrem(T)(string key, long count, T value) if(isValidRedisValueType!T) { return request!long("LREM", key, count, value); }
	/// Sets the list element at index to value.
	void lset(T)(string key, long index, T value) if(isValidRedisValueType!T) { request("LSET", key, index, value); }
	/// Trim an existing list so that it will contain only the specified range of elements specified.
	/// Equivalent to $(D range = range[start .. stop+1])
	void ltrim(string key, long start, long stop) { request("LTRIM",  key, start, stop); }
	/// Removes and returns the last element of the list stored at key.
	T rpop(T = string)(string key) if(isValidRedisValueReturn!T) { return request!T("RPOP", key); }
	/// Removes and returns the first element of the list stored at key.
	T lpop(T = string)(string key) if(isValidRedisValueReturn!T) { return request!T("LPOP", key); }
	/// BLPOP is a blocking list pop primitive. It is the blocking version of LPOP because it blocks
	/// the connection when there are no elements to pop from any of the given lists.
	Nullable!(Tuple!(string, T)) blpop(T = string)(string key, long seconds) if(isValidRedisValueReturn!T)
	{
		auto reply = request!(RedisReply!(ubyte[]))("BLPOP", key, seconds);
		Nullable!(Tuple!(string, T)) ret;
		if (reply.empty || reply.frontIsNull) return ret;
		string rkey = reply.front.convertToType!string();
		reply.popFront();
		ret = tuple(rkey, reply.front.convertToType!T());
		return ret;
	}
	/// Atomically returns and removes the last element (tail) of the list stored at source,
	/// and pushes the element at the first element (head) of the list stored at destination.
	T rpoplpush(T = string)(string key, string destination) if(isValidRedisValueReturn!T) { return request!T("RPOPLPUSH", key, destination); }

	/*
		Sets
	*/
	/// Add the specified members to the set stored at key. Specified members that are already a member of this set are ignored.
	/// If key does not exist, a new set is created before adding the specified members.
	long sadd(ARGS...)(string key, ARGS args) { return request!long("SADD", key, args); }
	/// Returns the set cardinality (number of elements) of the set stored at key.
	long scard(string key) { return request!long("SCARD", key); }
	/// Returns the members of the set resulting from the difference between the first set and all the successive sets.
	RedisReply!T sdiff(T = string)(scope string[] keys...) if(isValidRedisValueType!T) { return request!(RedisReply!T)("SDIFF", keys); }
	/// This command is equal to SDIFF, but instead of returning the resulting set, it is stored in destination.
	/// If destination already exists, it is overwritten.
	long sdiffStore(string destination, scope string[] keys...) { return request!long("SDIFFSTORE", destination, keys); }
	/// Returns the members of the set resulting from the intersection of all the given sets.
	RedisReply!T sinter(T = string)(string[] keys) if(isValidRedisValueType!T) { return request!(RedisReply!T)("SINTER", keys); }
	/// This command is equal to SINTER, but instead of returning the resulting set, it is stored in destination.
	/// If destination already exists, it is overwritten.
	long sinterStore(string destination, scope string[] keys...) { return request!long("SINTERSTORE", destination, keys); }
	/// Returns if member is a member of the set stored at key.
	bool sisMember(T)(string key, T member) if(isValidRedisValueType!T) { return request!bool("SISMEMBER", key, member); }
	/// Returns all the members of the set value stored at key.
	RedisReply!T smembers(T = string)(string key) if(isValidRedisValueType!T) { return request!(RedisReply!T)("SMEMBERS", key); }
	/// Move member from the set at source to the set at destination. This operation is atomic.
	/// In every given moment the element will appear to be a member of source or destination for other clients.
	bool smove(T)(string source, string destination, T member) if(isValidRedisValueType!T) { return request!bool("SMOVE", source, destination, member); }
	/// Removes and returns a random element from the set value stored at key.
	T spop(T = string)(string key) if(isValidRedisValueReturn!T) { return request!T("SPOP", key ); }
	/// Returns a random element from the set stored at key.
	T srandMember(T = string)(string key) if(isValidRedisValueReturn!T) { return request!T("SRANDMEMBER", key ); }
	///returns count random elements from the set stored at key
	RedisReply!T srandMember(T = string)(string key, long count) if(isValidRedisValueReturn!T) { return request!(RedisReply!T)("SRANDMEMBER", key, count ); }


	/// Remove the specified members from the set stored at key.
	long srem(ARGS...)(string key, ARGS args) { return request!long("SREM", key, args); }
	/// Returns the members of the set resulting from the union of all the given sets.
	RedisReply!T sunion(T = string)(scope string[] keys...) if(isValidRedisValueType!T) { return request!(RedisReply!T)("SUNION", keys); }
	/// This command is equal to SUNION, but instead of returning the resulting set, it is stored in destination.
	long sunionStore(scope string[] keys...) { return request!long("SUNIONSTORE", keys); }

	/*
		Sorted Sets
	*/
	/// Add one or more members to a sorted set, or update its score if it already exists
	long zadd(ARGS...)(string key, ARGS args) { return request!long("ZADD", key, args); }
	/// Returns the sorted set cardinality (number of elements) of the sorted set stored at key.
	long zcard(string key) { return request!long("ZCARD", key); }
	/// Returns the number of elements in the sorted set at key with a score between min and max
	long zcount(string RNG = "[]")(string key, double min, double max) { return request!long("ZCOUNT", key, getMinMaxArgs!RNG(min, max)); }
	/// Increments the score of member in the sorted set stored at key by increment.
	double zincrby(T)(string key, double value, T member) if (isValidRedisValueType!T) { return request!double("ZINCRBY", key, value, member); }
	//TODO: zinterstore
	/// Returns the specified range of elements in the sorted set stored at key.
	RedisReply!T zrange(T = string)(string key, long start, long end, bool with_scores = false)
		if(isValidRedisValueType!T)
	{
		if (with_scores) return request!(RedisReply!T)("ZRANGE", key, start, end, "WITHSCORES");
		else return request!(RedisReply!T)("ZRANGE", key, start, end);
	}

	long zlexCount(string key, string min = "-", string max = "+") { return request!long("ZLEXCOUNT", key, min, max); }

	/// When all the elements in a sorted set are inserted with the same score, in order to force lexicographical ordering,
	/// this command returns all the elements in the sorted set at key with a value between min and max.
	RedisReply!T zrangeByLex(T = string)(string key, string min = "-", string max = "+", long offset = 0, long count = -1)
		if(isValidRedisValueType!T)
	{
		if (offset > 0 || count != -1) return request!(RedisReply!T)("ZRANGEBYLEX", key, min, max, "LIMIT", offset, count);
		else return request!(RedisReply!T)("ZRANGEBYLEX", key, min, max);
	}

	/// Returns all the elements in the sorted set at key with a score between start and end inclusively
	RedisReply!T zrangeByScore(T = string, string RNG = "[]")(string key, double start, double end, bool with_scores = false)
		if(isValidRedisValueType!T)
	{
		if (with_scores) return request!(RedisReply!T)("ZRANGEBYSCORE", key, getMinMaxArgs!RNG(start, end), "WITHSCORES");
		else return request!(RedisReply!T)("ZRANGEBYSCORE", key, getMinMaxArgs!RNG(start, end));
	}

	/// Computes an internal list of elements in the sorted set at key with a score between start and end inclusively,
	/// and returns a range subselection similar to $(D results[offset .. offset+count])
	RedisReply!T zrangeByScore(T = string, string RNG = "[]")(string key, double start, double end, long offset, long count, bool with_scores = false)
		if(isValidRedisValueType!T)
	{
		assert(offset >= 0);
		assert(count >= 0);
		if (with_scores) return request!(RedisReply!T)("ZRANGEBYSCORE", key, getMinMaxArgs!RNG(start, end), "WITHSCORES", "LIMIT", offset, count);
		else return request!(RedisReply!T)("ZRANGEBYSCORE", key, getMinMaxArgs!RNG(start, end), "LIMIT", offset, count);
	}

	/// Returns the rank of member in the sorted set stored at key, with the scores ordered from low to high.
	long zrank(T)(string key, T member)
		if (isValidRedisValueType!T)
	{
		auto str = request!string("ZRANK", key, member);
		return str != "" ? parse!long(str) : -1;
	}

	/// Removes the specified members from the sorted set stored at key.
	long zrem(ARGS...)(string key, ARGS members) { return request!long("ZREM", key, members); }
	/// Removes all elements in the sorted set stored at key with rank between start and stop.
	long zremRangeByRank(string key, long start, long stop) { return request!long("ZREMRANGEBYRANK", key, start, stop); }
	/// Removes all elements in the sorted set stored at key with a score between min and max (inclusive).
	long zremRangeByScore(string RNG = "[]")(string key, double min, double max) { return request!long("ZREMRANGEBYSCORE", key, getMinMaxArgs!RNG(min, max));}
	/// Returns the specified range of elements in the sorted set stored at key.
	RedisReply!T zrevRange(T = string)(string key, long start, long end, bool with_scores = false)
		if(isValidRedisValueType!T)
	{
		if (with_scores) return request!(RedisReply!T)("ZREVRANGE", key, start, end, "WITHSCORES");
		else return request!(RedisReply!T)("ZREVRANGE", key, start, end);
	}

	/// Returns all the elements in the sorted set at key with a score between max and min (including elements with score equal to max or min).
	RedisReply!T zrevRangeByScore(T = string, string RNG = "[]")(string key, double min, double max, bool with_scores=false)
		if(isValidRedisValueType!T)
	{
		if (with_scores) return request!(RedisReply!T)("ZREVRANGEBYSCORE", key, getMinMaxArgs!RNG(min, max), "WITHSCORES");
		else return request!(RedisReply!T)("ZREVRANGEBYSCORE", key, getMinMaxArgs!RNG(min, max));
	}

	/// Computes an internal list of elements in the sorted set at key with a score between max and min, and
	/// returns a window of elements selected in a way equivalent to $(D results[offset .. offset + count])
	RedisReply!T zrevRangeByScore(T = string, string RNG = "[]")(string key, double min, double max, long offset, long count, bool with_scores=false)
		if(isValidRedisValueType!T)
	{
		assert(offset >= 0);
		assert(count >= 0);
		if (with_scores) return request!(RedisReply!T)("ZREVRANGEBYSCORE", key, getMinMaxArgs!RNG(min, max), "WITHSCORES", "LIMIT", offset, count);
		else return request!(RedisReply!T)("ZREVRANGEBYSCORE", key, getMinMaxArgs!RNG(min, max), "LIMIT", offset, count);
	}

	/// Returns the rank of member in the sorted set stored at key, with the scores ordered from high to low.
	long zrevRank(T)(string key, T member)
		if (isValidRedisValueType!T)
	{
		auto str = request!string("ZREVRANK", key, member);
		return str != "" ? parse!long(str) : -1;
	}

	/// Returns the score of member in the sorted set at key.
	RedisReply!T zscore(T = string, U)(string key, U member)
		if(isValidRedisValueType!T && isValidRedisValueType!U)
	{
		return request!(RedisReply!T)("ZSCORE", key, member);
	}

	/*
		Hyperloglog
	*/

	/// Adds one or more Keys to a HyperLogLog data structure .
	long pfadd(ARGS...)(string key, ARGS args) { return request!long("PFADD", key, args); }

	/** Returns the approximated cardinality computed by the HyperLogLog data
		structure stored at the specified key.

		When called with a single key, returns the approximated cardinality
		computed by the HyperLogLog data structure stored at the specified
		variable, which is 0 if the variable does not exist.

		When called with multiple keys, returns the approximated cardinality
		of the union of the HyperLogLogs passed, by internally merging the
		HyperLogLogs stored at the provided keys into a temporary HyperLogLog.
	*/
	long pfcount(scope string[] keys...) { return request!long("PFCOUNT", keys); }

	/// Merge multiple HyperLogLog values into a new one.
	void pfmerge(ARGS...)(string destkey, ARGS args) { request("PFMERGE", destkey, args); }


	//TODO: zunionstore

	/*
		Pub / Sub
	*/

	/// Publishes a message to all clients subscribed at the channel
	long publish(string channel, string message)
	{
		auto str = request!string("PUBLISH", channel, message);
		return str != "" ? parse!long(str) : -1;
	}

	/// Inspect the state of the Pub/Sub subsystem
	RedisReply!T pubsub(T = string)(string subcommand, scope string[] args...)
		if(isValidRedisValueType!T)
	{
		return request!(RedisReply!T)("PUBSUB", subcommand, args);
	}

	/*
		TODO: Transactions
	*/
	/// Return the number of keys in the selected database
	long dbSize() { return request!long("DBSIZE"); }

	/*
		LUA Scripts
	*/
	/// Execute a Lua script server side
	RedisReply!T eval(T = string, ARGS...)(string lua_code, scope string[] keys, scope ARGS args)
		if(isValidRedisValueType!T)
	{
		return request!(RedisReply!T)("EVAL", lua_code, keys.length, keys, args);
	}
	/// Evaluates a script cached on the server side by its SHA1 digest. Scripts are cached on the server side using the scriptLoad function.
	RedisReply!T evalSHA(T = string, ARGS...)(string sha, scope string[] keys, scope ARGS args)
		if(isValidRedisValueType!T)
	{
		return request!(RedisReply!T)("EVALSHA", sha, keys.length, keys, args);
	}

	//scriptExists
	//scriptFlush
	//scriptKill

	/// Load a script into the scripts cache, without executing it. Run it using evalSHA.
	string scriptLoad(string lua_code) { return request!string("SCRIPT", "LOAD", lua_code); }

	/// Run the specified command and arguments in the Redis database server
	T request(T = void, ARGS...)(string command, scope ARGS args)
	{
		return m_client.requestDB!(T, ARGS)(m_index, command, args);
	}

	private static string[2] getMinMaxArgs(string RNG)(double min, double max)
	{
		// TODO: avoid GC allocations
		static assert(RNG.length == 2, "The RNG range specification must be two characters long");

		string[2] ret;
		string mins, maxs;
		mins = min == -double.infinity ? "-inf" : min == double.infinity ? "+inf" : format(typeFormatString!double, min);
		maxs = max == -double.infinity ? "-inf" : max == double.infinity ? "+inf" : format(typeFormatString!double, max);

		static if (RNG[0] == '[') ret[0] = mins;
		else static if (RNG[0] == '(') ret[0] = '('~mins;
		else static assert(false, "Opening range specification mist be either '[' or '('.");

		static if (RNG[1] == ']') ret[1] = maxs;
		else static if (RNG[1] == ')') ret[1] = '('~maxs;
		else static assert(false, "Closing range specification mist be either ']' or ')'.");

		return ret;
	}
}


/**
	A redis subscription listener
*/
import std.datetime;
import std.variant;
import std.typecons : Tuple, tuple;
import std.container : Array;
import std.algorithm : canFind;
import std.range : takeOne;
import std.array : array;

import vibe.core.concurrency;
import vibe.core.sync;

alias RedisSubscriber = FreeListRef!RedisSubscriberImpl;

final class RedisSubscriberImpl {
	private {
		RedisClient m_client;
		LockedConnection!RedisConnection m_lockedConnection;
		bool[string] m_subscriptions;
		string[] m_pendingSubscriptions;
		bool m_listening;
		bool m_stop;
		Task m_listener;
		Task m_listenerHelper;
		Task m_waiter;
		Task m_stopWaiter;
		InterruptibleRecursiveTaskMutex m_mutex;
		InterruptibleTaskMutex m_connMutex;
	}

	private enum Action {
		DATA,
		STOP,
		STARTED,
		SUBSCRIBE,
		UNSUBSCRIBE
	}

	@property bool isListening() const {
		return m_listening;
	}

	/// Get a list of channels with active subscriptions
	@property string[] subscriptions() const {
		return () @trusted { return m_subscriptions.keys; } ();
	}

	bool hasSubscription(string channel) const {
		return (channel in m_subscriptions) !is null && m_subscriptions[channel];
	}

	this(RedisClient client) {

		logTrace("this()");
		m_client = client;
		m_mutex = new InterruptibleRecursiveTaskMutex;
		m_connMutex = new InterruptibleTaskMutex;
	}

	// FIXME: instead of waiting here, the class must be reference counted
	// and destructions needs to be defered until everything is stopped
	~this() {
		logTrace("~this");
		waitForStop();
	}

	// Task will block until the listener is finished
	private void waitForStop()
	{
		logTrace("waitForStop");
		if (!m_listening) return;

		void impl() @safe {
			m_mutex.performLocked!({
				m_stopWaiter = Task.getThis();
			});
			if (!m_listening) return; // verify again in case the mutex was locked by bstop
			scope(exit) {
				m_mutex.performLocked!({
					m_stopWaiter = Task();
				});
			}
			bool stopped;
			do {
				() @trusted { receive((Action act) { if (act == Action.STOP) stopped = true;  }); } ();
			} while (!stopped);

			enforce(stopped, "Failed to wait for Redis listener to stop");
		}
		inTask(&impl);
	}

	/// Stop listening and yield until the operation is complete.
	void bstop(){
		logTrace("bstop");
		if (!m_listening) return;

		void impl() @safe {
			m_mutex.performLocked!({
				m_waiter = Task.getThis();
				scope(exit) m_waiter = Task();
				stop();

				bool stopped;
				do {
					if (!() @trusted { return receiveTimeout(3.seconds, (Action act) { if (act == Action.STOP) stopped = true;  }); } ())
						break;
				} while (!stopped);

				enforce(stopped, "Failed to wait for Redis listener to stop");
			});
		}
		inTask(&impl);
	}

	/// Stop listening asynchroneously
	void stop(){
		logTrace("stop");
		if (!m_listening)
			return;

		void impl() @safe {
			m_mutex.performLocked!({
				m_stop = true;
				() @trusted { m_listener.send(Action.STOP); } ();
				// send a message to wake up the listenerHelper from the reply
				if (m_subscriptions.length > 0) {
					m_connMutex.performLocked!(() {
						_request_void(m_lockedConnection, "UNSUBSCRIBE", () @trusted { return cast(string[]) m_subscriptions.keys.takeOne.array; } ());
					});
					sleep(30.msecs);
				}
			});
		}
		inTask(&impl);
	}

	private bool hasNewSubscriptionIn(scope string[] args) {
		bool has_new;
		foreach (arg; args)
			if (!hasSubscription(arg))
				has_new = true;
		if (!has_new)
			return false;

		return true;
	}

	private bool anySubscribed(scope string[] args) {

		bool any_subscribed;
		foreach (arg ; args) {
			if (hasSubscription(arg))
				any_subscribed = true;
		}
		return any_subscribed;
	}

	/// Completes the subscription for a listener to start receiving pubsub messages
	/// on the corresponding channel(s). Returns instantly if already subscribed.
	/// If a connection error is thrown here, it stops the listener.
	void subscribe(scope string[] args...)
	{
		logTrace("subscribe");
		if (!m_listening) {
			foreach (arg; args)
				m_pendingSubscriptions ~= arg;
			return;
		}

		if (!hasNewSubscriptionIn(args))
			return;

		void impl() @safe {

			scope(failure) { logTrace("Failure"); bstop(); }
			try {
				m_mutex.performLocked!({
					m_waiter = Task.getThis();
					scope(exit) m_waiter = Task();
					bool subscribed;
					m_connMutex.performLocked!({
						_request_void(m_lockedConnection, "SUBSCRIBE", args);
					});
					while(!() @trusted { return m_subscriptions.byKey.canFind(args); } ()) {
						if (!() @trusted { return receiveTimeout(2.seconds, (Action act) { enforce(act == Action.SUBSCRIBE);  }); } ())
							break;

						subscribed = true;
					}
					debug {
						auto keys = () @trusted { return m_subscriptions.keys; } ();
						logTrace("Can find keys?: %s",  keys.canFind(args));
						logTrace("Subscriptions: %s", keys);
					}
					enforce(subscribed, "Could not complete subscription(s).");
				});
			} catch (Exception e) {
				logDebug("Redis subscribe() failed: ", e.msg);
			}
		}
		inTask(&impl);
	}

	/// Unsubscribes from the channel(s) specified, returns immediately if none
	/// is currently being listened.
	/// If a connection error is thrown here, it stops the listener.
	void unsubscribe(scope string[] args...)
	{
		logTrace("unsubscribe");

		void impl() @safe {

			if (!anySubscribed(args))
				return;

			scope(failure) bstop();
			assert(m_listening);

			m_mutex.performLocked!({
				m_waiter = Task.getThis();
				scope(exit) m_waiter = Task();
				bool unsubscribed;
				m_connMutex.performLocked!({
					_request_void(m_lockedConnection, "UNSUBSCRIBE", args);
				});
				while(() @trusted { return m_subscriptions.byKey.canFind(args); } ()) {
					if (!() @trusted { return receiveTimeout(2.seconds, (Action act) { enforce(act == Action.UNSUBSCRIBE);  }); } ()) {
						unsubscribed = false;
						break;
					}
					unsubscribed = true;
				}
				debug {
					auto keys = () @trusted { return m_subscriptions.keys; } ();
					logTrace("Can find keys?: %s",  keys.canFind(args));
					logTrace("Subscriptions: %s", keys);
				}
				enforce(unsubscribed, "Could not complete unsubscription(s).");
			});
		}
		inTask(&impl);
	}

	/// Same as subscribe, but uses glob patterns, and does not return instantly if
	/// the subscriptions are already registered.
	/// throws Exception if the pattern does not yield a new subscription.
	void psubscribe(scope string[] args...)
	{
		logTrace("psubscribe");
		void impl() @safe {
			scope(failure) bstop();
			assert(m_listening);
			m_mutex.performLocked!({
				m_waiter = Task.getThis();
				scope(exit) m_waiter = Task();
				bool subscribed;
				m_connMutex.performLocked!({
					_request_void(m_lockedConnection, "PSUBSCRIBE", args);
				});

				if (!() @trusted { return receiveTimeout(2.seconds, (Action act) { enforce(act == Action.SUBSCRIBE);  }); } ())
					subscribed = false;
				else
					subscribed = true;

				debug logTrace("Subscriptions: %s", () @trusted { return m_subscriptions.keys; } ());
				enforce(subscribed, "Could not complete subscription(s).");
			});
		}
		inTask(&impl);
	}

	/// Same as unsubscribe, but uses glob patterns, and does not return instantly if
	/// the subscriptions are not registered.
	/// throws Exception if the pattern does not yield a new unsubscription.
	void punsubscribe(scope string[] args...)
	{
		logTrace("punsubscribe");
		void impl() @safe {
			scope(failure) bstop();
			assert(m_listening);
			m_mutex.performLocked!({
				m_waiter = Task.getThis();
				scope(exit) m_waiter = Task();
				bool unsubscribed;
				m_connMutex.performLocked!({
					_request_void(m_lockedConnection, "PUNSUBSCRIBE", args);
				});
				if (!() @trusted { return receiveTimeout(2.seconds, (Action act) { enforce(act == Action.UNSUBSCRIBE);  }); } ())
					unsubscribed = false;
				else
					unsubscribed = true;

				debug {
					auto keys = () @trusted { return m_subscriptions.keys; } ();
					logTrace("Can find keys?: %s",  keys.canFind(args));
					logTrace("Subscriptions: %s", keys);
				}
				enforce(unsubscribed, "Could not complete unsubscription(s).");
			});
		}
		inTask(&impl);
	}

	private void inTask(scope void delegate() @safe impl) {
		logTrace("inTask");
		if (Task.getThis() == Task())
		{
			Throwable ex;
			bool done;
			Task task = runTask({
				logDebug("inTask %s", Task.getThis());
				try impl();
				catch (Exception e) {
					ex = e;
				}
				done = true;
			});
			task.join();
			logDebug("done");
			if (ex)
				throw ex;
		}
		else
			impl();
	}

	private void init(){

		logTrace("init");
		if (!m_lockedConnection) {
			m_lockedConnection = m_client.m_connections.lockConnection();
			m_lockedConnection.setAuth(m_client.m_authPassword);
			m_lockedConnection.setDB(m_client.m_selectedDB);
		}

		if (!m_lockedConnection.conn || !m_lockedConnection.conn.connected) {
			try m_lockedConnection.conn = connectTCP(m_lockedConnection.m_host, m_lockedConnection.m_port);
			catch (Exception e) {
				throw new Exception(format("Failed to connect to Redis server at %s:%s.", m_lockedConnection.m_host, m_lockedConnection.m_port), __FILE__, __LINE__, e);
			}
			m_lockedConnection.conn.tcpNoDelay = true;
			m_lockedConnection.setAuth(m_client.m_authPassword);
			m_lockedConnection.setDB(m_client.m_selectedDB);
		}
	}

	// Same as listen, but blocking
	void blisten(void delegate(string, string) @safe onMessage, Duration timeout = 0.seconds)
	{
		init();

		void onSubscribe(string channel) @safe {
			logTrace("Callback subscribe(%s)", channel);
			m_subscriptions[channel] = true;
			if (m_waiter != Task())
				() @trusted { m_waiter.send(Action.SUBSCRIBE); } ();
		}

		void onUnsubscribe(string channel) @safe {
			logTrace("Callback unsubscribe(%s)", channel);
			m_subscriptions.remove(channel);
			if (m_waiter != Task())
				() @trusted { m_waiter.send(Action.UNSUBSCRIBE); } ();
		}

		void teardown() @safe { // teardown
			logTrace("Redis listener exiting");
			// More publish commands may be sent to this connection after recycling it, so we
			// actively destroy it
			Action act;
			// wait for the listener helper to send its stop message
			while (act != Action.STOP)
				act = () @trusted { return receiveOnly!Action(); } ();
			m_lockedConnection.conn.close();
			m_lockedConnection.destroy();
			m_listening = false;
			return;
		}
		// http://redis.io/topics/pubsub
		/**
			 	SUBSCRIBE first second
				*3
				$9
				subscribe
				$5
				first
				:1
				*3
				$9
				subscribe
				$6
				second
				:2
			*/
		// This is a simple parser/handler for subscribe/unsubscribe/publish
		// commands sent by redis. The PubSub client protocol is simple enough

		void pubsub_handler() {
			TCPConnection conn = m_lockedConnection.conn;
			logTrace("Pubsub handler");
			void dropCRLF() @safe {
				ubyte[2] crlf;
				conn.read(crlf);
			}
			size_t readArgs() @safe {
				char[8] ucnt;
				ubyte[1] num;
				size_t i;
				do {
					conn.read(num);
					if (num[0] >= 48 && num[0] <= 57)
						ucnt[i] = num[0];
					else break;
					i++;
				}
				while (true); // ascii
				ubyte[1] b;
				conn.read(b);
				logTrace("Found %s", ucnt);
				// the new line is consumed when num is not in range.
				return ucnt[0 .. i].to!size_t;
			}
			// find the number of arguments in the array
			ubyte[1] symbol;
			conn.read(symbol);
			enforce(symbol[0] == '*', "Expected '*', got '" ~ symbol.to!string ~ "'");
			size_t args = readArgs();
			// get the number of characters in the first string (the command)
			conn.read(symbol);
			enforce(symbol[0] == '$', "Expected '$', got '" ~ symbol.to!string ~ "'");
			size_t cnt = readArgs();
			ubyte[] cmd = () @trusted { return theAllocator.makeArray!ubyte(cnt); } ();
			scope(exit) () @trusted { theAllocator.dispose(cmd); } ();
			conn.read(cmd);
			dropCRLF();
			// find the channel
			conn.read(symbol);
			enforce(symbol[0] == '$', "Expected '$', got '" ~ symbol.to!string ~ "'");
			cnt = readArgs();
			ubyte[] str = new ubyte[cnt];
			conn.read(str);
			dropCRLF();
			string channel = () @trusted { return cast(string)str; } ();
			logTrace("chan: %s", channel);

			if (cmd == "message") { // find the message
				conn.read(symbol);
				enforce(symbol[0] == '$', "Expected '$', got '" ~ symbol.to!string ~ "'");
				cnt = readArgs();
				str = new ubyte[cnt];
				conn.read(str); // channel
				string message = () @trusted { return cast(string)str.idup; } ();
				logTrace("msg: %s", message);
				dropCRLF();
				onMessage(channel, message);
			}
			else if (cmd == "subscribe" || cmd == "unsubscribe") { // find the remaining subscriptions
				bool is_subscribe = (cmd == "subscribe");
				conn.read(symbol);
				enforce(symbol[0] == ':', "Expected ':', got '" ~ symbol.to!string ~ "'");
				cnt = readArgs(); // number of subscriptions
				logTrace("subscriptions: %d", cnt);
				if (is_subscribe)
					onSubscribe(channel);
				else
					onUnsubscribe(channel);

				// todo: enforce the number of subscriptions?
			}
			else assert(false, "Unrecognized pubsub wire protocol command received");
		}

		// Waits for data and advises the handler
		m_listenerHelper = runTask( {
			while(true) {
				if (!m_stop && m_lockedConnection.conn && m_lockedConnection.conn.waitForData(100.msecs)) {
					// We check every 5 seconds if this task should stay active
					if (m_stop)	break;
					else if (m_lockedConnection.conn && !m_lockedConnection.conn.dataAvailableForRead) continue;
					// Data has arrived, this task is in charge of notifying the main handler loop
					logTrace("Notify data arrival");

					() @trusted { receiveTimeout(0.seconds, (Variant v) {}); } (); // clear message queue
					() @trusted { m_listener.send(Action.DATA); } ();
					if (!() @trusted { return receiveTimeout(5.seconds, (Action act) { assert(act == Action.DATA); }); } ())
						assert(false);

				} else if (m_stop || !m_lockedConnection.conn) break;
				logTrace("No data arrival in 100 ms...");
			}
			logTrace("Listener Helper exit.");
			() @trusted { m_listener.send(Action.STOP); } ();
		} );

		m_listening = true;
		logTrace("Redis listener now listening");
		if (m_waiter != Task())
			() @trusted { m_waiter.send(Action.STARTED); } ();

		if (timeout == 0.seconds)
			timeout = 365.days; // make sure 0.seconds is considered as big.

		scope(exit) {
			logTrace("Redis Listener exit.");
			if (!m_stop) {
				stop(); // notifies the listenerHelper
			}
			m_listenerHelper.join();
			// close the data connections
			teardown();

			if (m_waiter != Task())
				() @trusted { m_waiter.send(Action.STOP); } ();
			if (m_stopWaiter != Task())
				() @trusted { m_stopWaiter.send(Action.STOP); } ();

			m_listenerHelper = Task();
			m_listener = Task();
			m_stop = false;
		}

		// Start waiting for data notifications to arrive
		while(true) {

			auto handler = (Action act) {
				if (act == Action.STOP) m_stop = true;
				if (m_stop) return;
				logTrace("Calling PubSub Handler");
				m_connMutex.performLocked!({
					pubsub_handler(); // handles one command at a time
				});
				() @trusted { m_listenerHelper.send(Action.DATA); } ();
			};

			if (!() @trusted { return receiveTimeout(timeout, handler); } () || m_stop) {
				logTrace("Redis Listener stopped");
				break;
			}

		}

	}
	/// ditto
	deprecated("Use an @safe message callback")
	void blisten(void delegate(string, string) @system onMessage, Duration timeout = 0.seconds)
	{
		blisten((string ch, string msg) @trusted => onMessage(ch, msg));
	}

	/// Waits for messages and calls the callback with the channel and the message as arguments.
	/// The timeout is passed over to the listener, which closes after the period of inactivity.
	/// Use 0.seconds timeout to specify a very long time (365 days)
	/// Errors will be sent to Callback Delegate on channel "Error".
	Task listen(void delegate(string, string) @safe callback, Duration timeout = 0.seconds)
	{
		logTrace("Listen");
		void impl() @safe {
			logTrace("Listen");
			m_waiter = Task.getThis();
			scope(exit) m_waiter = Task();
			Throwable ex;
			m_listener = runTask({
				try blisten(callback, timeout);
				catch(Exception e) {
					ex = e;
					if (m_waiter != Task() && !m_listening) {
						() @trusted { m_waiter.send(Action.STARTED); } ();
						return;
					}
					callback("Error", e.msg);
				}
			});
			m_mutex.performLocked!({
				import std.datetime : usecs;
				() @trusted { receiveTimeout(2.seconds, (Action act) { assert( act == Action.STARTED); }); } ();
				if (ex) throw ex;
				enforce(m_listening, "Failed to start listening, timeout of 2 seconds expired");
			});

			foreach (channel; m_pendingSubscriptions) {
				subscribe(channel);
			}

			m_pendingSubscriptions = null;
		}
		inTask(&impl);
		return m_listener;
	}
	/// ditto
	deprecated("Use an @safe message callback")
	Task listen(void delegate(string, string) @system onMessage, Duration timeout = 0.seconds)
	{
		return listen((string ch, string msg) @trusted => onMessage(ch, msg));
	}
}



/** Range interface to a single Redis reply.
*/
struct RedisReply(T = ubyte[]) {
	static assert(isInputRange!RedisReply);

	private {
		uint m_magic = 0x15f67ab3;
		RedisConnection m_conn;
		LockedConnection!RedisConnection m_lockedConnection;
	}

	alias ElementType = T;

	private this(RedisConnection conn)
	{
		m_conn = conn;
		auto ctx = &conn.m_replyContext;
		assert(ctx.refCount == 0);
		*ctx = RedisReplyContext.init;
		ctx.refCount++;
	}

	this(this)
	{
		assert(m_magic == 0x15f67ab3);
		if (m_conn) {
			auto ctx = &m_conn.m_replyContext;
			assert(ctx.refCount > 0);
			ctx.refCount++;
		}
	}

	~this()
	{
		assert(m_magic == 0x15f67ab3);
		if (m_conn) {
			if (!--m_conn.m_replyContext.refCount)
				drop();
		}
	}

	@property bool empty() const { return !m_conn || m_conn.m_replyContext.index >= m_conn.m_replyContext.length; }

	/** Returns the current element of the reply.

		Note that byte and character arrays may be returned as slices to a
		temporary buffer. This buffer will be invalidated on the next call to
		$(D popFront), so it needs to be duplicated for permanent storage.
	*/
	@property T front()
	{
		assert(!empty, "Accessing the front of an empty RedisReply!");
		auto ctx = &m_conn.m_replyContext;
		if (!ctx.hasData) readData();

		ubyte[] ret = ctx.data;

		return convertToType!T(ret);
	}

	@property bool frontIsNull()
	const {
		assert(!empty, "Accessing the front of an empty RedisReply!");
		return m_conn.m_replyContext.frontIsNull;
	}

	/** Pops the current element of the reply
	*/
	void popFront()
	{
		assert(!empty, "Popping the front of an empty RedisReply!");

		auto ctx = &m_conn.m_replyContext;

		if (!ctx.hasData) readData(); // ensure that we actually read the data entry from the wire
		clearData();
		ctx.index++;

		if (ctx.index >= ctx.length && ctx.refCount == 1) {
			ctx.refCount = 0;
			m_conn = null;
			m_lockedConnection.destroy();
		}
	}


	/// Legacy property for hasNext/next based iteration
	@property bool hasNext() const { return !empty; }

	/// Legacy property for hasNext/next based iteration
	TN next(TN : E[], E)()
	{
		assert(hasNext, "end of reply");

		auto ret = front.dup;
		popFront();
		return () @trusted { return cast(TN)ret; } ();
	}

	void drop()
	{
		if (!m_conn) return;
		while (!empty) popFront();
	}

	private void readData()
	{
		auto ctx = &m_conn.m_replyContext;
		assert(!ctx.hasData && ctx.initialized);

		if (ctx.multi)
			readBulk(() @trusted { return cast(string)m_conn.conn.readLine(); } ());
	}

	private void clearData()
	{
		auto ctx = &m_conn.m_replyContext;
		ctx.data = null;
		ctx.hasData = false;
	}

	private @property void lockedConnection(ref LockedConnection!RedisConnection conn)
	{
		assert(m_conn !is null);
		m_lockedConnection = conn;
	}

	private void initialize()
	{
		assert(m_conn !is null);
		auto ctx = &m_conn.m_replyContext;
		assert(!ctx.initialized);
		ctx.initialized = true;

		ubyte[] ln = m_conn.conn.readLine();

		switch (ln[0]) {
			default:
				m_conn.conn.close();
				throw new Exception(format("Unknown reply type: %s", cast(char)ln[0]));
			case '+': ctx.data = ln[1 .. $]; ctx.hasData = true; break;
			case '-': throw new Exception(() @trusted { return cast(string)ln[1 .. $]; } ());
			case ':': ctx.data = ln[1 .. $]; ctx.hasData = true; break;
			case '$':
				readBulk(() @trusted { return cast(string)ln; } ());
				break;
			case '*':
				if (ln.startsWith(cast(const(ubyte)[])"*-1")) {
					ctx.length = 0; // TODO: make this NIL reply distinguishable from a 0-length array
				} else {
					ctx.multi = true;
					scope (failure) m_conn.conn.close();
					ctx.length = to!long(() @trusted { return cast(string)ln[1 .. $]; } ());
				}
				break;
		}
	}

	private void readBulk(string sizeLn)
	{
		assert(m_conn !is null);
		auto ctx = &m_conn.m_replyContext;
		if (sizeLn.startsWith("$-1")) {
			ctx.frontIsNull = true;
			ctx.hasData = true;
			ctx.data = null;
		} else {
			auto size = to!size_t(sizeLn[1 .. $]);
			auto data = new ubyte[size];
			m_conn.conn.read(data);
			m_conn.conn.readLine();
			ctx.frontIsNull = false;
			ctx.hasData = true;
			ctx.data = data;
		}
	}
}

class RedisProtocolException : Exception {
	this(string message, string file = __FILE__, size_t line = __LINE__, Exception next = null)
	{
		super(message, file, line, next);
	}
}

template isValidRedisValueReturn(T)
{
	import std.typecons;
	static if (isInstanceOf!(Nullable, T)) {
		enum isValidRedisValueReturn = isValidRedisValueType!(typeof(T.init.get()));
	} else static if (isInstanceOf!(RedisReply, T)) {
		enum isValidRedisValueReturn = isValidRedisValueType!(T.ElementType);
	} else enum isValidRedisValueReturn = isValidRedisValueType!T;
}

template isValidRedisValueType(T)
{
	enum isValidRedisValueType = is(T : const(char)[]) || is(T : const(ubyte)[]) || is(T == long) || is(T == double) || is(T == bool);
}

private RedisReply!T getReply(T = ubyte)(RedisConnection conn)
{
	auto repl = RedisReply!T(conn);
	repl.initialize();
	return repl;
}

private struct RedisReplyContext {
	long refCount = 0;
	ubyte[] data;
	bool hasData;
	bool multi = false;
	bool initialized = false;
	bool frontIsNull = false;
	long length = 1;
	long index = 0;
	ubyte[128] dataBuffer;
}

private final class RedisConnection {
	private {
		string m_host;
		ushort m_port;
		TCPConnection m_conn;
		string m_password;
		long m_selectedDB;
		RedisReplyContext m_replyContext;
	}

	this(string host, ushort port)
	{
		m_host = host;
		m_port = port;
	}

	@property TCPConnection conn() { return m_conn; }
	@property void conn(TCPConnection conn) { m_conn = conn; }

	void setAuth(string password)
	{
		if (m_password == password) return;
		_request_reply(this, "AUTH", password);
		m_password = password;
	}

	void setDB(long index)
	{
		if (index == m_selectedDB) return;
		_request_reply(this, "SELECT", index);
		m_selectedDB = index;
	}

	private static long countArgs(ARGS...)(scope ARGS args)
	{
		long ret = 0;
		foreach (i, A; ARGS) {
			static if (isArray!A && !(is(A : const(ubyte[])) || is(A : const(char[])))) {
				foreach (arg; args[i])
					ret += countArgs(arg);
			} else ret++;
		}
		return ret;
	}

	unittest {
		assert(countArgs() == 0);
		assert(countArgs(1, 2, 3) == 3);
		assert(countArgs("1", ["2", "3", "4"]) == 4);
		assert(countArgs([["1", "2"], ["3"]]) == 3);
	}

	private static void writeArgs(R, ARGS...)(R dst, scope ARGS args)
		if (isOutputRange!(R, char))
	{
		foreach (i, A; ARGS) {
			static if (is(A == bool)) {
				writeArgs(dst, args[i] ? "1" : "0");
			} else static if (is(A : long) || is(A : real) || is(A == string)) {
				auto alen = formattedLength(args[i]);
				enum fmt = "$%d\r\n"~typeFormatString!A~"\r\n";
				dst.formattedWrite(fmt, alen, args[i]);
			} else static if (is(A : const(ubyte[])) || is(A : const(char[]))) {
				dst.formattedWrite("$%s\r\n", args[i].length);
				dst.put(args[i]);
				dst.put("\r\n");
			} else static if (isArray!A) {
				foreach (arg; args[i])
					writeArgs(dst, arg);
			} else static assert(false, "Unsupported Redis argument type: " ~ A.stringof);
		}
	}

	unittest {
		import std.array : appender;
		auto dst = appender!string;
		writeArgs(dst, false, true, ["2", "3"], "4", 5.0);
		assert(dst.data == "$1\r\n0\r\n$1\r\n1\r\n$1\r\n2\r\n$1\r\n3\r\n$1\r\n4\r\n$1\r\n5\r\n");
	}

	private static long formattedLength(ARG)(scope ARG arg)
	{
		static if (is(ARG == string)) return arg.length;
		else {
			import vibe.internal.rangeutil;
			long length;
			auto rangeCnt = RangeCounter(() @trusted { return &length; } ());
			rangeCnt.formattedWrite(typeFormatString!ARG, arg);
			return length;
		}
	}
}

private void _request_void(ARGS...)(RedisConnection conn, string command, scope ARGS args)
{
	import vibe.stream.wrapper;

	if (!conn.conn || !conn.conn.connected) {
		try conn.conn = connectTCP(conn.m_host, conn.m_port);
		catch (Exception e) {
			throw new Exception(format("Failed to connect to Redis server at %s:%s.", conn.m_host, conn.m_port), __FILE__, __LINE__, e);
		}
		conn.conn.tcpNoDelay = true;
	}

	auto nargs = conn.countArgs(args);
	auto rng = streamOutputRange(conn.conn);
	formattedWrite(() @trusted { return &rng; } (), "*%d\r\n$%d\r\n%s\r\n", nargs + 1, command.length, command);
	RedisConnection.writeArgs(() @trusted { return &rng; } (), args);
}

private RedisReply!T _request_reply(T = ubyte[], ARGS...)(RedisConnection conn, string command, scope ARGS args)
{
	import vibe.stream.wrapper;

	if (!conn.conn || !conn.conn.connected) {
		try conn.conn = connectTCP(conn.m_host, conn.m_port);
		catch (Exception e) {
			throw new Exception(format("Failed to connect to Redis server at %s:%s.", conn.m_host, conn.m_port), __FILE__, __LINE__, e);
		}
		conn.conn.tcpNoDelay = true;
	}

	auto nargs = conn.countArgs(args);
	auto rng = streamOutputRange(conn.conn);
	formattedWrite(() @trusted { return &rng; } (), "*%d\r\n$%d\r\n%s\r\n", nargs + 1, command.length, command);
	RedisConnection.writeArgs(() @trusted { return &rng; } (), args);
	rng.flush();

	return conn.getReply!T;
}

private T _request(T, ARGS...)(LockedConnection!RedisConnection conn, string command, scope ARGS args)
{
	import std.typecons;
	static if (isInstanceOf!(RedisReply, T)) {
		auto reply = _request_reply!(T.ElementType)(conn, command, args);
		reply.lockedConnection = conn;
		return reply;
	} else static if (is(T == void)) {
		_request_reply(conn, command, args);
	} else static if (isInstanceOf!(Nullable, T)) {
		alias TB = typeof(T.init.get());
		auto reply = _request_reply!TB(conn, command, args);
		T ret;
		if (!reply.frontIsNull) ret = reply.front;
		return ret;
	} else {
		auto reply = _request_reply!T(conn, command, args);
		return reply.front;
	}
}

private T convertToType(T)(ubyte[] data) /// NOTE: data must be unique!
{
	static if (isSomeString!T) () @trusted { validate(cast(T)data); } ();

	static if (is(T == ubyte[])) return data;
	else static if (is(T == string)) return cast(T)data.idup;
	else static if (is(T == bool)) return data[0] == '1';
	else static if (is(T == int) || is(T == long) || is(T == size_t) || is(T == double)) {
		auto str = () @trusted { return cast(string)data; } ();
		return parse!T(str);
	}
	else static assert(false, "Unsupported Redis reply type: " ~ T.stringof);
}

private template typeFormatString(T)
{
	static if (isFloatingPoint!T) enum typeFormatString = "%.16g";
	else enum typeFormatString = "%s";
}
