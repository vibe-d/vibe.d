/**
	Type safe implementations of common Redis storage idioms.

	Note that the API is still subject to change!

	Copyright: © 2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.redis.idioms;

import vibe.db.redis.redis;
import vibe.db.redis.types;

import core.time : msecs, seconds;


/**
*/
struct RedisCollection(T /*: RedisValue*/, RedisCollectionOptions OPTIONS = RedisCollectionOptions.defaults, size_t ID_LENGTH = 1)
{
	static assert(ID_LENGTH > 0, "IDs must have a length of at least one.");
	static assert(!(OPTIONS & RedisCollectionOptions.supportIteration) || ID_LENGTH == 1, "ID generation currently not supported for ID lengths greater 2.");

	alias IDS = Replicate!(long, ID_LENGTH);
	static if (ID_LENGTH == 1) alias IDType = long;
	else alias IDType = Tuple!IDS;

	private {
		RedisDatabase m_db;
		string[ID_LENGTH] m_prefix;
		string m_suffix;
		static if (OPTIONS & RedisCollectionOptions.supportIteration || OPTIONS & RedisCollectionOptions.supportPaging) {
			@property string m_idCounter() const { return m_prefix[0] ~ "max"; }
			@property string m_allSet() const { return m_prefix[0] ~ "all"; }
		}
	}

	this(RedisDatabase db, Replicate!(string, ID_LENGTH) name, string suffix = null)
	{
		initialize(db, name, suffix);
	}

	void initialize(RedisDatabase db, Replicate!(string, ID_LENGTH) name, string suffix = null)
	{
		m_db = db;
		foreach (i, N; name) {
			if (i == 0) m_prefix[i] = name[i] ~ ":";
			else m_prefix[i] = ":" ~ name[i] ~ ":";
		}
		if (suffix.length) m_suffix = ":" ~ suffix;
	}

	@property inout(RedisDatabase) database() inout { return m_db; }

	T opIndex(IDS id) { return T(m_db, getKey(id)); }

	static if (OPTIONS & RedisCollectionOptions.supportIteration || OPTIONS & RedisCollectionOptions.supportPaging) {
		/** Creates an ID without setting a corresponding value.
		*/
		IDType createID()
		{
			auto id = m_db.incr(m_idCounter);
			static if (OPTIONS & RedisCollectionOptions.supportPaging)
				m_db.zadd(m_allSet, id, id);
			else m_db.sadd(m_allSet, id);
			return id;
		}

		IDType add(U)(U args)
		{
			auto id = createID();
			this[id] = args;
			return id;
		}

		bool isMember(long id)
		{
			static if (OPTIONS & RedisCollectionOptions.supportPaging)
				return m_db.zscore(m_allSet, id).hasNext();
			else return m_db.sisMember(m_allSet, id);
		}

		static if (OPTIONS & RedisCollectionOptions.supportPaging) {
			// TODO: add range queries
		}

		int opApply(int delegate(long id) del)
		{
			static if (OPTIONS & RedisCollectionOptions.supportPaging) {
				foreach (id; m_db.zrange!long(m_allSet, 0, -1))
					if (auto ret = del(id))
						return ret;
			} else {
				foreach (id; m_db.smembers!long(m_allSet))
					if (auto ret = del(id))
						return ret;
			}
			return 0;
		}

		int opApply(int delegate(long id, T) del)
		{
			static if (OPTIONS & RedisCollectionOptions.supportPaging) {
				foreach (id; m_db.zrange!long(m_allSet, 0, -1))
					if (auto ret = del(id, this[id]))
						return ret;
			} else {
				foreach (id; m_db.smembers!long(m_allSet))
					if (auto ret = del(id, this[id]))
						return ret;
			}
			return 0;
		}
	}

	/** Removes an ID along with the corresponding value.
	*/
	void remove(IDS id)
	{
		this[id].remove();
		static if (OPTIONS & RedisCollectionOptions.supportIteration || OPTIONS & RedisCollectionOptions.supportPaging) {
			static if (OPTIONS & RedisCollectionOptions.supportPaging)
				m_db.zrem(m_allSet, id);
			else
				m_db.srem(m_allSet, id);
		}
	}


	private string getKey(IDS ids)
	{
		import std.conv;
		static if (ID_LENGTH == 1) {
			return m_prefix[0] ~ ids.to!string ~ m_suffix;
		} else {
			string ret;
			foreach (i, id; ids) ret ~= m_prefix[i] ~ id.to!string;
			return ret ~ m_suffix;
		}
	}
}

enum RedisCollectionOptions {
	none             = 0,    // Plain collection without iteration/paging support
	supportIteration = 1<<0, // Store IDs in a set to be able to iterate and check for existence
	supportPaging    = 1<<1, // Store IDs in a sorted set, to support range based queries
	defaults = supportIteration
}


