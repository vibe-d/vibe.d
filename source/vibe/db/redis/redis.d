/**
	Redis database client implementation.

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger
*/
module vibe.db.redis.redis;

public import vibe.core.net;

import vibe.core.connectionpool;
import vibe.core.core;
import vibe.core.log;
import vibe.stream.operations;
import std.conv;
import std.exception;
import std.format;
import std.range : isOutputRange;
import std.string;
import std.traits;
import std.utf;

// TODO: convert RedisReply to expose an input range interface


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

	/// Returns Redis version
	@property string redisVersion() { return m_version; }

	deprecated("Use getDatabase() to access individual databases instead.")
	@property RedisDatabase selectedDB() { return getDatabase(m_selectedDB); }

	deprecated("Use getDatabase() to access individual databases instead.")
	void select(long db_index) { m_selectedDB = db_index; }

	deprecated("Use getDatabase() to access individual databases.")
	alias selectedDB this;

	/** Returns a handle to the given database.
	*/
	RedisDatabase getDatabase(long index) { return RedisDatabase(this, index); }

	/*
		Connection
	*/
	void auth(string password) { m_authPassword = password; }
	T echo(T : E[], E)(T data) { return request!T("ECHO", data); }
	void ping() { request("PING"); }
	void quit() { request("QUIT"); }

	/*
		Server
	*/

	//TODO: BGREWRITEAOF
	//TODO: BGSAVE

	T getConfig(T : E[], E)(string parameter) { return request!T("GET CONFIG", parameter); }
	void setConfig(T : E[], E)(string parameter, T value) { request("SET CONFIG", parameter, value); }
	void configResetStat() { request("CONFIG RESETSTAT"); }
	//TOOD: Debug Object
	//TODO: Debug Segfault
	void flushAll() { request("FLUSHALL"); }
	void flushDB() { request("FLUSHDB"); }
	string info() { return request!string("INFO"); }
	long lastSave() { return request!long("LASTSAVE"); }
	//TODO monitor
	void save() { request("SAVE"); }
	void shutdown() { request("SHUTDOWN"); }
	void slaveOf(string host, ushort port) { request("SLAVEOF", host, port); }
	//TODO slowlog
	//TODO sync

	private T request(T = void, ARGS...)(string command, ARGS args)
	{
		return requestDB!(T, ARGS)(m_selectedDB, command, args);
	}

	private T requestDB(T, ARGS...)(long db, string command, ARGS args)
	{
		auto conn = m_connections.lockConnection();
		conn.setAuth(m_authPassword);
		conn.setDB(db);
		static if (is(T == void)) {
			version (RedisDebug) {
				import std.stdio;
				
				import std.array, std.traits, std.algorithm;
				string[] arr;
				foreach(i, A; ARGS){
					static if (!isSomeString!A && isArray!A){
						arr ~= "[" ~ (cast(string[])args[i].map!(a=> a.to!string).array).joiner(",").to!string ~ "]";
					}
					else
					{
						arr ~= args[i].to!string; 
					}
				}
				logInfo("Redis request: %s ( %s ) => (void)", command, arr);
			}
			return _request!T(conn, command, args);
		} else static if (!is (T == RedisReply)) {
			auto ret = _request!T(conn, command, args);
			version (RedisDebug) {
				import std.stdio;

				import std.array, std.traits, std.algorithm;
				string[] arr;
				foreach(i, A; ARGS){
					static if (!isSomeString!A && isArray!A){
						arr ~= "[" ~ (cast(string[])args[i].map!(a=> a.to!string).array).joiner(",").to!string ~ "]";
					}
					else
					{
						arr ~= args[i].to!string;
					}
				}
				logInfo("Redis request: %s ( %s ) => %s", command, arr, ret.to!string);
			}
			return ret;
		} else {
			auto ret = _request!T(conn, command, args);
			version (RedisDebug) {
				import std.stdio;
				
				import std.array, std.traits, std.algorithm;
				string[] arr;
				foreach(i, A; ARGS){
					static if (!isSomeString!A && isArray!A){
						arr ~= "[" ~ (cast(string[])args[i].map!(a=> a.to!string).array).joiner(",").to!string ~ "]";
					}
					else
					{
						arr ~= args[i].to!string;
					}
				}
				logInfo("Redis request: %s ( %s ) => (RedisReply)", command, arr);
			}
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

	long del(string[] keys...) { return request!long("DEL", keys); }
	bool exists(string key) { return request!bool("EXISTS", key); }
	bool expire(string key, long seconds) { return request!bool("EXPIRE", key, seconds); }
	bool expireAt(string key, long timestamp) { return request!bool("EXPIREAT", key, timestamp); }
	RedisReply keys(string pattern) { return request!RedisReply("KEYS", pattern); }
	bool move(string key, string db) { return request!bool("MOVE", key, db); }
	bool persists(string key) { return request!bool("PERSISTS", key); }
	//TODO: object
	string randomKey() { return request!string("RANDOMKEY"); }
	void rename(string key, string newkey) { request("RENAME", key, newkey); }
	bool renameNX(string key, string newkey) { return request!bool("RENAMENX", key, newkey); }
	//TODO sort
	long ttl(string key) { return request!long("TTL", key); }
	string type(string key) { return request!string("TYPE", key); }
	//TODO eval

	/*
		String Commands
	*/

	long append(T : E[], E)(string key, T suffix) { return request!long("APPEND", key, suffix); }
	long decr(string key, long value = 1) { return value == 1 ? request!long("DECR", key) : request!long("DECRBY", key, value); }
	T get(T : E[], E)(string key) { return request!T("GET", key); }
	bool getBit(string key, long offset) { return request!bool("GETBIT", key, offset); }
	T getRange(T : E[], E)(string key, long start, long end) { return request!T("GETRANGE", start, end); }
	T getSet(T : E[], E)(string key, T value) { return request!T("GET", key, value); }
	long incr(string key, long value = 1) { return value == 1 ? request!long("INCR", key) : request!long("INCRBY", key, value); }
	RedisReply mget(string[] keys) { return request!RedisReply("MGET", keys); }
	
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

	void set(T : E[], E)(string key, T value) { request("SET", key, value); }
	bool setBit(string key, long offset, bool value) { return request!bool("SETBIT", key, offset, value ? "1" : "0"); }
	void setEX(T : E[], E)(string key, long seconds, T value) { request("SETEX", key, seconds, value); }
	bool setNX(T : E[], E)(string key, T value) { return request!bool("SETNX", key, value); }
	long setRange(T : E[], E)(string key, long offset, T value) { return request!long("SETRANGE", key, offset, value); }
	long strlen(string key) { return request!long("STRLEN", key); }

	/*
		Hashes
	*/

	long hdel(string key, string[] fields...) { return request!long("HDEL", key, fields); }
	bool hexists(string key, string field) { return request!bool("HEXISTS", key, field); }
	void hset(T : E[], E)(string key, string field, T value) { request("HSET", key, field, value); }
	T hget(T : E[], E)(string key, string field) { return request!T("HGET", key, field); }
	RedisReply hgetAll(string key) { return request!RedisReply("HGETALL", key); }
	long hincr(string key, string field, long value=1) { return request!long("HINCRBY", key, field, value); }
	RedisReply hkeys(string key) { return request!RedisReply("HKEYS", key); }
	long hlen(string key) { return request!long("HLEN", key); }
	RedisReply hmget(string key, string[] fields...) { return request!RedisReply("HMGET", key, fields); }
	void hmset(ARGS...)(string key, ARGS args) { request("HMSET", key, args); }
	bool hmsetNX(ARGS...)(string key, ARGS args) { return request!bool("HMSET", key, args); }
	RedisReply hvals(string key) { return request!RedisReply("HVALS", key); }
	T lindex(T : E[], E)(string key, long index) { return request!T("LINDEX", key, index); }
	long linsertBefore(T1, T2)(string key, T1 pivot, T2 value) { return request!long("LINSERT", key, "BEFORE", pivot, value); }
	long linsertAfter(T1, T2)(string key, T1 pivot, T2 value) { return request!long("LINSERT", key, "AFTER", pivot, value); }
	long llen(string key) { return request!long("LLEN", key); }
	long lpush(ARGS...)(string key, ARGS args) { return request!long("LPUSH", key, args); }
	long lpushX(T)(string key, T value) { return request!long("LPUSHX", key, value); }
	long rpush(ARGS...)(string key, ARGS args) { return request!long("RPUSH", key, args); }
	long rpushX(T)(string key, T value) { return request!long("RPUSHX", key, value); }
	RedisReply lrange(string key, long start, long stop) { return request!RedisReply("LRANGE",  key, start, stop); }
	long lrem(T : E[], E)(string key, long count, T value) { return request!long("LREM", count, value); }
	void lset(T : E[], E)(string key, long index, T value) { request("LSET", key, index, value); }
	void ltrim(string key, long start, long stop) { request("LTRIM",  key, start, stop); }
	T rpop(T : E[], E)(string key) { return request!T("RPOP", key); }
	T lpop(T : E[], E)(string key) { return request!T("LPOP", key); }
	T blpop(T : E[], E)(string key, long seconds) { return request!T("BLPOP", key, seconds); }
	T rpoplpush(T : E[], E)(string key, string destination) { return request!T("RPOPLPUSH", key, destination); }

	/*
		Sets
	*/

	long sadd(ARGS...)(string key, ARGS args) { return request!long("SADD", key, args); }
	long scard(string key) { return request!long("SCARD", key); }
	RedisReply sdiff(string[] keys...) { return request!RedisReply("SDIFF", keys); }
	long sdiffStore(string destination, string[] keys...) { return request!long("SDIFFSTORE", destination, keys); }
	RedisReply sinter(string[] keys) { return request!RedisReply("SINTER", keys); }
	long sinterStore(string destination, string[] keys...) { return request!long("SINTERSTORE", destination, keys); }
	bool sisMember(T : E[], E)(string key, T member) { return request!bool("SISMEMBER", key, member); }
	RedisReply smembers(string key) { return request!RedisReply("SMEMBERS", key); }
	bool smove(T : E[], E)(string source, string destination, T member) { return request!bool("SMOVE", source, destination, member); }
	T spop(T : E[], E)(string key) { return request!T("SPOP", key ); }
	T srandMember(T : E[], E)(string key) { return request!T("SRANDMEMBER", key ); }
	long srem(ARGS...)(string key, ARGS args) { return request!long("SREM", key, args); }
	RedisReply sunion(string[] keys...) { return request!RedisReply("SUNION", keys); }
	long sunionStore(string[] keys...) { return request!long("SUNIONSTORE", keys); }

	/*
		Sorted Sets
	*/

	long zadd(ARGS...)(string key, ARGS args) { return request!long("ZADD", key, args); }
	long Zcard(string key) { return request!long("ZCARD", key); }
	// TODO:
	// supports only inclusive intervals
	// see http://redis.io/commands/zrangebyscore
	long zcount(string key, double min, double max) { return request!long("ZCOUNT", key, min, max); }
	double zincrby(string key, double value, string member) { return request!double("ZINCRBY", value, member); }
	//TODO: zinterstore
	RedisReply zrange(string key, long start, long end, bool withScores=false) {
		string[] args = [key, to!string(start), to!string(end)];
		if (withScores) args ~= "WITHSCORES";
		return request!RedisReply("ZRANGE", args);
	}

	// TODO:
	// supports only inclusive intervals
	// see http://redis.io/commands/zrangebyscore
	RedisReply zrangeByScore(string key, double start, double end, bool withScores=false) {
		string[] args = [key, to!string(start), to!string(end)];
		if (withScores) args ~= "WITHSCORES";
		return request!RedisReply("ZRANGEBYSCORE", args);
	}

	// TODO:
	// supports only inclusive intervals
	// see http://redis.io/commands/zrangebyscore
	RedisReply zrangeByScore(string key, double start, double end, long offset, long count, bool withScores=false) {
		assert(offset >= 0);
		assert(count >= 0);
		string[] args = [key, to!string(start), to!string(end)];
		if (withScores) args ~= "WITHSCORES";
		args ~= ["LIMIT", to!string(offset), to!string(count)];
		return request!RedisReply("ZRANGEBYSCORE", args);
	}

	long zrank(string key, string member) {
		auto str = request!string("ZRANK", key, member);
		return str ? parse!long(str) : -1;
	}
	long zrem(string key, string[] members...) { return request!long("ZREM", key, members); }
	long zremRangeByRank(string key, long start, long stop) { return request!long("ZREMRANGEBYRANK", key, start, stop); }
	// TODO:
	// supports only inclusive intervals
	// see http://redis.io/commands/zrangebyscore
	long zremRangeByScore(string key, double min, double max) { return request!long("ZREMRANGEBYSCORE", key, min, max);}

	RedisReply zrevRange(string key, long start, long end, bool withScores=false) {
		string[] args = [key, to!string(start), to!string(end)];
		if (withScores) args ~= "WITHSCORES";
		return request!RedisReply("ZREVRANGE", args);
	}

	// TODO:
	// supports only inclusive intervals
	// see http://redis.io/commands/zrangebyscore
	RedisReply zrevRangeByScore(string key, double min, double max, bool withScores=false) {
		string[] args = [key, to!string(min), to!string(max)];
		if (withScores) args ~= "WITHSCORES";
		return request!RedisReply("ZREVRANGEBYSCORE", args);
	}

	// TODO:
	// supports only inclusive intervals
	// see http://redis.io/commands/zrangebyscore
	RedisReply zrevRangeByScore(string key, double min, double max, long offset, long count, bool withScores=false) {
		assert(offset >= 0);
		assert(count >= 0);
		string[] args = [key, to!string(min), to!string(max)];
		if (withScores) args ~= "WITHSCORES";
		args ~= ["LIMIT", to!string(offset), to!string(count)];
		return request!RedisReply("ZREVRANGEBYSCORE", args);
	}

	long zrevRank(string key, string member) {
		auto str = request!string("ZREVRANK", key, member);
		return str ? parse!long(str) : -1;
	}

	RedisReply zscore(string key, string member) { return request!RedisReply("ZSCORE", key, member); }
	//TODO: zunionstore

	/*
		Pub / Sub
	*/
	long publish(string channel, string message) {
		auto str = request!string("PUBLISH", channel, message);
		return str ? parse!long(str) : -1;
	}

	RedisReply pubsub(string subcommand, string[] args...) {
		return request!RedisReply("PUBSUB", subcommand, args);
	}

	/*
		TODO: Transactions
	*/
	long dbSize() { return request!long("DBSIZE"); }

	T request(T = void, ARGS...)(string command, ARGS args)
	{
		return m_client.requestDB!(T, ARGS)(m_index, command, args);
	}
}


/**
	A redis subscription listener
*/
import std.datetime;
import vibe.core.concurrency;
import std.variant;
import std.typecons : Tuple, tuple;
import std.datetime;

final class RedisSubscriber {
	private {
		RedisClient m_client;
		LockedConnection!RedisConnection m_lockedConnection;
		bool[string] m_subscriptions;
		void delegate(string[] args) m_capture;
		bool m_listening;
		bool m_stop;
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
		m_client = client;
	}

	bool bstop(){
		if (!stop()) return false;
		while (m_listening) sleep(1.msecs);
		return true;
	}

	bool stop(){
		if (!m_listening)
			return false;
		m_stop = true;
		return true;
	}

	void subscribe(string[] args...) { 
		assert(m_listening);
		m_capture = (channels){
			logInfo("Callback subscribe(%s)", channels);
			foreach (channel; channels) m_subscriptions[channel] = true;
		};
		_request_void(m_lockedConnection, "SUBSCRIBE", args); 
		while (m_capture !is null) sleep(1.msecs);
	}

	void unsubscribe(string[] args...) { 
		assert(m_listening);
		m_capture = (channels){
			logInfo("Callback unsubscribe(%s)", channels);
			foreach (channel; channels) m_subscriptions.remove(channel);
		};
		_request_void(m_lockedConnection, "UNSUBSCRIBE", args);
		while (m_capture !is null) sleep(1.msecs);
	}

	void psubscribe(string[] args...) {
		assert(m_listening); 
		m_capture = (channels){
			logInfo("Callback psubscribe(%s)", channels);
			foreach (channel; channels) m_subscriptions[channel] = true;
		};
		_request_void(m_lockedConnection, "PSUBSCRIBE", args);
		while (m_capture !is null) sleep(1.msecs);
	}

	void punsubscribe(string[] args...) { 
		assert(m_listening);
		m_capture = (channels){
			logInfo("Callback punsubscribe(%s)", channels);
			foreach (channel; channels) m_subscriptions.remove(channel);
		};
		_request_void(m_lockedConnection, "PUNSUBSCRIBE", args);
		while (m_capture !is null) sleep(1.msecs);
	}

	private string getString(){
		auto ln = cast(string)m_lockedConnection.conn.readLine();
		enforceEx!RedisProtocolException(ln[0] == "$"[0], "Expected a string length, received bad response : " ~ ln);
		//auto strLen = ln[1..$].to!long;
		auto str = cast(string)m_lockedConnection.conn.readLine();
		return str;
	}

	private void init(){
		if (m_lockedConnection is null){
			m_lockedConnection = m_client.m_connections.lockConnection();
			m_lockedConnection.setAuth(m_client.m_authPassword);
			m_lockedConnection.setDB(m_client.m_selectedDB);
		}
	}

	// Same as listen, but blocking
	void blisten(void delegate(string, string) callback, Duration timeout)
	{
		init();
		m_listening = true;
		while(true) {

			bool gotData;
			StopWatch sw;
			sw.start();
			while (!gotData){
				if (m_lockedConnection.conn.waitForData(5.seconds))	gotData = true;
				if (sw.peek().seconds > timeout.total!"seconds") { gotData = false;	break; }
				if (m_stop){ gotData = false; break; }
			}
			sw.stop();

			if (!gotData) { m_listening = false; m_lockedConnection.destroy(); return; }

			if (m_capture !is null){
				auto res = handler();
				m_capture(res[1]);
				enforceEx!RedisProtocolException(m_subscriptions.length == res[0], "Subscription count is different than reported by the Redis server");
				m_capture = null;
				continue;
			}

			auto ln = cast(string)m_lockedConnection.conn.readLine();
			string cmd;
			if (ln[0] == "$"[0]){
				cmd = cast(string)m_lockedConnection.conn.readLine();
			} 
			else if (ln[0] == "*"[0]) {
				cmd = getString();
			}else {
				enforceEx!RedisProtocolException(false, "expected $ or *");
			}
			if(cmd == "message") {
				auto channel = getString();
				auto message = getString();
				callback(channel, message);

			} 
			else {
				handler(); // get rid of it
			}
		}

	}
	private Tuple!(long, string[]) handler(){
		assert(m_lockedConnection !is null);

		auto ctx = RedisReplyContext.init;
		string[] channels;
		long subscriptions;

		void readBulk(string sizeLn)
		{
			assert(m_lockedConnection !is null);
			if (sizeLn.startsWith("$-1")) return;
			if (sizeLn.startsWith(':')){
				subscriptions = sizeLn[1..$].to!long;
				return;
			}
			else {
				auto data = cast(string)m_lockedConnection.conn.readLine();
				if (data != "subscribe" && data != "unsubscribe"){
					channels ~= cast(string)data;
				}
			}
		}

		@property bool hasNext() const { return m_lockedConnection && ctx.index < ctx.length; }

		void next(){

			if (!ctx.initialized){
				auto ln = cast(string)m_lockedConnection.conn.readLine();

				switch (ln[0]) {
					default: throw new Exception(format("Unknown reply type: %s", ln[0]));
					//case '+': ctx.data = cast(ubyte[])ln[1 .. $]; break;
					//case '-': throw new Exception(ln[1 .. $]);
					//case ':': ctx.data = cast(ubyte[])ln[1 .. $]; break;
					case '$': readBulk(ln); break;
					case '*':
						if (ln.startsWith("*-1")) {
							ctx.length = 0;
						} else {
							ctx.multi = true;
							ctx.length = to!long(ln[ 1 .. $ ]);
						}
						break;
				}
			}
			ctx.initialized = true;
			ctx.index++;
			if (ctx.multi) {
				auto ln = cast(string)m_lockedConnection.conn.readLine();
				readBulk(ln);
			}
		}
		while(hasNext) next();
		return tuple(subscriptions, channels);
	}


	// Waits for messages and calls the callback with the channel and the message as arguments
	Task listen(void delegate(string, string) callback, Duration timeout = 0.seconds)
	{
		auto task = runTask({
			blisten(callback, timeout);
		});
		import std.datetime;
		while(!m_listening) sleep(1.usecs);
		return task;
	}
}

struct RedisReply {
	import vibe.utils.memory : FreeListRef;
	private {
		uint m_magic = 0x15f67ab3;
		RedisConnection m_conn;
		LockedConnection!RedisConnection m_lockedConnection;
	}

	this(RedisConnection conn)
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

	@property bool hasNext() const { return m_conn && m_conn.m_replyContext.index < m_conn.m_replyContext.length; }

	T next(T : E[], E)()
	{
		assert(hasNext, "end of reply");
		auto ctx = &m_conn.m_replyContext;
		if (!ctx.initialized) init();
		ctx.index++;
		ubyte[] ret;
		if (ctx.multi) {
			auto ln = cast(string)m_conn.conn.readLine();
			ret = readBulk(ln);
		} else {
			ret = ctx.data;
		}
		if (!hasNext && ctx.refCount == 1) {
			ctx.refCount = 0;
			m_conn = null;
			m_lockedConnection.destroy();
		}

		static if (isSomeString!T) validate(cast(T)ret);
		enforce(ret.length % E.sizeof == 0, "bulk size must be multiple of element type size");
		return cast(T)ret;
	}

	void drop()
	{
		if (!m_conn) return;
		if (!m_conn.m_replyContext.initialized) init();
		while (hasNext) next!(ubyte[])();
	}

	// is this necessary?
	private ubyte[] readBulk(string sizeLn)
	{
		assert(m_conn !is null);
		if (sizeLn.startsWith("$-1")) return null;
		auto size = to!size_t(sizeLn[1 .. $]);
		auto data = new ubyte[size];
		m_conn.conn.read(data);
		m_conn.conn.readLine();
		return data;
	}

	private @property void lockedConnection(ref LockedConnection!RedisConnection conn)
	{
		assert(m_conn !is null);
		m_lockedConnection = conn;
	}

	private void init()
	{
		assert(m_conn !is null);
		auto ctx = &m_conn.m_replyContext;
		ctx.initialized = true;

		auto ln = cast(string)m_conn.conn.readLine();
		
		switch (ln[0]) {
			default: throw new Exception(format("Unknown reply type: %s", ln[0]));
			case '+': ctx.data = cast(ubyte[])ln[1 .. $]; break;
			case '-': throw new Exception(ln[1 .. $]);
			case ':': ctx.data = cast(ubyte[])ln[1 .. $]; break;
			case '$': ctx.data = readBulk(ln); break;
			case '*':
				if (ln.startsWith("*-1")) {
					ctx.length = 0;
				} else {
					ctx.multi = true;
					ctx.length = to!long(ln[ 1 .. $ ]);
				}
				break;
		}
	}
}

class RedisProtocolException : Exception {
	this(string message, string file = __FILE__, size_t line = __LINE__, Exception next = null)
	{
		super(message, file, line, next);
	}
}

private struct RedisReplyContext {
	long refCount = 0;
	ubyte[] data;
	long length = 1;
	long index = 0;
	bool multi = false;
	bool initialized = false;
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

	private static long countArgs(ARGS...)(ARGS args)
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

	private static void writeArgs(R, ARGS...)(R dst, ARGS args)
		if (isOutputRange!(R, char))
	{
		foreach (i, A; ARGS) {
			static if (is(A == bool)) {
				writeArgs(dst, args[i] ? "1" : "0");
			} else static if (is(A : long) || is(A : real) || is(A == string)) {
				auto alen = formattedLength(args[i]);
				dst.formattedWrite("$%d\r\n%s\r\n", alen, args[i]);
			} else static if (is(A : const(ubyte[])) || is(A : const(char[]))) {
				dst.formattedWrite("$%s\r\n", args[i].length);
				dst.put(args[i]);
				dst.put("\r\n");
			} else static if (isArray!A) {
				foreach (arg; args[i])
					writeArgs(dst, arg);
			} else static assert(false, "Unsupported Redis argument type: " ~ T.stringof);
		}
	}

	unittest {
		import std.array : appender;
		auto dst = appender!string;
		writeArgs(dst, false, true, ["2", "3"], "4", 5.0);
		assert(dst.data == "$1\r\n0\r\n$1\r\n1\r\n$1\r\n2\r\n$1\r\n3\r\n$1\r\n4\r\n$1\r\n5\r\n");
	}

	private static long formattedLength(ARG)(ARG arg)
	{
		static if (is(ARG == string)) return arg.length;
		else {
			long length;
			auto rangeCnt = RangeCounter(&length);
			rangeCnt.formattedWrite("%s", arg);
			return length;
		}
	}
}

private struct RangeCounter {
	import std.utf;
	long* length;

	this(long* _captureLength) {
		length = _captureLength;
	}

	void put(dchar ch) { *length += codeLength!char(ch); }
	void put(string str) { *length += str.length; }
}

private void _request_void(ARGS...)(RedisConnection conn, string command, ARGS args)
{
	if (!conn.conn || !conn.conn.connected) {
		try conn.conn = connectTCP(conn.m_host, conn.m_port);
		catch (Exception e) {
			throw new Exception(format("Failed to connect to Redis server at %s:%s.", conn.m_host, conn.m_port), __FILE__, __LINE__, e);
		}
	}
	
	auto nargs = conn.countArgs(args);
	conn.conn.formattedWrite("*%d\r\n$%d\r\n%s\r\n", nargs + 1, command.length, command);
	conn.writeArgs(conn.conn, args);
}

private RedisReply _request_reply(ARGS...)(RedisConnection conn, string command, ARGS args)
{
	if (!conn.conn || !conn.conn.connected) {
		try conn.conn = connectTCP(conn.m_host, conn.m_port);
		catch (Exception e) {
			throw new Exception(format("Failed to connect to Redis server at %s:%s.", conn.m_host, conn.m_port), __FILE__, __LINE__, e);
		}
	}

	auto nargs = conn.countArgs(args);
	conn.conn.formattedWrite("*%d\r\n$%d\r\n%s\r\n", nargs + 1, command.length, command);
	conn.writeArgs(conn.conn, args);

	return RedisReply(conn);
}

private T _request(T, ARGS...)(LockedConnection!RedisConnection conn, string command, ARGS args)
{ 
	RedisReply reply = _request_reply(conn, command, args);
	reply.lockedConnection = conn;
	static if (is(T == RedisReply)) return reply;
	else static if (is(T == bool)) return reply.next!string[0] == '1';
	else static if (is(T == int) || is(T == long) || is(T == size_t) || is(T == double)) {
		auto result = reply.next!string();
		return parse!T(result);
	}
	else static if (is(T == string)) return reply.next!string();
	else static assert(is(T == void), "Unsupported Redis reply type: " ~ T.stringof);
}
