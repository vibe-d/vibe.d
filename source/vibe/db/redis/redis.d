module vibe.db.redis.redis;

public import vibe.core.net;

import vibe.core.log;
import vibe.stream.operations;
import std.string;
import std.conv;
import std.exception;
import std.traits;
import std.utf;

final class RedisReply {

	private {
		private TcpConnection m_conn;
		ubyte[] m_data;
		size_t m_length;
		size_t m_index;
		bool m_multi;
	}
	
	this(TcpConnection conn) {
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
				m_length = parse!size_t(ln[ 1 .. $ ]);
				break;
			default:
				assert(false, "Unknown reply type");
		}
	}

	private ubyte[] readBulk( string sizeLn )	
	{
		if ( sizeLn.startsWith("$-1") ) return null;
		auto size = parse!size_t( sizeLn[1 .. $] );
		auto data = new ubyte[size];
		m_conn.read(data);
		m_conn.readLine();
		return data;
	}

	@property bool hasNext() { return  m_index < m_length; }

	T next(T : E[], E)() {
		assert( hasNext, "end of reply" );
		m_index++;
		ubyte[] ret;
		if( m_multi ) {
			auto ln = cast(string)m_conn.readLine();
			ret = readBulk(ln);
		} else {
			ret = m_data;
		}
		static if( isSomeString!T ) validate(cast(T)ret);
		enforce(ret.length % E.sizeof == 0, "bulk size must be multiple of element type size");
		return cast(T)ret;
	}
}

final class RedisClient {
	
	private {
		string m_host;
		ushort m_port;
		TcpConnection m_conn;
	}

	this() {}

	void connect(string host = "127.0.0.1", ushort port = 6379) {
		m_host = host;
		m_port = port;
	}

	private {
		ubyte[][] argsToUbyte(ARGS...)(ARGS args) {
		    static assert(ARGS.length % 2 == 0 && ARGS.length >= 2, "Arguments to mset must be pairs of key/value");
		    foreach( i, T; ARGS ){
		        static assert(i % 2 != 0 || is(T == string), "Keys must be strings.");
		        static assert(i % 2 != 1 || isArray!T, "Values must be arrays.");
		    }
		    ubyte[][] ret;
		    foreach( i, arg; args) ret ~= cast(ubyte[])arg;
		    return ret;
		}
	}
	size_t del(string[] keys...) {
		return request!size_t("DEL", cast(ubyte[][])keys);
	}

	bool exists(string key) {
		return request!bool("EXISTS", cast(ubyte[])key);
	}

	bool expire(string key, size_t seconds) {
		return request!bool("EXPIRE", cast(ubyte[])key, cast(ubyte[])to!string(seconds));
	}

	bool expireAt(string key, long timestamp) {
		return request!bool("EXPIREAT", cast(ubyte[])key, cast(ubyte[])to!string(timestamp));
	}

	RedisReply keys(string pattern) {
		return request("KEYS", cast(ubyte[])pattern);
	}

	bool move(string key, string db) {
		return request!bool("MOVE", cast(ubyte[])key, cast(ubyte[])db);
	}

	bool persists(string key) {
		return request!bool("PERSISTS", cast(ubyte[])key);
	}

	//TODO: object

	string randomKey() {
		return request("RANDOMKEY").next!string();
	}

	void rename(string key, string newkey) {
		request("RENAME", cast(ubyte[])key, cast(ubyte[])newkey);
	}

	bool renameNX(string key, string newkey) {
		return request!bool("RENAMENX", cast(ubyte[])key, cast(ubyte[])newkey);
	}

	//TODO sort

	long ttl(string key) {
		return request!long("TTL", cast(ubyte[])key);
	}

	string type(string key) {
		return request!string("TYPE", cast(ubyte[])key);
	}

	//TODO eval

	/*
		String Commands
	*/

	size_t append(T : E[], E)(string key, T suffix) {
		return request!size_t("APPEND", cast(ubyte[])key, cast(ubyte[])suffix);
	}

	int decr(string key, int value = 1) {
		return value == 1 ? request!int("DECR") : request!int("DECRBY", cast(ubyte[])to!string(value));
	}

	T get(T : E[], E)(string key) {
		return request("GET", cast(ubyte[])key).next!T();
	}

	bool getBit(string key, size_t offset) {
		return request!bool("GETBIT", cast(ubyte[])key, cast(ubyte[])to!string(offset));
	}

	T getRange(T : E[], E)(string key, size_t start, size_t end) {
		return request("GETRANGE", cast(ubyte[])to!string(start), cast(ubyte[])to!string(end)).next!T();
	}

	T getSet(T : E[], E)(string key, T value) {
		return request("GET", cast(ubyte[])key, cast(ubyte[])value).next!T();
	}