/** Models a set of numbered hashes.

	This structure is roughly equivalent to a $(D string[string][long]) and is
	commonly used to store collections of objects, such as all users of a
	service. For a strongly typed variant of this class, see
	$(D RedisObjectCollection).

	See_also: $(D RedisObjectCollection)
*/
template RedisHashCollection(RedisCollectionOptions OPTIONS = RedisCollectionOptions.defaults, size_t ID_LENGTH = 1)
{
	alias RedisHashCollection = RedisCollection!(RedisHash, OPTIONS, ID_LENGTH);
}


/** Models a strongly typed set of numbered hashes.

	This structure is roughly equivalent of a $(D T[long]).

	See_also: $(D RedisHashCollection)
*/
template RedisObjectCollection(T, RedisCollectionOptions OPTIONS = RedisCollectionOptions.defaults, size_t ID_LENGTH = 1)
{
	alias RedisObjectCollection = RedisCollection!(RedisObject!T, OPTIONS, ID_LENGTH);
}

///
unittest {
	struct User {
		string name;
		string email;
		int age;
		string password;
	}

	void test()
	{
		auto db = connectRedis("127.0.0.1").getDatabase(0);
		db.deleteAll();

		auto users = RedisObjectCollection!User(db, "users");
		assert(users.add(User("Tom", "tom@example.com", 42, "secret")) == 0);
		assert(users.add(User("Peter", "peter@example.com", 42, "secret")) == 1);

		auto peter = users[1];
		assert(peter.name == "Peter");
	}
}


/** Models a single strongly typed object.

	This structure is rougly equivalent to a value of type $(D T). The
	underlying data is represented as a Redis hash. This means that only
	primitive fields are supported for $(D T).
*/
struct RedisObject(T) {
	private {
		RedisHash!string m_hash;
	}

	this(RedisDatabase db, string key)
	{
		m_hash = RedisHash!string(db, key);
	}

	this(RedisHash!string hash)
	{
		m_hash = hash;
	}

	@property T get()
	{
		T ret;
		auto repl = m_hash.database.hmget(m_hash.key, keys);
		foreach (i, F; typeof(ret.tupleof)) {
			assert(!repl.empty);
			__traits(getMember, ret, keys[i]) = repl.front.fromRedis!F;
			repl.popFront();
		}
		assert(repl.empty);
		return ret;
	}

	@property bool exists() { return m_hash.value.exists(); }

	alias get this;

	void remove() { m_hash.remove(); }

	void opAssign(T val)
	{
		m_hash.database.hmset(m_hash.key, toTuple(toKeysAndValues(val)).expand);
	}

	mixin(fields());

	static private string fields()
	{
		string ret;
		foreach (name; keys) {
			ret ~= "@property auto "~name~"() { return RedisObjectField!(typeof(T."~name~"))(m_hash, \""~name~"\"); }\n";
			ret ~= "@property void "~name~"(typeof(T."~name~") val) { this."~name~".opAssign(val); }\n";
		}
		return ret;
	}

	/*@property auto opDispatch(string name)() //if (is(typeof(getMember, T.init, name)))
	{
		return RedisObjectField!(typeof(__traits(getMember, T.init, name)))(m_hash, name);
	}*/

	private static string[T.tupleof.length*2] toKeysAndValues(T val)
	{
		string[T.tupleof.length*2] ret;
		enum keys = fieldNames!T;
		foreach (i, m; val.tupleof) {
			ret[i*2+0] = keys[i];
			ret[i*2+1] = m.toRedis();
		}
		return ret;
	}

	private enum keys = fieldNames!T;
}

struct RedisObjectField(T) {
	private {
		RedisHash!string m_hash;
		string m_field;
	}

	this(RedisHash!string hash, string field)
	{
		m_hash = hash;
		m_field = field;
	}

	@property T get() { return m_hash.database.hget!string(m_hash.key, m_field).fromRedis!T; }

	alias get this;

	void opAssign(T val) { m_hash.database.hset(m_hash.key, m_field, val.toRedis); }

	void opUnary(string op)() if(op == "++") { m_hash.database.hincr(m_hash.key, m_field, 1); }
	void opUnary(string op)() if(op == "--") { m_hash.database.hincr(m_hash.key, m_field, -1); }

	void opOpAssign(string op)(long val) if (op == "+") { m_hash.database.hincr(m_hash.key, m_field, val); }
	void opOpAssign(string op)(long val) if (op == "-") { m_hash.database.hincr(m_hash.key, m_field, -val); }
	void opOpAssign(string op)(double val) if (op == "+") { m_hash.database.hincr(m_hash.key, m_field, val); }
	void opOpAssign(string op)(double val) if (op == "-") { m_hash.database.hincr(m_hash.key, m_field, -val); }
}


