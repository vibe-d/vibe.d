/**
	Cookie based session support.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger, Sönke Ludwig, Ilya Shipunov
*/
module vibe.http.session;

import vibe.core.log;
import vibe.crypto.cryptorand;

import std.array;
import std.base64;
import std.traits : hasAliasing;
import std.variant;

//random number generator
//TODO: Use Whirlpool or SHA-512 here
private SHA1HashMixerRNG g_rng;

//The "URL and Filename safe" Base64 without padding
alias Base64URLNoPadding = Base64Impl!('-', '_', Base64.NoPadding);


/**
	Represents a single HTTP session.

	Indexing the session object with string keys allows to store arbitrary key/value pairs.
*/
struct Session {
	private {
		SessionStore m_store;
		string m_id;
		SessionStorageType m_storageType;
	}

	// created by the SessionStore using SessionStore.createSessionInstance
	private this(SessionStore store, string id = null)
	@safe {
		assert(id.length > 0);
		m_store = store;
		m_id = id;
		m_storageType = store.storageType;
	}

	/** Checks if the session is active.

		This operator enables a $(D Session) value to be used in conditionals
		to check if they are actially valid/active.
	*/
	bool opCast() const @safe { return m_store !is null; }

	///
	unittest {
		//import vibe.http.server;
		// workaround for cyclic module ctor compiler error
		class HTTPServerRequest { Session session; string[string] form; }
		class HTTPServerResponse { Session startSession() { assert(false); } }

		void login(scope HTTPServerRequest req, scope HTTPServerResponse res)
		{
			// TODO: validate username+password

			// ensure that there is an active session
			if (!req.session) req.session = res.startSession();

			// update session variables
			req.session.set("loginUser", req.form["user"]);
		}
	}

	/// Returns the unique session id of this session.
	@property string id() const @safe { return m_id; }

	/// Queries the session for the existence of a particular key.
	bool isKeySet(string key) @safe { return m_store.isKeySet(m_id, key); }

	/** Gets a typed field from the session.
	*/
	const(T) get(T)(string key, lazy T def_value = T.init)
	@trusted { // Variant, deserializeJson/deserializeBson
		static assert(!hasAliasing!T, "Type "~T.stringof~" contains references, which is not supported for session storage.");
		auto val = m_store.get(m_id, key, serialize(def_value));
		return deserialize!T(val);
	}

	/** Sets a typed field to the session.
	*/
	void set(T)(string key, T value)
	{
		static assert(!hasAliasing!T, "Type "~T.stringof~" contains references, which is not supported for session storage.");
		m_store.set(m_id, key, serialize(value));
	}

	// Removes a field from a session
	void remove(string key) @safe { m_store.remove(m_id, key); }

	/**
		Enables foreach-iteration over all keys of the session.
	*/
	int opApply(scope int delegate(string key) @safe del)
	@safe {
		return m_store.iterateSession(m_id, del);
	}
	///
	unittest {
		//import vibe.http.server;
		// workaround for cyclic module ctor compiler error
		class HTTPServerRequest { Session session; }
		class HTTPServerResponse { import vibe.core.stream; OutputStream bodyWriter() @safe { assert(false); } string contentType; }

		// sends all session entries to the requesting browser
		// assumes that all entries are strings
		void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
		{
			res.contentType = "text/plain";
			req.session.opApply((key) @safe {
				res.bodyWriter.write(key ~ ": " ~ req.session.get!string(key) ~ "\n");
				return 0;
			});
		}
	}

	package void destroy() @safe { m_store.destroy(m_id); }

	private Variant serialize(T)(T val)
	{
		import vibe.data.json;
		import vibe.data.bson;

		final switch (m_storageType) with (SessionStorageType) {
			case native: return () @trusted { return Variant(val); } ();
			case json: return () @trusted { return Variant(serializeToJson(val)); } ();
			case bson: return () @trusted { return Variant(serializeToBson(val)); } ();
		}
	}