	int incr(string key, int value = 1) {
		return value == 1 ? request!int("INCR") : request!int("INCRBY", cast(ubyte[])to!string(value));
	}

	RedisReply mget(string[] keys) {
		return request("MGET", cast(ubyte[][])keys);
	}

	void mset(ARGS...)(ARGS args) {
	    request("MSET", argsToUbyte!ARGS(args));
	}
	
	bool msetNX(ARGS...)(ARGS args) {
	    return request!bool("MSETEX", argsToUbyte!ARGS(args));
	}

	void set(T : E[], E)(string key, T value) {
		request("SET", cast(ubyte[])key, cast(ubyte[])value);
	}

	bool setBit(string key, size_t offset, bool value) {
		return request!bool("SETBIT", cast(ubyte[])key, cast(ubyte[])to!string(offset), value ? ['1'] : ['0']);
	}

	void setEX(T : E[], E)(string key, size_t seconds, T value) {
		ubyte[] val = cast(ubyte[])value;
		request("SETEX", cast(ubyte[])key, cast(ubyte[])to!string(seconds), cast(ubyte[])value);
	}

	bool setNX(T : E[], E)(string key, T value) {
		return request!bool("SETNX", cast(ubyte[])key, cast(ubyte[])value);
	}

	size_t setRange(T : E[], E)(string key, size_t offset, T value) {
		return request!size_t("SETRANGE", cast(ubyte[])key, cast(ubyte[])to!string(offset), cast(ubyte[])value);
	}

	size_t strlen(string key) {
		return request!size_t("STRLEN", cast(ubyte[])key);	
	}

	/*
		Hashes
	*/

	size_t hdel(string key, string[] fields...) {
		ubyte[][] args = [cast(ubyte[])key] ~ cast(ubyte[][])fields;
		return request!size_t("HDEL", args);
	}

	bool hexists(string key, string field) {
		return request!bool("HEXISTS", cast(ubyte[])key, cast(ubyte[])field);
	}

	T hget(T : E[], E)(string key, string field) {
		return request("HGET", cast(ubyte[])key, cast(ubyte[])field).next!T();
	}

	RedisReply hgetAll(string key) {
		return request("HGETALL", cast(ubyte[])key);
	}

	int hincr(string key, string field, int value=1) {
		return request!int("HINCRBY", cast(ubyte[])key, cast(ubyte[])field, cast(ubyte[])to!string(value));
	}

	RedisReply hkeys(string key) {
		return request("HKEYS", cast(ubyte[])key);
	}

	size_t hlen(string key) {
		return request!size_t("HLEN", cast(ubyte[])key);
	}

	RedisReply hmget(string key, string[] fields...) {
		ubyte[][] args = cast(ubyte[])key ~ cast(ubyte[][])fields;
		return request("HMGET", args);
	}

	void hmset(ARGS...)(string key, ARGS args) {
		ubyte[][] list = cast(ubyte[])key ~ argsToUbyte!ARGS(args);
	    request("HMSET", list);
	}

	bool hmsetNX(ARGS...)(string key, ARGS args) {
		ubyte[][] list = cast(ubyte[])key ~ argsToUbyte!ARGS(args);
		return request!bool("HMSET", list);
	}

	RedisReply hvals(string key) {
		return request("HVALS", cast(ubyte[])key);
	}

	T lindex(T : E[], E)(string key, size_t index) {
		return request("LINDEX", cast(ubyte[])key, cast(ubyte[])to!string(index)).next!T();
	}

	size_t linsertBefore(T1, T2)(string key, T1 pivot, T2 value) {
		return request!size_t("LINSERT", cast(ubyte[])key, cast(ubyte[])"BEFORE", cast(ubyte[])pivot, cast(ubyte[])value);
	}

	size_t linsertAfter(T1, T2)(string key, T1 pivot, T2 value) {
		return request!size_t("LINSERT", cast(ubyte[])key, cast(ubyte[])"AFTER", cast(ubyte[])pivot, cast(ubyte[])value);
	}

	size_t llen(string key) {
		return request!size_t("LLEN", cast(ubyte[])key);
	}

	T lpop(T : E[], E)(string key) {
		return request("LPOP", cast(ubyte[])key).next!T();
	}

	size_t lpush(ARGS...)(string key, ARGS args) {
		ubyte[][] list = cast(ubyte[])key ~ argsToUbyte!ARGS(args);
		return request!size_t("LPUSH", list);
	}

	size_t lpushX(ARGS...)(string key, T value) {
		return request!size_t("LPUSH", cast(ubyte[])key, cast(ubyte[])value);
	}

	RedisReply lrange(string key, size_t start, size_t stop) {
		return request("LRANGE",  cast(ubyte[])key, cast(ubyte[])to!string(start), cast(ubyte[])to!string(stop));
	}

