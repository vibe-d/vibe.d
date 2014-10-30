/**
	Redis database client implementation.

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger, Sönke Ludwig, Michael Eisendle, Etienne Cimon
*/
module vibe.db.redis.redis;

public import vibe.core.net;

import vibe.core.connectionpool;
import vibe.core.core;
import vibe.core.log;
import vibe.utils.memory : allocArray, freeArray, manualAllocator, defaultAllocator;
import vibe.stream.operations;
import std.conv;
import std.exception;
import std.format;
import std.range : isInputRange, isOutputRange;
import std.string;
import std.traits;
import std.utf;


/**
	Returns a RedisClient that can be used to communicate to the specified database server.
*/
RedisClient connectRedis(string host, ushort port = 6379)
{
	return new RedisClient(host, port);
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

	this(string host = "127.0.0.1", ushort port = 6379)
	{
		m_connections = new ConnectionPool!RedisConnection({
			return new RedisConnection(host, port);
		});
	}

	/// Returns Redis version
	@property string redisVersion()
	{
		if(!m_version)
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
	void auth(string password) { m_authPassword = password; }
	T echo(T, U)(U data) if(isValidRedisValueReturn!T && isValidRedisValueType!U) { return request!T("ECHO", data); }
	void ping() { request("PING"); }
	void quit() { request("QUIT"); }

	/*
		Server
	*/

	//TODO: BGREWRITEAOF
	//TODO: BGSAVE

	T getConfig(T)(string parameter) if(isValidRedisValueReturn!T) { return request!T("GET CONFIG", parameter); }
	void setConfig(T)(string parameter, T value) if(isValidRedisValueType!T) { request("SET CONFIG", parameter, value); }
	void configResetStat() { request("CONFIG RESETSTAT"); }
	//TOOD: Debug Object
	//TODO: Debug Segfault

	/** Deletes all keys from all databases.

		See_also: $(LINK2 http://redis.io/commands/flushall, FLUSHALL)
	*/
	void deleteAll() { request("FLUSHALL"); }
	/// Scheduled for deprecation, use $(D deleteAll) instead.
	alias flushAll = deleteAll;

	/// Scheduled for deprecation, use $(D RedisDatabase.deleteAll) instead.
	void flushDB() { request("FLUSHDB"); }

	string info() { return request!string("INFO"); }
	long lastSave() { return request!long("LASTSAVE"); }
	//TODO monitor
	void save() { request("SAVE"); }
	void shutdown() { request("SHUTDOWN"); }
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

	long del(scope string[] keys...) { return request!long("DEL", keys); }
	bool exists(string key) { return request!bool("EXISTS", key); }
	bool expire(string key, long seconds) { return request!bool("EXPIRE", key, seconds); }
	bool expire(string key, Duration timeout) { return request!bool("PEXPIRE", key, timeout.total!"msecs"); }
	bool expireAt(string key, long timestamp) { return request!bool("EXPIREAT", key, timestamp); }
	RedisReply!T keys(T = string)(string pattern) if(isValidRedisValueType!T) { return request!(RedisReply!T)("KEYS", pattern); }
	bool move(string key, long db) { return request!bool("MOVE", key, db); }
	bool persist(string key) { return request!bool("PERSIST", key); }
	//TODO: object
	string randomKey() { return request!string("RANDOMKEY"); }
	void rename(string key, string newkey) { request("RENAME", key, newkey); }
	bool renameNX(string key, string newkey) { return request!bool("RENAMENX", key, newkey); }
	//TODO sort
	long ttl(string key) { return request!long("TTL", key); }
	long pttl(string key) { return request!long("PTTL", key); }
	string type(string key) { return request!string("TYPE", key); }

	/*
		String Commands
	*/

	long append(T)(string key, T suffix) if(isValidRedisValueType!T) { return request!long("APPEND", key, suffix); }
	long decr(string key, long value = 1) { return value == 1 ? request!long("DECR", key) : request!long("DECRBY", key, value); }
	T get(T = string)(string key) if(isValidRedisValueReturn!T) { return request!T("GET", key); }
	bool getBit(string key, long offset) { return request!bool("GETBIT", key, offset); }
	T getRange(T = string)(string key, long start, long end) if(isValidRedisValueReturn!T) { return request!T("GETRANGE", key, start, end); }
	T getSet(T = string, U)(string key, U value) if(isValidRedisValueReturn!T && isValidRedisValueType!U) { return request!T("GETSET", key, value); }
	long incr(string key, long value = 1) { return value == 1 ? request!long("INCR", key) : request!long("INCRBY", key, value); }
	long incr(string key, double value) { return request!long("INCRBYFLOAT", key, value); }
	RedisReply!T mget(T = string)(string[] keys) if(isValidRedisValueType!T) { return request!(RedisReply!T)("MGET", keys); }

	void mset(ARGS...)(ARGS args)
	{
		static assert(ARGS.length % 2 == 0 && ARGS.length >= 2, "Arguments to mset must be pairs of key/value");
		foreach (i, T; ARGS ) static assert(i % 2 != 0 || is(T == string), "Keys must be strings.");
		request("MSET", args);
	}

	bool msetNX(ARGS...)(ARGS args) {
		static assert(ARGS.length % 2 == 0 && ARGS.length >= 2, "Arguments to mset must be pairs of key/value");
		foreach (i, T; ARGS ) static assert(i % 2 != 0 || is(T == string), "Keys must be strings.");
		return request!bool("MSETEX", args);
	}

	void set(T)(string key, T value) if(isValidRedisValueType!T) { request("SET", key, value); }
	bool setNX(T)(string key, T value) if(isValidRedisValueType!T) { return request!bool("SETNX", key, value); }
	bool setXX(T)(string key, T value) if(isValidRedisValueType!T) { return "OK" == request!string("SET", key, value, "XX"); }
	bool setNX(T)(string key, T value, Duration expire_time) if(isValidRedisValueType!T) { return "OK" == request!string("SET", key, value, "PX", expire_time.total!"msecs", "NX"); }
	bool setXX(T)(string key, T value, Duration expire_time) if(isValidRedisValueType!T) { return "OK" == request!string("SET", key, value, "PX", expire_time.total!"msecs", "XX"); }
	bool setBit(string key, long offset, bool value) { return request!bool("SETBIT", key, offset, value ? "1" : "0"); }
	void setEX(T)(string key, long seconds, T value) if(isValidRedisValueType!T) { request("SETEX", key, seconds, value); }
	long setRange(T)(string key, long offset, T value) if(isValidRedisValueType!T) { return request!long("SETRANGE", key, offset, value); }
	long strlen(string key) { return request!long("STRLEN", key); }

	/*
		Hashes
	*/

	long hdel(string key, scope string[] fields...) { return request!long("HDEL", key, fields); }
	bool hexists(string key, string field) { return request!bool("HEXISTS", key, field); }
	void hset(T)(string key, string field, T value) if(isValidRedisValueType!T) { request("HSET", key, field, value); }
	bool hsetNX(T)(string key, string field, T value) if(isValidRedisValueType!T) { return request!bool("HSETNX", key, field, value); }
	T hget(T = string)(string key, string field) if(isValidRedisValueReturn!T) { return request!T("HGET", key, field); }
	RedisReply!T hgetAll(T = string)(string key) if(isValidRedisValueType!T) { return request!(RedisReply!T)("HGETALL", key); }
	long hincr(string key, string field, long value=1) { return request!long("HINCRBY", key, field, value); }
	long hincr(string key, string field, double value) { return request!long("HINCRBYFLOAT", key, field, value); }
	RedisReply!T hkeys(T = string)(string key) if(isValidRedisValueType!T) { return request!(RedisReply!T)("HKEYS", key); }
	long hlen(string key) { return request!long("HLEN", key); }
	RedisReply!T hmget(T = string)(string key, scope string[] fields...) if(isValidRedisValueType!T) { return request!(RedisReply!T)("HMGET", key, fields); }
	void hmset(ARGS...)(string key, ARGS args) { request("HMSET", key, args); }
	bool hmsetNX(ARGS...)(string key, ARGS args) { return request!bool("HMSET", key, args); }
	RedisReply!T hvals(T = string)(string key) if(isValidRedisValueType!T) { return request!(RedisReply!T)("HVALS", key); }

	/*
		Lists
	*/

	T lindex(T = string)(string key, long index) if(isValidRedisValueReturn!T) { return request!T("LINDEX", key, index); }
	long linsertBefore(T1, T2)(string key, T1 pivot, T2 value) if(isValidRedisValueType!T1 && isValidRedisValueType!T2) { return request!long("LINSERT", key, "BEFORE", pivot, value); }
	long linsertAfter(T1, T2)(string key, T1 pivot, T2 value) if(isValidRedisValueType!T1 && isValidRedisValueType!T2) { return request!long("LINSERT", key, "AFTER", pivot, value); }
	long llen(string key) { return request!long("LLEN", key); }
	long lpush(ARGS...)(string key, ARGS args) { return request!long("LPUSH", key, args); }
	long lpushX(T)(string key, T value) if(isValidRedisValueType!T) { return request!long("LPUSHX", key, value); }
	long rpush(ARGS...)(string key, ARGS args) { return request!long("RPUSH", key, args); }
	long rpushX(T)(string key, T value) if(isValidRedisValueType!T) { return request!long("RPUSHX", key, value); }
	RedisReply!T lrange(T = string)(string key, long start, long stop) { return request!(RedisReply!T)("LRANGE",  key, start, stop); }
	long lrem(T)(string key, long count, T value) if(isValidRedisValueType!T) { return request!long("LREM", key, count, value); }
	void lset(T)(string key, long index, T value) if(isValidRedisValueType!T) { request("LSET", key, index, value); }
	void ltrim(string key, long start, long stop) { request("LTRIM",  key, start, stop); }
	T rpop(T = string)(string key) if(isValidRedisValueReturn!T) { return request!T("RPOP", key); }
	T lpop(T = string)(string key) if(isValidRedisValueReturn!T) { return request!T("LPOP", key); }
	T blpop(T = string)(string key, long seconds) if(isValidRedisValueReturn!T) { return request!T("BLPOP", key, seconds); }
	T rpoplpush(T = string)(string key, string destination) if(isValidRedisValueReturn!T) { return request!T("RPOPLPUSH", key, destination); }

	/*
		Sets
	*/

	long sadd(ARGS...)(string key, ARGS args) { return request!long("SADD", key, args); }
	long scard(string key) { return request!long("SCARD", key); }
	RedisReply!T sdiff(T = string)(scope string[] keys...) if(isValidRedisValueType!T) { return request!(RedisReply!T)("SDIFF", keys); }
	long sdiffStore(string destination, scope string[] keys...) { return request!long("SDIFFSTORE", destination, keys); }
	RedisReply!T sinter(T = string)(string[] keys) if(isValidRedisValueType!T) { return request!(RedisReply!T)("SINTER", keys); }
	long sinterStore(string destination, scope string[] keys...) { return request!long("SINTERSTORE", destination, keys); }
	bool sisMember(T)(string key, T member) if(isValidRedisValueType!T) { return request!bool("SISMEMBER", key, member); }
	RedisReply!T smembers(T = string)(string key) if(isValidRedisValueType!T) { return request!(RedisReply!T)("SMEMBERS", key); }
	bool smove(T)(string source, string destination, T member) if(isValidRedisValueType!T) { return request!bool("SMOVE", source, destination, member); }
	T spop(T = string)(string key) if(isValidRedisValueReturn!T) { return request!T("SPOP", key ); }
	T srandMember(T = string)(string key) if(isValidRedisValueReturn!T) { return request!T("SRANDMEMBER", key ); }
	long srem(ARGS...)(string key, ARGS args) { return request!long("SREM", key, args); }
	RedisReply!T sunion(T = string)(scope string[] keys...) if(isValidRedisValueType!T) { return request!(RedisReply!T)("SUNION", keys); }
	long sunionStore(scope string[] keys...) { return request!long("SUNIONSTORE", keys); }

	/*
		Sorted Sets
	*/

	long zadd(ARGS...)(string key, ARGS args) { return request!long("ZADD", key, args); }
	long zcard(string key) { return request!long("ZCARD", key); }
	deprecated("Use zcard() instead.") alias Zcard = zcard;
	// see http://redis.io/commands/zcount
	long zcount(string RNG = "[]")(string key, double min, double max) { return request!long("ZCOUNT", key, getMinMaxArgs!RNG(min, max)); }
	double zincrby(T)(string key, double value, T member) if (isValidRedisValueType!T) { return request!double("ZINCRBY", key, value, member); }
	//TODO: zinterstore
	// see http://redis.io/commands/zrange
	RedisReply!T zrange(T = string)(string key, long start, long end, bool with_scores = false)
		if(isValidRedisValueType!T)
	{
		if (with_scores) return request!(RedisReply!T)("ZRANGE", key, start, end, "WITHSCORES");
		else return request!(RedisReply!T)("ZRANGE", key, start, end);
	}

	// see http://redis.io/commands/zrangebyscore
	RedisReply!T zrangeByScore(T = string, string RNG = "[]")(string key, double start, double end, bool with_scores = false)
		if(isValidRedisValueType!T)
	{
		if (with_scores) return request!(RedisReply!T)("ZRANGEBYSCORE", key, getMinMaxArgs!RNG(start, end), "WITHSCORES");
		else return request!(RedisReply!T)("ZRANGEBYSCORE", key, getMinMaxArgs!RNG(start, end));
	}

	// see http://redis.io/commands/zrangebyscore
	RedisReply!T zrangeByScore(T = string, string RNG = "[]")(string key, double start, double end, long offset, long count, bool with_scores = false)
		if(isValidRedisValueType!T)
	{
		assert(offset >= 0);
		assert(count >= 0);
		if (with_scores) return request!(RedisReply!T)("ZRANGEBYSCORE", key, getMinMaxArgs!RNG(start, end), "WITHSCORES", "LIMIT", offset, count);
		else return request!(RedisReply!T)("ZRANGEBYSCORE", key, getMinMaxArgs!RNG(start, end), "LIMIT", offset, count);
	}

	long zrank(T)(string key, T member)
		if (isValidRedisValueType!T)
	{
		auto str = request!string("ZRANK", key, member);
		return str ? parse!long(str) : -1;
	}
	long zrem(ARGS...)(string key, ARGS members) { return request!long("ZREM", key, members); }
	long zremRangeByRank(string key, long start, long stop) { return request!long("ZREMRANGEBYRANK", key, start, stop); }
	// see http://redis.io/commands/zrangebyscore
	long zremRangeByScore(string RNG = "[]")(string key, double min, double max) { return request!long("ZREMRANGEBYSCORE", key, getMinMaxArgs!RNG(min, max));}

	RedisReply!T zrevRange(T = string)(string key, long start, long end, bool with_scores = false)
		if(isValidRedisValueType!T)
	{
		if (with_scores) return request!(RedisReply!T)("ZREVRANGE", key, start, end, "WITHSCORES");
		else return request!(RedisReply!T)("ZREVRANGE", key, start, end);
	}

	// see http://redis.io/commands/zrangebyscore
	RedisReply!T zrevRangeByScore(T = string, string RNG = "[]")(string key, double min, double max, bool with_scores=false)
		if(isValidRedisValueType!T)
	{
		if (with_scores) return request!(RedisReply!T)("ZREVRANGEBYSCORE", key, getMinMaxArgs!RNG(min, max), "WITHSCORES");
		else return request!(RedisReply!T)("ZREVRANGEBYSCORE", key, getMinMaxArgs!RNG(min, max));
	}

	// see http://redis.io/commands/zrangebyscore
	RedisReply!T zrevRangeByScore(T = string, string RNG = "[]")(string key, double min, double max, long offset, long count, bool with_scores=false)
		if(isValidRedisValueType!T)
	{
		assert(offset >= 0);
		assert(count >= 0);
		if (with_scores) return request!(RedisReply!T)("ZREVRANGEBYSCORE", key, getMinMaxArgs!RNG(min, max), "WITHSCORES", "LIMIT", offset, count);
		else return request!(RedisReply!T)("ZREVRANGEBYSCORE", key, getMinMaxArgs!RNG(min, max), "LIMIT", offset, count);
	}

	long zrevRank(T)(string key, T member)
		if (isValidRedisValueType!T)
	{
		auto str = request!string("ZREVRANK", key, member);
		return str ? parse!long(str) : -1;
	}

	RedisReply!T zscore(T = string, U)(string key, U member)
		if(isValidRedisValueType!T && isValidRedisValueType!U)
	{
		return request!(RedisReply!T)("ZSCORE", key, member);
	}
	//TODO: zunionstore

	/*
		Pub / Sub
	*/
	long publish(string channel, string message)
	{
		auto str = request!string("PUBLISH", channel, message);
		return str ? parse!long(str) : -1;
	}

	RedisReply!T pubsub(T = string)(string subcommand, scope string[] args...)
		if(isValidRedisValueType!T)
	{
		return request!(RedisReply!T)("PUBSUB", subcommand, args);
	}

	/*
		TODO: Transactions
	*/
	long dbSize() { return request!long("DBSIZE"); }

	/*
		LUA Scripts
	*/
	RedisReply!T eval(T = string, ARGS...)(string lua_code, scope string[] keys, scope ARGS args)
		if(isValidRedisValueType!T)
	{
		return request!(RedisReply!T)("EVAL", lua_code, keys.length, keys, args);
	}

	RedisReply!T evalSHA(T = string, ARGS...)(string sha, scope string[] keys, scope ARGS args)
		if(isValidRedisValueType!T)
	{
		return request!(RedisReply!T)("EVALSHA", sha, keys.length, keys, args);
	}

	//scriptExists
	//scriptFlush
	//scriptKill

	string scriptLoad(string lua_code) { return request!string("SCRIPT", "LOAD", lua_code); }


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
import vibe.core.concurrency;
import std.variant;
import std.typecons : Tuple, tuple;
import std.container : Array;
import std.algorithm : canFind;
import std.range : takeOne;
import std.array : array;

import vibe.utils.memory;

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
		RecursiveTaskMutex m_mutex;
		TaskMutex m_connMutex;
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

	@property string[] subscriptions() const {
		return m_subscriptions.keys;
	}

	bool hasSubscription(string channel) const {
		return (channel in m_subscriptions) !is null && m_subscriptions[channel];
	}

	this(RedisClient client) {

		logTrace("this()");
		m_client = client;
		m_mutex = new RecursiveTaskMutex;
		m_connMutex = new TaskMutex;
	}

	~this() {
		logTrace("~this");
		bstop();
	}

	void bstop(){
		logTrace("bstop");
		if (!m_listening)
			return;
		void impl() {
			synchronized (m_mutex) {
				m_waiter = Task.getThis();
				scope(exit) m_waiter = Task();
				stop();

				bool stopped;
				do {
					if (!receiveTimeout(3.seconds, (Action act) { if (act == Action.STOP) stopped = true;  })) 
						break;
				}
				while (!stopped);
				
				enforce(stopped, "Failed to wait for Redis listener to stop");
			}
		}
		inTask(&impl);
	}


	void stop(){
		logTrace("stop");
		if (!m_listening)
			return;

		void impl() {
			synchronized (m_mutex) {
				m_stop = true;
				m_listener.send(Action.STOP);
				// send a message to wake up the listenerHelper from the reply
				if (m_subscriptions.length > 0) {
					synchronized(m_connMutex)
						_request_void(m_lockedConnection, "UNSUBSCRIBE", cast(string[]) m_subscriptions.keys.takeOne.array );
					sleep(30.msecs);
				}
			}
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

		void impl() {

			scope(failure) { logTrace("Failure"); bstop(); }
			try synchronized(m_mutex) {
				m_waiter = Task.getThis();
				scope(exit) m_waiter = Task();
				bool subscribed;
				synchronized(m_connMutex)
					_request_void(m_lockedConnection, "SUBSCRIBE", args);
				while(!m_subscriptions.keys.canFind(args)) {
					if (!receiveTimeout(2.seconds, (Action act) { enforce(act == Action.SUBSCRIBE);  })) 
						break;

					subscribed = true;
				}
				logTrace("Can find keys? : " ~ m_subscriptions.keys.canFind(args).to!string);
				logTrace("Subscriptions: " ~ m_subscriptions.keys.to!string);
				enforce(subscribed, "Could not complete subscription(s).");

			} catch (Throwable e) {
				logTrace(e.toString());
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

		void impl() {

			if (!anySubscribed(args))
				return;

			scope(failure) bstop();
			assert(m_listening);
			synchronized(m_mutex) {
				m_waiter = Task.getThis();
				scope(exit) m_waiter = Task();
				bool unsubscribed;
				synchronized(m_connMutex)
					_request_void(m_lockedConnection, "UNSUBSCRIBE", args);
				while(m_subscriptions.keys.canFind(args)) {
					if (!receiveTimeout(2.seconds, (Action act) { enforce(act == Action.UNSUBSCRIBE);  })) {
						unsubscribed = false;
						break;
					}
					unsubscribed = true;
				}
				logTrace("Can find keys? : " ~ m_subscriptions.keys.canFind(args).to!string);
				logTrace("Subscriptions: " ~ m_subscriptions.keys.to!string);
				enforce(unsubscribed, "Could not complete unsubscription(s).");
				
			}

		}
		inTask(&impl);
	}

	/// Same as subscribe, but uses glob patterns, and does not return instantly if
	/// the subscriptions are already registered.
	/// throws Exception if the pattern does not yield a new subscription.
	void psubscribe(scope string[] args...)
	{
		logTrace("psubscribe");
		void impl() {
			scope(failure) bstop();
			assert(m_listening);
			synchronized(m_mutex) {
				m_waiter = Task.getThis();
				scope(exit) m_waiter = Task();
				bool subscribed;
				synchronized(m_connMutex)
					_request_void(m_lockedConnection, "PSUBSCRIBE", args);

				if (!receiveTimeout(2.seconds, (Action act) { enforce(act == Action.SUBSCRIBE);  })) 
					subscribed = false;
				else
					subscribed = true;

				logTrace("Subscriptions: " ~ m_subscriptions.keys.to!string);
				enforce(subscribed, "Could not complete subscription(s).");
				
			}
		}
		inTask(&impl);
	}
	
	/// Same as unsubscribe, but uses glob patterns, and does not return instantly if
	/// the subscriptions are not registered.
	/// throws Exception if the pattern does not yield a new unsubscription.
	void punsubscribe(scope string[] args...)
	{
		logTrace("punsubscribe");
		void impl() {
			scope(failure) bstop();
			assert(m_listening);
			synchronized(m_mutex) {
				m_waiter = Task.getThis();
				scope(exit) m_waiter = Task();
				bool unsubscribed;
				synchronized(m_connMutex)
					_request_void(m_lockedConnection, "PUNSUBSCRIBE", args);
				if (!receiveTimeout(2.seconds, (Action act) { enforce(act == Action.UNSUBSCRIBE);  }))
					unsubscribed = false;
				else
					unsubscribed = true;
				
				logTrace("Can find keys? : " ~ m_subscriptions.keys.canFind(args).to!string);
				logTrace("Subscriptions: " ~ m_subscriptions.keys.to!string);
				enforce(unsubscribed, "Could not complete unsubscription(s).");
				
			}
		}
		inTask(&impl);
	}

	private void inTask(void delegate() impl) {
		logTrace("inTask");
		if (Task.getThis() == Task())
		{
			import vibe.core.driver;
			Throwable ex;
			bool done;
			Task task = runTask({
				logDebug("inTask" ~ Task.getThis().to!string);
				try impl();
				catch (Throwable e) {
					ex = e;
				}
				done = true;
			});
			while(!done && !ex) {
				processEvents();
			}
			logDebug("done");
			if (ex)
				throw ex;
		}
		else
			impl();
	}

	private void init(){

		logTrace("init");
		if (m_lockedConnection.__conn is null){
			m_lockedConnection = m_client.m_connections.lockConnection();
			m_lockedConnection.setAuth(m_client.m_authPassword);
			m_lockedConnection.setDB(m_client.m_selectedDB);
		}

		if (!m_lockedConnection.conn || !m_lockedConnection.conn.connected) {
			try m_lockedConnection.conn = connectTCP(m_lockedConnection.m_host, m_lockedConnection.m_port);
			catch (Exception e) {
				throw new Exception(format("Failed to connect to Redis server at %s:%s.", m_lockedConnection.m_host, m_lockedConnection.m_port), __FILE__, __LINE__, e);
			}
			
			m_lockedConnection.setAuth(m_client.m_authPassword); 
			m_lockedConnection.setDB(m_client.m_selectedDB);
		}
	}

	// Same as listen, but blocking
	void blisten(void delegate(string, string) onMessage, Duration timeout = 0.seconds)
	{
		init();

		void onSubscribe(string channel) {
			logTrace("Callback subscribe(%s)", channel);
			m_subscriptions[channel] = true;
			if (m_waiter != Task())
				m_waiter.send(Action.SUBSCRIBE);
		}

		void onUnsubscribe(string channel) {
			logTrace("Callback unsubscribe(%s)", channel);
			m_subscriptions.remove(channel);
			if (m_waiter != Task())
				m_waiter.send(Action.UNSUBSCRIBE);
		}

		void teardown() { // teardown
			logTrace("Redis listener exiting");
			// More publish commands may be sent to this connection after recycling it, so we
			// actively destroy it
			Action act;
			// wait for the listener helper to send its stop message
			while (act != Action.STOP) 
				act = receiveOnly!Action();
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
			ubyte[] newLine = allocArray!ubyte(manualAllocator(), 1);
			scope(exit) freeArray(manualAllocator(), newLine);
			logTrace("Pubsub handler");
			void delegate() dropCRLF = {
				conn.read(newLine);
				conn.read(newLine);
			};
			size_t delegate() readArgs = {
				char[] ucnt = allocArray!char(manualAllocator(), 8);
				scope(exit) freeArray(manualAllocator(), ucnt);
				ubyte num;
				size_t i;
				do {
					conn.read((&num)[0..1]);
					if (num >= 48 && num <= 57)
						ucnt[i] = num;
					else break;
					i++;
				}
				while (true); // ascii
				conn.read(newLine);
				logTrace("Found %s", ucnt);
				// the new line is consumed when num is not in range.
				return ucnt[0 .. i].to!size_t;
			};
			// find the number of arguments in the array
			ubyte symbol;
			conn.read((&symbol)[0 .. 1]);
			enforce(symbol == '*', "Expected '*', got '" ~ symbol.to!string ~ "'");
			size_t args = readArgs();
			// get the number of characters in the first string (the command)
			conn.read((&symbol)[0 .. 1]);
			enforce(symbol == '$', "Expected '$', got '" ~ symbol.to!string ~ "'");
			size_t cnt = readArgs();
			ubyte[] cmd = allocArray!ubyte(manualAllocator(), cnt);
			scope(exit) freeArray(manualAllocator(), cmd);
			conn.read(cmd);
			dropCRLF();
			// find the channel
			conn.read((&symbol)[0 .. 1]);
			enforce(symbol == '$', "Expected '$', got '" ~ symbol.to!string ~ "'");
			cnt = readArgs();
			ubyte[] str = allocArray!ubyte(manualAllocator(), cnt);
			conn.read(str);
			dropCRLF();
			string channel = cast(string) str.idup; // copy to GC to avoid bugs
			freeArray(manualAllocator(), str);
			logTrace("chan: %s", channel);

			if (cmd == "message") { // find the message
				conn.read((&symbol)[0 .. 1]);
				enforce(symbol == '$', "Expected '$', got '" ~ symbol.to!string ~ "'");
				cnt = readArgs();
				str = allocArray!ubyte(manualAllocator(), cnt);
				conn.read(str); // channel
				string message = cast(string) str.idup; // copy to GC to avoid bugs
				logTrace("msg: %s", message);
				freeArray(manualAllocator(), str);
				dropCRLF();
				onMessage(channel, message);
			}
			else if (cmd == "subscribe" || cmd == "unsubscribe") { // find the remaining subscriptions
				bool is_subscribe = (cmd == "subscribe");
				conn.read((&symbol)[0 .. 1]);
				enforce(symbol == ':', "Expected ':', got '" ~ symbol.to!string ~ "'");
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

					Task.getThis().messageQueue.clear();
					m_listener.send(Action.DATA);
					if (!receiveTimeout(5.seconds, (Action act) { assert(act == Action.DATA); }))
						assert(false);

				} else if (m_stop || !m_lockedConnection.conn) break;
				logTrace("No data arrival in 100 ms...");
			}
			logTrace("Listener Helper exit.");
			m_listener.send(Action.STOP);
		} );

		m_listening = true;
		logTrace("Redis listener now listening");
		if (m_waiter != Task())
			m_waiter.send(Action.STARTED);

		if (timeout == 0.seconds)
			timeout = 365.days; // make sure 0.seconds is considered as big.

		scope(exit) {
			logTrace("Redis Listener exit.");
			if (!m_stop) {
				stop(); // notifies the listenerHelper
			}
			// close the data connections
			teardown();
			
			if (m_waiter != Task())
				m_waiter.send(Action.STOP);
			
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
				synchronized(m_connMutex)
					pubsub_handler(); // handles one command at a time
				m_listenerHelper.send(Action.DATA);
			};

			if (!receiveTimeout(timeout, handler) || m_stop) {
				logTrace("Redis Listener stopped");
				break;
			}

		}

	}

	/// Waits for messages and calls the callback with the channel and the message as arguments.
	/// The timeout is passed over to the listener, which closes after the period of inactivity.
	/// Use 0.seconds timeout to specify a very long time (365 days)
	/// Errors will be sent to Callback Delegate on channel "Error".
	Task listen(void delegate(string, string) callback, Duration timeout = 0.seconds)
	{
		logTrace("Listen");
		void impl() {
			logTrace("Listen");
			m_waiter = Task.getThis();
			scope(exit) m_waiter = Task();
			Throwable ex;
			m_listener = runTask({
				try blisten(callback, timeout);
				catch(Throwable e) {
					ex = e;
					if (m_waiter != Task() && !m_listening) {
						m_waiter.send(Action.STARTED);
						return;
					}
					callback("Error", e.toString());
				}
			});
			synchronized(m_mutex) {
				import std.datetime : usecs;
				receiveTimeout(2.seconds, (Action act) { assert( act == Action.STARTED); });
				if (ex) throw ex;
				enforce(m_listening, "Failed to start listening, timeout of 2 seconds expired");
			}


			foreach (channel; m_pendingSubscriptions) {
				subscribe(channel);
			}

			m_pendingSubscriptions = null;
		}
		inTask(&impl);
		return m_listener;
	}
}



/** Range interface to a single Redis reply.
*/
struct RedisReply(T = ubyte[]) {
	import vibe.utils.memory : FreeListRef;

	static assert(isInputRange!RedisReply);

	private {
		uint m_magic = 0x15f67ab3;
		RedisConnection m_conn;
		LockedConnection!RedisConnection m_lockedConnection;
	}

	alias ElementType = T;

	this(RedisConnection conn)
	{
		m_conn = conn;
		auto ctx = &conn.m_replyContext;
		assert(ctx.refCount == 0);
		*ctx = RedisReplyContext.init;
		ctx.refCount++;
		initialize();
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

		static if (isSomeString!T) validate(cast(T)ret);

		static if (is(T == ubyte[])) return ret;
		else static if (is(T == string)) return cast(T)ret.idup;
		else static if (is(T == bool)) return ret[0] == '1';
		else static if (is(T == int) || is(T == long) || is(T == size_t) || is(T == double)) {
			auto str = cast(string)ret;
			return parse!T(str);
		}
		else static assert(false, "Unsupported Redis reply type: " ~ T.stringof);
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
		return cast(TN)ret;
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
			readBulk(cast(string)m_conn.conn.readLine());
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

		auto ln = cast(string)m_conn.conn.readLine();

		switch (ln[0]) {
			default: throw new Exception(format("Unknown reply type: %s", ln[0]));
			case '+': ctx.data = cast(ubyte[])ln[1 .. $]; ctx.hasData = true; break;
			case '-': throw new Exception(ln[1 .. $]);
			case ':': ctx.data = cast(ubyte[])ln[1 .. $]; ctx.hasData = true; break;
			case '$':
				readBulk(ln);
				break;
			case '*':
				if (ln.startsWith("*-1")) {
					ctx.length = 0; // TODO: make this NIL reply distinguishable from a 0-length array
				} else {
					ctx.multi = true;
					ctx.length = to!long(ln[ 1 .. $ ]);
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
			auto rangeCnt = RangeCounter(&length);
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
	}

	auto nargs = conn.countArgs(args);
	auto rng = StreamOutputRange(conn.conn);
	formattedWrite(&rng, "*%d\r\n$%d\r\n%s\r\n", nargs + 1, command.length, command);
	RedisConnection.writeArgs(&rng, args);
}

private RedisReply!T _request_reply(T = ubyte[], ARGS...)(RedisConnection conn, string command, scope ARGS args)
{
	import vibe.stream.wrapper;

	if (!conn.conn || !conn.conn.connected) {
		try conn.conn = connectTCP(conn.m_host, conn.m_port);
		catch (Exception e) {
			throw new Exception(format("Failed to connect to Redis server at %s:%s.", conn.m_host, conn.m_port), __FILE__, __LINE__, e);
		}
	}

	auto nargs = conn.countArgs(args);
	auto rng = StreamOutputRange(conn.conn);
	formattedWrite(&rng, "*%d\r\n$%d\r\n%s\r\n", nargs + 1, command.length, command);
	RedisConnection.writeArgs(&rng, args);
	rng.flush();

	return RedisReply!T(conn);
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

private template typeFormatString(T)
{
	static if (isFloatingPoint!T) enum typeFormatString = "%.16g";
	else enum typeFormatString = "%s";
}