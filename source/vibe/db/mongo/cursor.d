/**
	MongoDB cursor abstraction

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.cursor;

public import vibe.data.bson;

import vibe.db.mongo.connection;
import vibe.db.mongo.client;

import std.exception;


/**
	Represents a cursor for a MongoDB query.

	Use foreach( doc; cursor ) to iterate over the list of documents.

	This struct uses reference counting to destroy the underlying MongoDB cursor.
*/
struct MongoCursor {
	private MongoCursorData m_data;

	package this(MongoClient client, string collection, int nret, Reply first_chunk)
	{
		m_data = new MongoCursorData(client, collection, nret, first_chunk);
	}

	this(this)
	{
		if( m_data ) m_data.m_refCount++;
	}

	~this()
	{
		if( m_data && --m_data.m_refCount == 0 ){
			m_data.destroy();
		}
	}

	/**
		Returns true if there are more documents for this cursor.

		Throws: An exception if there is a query or communication error.
	*/
	@property bool empty() { return m_data ? m_data.empty() : true; }

	/**
		Returns the current document of the response.

		Use empty and popFront to iterate over the list of documents using an
		input range interface. Note that calling this function is only allowed
		if empty returns false.
	*/
	@property Bson front() { return m_data.front; }

	/**
		Advances the cursor to the next document of the response.

		Note that calling this function is only allowed if empty returns false.
	*/
	void popFront() { m_data.popFront(); }

	/**
		Iterates over all remaining documents.

		Note that iteration is one-way - elements that have already been visited
		will not be visited again if another iteration is done.

		Throws: An exception if there is a query or communication error.
	*/
	int opApply(int delegate(ref Bson doc) del)
	{
		if( !m_data ) return 0;

		while( !m_data.empty ){
			auto doc = m_data.front;
			m_data.popFront();
			if( auto ret = del(doc) )
				return ret;
		}
		return 0;
	}

	/**
		Iterates over all remaining documents.

		Note that iteration is one-way - elements that have already been visited
		will not be visited again if another iteration is done.

		Throws: An exception if there is a query or communication error.
	*/
	int opApply(int delegate(ref size_t idx, ref Bson doc) del)
	{
		if( !m_data ) return 0;

		while( !m_data.empty ){
			auto idx = m_data.index;
			auto doc = m_data.front;
			m_data.popFront();
			if( auto ret = del(idx, doc) )
				return ret;
		}
		return 0;
	}
}


/**
	Internal class exposed through MongoCursor.
*/
private class MongoCursorData {
	private {
		int m_refCount = 1;
		MongoClient m_client;
		string m_collection;
		long m_cursor;
		int m_nret;
		int m_offset;
		size_t m_currentDoc = 0;
		Bson[] m_documents;
	}

	this(MongoClient client, string collection, int nret, Reply first_chunk)
	{
		m_client = client;
		m_collection = collection;
		m_cursor = first_chunk.cursor;
		m_nret = nret;
		handleReply(first_chunk);
	}

	@property bool empty()
	{
		if( m_currentDoc < m_documents.length )
			return false;
		if( m_cursor == 0 )
			return true;

		auto conn = m_client.lockConnection();
		auto reply = conn.getMore(m_collection, m_nret, m_cursor);
		handleReply(reply);
		return m_currentDoc >= m_documents.length;
	}

	@property size_t index()
	{
		enforce(!empty(), "Cursor has no more data.");
		return m_offset + m_currentDoc;
	}

	@property Bson front()
	{
		enforce(!empty(), "Cursor has no more data.");
		return m_documents[m_currentDoc];
	}

	void popFront()
	{
		m_currentDoc++;
	}

	private void destroy()
	{
		if( m_cursor == 0 ) return;
		auto conn = m_client.lockConnection();
		conn.killCursors((&m_cursor)[0 .. 1]);
		m_cursor = 0;
	}

	private void handleReply(Reply reply)
	{
		enforce(!(reply.flags & ReplyFlags.CursorNotFound), "Invalid cursor handle.");
		enforce(!(reply.flags & ReplyFlags.QueryFailure), "Query failed.");

		m_offset = reply.firstDocument;
		m_documents = reply.documents;
		m_currentDoc = 0;

		if( reply.cursor == 0 )
			destroy();
	}
}