	size_t lrem(T : E[], E)(string key, size_t count, T value) {
		return request!size_t("LREM", cast(ubyte[])to!string(count), cast(ubyte[])value);
	}

	void lset(T : E[], E)(string key, size_t index, T value) {
		request("LSET", cast(ubyte[])key, cast(ubyte[])to!string(index), cast(ubyte[])value);
	}
	
	void ltrim(string key, size_t start, size_t stop) {
		request("LTRIM",  cast(ubyte[])key, cast(ubyte[])to!string(start), cast(ubyte[])to!string(stop));
	}

	T rpop(T : E[], E)(string key) {
		return request("RPOP", cast(ubyte[])key).next!T();
	}

	T lpop(T : E[], E)(string key) {
		return request("LPOP", cast(ubyte[])key).next!T();
	}
	
	T rpoplpush(T : E[], E)(string key, string destination) {
		return request("RPOPLPUSH", cast(ubyte[])key, cast(ubyte[])destination).next!T();
	}

	/*
		Sets
	*/

	size_t sadd(ARGS...)(string key, ARGS args) {
		ubyte[][] list = cast(ubyte[])key ~ argsToUbyte!ARGS(args);
		return request!size_t("SADD", list);
	}

	size_t scard(string key) {
		return request!size_t("SCARD", cast(ubyte[])key);
	}

	RedisReply sdiff(string[] keys...) {
		return request("SDIFF", cast(ubyte[][])keys);
	}

	size_t sdiffStore(string destination, string[] keys...) {
		ubyte[][] args = cast(ubyte[])destination ~ cast(ubyte[][])keys;
		return request!size_t("SDIFFSTORE", args);
	}

	RedisReply sinter(string[] keys) {
		return request("SINTER", cast(ubyte[][])keys);
	}

	size_t sinterStore(string destination, string[] keys...) {
		ubyte[][] args = cast(ubyte[])destination ~ cast(ubyte[][])keys;
		return request!size_t("SINTERSTORE", args);
	}

	bool sisMember(T : E[], E)(string key, T member) {
		return request!bool("SISMEMBER", cast(ubyte[])key, cast(ubyte[])member);
	}

	bool smembers(string key) {
		return request!bool("SMEMBERS", cast(ubyte[])key);
	}

	bool smove(T : E[], E)(string source, string destination, T member) {
		return request!bool("SMOVE", cast(ubyte[])source, cast(ubyte[])destination, cast(ubyte[])member);
	}

	T spop(T : E[], E)(string key) {
		return request("SPOP", cast(ubyte[])key ).next!T();
	}

	T srandMember(T : E[], E)(string key) {
		return request("SRANDMEMBER", cast(ubyte[])key ).next!T();
	}

	size_t srem(ARGS...)(string key, ARGS args) {
		ubyte[][] list = cast(ubyte[])key ~ argsToUbyte!ARGS(args);
		return request!size_t("SREM", list);
	}

	RedisReply sunion(string[] keys...) {
		return request("SUNION", cast(ubyte[][])keys);
	}

	size_t sunionStore(string[] keys...) {
		return request!size_t("SUNIONSTORE", cast(ubyte[][])keys);
	}

	/*
		Sorted Sets
	*/

	size_t zadd(ARGS...)(string key, ARGS args) {
		ubyte[][] list = cast(ubyte[])key ~ argsToUbyte!ARGS(args);
		return request!size_t("SADD", list);
	}

	size_t Zcard(string key) {
		return request!size_t("ZCARD", cast(ubyte[])key);
	}

	size_t zcount(string key, double min, double max) {
		return request!size_t("SCARD", cast(ubyte[])key);
	}

	double zincrby(string key, double value, string member) {
		return request!double("ZINCRBY", cast(ubyte[])to!string(value), cast(ubyte[])member);
	}

	//TODO: zinterstore

	RedisReply zrange(string key, size_t start, size_t end, bool withScores=false) {
		ubyte[][] args = [cast(ubyte[])key, cast(ubyte[])to!string(start), cast(ubyte[])to!string(end)];
		if (withScores) args ~= cast(ubyte[])"WITHSCORES";
		return request("ZRANGE", args);
	}

	RedisReply zrangeByScore(string key, size_t start, size_t end, bool withScores=false) {
		ubyte[][] args = [cast(ubyte[])key, cast(ubyte[])to!string(start), cast(ubyte[])to!string(end)];
		if (withScores) args ~= cast(ubyte[])"WITHSCORES";
		return request("ZRANGEBYSCORE", args);
	}

	RedisReply zrangeByScore(string key, size_t start, size_t end, size_t offset, size_t count, bool withScores=false) {
		ubyte[][] args = [cast(ubyte[])key, cast(ubyte[])to!string(start), cast(ubyte[])to!string(end)];
		if (withScores) args ~= cast(ubyte[])"WITHSCORES";
                args ~= cast(ubyte[])"LIMIT" ~ cast(ubyte[])to!string(offset) ~ cast(ubyte[])to!string(count);
		return request("ZRANGEBYSCORE", args);
	}

