/**
	Cookie based session support.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger, Sönke Ludwig
*/
module vibe.http.session;

import vibe.core.log;

import std.base64;
import std.array;
import std.random;

	
/**
	Represents a single HTTP session.

	Indexing the session object with string keys allows to store arbitrary key/value pairs.
*/
final class Session {
	private {
		SessionStore m_store;
		string m_id;
	}

	private this(SessionStore store, string id = null)
	{
		m_store = store;
		if (id) {
			m_id = id;
		} else {
			auto rnd = appender!(ubyte[])();
			foreach(i;0..16) rnd.put(cast(ubyte)uniform(0, 255));			
			m_id = cast(immutable)Base64.encode(rnd.data);			
		}
	}

	/// Returns the unique session id of this session.
	@property string id() const { return m_id; }

	/// Queries the session for the existence of a particular key.
	bool isKeySet(string key) const { return m_store.isKeySet(m_id, key); }

	/**
		Enables foreach-iteration over all key/value pairs of the session.

		Examples:
		---
		// sends all session entries to the requesting browser
		void handleRequest(HttpServerRequest req, HttpServerResponse res)
		{
			res.contentType = "text/plain";
			foreach(key, value; req.session)
				res.bodyWriter.write(key ~ ": " ~ value ~ "\n");
		}
		---
	*/
	int opApply(int delegate(ref string key, ref string value) del)
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
		void handleRequest(HttpServerRequest req, HttpServerResponse res)
		{
			res.contentType = "text/plain";
			res.bodyWriter.write("Username: " ~ req.session["userName"]);
			res.bodyWriter.write("Request count: " ~ req.session["requestCount"]);
			req.session["requestCount"] = to!string(req.session["requestCount"].to!int + 1);
		}
		---
	*/
	string opIndex(string name) const { return m_store.get(m_id, name); }
	/// ditto
	void opIndexAssign(string value, string name) { m_store.set(m_id, name, value); }

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
	void set(string id, string name, string value);

	/// Returns the value for a given session key.
	string get(string id, string name, string defaultVal = null) const;

	/// Determines if a certain session key is set.
	bool isKeySet(string id, string key) const;

	/// Terminates the given sessiom.
	void destroy(string id);

	/// Iterates all key/value pairs stored in the given session. 
	int delegate(int delegate(ref string key, ref string value)) iterateSession(string id);

	/// Creates a new Session object which sources its contents from this store.
	protected final Session createSessionInstance(string id = null)
	{
		return new Session(this, id);
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
		string[string][string] m_sessions;
	}

	Session create()
	{
		auto s = new Session(this);
		m_sessions[s.id] = null;
		return s;
	}

	Session open(string id)
	{
		auto pv = id in m_sessions;
		return pv ? new Session(this, id) : null;	
	}

	void set(string id, string name, string value)
	{
		m_sessions[id][name] = value;
		foreach(k, v; m_sessions[id]) logTrace("Csession[%s][%s] = %s", id, k, v);
	}

	string get(string id, string name, string defaultVal=null)
	const {
		assert(id in m_sessions, "session not in store");
		foreach(k, v; m_sessions[id]) logTrace("Dsession[%s][%s] = %s", id, k, v);
		if (auto pv = name in m_sessions[id]) {
			return *pv;			
		} else {
			return defaultVal;
		}
	}

	bool isKeySet(string id, string key)
	const {
		return (key in m_sessions[id]) !is null;
	}

	void destroy(string id)
	{
		m_sessions.remove(id);
	}

	int delegate(int delegate(ref string key, ref string value)) iterateSession(string id)
	{
		assert(id in m_sessions, "session not in store");
		int iterator(int delegate(ref string key, ref string value) del)
		{
			foreach( key, ref value; m_sessions[id] )
				if( auto ret = del(key, value) != 0 )
					return ret;
			return 0;
		}
		return &iterator;
	}
}
