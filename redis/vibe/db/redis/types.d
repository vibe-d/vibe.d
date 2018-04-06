/**
	Convenience wrappers types for accessing Redis keys.

	Note that the API is still subject to change!

	Copyright: © 2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.redis.types;

import vibe.db.redis.redis;

import std.conv : to;
import std.datetime : SysTime;
import std.typecons : Nullable;
import core.time : Duration, msecs, seconds;


/** Returns a handle to a string type value.
*/
RedisString!T getAsString(T = string)(RedisDatabase db, string key)
{
	return RedisString!T(db, key);
}

///
unittest {
	void test()
	{
		auto db = connectRedis("127.0.0.1").getDatabase(0);
		auto str = db.getAsString("some_string");
		str = "test";
	}
}



/** Returns a handle to a set type value.
*/
RedisSet!T getAsSet(T = string)(RedisDatabase db, string key)
{
	return RedisSet!T(db, key);
}

///
unittest {
	void test()
	{
		auto db = connectRedis("127.0.0.1").getDatabase(0);
		auto set = db.getAsSet("some_set");
		set.insert("test");
	}
}


/** Returns a handle to a set type value.
*/
RedisZSet!T getAsZSet(T = string)(RedisDatabase db, string key)
{
	return RedisZSet!T(db, key);
}

///
unittest {
	void test()
	{
		auto db = connectRedis("127.0.0.1").getDatabase(0);
		auto set = db.getAsZSet("some_sorted_set");
		set.insert(1, "test");
	}
}


/** Returns a handle to a hash type value.
*/
RedisHash!T getAsHash(T = string)(RedisDatabase db, string key)
{
	return RedisHash!T(db, key);
}

///
unittest {
	void test()
	{
		auto db = connectRedis("127.0.0.1").getDatabase(0);
		auto hash = db.getAsHash("some_hash");
		hash["test"] = "123";
	}
}


/** Returns a handle to a list type value.
*/
RedisList!T getAsList(T = string)(RedisDatabase db, string key)
{
	return RedisList!T(db, key);
}

///
unittest {
	void test()
	{
		auto db = connectRedis("127.0.0.1").getDatabase(0);
		auto list = db.getAsList!long("some_list");
		list.insertFront(123);
	}
}


/**
	Converts the given value to a binary/string representation suitable for
	Redis storage.

	These functions are used by the proxy types of this module to convert
	between Redis and D.

	See_also: $(D fromRedis)
*/
string toRedis(T)(T value)
{
	import std.format;
	import std.traits;
	import vibe.data.serialization;
	static if (is(T == bool)) return value ? "1": "0";
	else static if (is(T : long) || is(T : double)) return value.to!string;
	else static if (isSomeString!T) return value.to!string;
	else static if (is(T : const(ubyte)[])) return cast(string)value;
	else static if (isISOExtStringSerializable!T) return value == T.init ? null : value.toISOExtString();
	else static if (isStringSerializable!T) return value.toString();
	else static assert(false, "Unsupported type: "~T.stringof);
}
/// ditto
void toRedis(R, T)(ref R dst, T value)
{
	import std.format;
	import std.traits;
	import vibe.data.serialization;
	static if (is(T == bool)) dst.put(value ? '1' : '0');
	else static if (is(T : long)) dst.formattedWrite("%s", value);
	else static if (isSomeString!T) dst.formattedWrite("%s", value);
	else static if(is(T : const(ubyte)[])) dst.put(value);
	else static if (isISOExtStringSerializable!T) dst.put(value == T.init ? null : value.toISOExtString());
	else static if (isStringSerializable!T) dst.put(value.toString());
	else static assert(false, "Unsupported type: "~T.stringof);
}


/**
	Converts a Redis value back to its original representation.

	These functions are used by the proxy types of this module to convert
	between Redis and D.

	See_also: $(D toRedis)
*/
T fromRedis(T)(string value)
{
	import std.conv;
	import std.traits;
	import vibe.data.serialization;
	static if (is(T == bool)) return value != "0" && value != "false";
	else static if (is(T : long) || is(T : double)) return value.to!T;
	else static if (isSomeString!T) return value.to!T;
	else static if (is(T : const(ubyte)[])) return cast(T)value;
	else static if (isISOExtStringSerializable!T) return value.length ? T.fromISOExtString(value) : T.init;
	else static if (isStringSerializable!T) return T.fromString(value);
	else static assert(false, "Unsupported type: "~T.stringof);
}


