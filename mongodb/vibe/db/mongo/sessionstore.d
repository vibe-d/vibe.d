/**
	MongoDB based HTTP session store.

	Copyright: © 2017 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.sessionstore;

import vibe.data.json;
import vibe.db.mongo.mongo;
import vibe.http.session;
import core.time;
import std.datetime : Clock, SysTime, UTC;
import std.typecons : Nullable;
import std.variant;

///
unittest {
	import vibe.core.core : runApplication;
	import vibe.db.mongo.sessionstore : MongoSessionStore;
	import vibe.http.server : HTTPServerSettings, listenHTTP;
	import vibe.http.router : URLRouter;
	import core.time : hours;

	void main()
	{
		auto store = new MongoSessionStore("mongodb://127.0.0.1/mydb", "sessions");
		store.expirationTime = 5.hours;

		auto settings = new HTTPServerSettings("127.0.0.1:8080");
		settings.sessionStore = store;

		auto router = new URLRouter;
		// TODO: add some routes

		listenHTTP(settings, router);

		runApplication();
	}
}


final class MongoSessionStore : SessionStore {
@safe:
	private {
		MongoCollection m_sessions;
		Duration m_expirationTime = Duration.max;
	}

	/** Constructs a new MongoDB session store.

		Params:
			url = URL of the MongoDB database (e.g. `"mongodb://localhost/mydb"`)
			database = Name of the database to use
			collection = Optional collection name to store the sessions in
	*/
	this(string url, string collection = "sessions")
	{
		import std.exception : enforce;

		MongoClientSettings settings;
		enforce(parseMongoDBUrl(settings, url),
			"Failed to parse MongoDB URL.");
		auto db = connectMongoDB(settings).getDatabase(settings.database);
		m_sessions = db[collection];
	}

	/** The duration without access after which a session expires.
	*/
	@property Duration expirationTime() const { return m_expirationTime; }
	/// ditto
	@property void expirationTime(Duration dur)
	{
		import std.typecons : tuple;
		m_sessions.ensureIndex([tuple("time", 1)], IndexFlags.none, dur);
		m_expirationTime = dur;
	}

	@property SessionStorageType storageType() const { return SessionStorageType.bson; }

	Session create()
	{
		auto s = createSessionInstance();
		m_sessions.insert(SessionEntry(s.id, Clock.currTime(UTC())));
		return s;
	}

	Session open(string id)
	{
		auto res = m_sessions.findAndModify(["_id": id], ["$set": ["time": Clock.currTime(UTC())]], ["_id": 1]);
		if (!res.isNull) return createSessionInstance(id);
		return Session.init;
	}

	void set(string id, string name, Variant value)
	@trusted {
		m_sessions.update(["_id": id], ["$set": [name.escape: value.get!Bson, "time": Clock.currTime(UTC()).serializeToBson]]);
	}

	Variant get(string id, string name, lazy Variant defaultVal)
	@trusted {
		auto f = name.escape;
		auto r = m_sessions.findOne(["_id": id], [f: 1]);
		if (r.isNull) return defaultVal;
		auto v = r.tryIndex(f);
		if (v.isNull) return defaultVal;
		return Variant(v.get);
	}

	bool isKeySet(string id, string key)
	{
		auto f = key.escape;
		auto r = m_sessions.findOne(["_id": id], [f: 1]);
		if (r.isNull) return false;
		return !r.tryIndex(f).isNull;
	}

	void remove(string id, string key)
	{
		m_sessions.update(["_id": id], ["$unset": [key.escape: 1]]);
	}

	void destroy(string id)
	{
		m_sessions.remove(["_id": id]);
	}

	int iterateSession(string id, scope int delegate(string key) @safe del)
	{
		import std.algorithm.searching : startsWith;

		auto r = m_sessions.findOne(["_id": id]);
		foreach (k, _; r.byKeyValue) {
			if (k.startsWith("f_")) {
				auto f = k.unescape;
				if (auto ret = del(f))
					return ret;
			}
		}
		return 0;
	}

	private static struct SessionEntry {
		string _id;
		SysTime time;
	}
}


private string escape(string field_name)
@safe {
	import std.array : appender;
	import std.format : formattedWrite;

	auto ret = appender!string;
	ret.reserve(field_name.length + 2);
	ret.put("f_");
	foreach (char ch; field_name) {
		switch (ch) {
			default:
				ret.formattedWrite("+%02X", cast(int)ch);
				break;
			case 'a': .. case 'z':
			case 'A': .. case 'Z':
			case '0': .. case '9':
			case '_', '-':
				ret.put(ch);
				break;
		}
	}
	return ret.data;
}

private string unescape(string key)
@safe {
	import std.algorithm.searching : startsWith;
	import std.array : appender;
	import std.conv : to;

	assert(key.startsWith("f_"));
	key = key[2 .. $];
	auto ret = appender!string;
	ret.reserve(key.length);
	while (key.length) {
		if (key[0] == '+') {
			ret.put(cast(char)key[1 .. 3].to!int(16));
			key = key[3 .. $];
		} else {
			ret.put(key[0]);
			key = key[1 .. $];
		}
	}
	return ret.data;
}

@safe unittest {
	void test(string raw, string enc) {
		assert(escape(raw) == enc);
		assert(unescape(enc) == raw);
	}
	test("foo", "f_foo");
	test("foo.bar", "f_foo+2Ebar");
	test("foo+bar", "f_foo+2Bbar");
}

