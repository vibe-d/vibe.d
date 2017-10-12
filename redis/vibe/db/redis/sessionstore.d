module vibe.db.redis.sessionstore;

import vibe.data.json;
import vibe.db.redis.redis;
import vibe.http.session;
import core.time;
import std.typecons : Nullable;
import std.variant;


final class RedisSessionStore : SessionStore {
	private {
		RedisDatabase m_db;
		Duration m_expirationTime = Duration.max;
	}

	/** Constructs a new Redis session store.

		Params:
			host = Host name of the Redis instance to connect to
			database = Database number to select on the server
			port = Optional port number to use when connecting to the server
	*/
	this(string host, long database, ushort port = RedisClient.defaultPort)
	{
		m_db = connectRedis(host, port).getDatabase(database);
	}

	/** The duration without access after which a session expires.
	*/
	@property Duration expirationTime() const { return m_expirationTime; }
	/// ditto
	@property void expirationTime(Duration dur) { m_expirationTime = dur; }

	@property SessionStorageType storageType() const { return SessionStorageType.json; }

	Session create()
	{
		auto s = createSessionInstance();
		m_db.hset(s.id, "__SESS", true); // set place holder to avoid create empty hash
		assert(m_db.exists(s.id));
		if (m_expirationTime != Duration.max)
			m_db.expire(s.id, m_expirationTime);
		return s;
	}

	Session open(string id)
	{
		if (m_db.exists(id))
		{
			auto s = createSessionInstance(id);
			if (m_expirationTime != Duration.max)
				m_db.expire(s.id, m_expirationTime);
			return s;
		}
		return Session.init;
	}

	void set(string id, string name, Variant value)
	@trusted {
		m_db.hset(id, name, value.get!Json.toString());
	}

	Variant get(string id, string name, lazy Variant defaultVal)
	@trusted {
		auto v = m_db.hget!(Nullable!string)(id, name);
		return v.isNull ? defaultVal : Variant(parseJsonString(v.get));
	}

	bool isKeySet(string id, string key)
	{
		return m_db.hexists(id, key);
	}

	void remove(string id, string key)
	{
		m_db.hdel(id, key);
	}

	void destroy(string id)
	{
		m_db.del(id);
	}

	int delegate(int delegate(ref string key, ref Variant value)) iterateSession(string id)
	{
		assert(false, "Not available for RedisSessionStore");
	}

	int iterateSession(string id, scope int delegate(string key) @safe del)
	{
		auto res = m_db.hkeys(id);
		while (!res.empty) {
			auto key = res.front;
			res.popFront();
			if (auto ret = del(key))
				return ret;
		}
		return 0;
	}
}