/** Models a strongly typed numbered set of values.


*/
template RedisSetCollection(T, RedisCollectionOptions OPTIONS = RedisCollectionOptions.defaults, size_t ID_LENGTH = 1)
{
	alias RedisSetCollection = RedisCollection!(RedisSet!T, OPTIONS, ID_LENGTH);
}

///
unittest {
	void test()
	{
		auto db = connectRedis("127.0.0.1").getDatabase(0);
		auto user_groups = RedisSetCollection!(string, RedisCollectionOptions.none)(db, "user_groups");

		// add some groups for user with ID 0
		user_groups[0].insert("cooking");
		user_groups[0].insert("hiking");
		// add some groups for user with ID 1
		user_groups[1].insert("coding");

		assert(user_groups[0].contains("hiking"));
		assert(!user_groups[0].contains("coding"));
		assert(user_groups[1].contains("coding"));

		user_groups[0].remove("hiking");
		assert(!user_groups[0].contains("hiking"));
	}
}


/** Models a strongly typed numbered set of values.


*/
template RedisListCollection(T, RedisCollectionOptions OPTIONS = RedisCollectionOptions.defaults, size_t ID_LENGTH = 1)
{
	alias RedisListCollection = RedisCollection!(RedisList!T, OPTIONS, ID_LENGTH);
}


/** Models a strongly typed numbered set of values.


*/
template RedisStringCollection(T = string, RedisCollectionOptions OPTIONS = RedisCollectionOptions.defaults, size_t ID_LENGTH = 1)
{
	alias RedisStringCollection = RedisCollection!(RedisString!T, OPTIONS, ID_LENGTH);
}


// TODO: support distributed locking
struct RedisLock {
	private {
		RedisDatabase m_db;
		string m_key;
		string m_scriptSHA;
	}

	this(RedisDatabase db, string lock_key)
	{
		m_db = db;
		m_key = lock_key;
		m_scriptSHA = m_db.scriptLoad(
`if redis.call("get",KEYS[1]) == ARGV[1] then
	return redis.call("del",KEYS[1])
else
	return 0
end`);
	}

	void performLocked(scope void delegate() del)
	{
		import std.random;
		import vibe.core.core;
		import vibe.data.bson;

		auto lockval = BsonObjectID.generate();
		while (!m_db.setNX(m_key, cast(ubyte[])lockval, 30.seconds))
			sleep(uniform(1, 50).msecs);

		scope (exit) m_db.evalSHA!(string, ubyte[])(m_scriptSHA, [m_key], cast(ubyte[])lockval);

		del();
	}
}


// utility structure, temporarily placed here
struct JsonEncoded(T) {
	import vibe.data.json;
	T value;

	alias value this;

	static JsonEncoded fromString(string str) { return JsonEncoded(deserializeJson!T(str)); }
	string toString() { return serializeToJsonString(value); }

	static assert(isStringSerializable!JsonEncoded);
}
JsonEncoded!T jsonEncoded(T)(T value) { return JsonEncoded!T(value); }


// utility structure, temporarily placed here
struct LazyString(T...) {
	private {
		T m_values;
	}

	this(T values) { m_values = values; }

	void toString(void delegate(string) sink)
	{
		foreach (v; m_values)
			dst.formattedWrite("%s", v);
	}
}


/**
	Strips all non-Redis fields from a struct.

	The returned struct will contain only fiels that can be converted using
	$(D toRedis) and that have names different than "id" or "_id".

	To reconstruct the full struct type, use the $(D RedisStripped.unstrip)
	method.
*/
RedisStripped!(T, strip_id) redisStrip(bool strip_id = true, T)(in T val) { return RedisStripped!(T, strip_id)(val); }

/**
	Represents the stripped type of a struct.

	Strips all fields that cannot be directly stored as values in the Redis
	database. By default, any field named `id` or `_id` is also stripped. Set
	the `strip_id` parameter to `false` to keep those fields.

	See_also: $(D redisStrip)
*/
struct RedisStripped(T, bool strip_id = true) {
	import std.traits : Select, select;
	import std.typetuple;

	//pragma(msg, membersString!());
	mixin(membersString());

	alias StrippedMembers = FilterToType!(Select!(strip_id, isNonRedisTypeOrID, isNonRedisType), T.tupleof);
	alias UnstrippedMembers = FilterToType!(Select!(strip_id, isRedisTypeAndNotID, isRedisType), T.tupleof);
	alias strippedMemberIndices = indicesOf!(Select!(strip_id, isNonRedisTypeOrID, isNonRedisType), T.tupleof);
	alias unstrippedMemberIndices = indicesOf!(Select!(strip_id, isRedisTypeAndNotID, isRedisType), T.tupleof);

