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

	private this(SessionStore store, string id=null) {
		m_store = store;
		if (id) {
			m_id = id;
		} else {
			auto rnd = appender!(ubyte[])();
			foreach(i;0..16) rnd.put(cast(ubyte)uniform(0, 255));			
			m_id = cast(immutable)Base64.encode(rnd.data);			
		}
	}

	int opApply(int delegate(ref string key, ref string value) del)
	{
		foreach( key, ref value; m_store.iterateSession(m_id) )
			if( auto ret = del(key, value) != 0 )
				return ret;
		return 0;
	}
	
	/// Returns the unique session id of this session.
	@property string id() const { return m_id; }

	/// Gets/sets a key/value pair stored within the session.
	string opIndex(string name) const { return m_store.get(m_id, name); }
	/// ditto
	void opIndexAssign(string value, string name) { m_store.set(m_id, name, value); }

	/// Queries the session for the existence of a particular key.
	bool isKeySet(string key) const { return m_store.isKeySet(m_id, key); }

	package void destroy() { m_store.destroy(m_id); }
}


/**
	Interface for a basic session store.

	A sesseion store is responsible for storing the id and the associated key/value pairs of a
	session.
*/
interface SessionStore {
	Session create();
	Session open(string id);
	void set(string id, string name, string value);
	string get(string id, string name, string defaultVal = null) const;
	bool isKeySet(string id, string key) const;
	void destroy(string id);
	int delegate(int delegate(ref string key, ref string value)) iterateSession(string id);
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
	this() {}

	Session create() {
		return new Session(this);
	}
	Session open(string id) {
		auto pv = id in m_sessions;
		return pv ? new Session(this, id) : null;	
	}
	void set(string id, string name, string value) {
		m_sessions[id][name] = value;
		foreach(k,v; m_sessions[id]) logInfo("Csession[%s][%s] = %s", id, k, v);
	}
	string get(string id, string name, string defaultVal=null)
	const {
		assert(id in m_sessions, "session not in store");
		foreach(k,v; m_sessions[id]) logInfo("Dsession[%s][%s] = %s", id, k, v);
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
		return (int delegate(ref string, ref string) del){
			foreach( key, ref value; m_sessions[id] )
				if( auto ret = del(key, value) != 0 )
					return ret;
			return 0;
		};
	}

}