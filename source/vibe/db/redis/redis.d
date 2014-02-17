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
		long m_selectedDB;
		string m_version;
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
	int decr(string key, int value = 1) { return value == 1 ? request!int("DECR", key) : request!int("DECRBY", key, value); }
	T get(T : E[], E)(string key) { return request!T("GET", key); }
	bool getBit(string key, long offset) { return request!bool("GETBIT", key, offset); }
	T getRange(T : E[], E)(string key, long start, long end) { return request!T("GETRANGE", start, end); }
	T getSet(T : E[], E)(string key, T value) { return request!T("GET", key, value); }
	int incr(string key, int value = 1) { return value == 1 ? request!int("INCR", key) : request!int("INCRBY", key, value); }
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
	int hincr(string key, string field, int value=1) { return request!int("HINCRBY", key, field, value); }
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

	long zadd(ARGS...)(string key, ARGS args) { return request!long("SADD", key, args); }
	long Zcard(string key) { return request!long("ZCARD", key); }
	long zcount(string key, double min, double max) { return request!long("ZCOUNT", key, min, max); }
	double zincrby(string key, double value, string member) { return request!double("ZINCRBY", value, member); }
	//TODO: zinterstore
	RedisReply zrange(string key, long start, long end, bool withScores=false) {
		string[] args = [key, to!string(start), to!string(end)];
		if (withScores) args ~= "WITHSCORES";
		return request!RedisReply("ZRANGE", args);
	}

	RedisReply zrangeByScore(string key, long start, long end, bool withScores=false) {
		string[] args = [key, to!string(start), to!string(end)];
		if (withScores) args ~= "WITHSCORES";
		return request!RedisReply("ZRANGEBYSCORE", args);
	}

	RedisReply zrangeByScore(string key, long start, long end, long offset, long count, bool withScores=false) {
		string[] args = [key, to!string(start), to!string(end)];
		if (withScores) args ~= "WITHSCORES";
		args ~= ["LIMIT", to!string(offset), to!string(count)];
		return request!RedisReply("ZRANGEBYSCORE", args);
	}

	int zrank(string key, string member) {
		auto str = request!string("ZRANK", key, member);
		return str ? parse!int(str) : -1;
	}
	long zrem(string key, string[] members...) { return request!long("ZREM", key, members); }
	long zremRangeByRank(string key, int start, int stop) { return request!long("ZREMRANGEBYRANK", key, start, stop); }
	long zremRangeByScore(string key, double min, double max) { return request!long("ZREMRANGEBYSCORE", key, min, max);}

	RedisReply zrevRange(string key, long start, long end, bool withScores=false) {
		string[] args = [key, to!string(start), to!string(end)];
		if (withScores) args ~= "WITHSCORES";
		return request!RedisReply("ZREVRANGE", args);
	}

	RedisReply zrevRangeByScore(string key, double min, double max, bool withScores=false) {
		string[] args = [key, to!string(min), to!string(max)];
		if (withScores) args ~= "WITHSCORES";
		return request!RedisReply("ZREVRANGEBYSCORE", args);
	}

	int zrevRank(string key, string member) {
		auto str = request!string("ZREVRANK", key, member);
		return str ? parse!int(str) : -1;
	}

	RedisReply zscore(string key, string member) { return request!RedisReply("ZSCORE", key, member); }
	//TODO: zunionstore

	/*
		Pub / Sub
	*/
	int publish(string channel, string message) {
		auto str = request!string("PUBLISH", channel, message);
		return str ? parse!int(str) : -1;
	}

	RedisReply pubsub(string subcommand, string[] args...) {
		return request!RedisReply("PUBSUB", subcommand, args);
	}

	/*
		TODO: Transactions
	*/

	/*
		Connection
	*/
	void auth(string password) { m_authPassword = password; }
	T echo(T : E[], E)(T data) { return request!T("ECHO", data); }
	void ping() { request("PING"); }
	void quit() { request("QUIT"); }
	void select(long db_index) { m_selectedDB = db_index; }

	/*
		Server
	*/

	//TODO: BGREWRITEAOF
	//TODO: BGSAVE

	T getConfig(T : E[], E)(string parameter) { return request!T("GET CONFIG", parameter); }
	void setConfig(T : E[], E)(string parameter, T value) { request("SET CONFIG", parameter, value); }
	void configResetStat() { request("CONFIG RESETSTAT"); }
	long dbSize() { return request!long("DBSIZE"); }
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

	/// Returns Redis version
	@property string redisVersion() {
		return m_version;
	}

	T request(T = void, ARGS...)(string command, ARGS args)
	{
		auto conn = m_connections.lockConnection();
		conn.setAuth(m_authPassword);
		conn.setDB(m_selectedDB);
		return _request!T(conn, command, args);
	}
}

/**
	A redis subscription listener
*/
final class RedisSubscriber {
	private LockedConnection!RedisConnection m_conn;

	this(RedisClient client) {
		m_conn = client.m_connections.lockConnection();
		m_conn.setAuth(client.m_authPassword);
		m_conn.setDB(client.m_selectedDB);
	}

	void subscribe(string[] args...) {
		_request_simple(m_conn, false, "SUBSCRIBE", args);
	}