	this(in T src) { foreach (i, idx; unstrippedMemberIndices) this.tupleof[i] = src.tupleof[idx]; }

	/** Reconstructs the full (unstripped) struct value.

		The parameters for this method are all stripped fields in the order in
		which they appear in the original struct definition.
	*/
	T unstrip(StrippedMembers stripped_members) {
		T ret;
		populateRedisFields(ret, this.tupleof);
		populateNonRedisFields(ret, stripped_members);
		return ret;
	}

	private void populateRedisFields(ref T dst, UnstrippedMembers values)
	{
		foreach (i, v; values)
			dst.tupleof[unstrippedMemberIndices[i]] = v;
	}

	private void populateNonRedisFields(ref T dst, StrippedMembers values)
	{
		foreach (i, v; values)
			dst.tupleof[strippedMemberIndices[i]] = v;
	}


	/*pragma(msg, T);
	pragma(msg, "stripped: "~StrippedMembers.stringof~" - "~strippedMemberIndices.stringof);
	pragma(msg, "unstripped: "~UnstrippedMembers.stringof~" - "~unstrippedMemberIndices.stringof);*/

	private static string membersString()
	{
		string ret;
		foreach (idx; unstrippedMemberIndices) {
			enum name = __traits(identifier, T.tupleof[idx]);
			ret ~= "typeof(T."~name~") "~name~";\n";
		}
		return ret;
	}
}

unittest {
	static struct S1 { int id; string field; string[] array; }
	auto s1 = S1(42, "hello", ["world"]);
	auto s1s = redisStrip(s1);
	static assert(!is(typeof(s1s.id)));
	static assert(is(typeof(s1s.field)));
	static assert(!is(typeof(s1s.array)));
	assert(s1s.field == "hello");
	auto s1u = s1s.unstrip(42, ["world"]);
	assert(s1u == s1);
}

private template indicesOf(alias PRED, T...)
{
	import std.typetuple;
	template impl(size_t i) {
		static if (i < T.length) {
			static if (PRED!(T[i])) alias impl = TypeTuple!(i, impl!(i+1));
			else alias impl = impl!(i+1);
		} else alias impl = TypeTuple!();
	}
	alias indicesOf = impl!0;
}
private template FilterToType(alias PRED, T...) {
	import std.typetuple;
	template impl(size_t i) {
		static if (i < T.length) {
			static if (PRED!(T[i])) alias impl = TypeTuple!(typeof(T[i]), impl!(i+1));
			else alias impl = impl!(i+1);
		} else alias impl = TypeTuple!();
	}
	alias FilterToType = impl!0;
}
private template isRedisType(alias F) { enum isRedisType = is(typeof(&toRedis!(typeof(F)))); }
private template isNonRedisType(alias F) { enum isNonRedisType = !isRedisType!F; }
static assert(isRedisType!(int.init) && isRedisType!(string.init));
static assert(!isRedisType!((float[]).init));

private template isRedisTypeAndNotID(alias F) { import std.algorithm; enum isRedisTypeAndNotID = !__traits(identifier, F).among("_id", "id") && isRedisType!F; }
private template isNonRedisTypeOrID(alias F) { enum isNonRedisTypeOrID = !isRedisTypeAndNotID!F; }
static assert(isRedisTypeAndNotID!(int.init) && isRedisTypeAndNotID!(string.init));

private auto toTuple(size_t N, T)(T[N] values)
{
	import std.typecons;
	import std.typetuple;
	template impl(size_t i) {
		static if (i < N) alias impl = TypeTuple!(T, impl!(i+1));
		else alias impl = TypeTuple!();
	}
	Tuple!(impl!0) ret;
	foreach (i, T; impl!0) ret[i] = values[i];
	return ret;
}

private template fieldNames(T)
{
	import std.typetuple;
	template impl(size_t i) {
		static if (i < T.tupleof.length)
			alias impl = TypeTuple!(__traits(identifier, T.tupleof[i]), impl!(i+1));
		else alias impl = TypeTuple!();
	}
	enum string[T.tupleof.length] fieldNames = [impl!0];
}

unittest {
	static struct Test { int a; float b; void method() {} Test[] c; void opAssign(Test) {}; ~this() {} }
	static assert(fieldNames!Test[] == ["a", "b", "c"]);
}

private template Replicate(T, size_t L)
{
	import std.typetuple;
	static if (L > 0) {
		alias Replicate = TypeTuple!(T, Replicate!(T, L-1));
	} else alias Replicate = TypeTuple!();
}