	int zrank(string key, string member) {
		auto str = request!string("ZRANK", cast(ubyte[]) key, cast(ubyte[]) member);
		return str ? parse!int(str) : -1;
	}
	size_t zrem(string key, string[] members...) {
		ubyte[][] args = cast(ubyte[])key ~ cast(ubyte[][])members;
		return request!size_t("ZREM", args);
	}

	size_t zremRangeByRank(string key, int start, int stop) {
		return request!size_t("ZREMRANGEBYRANK", cast(ubyte[])key, cast(ubyte[])to!string(start), cast(ubyte[])to!string(stop));
	}

	size_t zremRangeByScore(string key, double min, double max) {
		return request!size_t("ZREMRANGEBYSCORE", cast(ubyte[])key, cast(ubyte[])to!string(min), cast(ubyte[])to!string(max));
	}	

	RedisReply zrevRange(string key, size_t start, size_t end, bool withScores=false) {
		ubyte[][] args = [cast(ubyte[])key, cast(ubyte[])to!string(start), cast(ubyte[])to!string(end)];
		if (withScores) args ~= cast(ubyte[])"WITHSCORES";
		return request("ZREVRANGE", args);
	}

	RedisReply zrevRangeByScore(string key, double min, double max, bool withScores=false) {
		ubyte[][] args = [cast(ubyte[])key, cast(ubyte[])to!string(min), cast(ubyte[])to!string(max)];
		if (withScores) args ~= cast(ubyte[])"WITHSCORES";
		return request("ZREVRANGEBYSCORE", args);
	}

	int zrevRank(string key, string member) {
		auto str = request!string("ZREVRANK", cast(ubyte[]) key, cast(ubyte[]) member);
		return str ? parse!int(str) : -1;
	}

	RedisReply zscore(string key, string member) {
		return request("ZSCORE", cast(ubyte[]) key, cast(ubyte[]) member);
	}

	//TODO: zunionstore

	/*
		TODO: Pub / Sub
	*/

	/*
		TODO: Transactions
	*/

	/*
		Connection
	*/
	void auth(string password) {
		request("AUTH", cast(ubyte[])password);
	}

	T echo(T : E[], E)(T data) {
		return request("AUTH", cast(ubyte[])data).next!T();
	}

	void ping() {
		request("PING");
	}

	void quit() {
		request("QUIT");
	}
	void select(size_t db_index) {
		request("SELECT", cast(ubyte[])to!string(db_index));
	}

	/*
		Server
	*/

	//TODO: BGREWRITEAOF
	//TODO: BGSAVE

	T getConfig(T : E[], E)(string parameter) {
		return request("GET CONFIG", cast(ubyte[])parameter).next!T();
	}

	void setConfig(T : E[], E)(string parameter, T value) {
		request("SET CONFIG", cast(ubyte[])parameter, cast(ubyte[])value);
	}

	void configResetStat() {
		request("CONFIG RESETSTAT");
	}

	size_t dbSize() {
		return request!size_t("DBSIZE");
	}

	//TOOD: Debug Object
	//TODO: Debug Segfault

	void flushAll() {
		request("FLUSHALL");
	}

	void flushDB() {
		request("FLUSHDB");
	}

	string info() {
		return request("INFO").next!string();
	}

	long lastSave() {
		return request!long("LASTSAVE");
	}

	//TODO monitor

	void save() {
		request("SAVE");
	}

	void shutdown() {
		request("SHUTDOWN");
	}

	void slaveOf(string host, ushort port) {
		request("SLAVEOF", cast(ubyte[])host, cast(ubyte[])to!string(port));
	}

	//TODO slowlog

	//TODO sync

	T request(T=RedisReply)(string command, in ubyte[][] args...) {
		if( !m_conn /*|| !m_conn.connected*/ ){
			m_conn = connectTcp(m_host, m_port);
		}
		m_conn.write(format("*%d\r\n$%d\r\n%s\r\n", args.length + 1, command.length, command));
		foreach( arg; args ) {
			m_conn.write(format("$%d\r\n", arg.length));
			m_conn.write(arg);
			m_conn.write("\r\n");
		}
		auto reply = new RedisReply(m_conn);
		static if( is(T == bool) ) {
			return reply.next!(ubyte[])()[0] == '1';
		} else static if ( is(T == int) || is(T == long) || is(T == size_t) || is(T == double) ) {
			auto str = reply.next!string();
			return parse!T(str);
		} else static if ( is(T == string) ) {
			return cast(string)reply.next!T();
		} else return reply;
	}
}