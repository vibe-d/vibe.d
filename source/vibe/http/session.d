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

static this()
{
	g_rng = new SHA1HashMixerRNG();
}

//The "URL and Filename safe" Base64 without padding
alias Base64Impl!('-', '_', Base64.NoPadding) Base64URLNoPadding;


/**
	Represents a single HTTP session.

	Indexing the session object with string keys allows to store arbitrary key/value pairs.
*/
final struct Session {
	private {
		SessionStore m_store;
		string m_id;
	}

	private this(SessionStore store, string id = null)
	{
		assert(id.length > 0);
		m_store = store;
		m_id = id;
	}

	bool opCast() const { return m_store !is null; }

	/// Returns the unique session id of this session.
	@property string id() const { return m_id; }

	/// Queries the session for the existence of a particular key.
	bool isKeySet(string key) { return m_store.isKeySet(m_id, key); }

	/** Gets a typed field from the session.
	*/
	const(T) get(T)(string key, lazy T def_value = T.init)
	{
		static assert(!hasAliasing!T, "Type "~T.stringof~" contains references, which is not supported for session storage.");
		return m_store.get(m_id, key, Variant(def_value)).get!T;
	}

	/** Sets a typed field to the session.
	*/
	void set(T)(string key, T value)
	{
		static assert(!hasAliasing!T, "Type "~T.stringof~" contains references, which is not supported for session storage.");
		m_store.set(m_id, key, Variant(value));
	}

	/**
		Enables foreach-iteration over all key/value pairs of the session.

		Examples:
		---
		// sends all session entries to the requesting browser
		void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
		{
			res.contentType = "text/plain";
			foreach(key, value; req.session)
				res.bodyWriter.write(key ~ ": " ~ value ~ "\n");
		}
		---
	*/
	int opApply(int delegate(ref string key, ref Variant value) del)
	{
		foreach( key, ref value; m_store.iterateSession(m_id) )
			if( auto ret = del(key, value) != 0 )
				return ret;
		return 0;
	}
	
	/**
		Gets/sets a key/value pair stored within the session.

		Returns null if the specified key is not set.

		Examples:
		---
		void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
		{
			res.contentType = "text/plain";
			res.bodyWriter.write("Username: " ~ req.session["userName"]);
			res.bodyWriter.write("Request count: " ~ req.session["requestCount"]);
			req.session["requestCount"] = to!string(req.session["requestCount"].to!int + 1);
		}
		---
	*/
	string opIndex(string name) { return m_store.get(m_id, name, Variant(string.init)).get!string; }
	/// ditto
	void opIndexAssign(string value, string name) { m_store.set(m_id, name, Variant(value)); }

	package void destroy() { m_store.destroy(m_id); }
}


/**
	Interface for a basic session store.

	A sesseion store is responsible for storing the id and the associated key/value pairs of a
	session.
*/
interface SessionStore {
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

	/// Terminates the given sessiom.
	void destroy(string id);

	/// Iterates all key/value pairs stored in the given session. 
	int delegate(int delegate(ref string key, ref Variant value)) iterateSession(string id);

	/// Creates a new Session object which sources its contents from this store.
	protected final Session createSessionInstance(string id = null)
	{
		if (!id.length) {
			ubyte[64] rand;
			g_rng.read(rand);
			id = cast(immutable)Base64URLNoPadding.encode(rand);
		}
		return Session(this, id);
	}
}


/**
	Session store for storing a session in local memory.

	If the server is running as a single instance (no thread or process clustering), this kind of
	session store provies the fastest and simplest way to store sessions. In any other case,
	a persistent session store based on a database is necessary.
*/
final class MemorySessionStore : SessionStore {
	private {
		Variant[string][string] m_sessions;
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
	{
		m_sessions[id][name] = value;
		foreach(k, v; m_sessions[id]) logTrace("Csession[%s][%s] = %s", id, k, v);
	}

	Variant get(string id, string name, lazy Variant defaultVal)
	{
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

	void destroy(string id)
	{
		m_sessions.remove(id);
	}

	int delegate(int delegate(ref string key, ref Variant value)) iterateSession(string id)
	{
		assert(id in m_sessions, "session not in store");
		int iterator(int delegate(ref string key, ref Variant value) del)
		{
			foreach( key, ref value; m_sessions[id] )
				if( auto ret = del(key, value) != 0 )
					return ret;
			return 0;
		}
		return &iterator;
	}
}