/** The type of a Redis key.
*/
enum RedisType {
	none,    /// Non-existent key
	string,  /// String/binary value
	list,    /// Linked list
	set,     /// Unsorted set
	zset,    /// Sorted set
	hash     /// Unsorted map
}


/** Represents a generic Redis value.
*/
struct RedisValue {
	private {
		RedisDatabase m_db;
		string m_key;
	}

	this(RedisDatabase db, string key) { m_db = db; m_key = key; }

	/** The database in which the key is stored.
	*/
	@property inout(RedisDatabase) database() inout { return m_db; }

	/** Name of the corresponding key.
	*/
	@property string key() const { return m_key; }

	/** Remaining time-to-live.

		Returns:
			The time until the key expires, if applicable. Returns
			$(D Duration.max) otherwise.

		See_also: $(LINK2 http://redis.io/commands/pttl, PTTL)
	*/
	@property Duration ttl()
	{
		auto ret = m_db.pttl(m_key);
		return ret >= 0 ? ret.msecs : Duration.max;
	}

	/** The data type of the referenced value.

		Queries the actual type of the value that is referenced by this
		key.

		See_also: $(LINK2 http://redis.io/commands/type, TYPE)
	*/
	@property RedisType type() { import std.conv; return m_db.type(m_key).to!RedisType; }

	/** Checks if the referenced key exists.

		See_also: $(LINK2 http://redis.io/commands/exists, EXISTS)
	*/
	@property bool exists() { return m_db.exists(m_key); }

	/** Removes the referenced key.

		Returns: $(D true) $(I iff) the key was successfully removed.

		See_also: $(LINK2 http://redis.io/commands/del, DEL)
	*/
	bool remove() { return m_db.del(m_key) > 0; }

	/** Sets the key for expiration after the given timeout.

		Note that Redis handles timeouts in second resolution, so that the
		timeout must be at least one second.

		Returns: $(D true) $(I iff) the expiration time was successfully set.

		See_also: $(LINK2 http://redis.io/commands/expire, EXPIRE)
	*/
	bool expire(Duration expire_time) { assert(expire_time >= 1.seconds); return m_db.expire(m_key, expire_time.total!"seconds"); }

	/** Sets the key for expiration at the given point in time.

		Note that Redis handles timeouts in second resolution, so that any
		fractional seconds of the given $(D expire_time) will be truncated.

		Returns: $(D true) $(I iff) the expiration time was successfully set.

		See_also: $(LINK2 http://redis.io/commands/expireat, EXPIREAT)
	*/
	bool expireAt(SysTime expire_time) { return m_db.expireAt(m_key, expire_time.toUnixTime()); }

	/** Removes any existing expiration time for the key.

		Returns:
			$(D true) $(I iff) the key exists and an existing timeout was removed.

		See_also: $(LINK2 http://redis.io/commands/persist, PERSIST)
	*/
	bool persist() { return m_db.persist(m_key); }

	/** Moves this key to a different database.

		Existing keys will not be overwritten.

		Returns:
			$(D true) $(I iff) the key exists and was successfully moved to the
			destination database.

		See_also: $(LINK2 http://redis.io/commands/move, MOVE)
	*/
	bool moveTo(long dst_database) { return m_db.move(m_key, dst_database); }

	/** Renames the referenced key.

		This method will also update this instance to refer to the renamed
		key.

		See_also: $(LINK2 http://redis.io/commands/rename, RENAME), $(D renameIfNotExist)
	*/
	void rename(string new_name) { m_db.rename(m_key, new_name); m_key = new_name; }

	/** Renames the referenced key if the destination key doesn't exist.

		This method will also update this instance to refer to the renamed
		key if the rename was successful.

		Returns:
			$(D true) $(I iff) the source key exists and the destination key doesn't
			exist.

		See_also: $(LINK2 http://redis.io/commands/renamenx, RENAMENX), $(D rename)
	*/
	bool renameIfNotExist(string new_name)
	{
		if (m_db.renameNX(m_key, new_name)) {
			m_key = new_name;
			return true;
		}
		return false;
	}

	//TODO sort
}


/** Represents a Redis string value.

	In addition to the methods specific to string values, all operations of
	$(D RedisValue) are available using an $(D alias this) declaration.
*/
struct RedisString(T = string) {
	RedisValue value;
	alias value this;