	void unsubscribe(string[] args...) {
		_request_simple(m_conn, false, "UNSUBSCRIBE", args);
	}

	void psubscribe(string[] args...) {
		_request_simple(m_conn, false, "PSUBSCRIBE", args);
	}

	void punsubscribe(string[] args...) {
		_request_simple(m_conn, false, "PUNSUBSCRIBE", args);
	}
	
	// Same as listen, but blocking
	void blisten(void delegate(string, string) callback) {
		while(true) {
			auto reply = this.m_conn.listen();
			auto cmd = reply.next!string;
			if(cmd == "message") {
				auto channel = reply.next!string;
				auto message = reply.next!string;
				callback(channel, message);
			} else if(cmd == "unsubscribe") {
				// keep track to how many channels we are subscribed and exit if none anymore
				reply.next!(ubyte[])(); // channel from which we get unsubsccribed
				reply = this.m_conn.listen(); // redis sends a *3 here despite what's in the docs...
				auto str = reply.next!string;
				int count = str ? parse!int(str) : -1;
				if(count == 0) {
					return;
				}
			}
		}
	}

	// Waits for messages and calls the callback with the channel and the message as arguments
	Task listen(void delegate(string, string) callback) {
		return runTask({
			blisten(callback);
		});
	}
}


final class RedisReply {
	private {
		TCPConnection m_conn;
		LockedConnection!RedisConnection m_lockedConnection;
		ubyte[] m_data;
		long m_length;
		long m_index;
		bool m_multi;
	}

	this(TCPConnection conn)
	{
		m_conn = conn;
		m_index = 0;
		m_length = 1;
		m_multi = false;

		auto ln = cast(string)m_conn.readLine();

		switch(ln[0]) {
			case '+':
				m_data = cast(ubyte[])ln[ 1 .. $ ];
				break;
			case '-':
				throw new Exception(ln[ 1 .. $ ]);
			case ':':
				m_data = cast(ubyte[])ln[ 1 .. $ ];
				break;
			case '$':
				m_data = readBulk(ln);
				break;
			case '*':
				if( ln.startsWith("*-1") ) {
					m_length = 0;
					return;
				}
				m_multi = true;
				m_length = to!long(ln[ 1 .. $ ]);
				break;
			default:
				assert(false, "Unknown reply type");
		}
	}

	@property bool hasNext() const { return  m_index < m_length; }

	T next(T : E[], E)()
	{
		assert( hasNext, "end of reply" );
		m_index++;
		ubyte[] ret;
		if (m_multi) {
			auto ln = cast(string)m_conn.readLine();
			ret = readBulk(ln);
		} else {
			ret = m_data;
		}
		if (m_index >= m_length && m_lockedConnection != null) m_lockedConnection.clear();
		static if (isSomeString!T) validate(cast(T)ret);
		enforce(ret.length % E.sizeof == 0, "bulk size must be multiple of element type size");
		return cast(T)ret;
	}

	// drop the whole
	void drop()
	{
		while (hasNext) next!(ubyte[])();
	}

	private ubyte[] readBulk( string sizeLn )
	{
		if (sizeLn.startsWith("$-1")) return null;
		auto size = to!long( sizeLn[1 .. $] );
		auto data = new ubyte[size];
		m_conn.read(data);
		m_conn.readLine();
		return data;
	}
}


private final class RedisConnection {
	private {
		string m_host;
		ushort m_port;
		TCPConnection m_conn;
		string m_password;
		long m_selectedDB;
	}

	this(string host, ushort port)
	{
		m_host = host;
		m_port = port;
	}

	@property{
		TCPConnection conn() { return m_conn; }
		void conn(TCPConnection conn) { m_conn = conn; }
	}

	void setAuth(string password)
	{
		if (m_password == password) return;
		_request_simple(this, true, "AUTH", password).drop();
		m_password = password;
	}

	void setDB(long index)
	{
		if (index == m_selectedDB) return;
		_request_simple(this, true, "SELECT", index).drop();
		m_selectedDB = index;
	}

	RedisReply listen() {
		if( !m_conn || !m_conn.connected ){
			throw new Exception("Cannot listen on connection without subscribing first.", __FILE__, __LINE__);
		}
		return new RedisReply(m_conn);
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

private RedisReply _request_simple(ARGS...)(RedisConnection conn, bool read, string command, ARGS args)
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

	if (!read) {
		return null;
	} else {
		return new RedisReply(conn.conn);
	}
}

private T _request(T, ARGS...)(LockedConnection!RedisConnection conn, string command, ARGS args)
{
	auto reply = _request_simple(conn, true, command, args);

	static if (is(T == RedisReply)) {
		reply.m_lockedConnection = conn;
		return reply;
	} else {
		scope (exit) reply.drop();

		static if (is(T == bool)) {
			return reply.next!string[0] == '1';
		} else static if ( is(T == int) || is(T == long) || is(T == size_t) || is(T == double) ) {
			auto str = reply.next!string();
			return parse!T(str);
		} else static if (is(T == string)) {
			return reply.next!string();
		} else static if (is(T == void)) {
		} else static assert(false, "Unsupported Redis reply type: " ~ T.stringof);
	}
}