	private T deserialize(T)(ref Variant val)
	{
		import vibe.data.json;
		import vibe.data.bson;

		final switch (m_storageType) with (SessionStorageType) {
			case native: return () @trusted { return val.get!T; } ();
			case json: return () @trusted { return deserializeJson!T(val.get!Json); } ();
			case bson: return () @trusted { return deserializeBson!T(val.get!Bson); } ();
		}
	}
}


/**
	Interface for a basic session store.

	A session store is responsible for storing the id and the associated key/value pairs of a
	session.
*/
interface SessionStore {
@safe:

	/// Returns the internal type used for storing session keys.
	@property SessionStorageType storageType() const;

	/// Creates a new session.
	Session create();

	/// Opens an existing session.
	Session open(string id);

	/// Sets a name/value pair for a given session.
	void set(string id, string name, Variant value);

	/// Returns the value for a given session key.
	Variant get(string id, string name, lazy Variant defaultVal);

	/// Determines if a certain session key is set.
	bool isKeySet(string id, string key);

	/// Removes a key from a session
	void remove(string id, string key);

	/// Terminates the given session.
	void destroy(string id);

	/// Iterates all keys stored in the given session.
	int iterateSession(string id, scope int delegate(string key) @safe del);

	/// Creates a new Session object which sources its contents from this store.
	protected final Session createSessionInstance(string id = null)
	{
		if (!id.length) {
			ubyte[64] rand;
			if (!g_rng) g_rng = new SHA1HashMixerRNG();
			g_rng.read(rand);
			id = () @trusted { return cast(immutable)Base64URLNoPadding.encode(rand); } ();
		}
		return Session(this, id);
	}
}

enum SessionStorageType {
	native,
	json,
	bson
}


/**
	Session store for storing a session in local memory.

	If the server is running as a single instance (no thread or process clustering), this kind of
	session store provies the fastest and simplest way to store sessions. In any other case,
	a persistent session store based on a database is necessary.
*/
final class MemorySessionStore : SessionStore {
@safe:

	private {
		Variant[string][string] m_sessions;
	}

	@property SessionStorageType storageType()
	const {
		return SessionStorageType.native;
	}

	Session create()
	{
		auto s = createSessionInstance();
		m_sessions[s.id] = null;
		return s;
	}

	Session open(string id)
	{
		auto pv = id in m_sessions;
		return pv ? createSessionInstance(id) : Session.init;
	}

	void set(string id, string name, Variant value)
	@trusted { // Variant
		m_sessions[id][name] = value;
		foreach(k, v; m_sessions[id]) logTrace("Csession[%s][%s] = %s", id, k, v);
	}

	Variant get(string id, string name, lazy Variant defaultVal)
	@trusted { // Variant
		assert(id in m_sessions, "session not in store");
		foreach(k, v; m_sessions[id]) logTrace("Dsession[%s][%s] = %s", id, k, v);
		if (auto pv = name in m_sessions[id]) {
			return *pv;
		} else {
			return defaultVal;
		}
	}

	bool isKeySet(string id, string key)
	{
		return (key in m_sessions[id]) !is null;
	}

	void remove(string id, string key)
	{
		m_sessions[id].remove(key);
	}

	void destroy(string id)
	{
		m_sessions.remove(id);
	}

	int delegate(int delegate(ref string key, ref Variant value) @safe) @safe iterateSession(string id)
	{
		assert(id in m_sessions, "session not in store");
		int iterator(int delegate(ref string key, ref Variant value) @safe del)
		@safe {
			foreach( key, ref value; m_sessions[id] )
				if( auto ret = del(key, value) != 0 )
					return ret;
			return 0;
		}
		return &iterator;
	}

	int iterateSession(string id, scope int delegate(string key) @safe del)
	@trusted { // hash map iteration
		assert(id in m_sessions, "session not in store");
		foreach (key; m_sessions[id].byKey)
			if (auto ret = del(key))
				return ret;
		return 0;
	}
}