	this(RedisDatabase db, string key) { value = RedisValue(db, key); }

	/** The length in bytes of the string.

		See_also: $(LINK2 http://redis.io/commands/strlen, STRLEN)
	*/
	@property long length() { return m_db.strlen(m_key); }

	T get() { return m_db.get!string(m_key).fromRedis!T; }

	T getSet(T value) { return m_db.getSet(m_key, value.toRedis).fromRedis!T; }
	bool getBit(long offset) { return m_db.getBit(m_key, offset); }
	bool setBit(long offset, bool value) { return m_db.setBit(m_key, offset, value); }
	void setExpire(T value, Duration expire_time) { assert(expire_time >= 1.seconds); m_db.setEX(m_key, expire_time.total!"seconds", value.toRedis); }
	bool setIfNotExist(T value) { return m_db.setNX(m_key, value.toRedis); }

	string getSubString(long start, long end) { return m_db.getRange!string(m_key, start, end); }
	long setSubString(long offset, string value) { return m_db.setRange(m_key, offset, value); }

	void opAssign(T value) { m_db.set(m_key, value.toRedis); }

	long opOpAssign(string OP)(string value) if (OP == "~") { return m_db.append(m_key, value); }
	long opUnary(string OP)() if (OP == "++") { return m_db.incr(m_key); }
	long opUnary(string OP)() if (OP == "--") { return m_db.decr(m_key); }
	long opOpAssign(string OP)(long value) if (OP == "+") {
		assert(value != 0);
		if (value > 0) return m_db.incr(m_key, value);
		else return m_db.decr(m_key, -value);
	}
	long opOpAssign(string OP)(long value) if (OP == "-") {
		assert(value != 0);
		if (value > 0) return m_db.incr(m_key, value);
		else return m_db.decr(m_key, -value);
	}
	long opOpAssign(string OP)(double value) if (OP == "+") { return m_db.incr(m_key, value); }
	long opOpAssign(string OP)(double value) if (OP == "-") { return m_db.incr(m_key, -value); }
}


/** Represents a Redis hash value.

	In addition to the methods specific to hash values, all operations of
	$(D RedisValue) are available using an $(D alias this) declaration.
*/
struct RedisHash(T = string) {
	RedisValue value;
	alias value this;

	this(RedisDatabase db, string key) { value = RedisValue(db, key); }

	bool remove() { return value.remove(); }
	size_t remove(scope string[] fields...) { return cast(size_t)m_db.hdel(m_key, fields); }
	bool exists(string field) { return m_db.hexists(m_key, field); }
	bool exists() { return value.exists; }

	void opIndexAssign(T value, string field) { m_db.hset(m_key, field, value.toRedis()); }
	T opIndex(string field) { return m_db.hget!string(m_key, field).fromRedis!T(); }

	T get(string field, T def_value)
	{
		import std.typecons;
		auto ret = m_db.hget!(Nullable!string)(m_key, field);
		return ret.isNull ? def_value : ret.fromRedis!T;
	}

	bool setIfNotExist(string field, T value)
	{
		return m_db.hsetNX(m_key, field, value.toRedis());
	}

	void opIndexOpAssign(string op)(T value, string field) if (op == "+") { m_db.hincr(m_key, field, value); }
	void opIndexOpAssign(string op)(T value, string field) if (op == "-") { m_db.hincr(m_key, field, -value); }

	int opApply(scope int delegate(string key, T value) del)
	{
		auto reply = m_db.hgetAll(m_key);
		while (reply.hasNext()) {
			auto key = reply.next!string();
			auto value = reply.next!string();
			if (auto ret = del(key, value.fromRedis!T))
				return ret;
		}
		return 0;
	}


	int opApply(scope int delegate(string key) del)
	{
		auto reply = m_db.hkeys(m_key);
		while (reply.hasNext()) {
			if (auto ret = del(reply.next!string()))
				return ret;
		}
		return 0;
	}

	long length() { return m_db.hlen(m_key); }

	// FIXME: support other types!
	void getMultiple(T[] dst, scope string[] fields...)
	{
		assert(dst.length == fields.length);
		auto reply = m_db.hmget(m_key, fields);
		size_t idx = 0;
		while (reply.hasNext())
			dst[idx++] = reply.next!string().fromRedis!T();
	}

