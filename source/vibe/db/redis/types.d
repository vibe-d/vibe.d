/**
	Convenience wrappers types for accessing Redis keys.

	Note that the API is still subject to change!

	Copyright: © 2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.redis.types;

import core.time : Duration, msecs, seconds;
import std.datetime : SysTime;
import vibe.db.redis.redis;


/** Returns a handle to a string type value.
*/
RedisString getAsString(RedisDatabase db, string key)
{
	return RedisString(db, key);
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
RedisSet getAsSet(RedisDatabase db, string key)
{
	return RedisSet(db, key);
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
RedisZSet getAsZSet(RedisDatabase db, string key)
{
	return RedisZSet(db, key);
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
RedisHash getAsHash(RedisDatabase db, string key)
{
	return RedisHash(db, key);
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
RedisList getAsList(RedisDatabase db, string key)
{
	return RedisList(db, key);
}

///
unittest {
	void test()
	{
		auto db = connectRedis("127.0.0.1").getDatabase(0);
		auto list = db.getAsList("some_list");
		list.insertFront(123);
	}
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

		Returns: $(D true) iff the key was successfully removed.

		See_also: $(LINK2 http://redis.io/commands/del, DEL)
	*/
	bool remove() { return m_db.del(m_key) > 0; }

	/** Sets the key for expiration after the given timeout.

		Note that Redis handles timeouts in second resolution, so that the
		timeout must be at least one second.

		Returns: $(D true) iff the expiration time was successfully set.

		See_also: $(LINK2 http://redis.io/commands/expire, EXPIRE)
	*/
	bool expire(Duration expire_time) { assert(expire_time >= 1.seconds); return m_db.expire(m_key, expire_time.total!"seconds"); }

	/** Sets the key for expiration at the given point in time.

		Note that Redis handles timeouts in second resolution, so that any
		fractional seconds of the given $(D expire_time) will be truncated.

		Returns: $(D true) iff the expiration time was successfully set.

		See_also: $(LINK2 http://redis.io/commands/expireat, EXPIREAT)
	*/
	bool expireAt(SysTime expire_time) { return m_db.expireAt(m_key, expire_time.toUnixTime()); }

	/** Removes any existing expiration time for the key.

		Returns:
			$(D true) iff the key exists and an existing timeout was removed.

		See_also: $(LINK2 http://redis.io/commands/persist, PERSIST)
	*/
	bool persist() { return m_db.persist(m_key); }

	/** Moves this key to a different database.

		Existing keys will not be overwritten.

		Returns:
			$(D true) iff the key exists and was successfully moved to the
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
			$(D true) iff the source key exists and the destination key doesn't
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
struct RedisString {
	RedisValue value;
	alias value this;

	this(RedisDatabase db, string key) { value = RedisValue(db, key); }

	/** The length in bytes of the string.

		See_also: $(LINK2 http://redis.io/commands/strlen, STRLEN)
	*/
	@property long length() { return m_db.strlen(m_key); }

	T get(T = string)() { return m_db.get!T(m_key); }

	T getSet(T = string)(T value) { return m_db.getSet(m_key, value); }
	bool getBit(long offset) { return m_db.getBit(m_key, offset); }
	bool setBit(long offset, bool value) { return m_db.setBit(m_key, offset, value); }
	void setExpire(T)(T value, Duration expire_time) { assert(expire_time >= 1.seconds); m_db.setEX(m_key, expire_time.total!"seconds", value); }
	bool setIfNotExist(string value) { return m_db.setNX(m_key, value); }

	string getSubString(long start, long end) { return m_db.getRange!string(m_key, start, end); }
	long setSubString(long offset, string value) { return m_db.setRange(m_key, offset, value); }

	void opAssign(string value) { m_db.set(m_key, value); }

	long opOpAssign(string OP)(string value) if (OP == "~") { return m_db.append(m_key, value); }
	long opUnary(string OP)() if (OP == "++" || OP == "--") {
		static if (OP == "++") return m_db.incr(m_key);
		else return m_db.decr(m_key);
	}
	long opOpAssign(string OP)(long value) if (OP == "+") {
		assert(value != 0);
		if (value > 0) return m_db.incr(m_key, value);
		else return m_eb.decr(m_key, -value);
	}
	long opOpAssign(string OP)(long value) if (OP == "-") {
		assert(value != 0);
		if (value > 0) return m_db.incr(m_key, value);
		else return m_eb.decr(m_key, -value);
	}
}


/** Represents a Redis hash value.

	In addition to the methods specific to hash values, all operations of
	$(D RedisValue) are available using an $(D alias this) declaration.
*/
struct RedisHash {
	RedisValue value;
	alias value this;

	this(RedisDatabase db, string key) { value = RedisValue(db, key); }

	size_t remove(scope string[] fields...) { return cast(size_t)m_db.hdel(m_key, fields); }
	bool exists(string field) { return m_db.hexists(m_key, field); }
	
	void opIndexAssign(string value, string field) { m_db.hset(m_key, field, value); }
	// FIXME: support ubyte[] or something
	string opIndex(string field) { return m_db.hget!string(m_key, field); }

	// FIXME: could also be a ubyte[]
	int opApply(int delegate(string key, string value) del)
	{
		auto reply = m_db.hgetAll(m_key);
		while (reply.hasNext()) {
			auto key = reply.next!string();
			auto value = reply.next!string();
			if (auto ret = del(key, value))
				return ret;
		}
		return 0;
	}

	void opIndexOpAssign(string op)(long value, string field) if (op == "+") { m_db.hincr(m_key, field, value); }
	void opIndexOpAssign(string op)(double value, string field) if (op == "+") { m_db.hincrfloat(m_key, field, value); }

	int opApply(int delegate(string key) del)
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
	void getMultiple(string[] dst, scope string[] fields...)
	{
		assert(dst.length == fields.length);
		auto reply = m_db.hmget(m_key, fields);
		size_t idx = 0;
		while (reply.hasNext())
			dst[idx++] = reply.next!string();
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
struct RedisList {
	RedisValue value;
	alias value this;

	this(RedisDatabase db, string key) { value = RedisValue(db, key); }

	//T lindex(T : E[], E)(string key, long index) { return request!T("LINDEX", key, index); }
	void opIndexAssign(T)(T value, long index) { m_db.lset(m_key, index, value); }

	long length() { return m_db.llen(m_key); }

	long insertBefore(T, U)(T pivot, U value) { return m_db.linsertBefore(m_key, pivot, value); }
	long insertAfter(T, U)(T pivot, U value) { return m_db.linsertAfter(m_key, pivot, value); }

	long insertFront(T)(T value) { return m_db.lpush(m_key, value); }
	long insertFrontIfExists(T)(T value) { return m_db.lpushx(m_key, value); }
	long insertBack(T)(T value) { return m_db.rpush(m_key, value); }
	long insertBackIfExists(T)(T value) { return m_db.rpushx(m_key, value); }

	long removeAll(T)(T value) { return m_db.lrem(m_key, 0, value); }
	long removeFirst(T)(T value, long count = 1) { assert(count > 0); return m_db.lrem(m_key, count, value); }
	long removeLast(T)(T value, long count = 1) { assert(count > 0); return m_db.lrem(m_key, -count, value); }

	void trim(long start, long end) { m_db.ltrim(m_key, start, end); }

	T removeFront(T)() { return m_db.lpop!T(m_key); }
	T removeBack(T)() { return m_db.rpop!T(m_key); }
	T removeFrontBlock(T)(Duration max_wait = 0.seconds) {
		assert(max_wait == 0.seconds || max_wait >= 1.seconds);
		return m_db.blpop(m_key, max_wait.total!"seconds");
	}

	//RedisReply lrange(string key, long start, long stop) { return request!RedisReply("LRANGE",  key, start, stop); }
	//T rpoplpush(T : E[], E)(string key, string destination) { return request!T("RPOPLPUSH", key, destination); }
}


/** Represents a Redis set value.

	In addition to the methods specific to set values, all operations of
	$(D RedisValue) are available using an $(D alias this) declaration.
*/
struct RedisSet {
	RedisValue value;
	alias value this;

	this(RedisDatabase db, string key) { value = RedisValue(db, key); }

	long insert(ARGS...)(ARGS args) { return m_db.sadd(m_key, args); }
	long remove(T)(T value) { return m_db.srem(m_key, value); }
	string pop() { return m_db.spop!string(m_key); }
	long length() { return m_db.scard(m_key); }

	string getRandom() { return m_db.srandMember!string(m_key); }

	//RedisReply sdiff(string[] keys...) { return request!RedisReply("SDIFF", keys); }
	//long sdiffStore(string destination, string[] keys...) { return request!long("SDIFFSTORE", destination, keys); }
	//RedisReply sinter(string[] keys) { return request!RedisReply("SINTER", keys); }
	//long sinterStore(string destination, string[] keys...) { return request!long("SINTERSTORE", destination, keys); }
	bool contains(T)(T value) { return m_db.sismember(m_key, value); }

	int opApply(int delegate(string value) del)
	{
		auto reply = m_db.smembers(m_key);
		while (reply.hasNext())
			if (auto ret = del(reply.next!string()))
				return ret;
		return 0;
	}

	//bool smove(T : E[], E)(string source, string destination, T member) { return request!bool("SMOVE", source, destination, member); }
	//RedisReply sunion(string[] keys...) { return request!RedisReply("SUNION", keys); }
	//long sunionStore(string[] keys...) { return request!long("SUNIONSTORE", keys); }
}


/** Represents a Redis sorted set value.

	In addition to the methods specific to sorted set values, all operations of
	$(D RedisValue) are available using an $(D alias this) declaration.
*/
struct RedisZSet {
	RedisValue value;
	alias value this;

	this(RedisDatabase db, string key) { value = RedisValue(db, key); }

	long insert(ARGS...)(ARGS args) { return m_db.zadd(m_key, args); }
	long remove(ARGS...)(ARGS members) { return m_db.zrem(m_key, members); }
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

	// TODO:
	// supports only inclusive intervals
	// see http://redis.io/commands/zrangebyscore
	//RedisReply zrevRangeByScore(string key, double min, double max, long offset, long count, bool withScores=false);

	//RedisReply zscore(string key, string member) { return request!RedisReply("ZSCORE", key, member); }
	//TODO: zunionstore
}