	// FIXME: support other types!
	/*void setMultiple(in string[] src, scope string[] fields...)
	{
		m_db.hmset(m_key, ...);
	}*/

	//RedisReply hvals(string key) { return request!RedisReply("HVALS", key); }
}


/** Represents a Redis list value.

	In addition to the methods specific to list values, all operations of
	$(D RedisValue) are available using an $(D alias this) declaration.
*/
struct RedisList(T = string) {
	RedisValue value;
	alias value this;

	this(RedisDatabase db, string key) { value = RedisValue(db, key); }

	Dollar opDollar() { return Dollar(0); }

	T opIndex(long index)
	{
		assert(index >= 0);
		return m_db.lindex!string(m_key, index).fromRedis!T;
	}
	T opIndex(Dollar index)
	{
		assert(index.offset < 0);
		return m_db.lindex!string(m_key, index.offset).fromRedis!T;
	}
	void opIndexAssign(T value, long index)
	{
		assert(index >= 0);
		m_db.lset(m_key, index, value.toRedis);
	}
	void opIndexAssign(T value, Dollar index)
	{
		assert(index.offset < 0);
		m_db.lset(m_key, index.offset, value.toRedis);
	}
	auto opSlice(S, E)(S start, E end)
		if ((is(S : long) || is(S == Dollar)) && (is(E : long) || is(E == Dollar)))
	{
		import std.algorithm;
		long s, e;
		static if (is(S == Dollar)) {
			assert(start.offset <= 0);
			s = start.offset;
		} else {
			assert(start >= 0);
			s = start;
		}
		static if (is(E == Dollar)) {
			assert(end.offset <= 0);
			e = end.offset - 1;
		} else {
			assert(end >= 0);
			e = end - 1;
		}
		return map!(e => e.fromRedis!T)(m_db.lrange(m_key, s, e));
	}
	auto opSlice()() { return this[0 .. $]; }

	long length() { return m_db.llen(m_key); }

	long insertBefore(T pivot, T value) { return m_db.linsertBefore(m_key, pivot.toRedis, value.toRedis); }
	long insertAfter(T pivot, T value) { return m_db.linsertAfter(m_key, pivot.toRedis, value.toRedis); }

	long insertFront(T value) { return m_db.lpush(m_key, value.toRedis); }
	long insertFrontIfExists(T value) { return m_db.lpushX(m_key, value.toRedis); }
	long insertBack(T value) { return m_db.rpush(m_key, value.toRedis); }
	long insertBackIfExists(T value) { return m_db.rpushX(m_key, value.toRedis); }

	long removeAll(T value) { return m_db.lrem(m_key, 0, value.toRedis); }
	long removeFirst(T value, long count = 1) { assert(count > 0); return m_db.lrem(m_key, count, value.toRedis); }
	long removeLast(T value, long count = 1) { assert(count > 0); return m_db.lrem(m_key, -count, value.toRedis); }

	void trim(long start, long end) { m_db.ltrim(m_key, start, end); }

	T removeFront() { return m_db.lpop!string(m_key).fromRedis!T; }
	T removeBack() { return m_db.rpop!string(m_key).fromRedis!T; }
	Nullable!T removeFrontBlock(Duration max_wait = 0.seconds) {
		assert(max_wait == 0.seconds || max_wait >= 1.seconds);
		auto r = m_db.blpop!string(m_key, max_wait.total!"seconds");
		return r.isNull ? Nullable!T.init : Nullable!T(r[1].fromRedis!T);
	}

	struct Dollar {
		long offset = 0;
		Dollar opAdd(long off) { return Dollar(offset + off); }
		Dollar opSub(long off) { return Dollar(offset - off); }
	}

	int opApply(scope int delegate(T) del)
	{
		foreach (v; this[0 .. $])
			if (auto ret = del(v))
				return ret;
		return 0;
	}

	//RedisReply lrange(string key, long start, long stop) { return request!RedisReply("LRANGE",  key, start, stop); }
	//T rpoplpush(T : E[], E)(string key, string destination) { return request!T("RPOPLPUSH", key, destination); }
}


/** Represents a Redis set value.

	In addition to the methods specific to set values, all operations of
	$(D RedisValue) are available using an $(D alias this) declaration.
*/
struct RedisSet(T = string) {
	RedisValue value;
	alias value this;

	this(RedisDatabase db, string key) { value = RedisValue(db, key); }

	long insert(ARGS...)(ARGS args) { return m_db.sadd(m_key, args); }
	long remove(T value) { return m_db.srem(m_key, value.toRedis()); }
	bool remove() { return value.remove(); }
	string pop() { return m_db.spop!string(m_key); }
	long length() { return m_db.scard(m_key); }

	string getRandom() { return m_db.srandMember!string(m_key); }

	//RedisReply sdiff(string[] keys...) { return request!RedisReply("SDIFF", keys); }
	//long sdiffStore(string destination, string[] keys...) { return request!long("SDIFFSTORE", destination, keys); }
	//RedisReply sinter(string[] keys) { return request!RedisReply("SINTER", keys); }
	//long sinterStore(string destination, string[] keys...) { return request!long("SINTERSTORE", destination, keys); }
	bool contains(T value) { return m_db.sisMember(m_key, value.toRedis()); }

	int opApply(scope int delegate(T value) del)
	{
		foreach (m; m_db.smembers!string(m_key))
			if (auto ret = del(m.fromRedis!T()))
				return ret;
		return 0;
	}

	bool intersects(scope RedisSet[] sets...)
	{
		import std.algorithm;
		import std.array;
		return !value.database.sinter(value.key ~ sets.map!(s => s.key).array).empty;
	}

	auto getAll()
	{
		import std.algorithm;
		return map!(r => r.fromRedis!T)(value.database.smembers(value.key));
	}

	//bool smove(T : E[], E)(string source, string destination, T member) { return request!bool("SMOVE", source, destination, member); }
	//RedisReply sunion(string[] keys...) { return request!RedisReply("SUNION", keys); }
	//long sunionStore(string[] keys...) { return request!long("SUNIONSTORE", keys); }
}


/** Represents a Redis sorted set value.

	In addition to the methods specific to sorted set values, all operations of
	$(D RedisValue) are available using an $(D alias this) declaration.
*/
struct RedisZSet(T = string) {
	RedisValue value;
	alias value this;

	this(RedisDatabase db, string key) { value = RedisValue(db, key); }

	long insert(ARGS...)(ARGS args) { return m_db.zadd(m_key, args); }
	long remove(ARGS...)(ARGS members) { return m_db.zrem(m_key, members); }
	bool remove() { return value.remove(); }
	long length() { return m_db.zcard(m_key); }

	long count(string INT = "[]")(double min, double max)
		if (INT == "[]")
	{
		return m_db.zcount(m_key, min, max);
	}

	long removeRangeByRank(long start, long end) { return m_db.zremRangeByRank(m_key, start, end); }
	long removeRangeByScore(string INT = "[]")(double min, double max) if (INT == "[]") { return m_db.zremRangeByScore(m_key, min, max); }

	double opIndexOpAssign(string op)(double value, string member) if (op == "+") { return m_db.zincrby(m_key, value, member); }

	long getRank(string member) { return m_db.zrank(m_key, member); }
	long getReverseRank(string member) { return m_db.zrevRank(m_key, member); }

	long countByLex(string min, string max) { return m_db.zlexCount(m_key, min, max); }

	//TODO: zinterstore

	//RedisReply zrange(string key, long start, long end, bool withScores=false);

	// TODO:
	// supports only inclusive intervals
	// see http://redis.io/commands/zrangebyscore
	//RedisReply zrangeByScore(string key, double start, double end, bool withScores=false);

	// TODO:
	// supports only inclusive intervals
	// see http://redis.io/commands/zrangebyscore
	//RedisReply zrangeByScore(string key, double start, double end, long offset, long count, bool withScores=false);

	//RedisReply zrevRange(string key, long start, long end, bool withScores=false);

	// TODO:
	// supports only inclusive intervals
	// see http://redis.io/commands/zrangebyscore
	//RedisReply zrevRangeByScore(string key, double min, double max, bool withScores=false);

	auto rangeByLex(T = string)(string min = "-", string max = "+", long offset = 0, long count = -1)
	{
		return m_db.zrangeByLex!T(m_key, min, max, offset, count);
	}

	// TODO:
	// supports only inclusive intervals
	// see http://redis.io/commands/zrangebyscore
	//RedisReply zrevRangeByScore(string key, double min, double max, long offset, long count, bool withScores=false);

	//RedisReply zscore(string key, string member) { return request!RedisReply("ZSCORE", key, member); }
	//TODO: zunionstore
}
