/**
	MongoDB cursor abstraction

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.cursor;

public import vibe.data.bson;

import vibe.db.mongo.connection;
import vibe.db.mongo.db;

import std.exception;


/**
	Represents a cursor for a MongoDB query.

	Use foreach( doc; cursor ) to iterate over the list of documents.

	This struct uses reference counting to destroy the underlying MongoDB cursor.
*/
struct MongoCursor {
	private MongoCursorData m_data;

	package this(MongoDB db, string collection, int nret, Reply first_chunk)
	{
		m_data = new MongoCursorData(db, collection, nret, first_chunk);
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
	bool empty() { return m_data ? !m_data.hasNext() : true; }

	/**
		Iterates over all remaining documents.

		Throws: An exception if there is a query or communication error.
	*/
	int opApply(int delegate(ref Bson doc) del)
	{
		if( !m_data ) return 0;

		while( m_data.hasNext() ){
			auto doc = m_data.getNext();
			if( auto ret = del(doc) )
				return ret;
		}
		return 0;
	}

	/**
		Iterates over all remaining documents.

		Throws: An exception if there is a query or communication error.
	*/
	int opApply(int delegate(ref size_t idx, ref Bson doc) del)
	{
		if( !m_data ) return 0;

		while( m_data.hasNext() ){
			auto idx = m_data.getNextIndex();
			auto doc = m_data.getNext();
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
		MongoDB m_db;
		string m_collection;
		long m_cursor;
		int m_nret;
		int m_offset;
		size_t m_currentDoc = 0;
		Bson[] m_documents;
	}

	this(MongoDB db, string collection, int nret, Reply first_chunk)
	{
		m_db = db;
		m_collection = collection;
		m_cursor = first_chunk.cursor;
		m_nret = nret;
		handleReply(first_chunk);
	}

	bool hasNext(){
		if( m_currentDoc < m_documents.length )
			return true;
		if( m_cursor == 0 )
			return false;

		auto conn = m_db.lockConnection();
		auto reply = conn.getMore(m_collection, m_nret, m_cursor);
		handleReply(reply);
		return m_currentDoc < m_documents.length;
	}

	size_t getNextIndex(){
		enforce(hasNext(), "Cursor has no more data.");
		return m_offset + m_currentDoc;
	}

	Bson getNext(){
		enforce(hasNext(), "Cursor has no more data.");
		return m_documents[m_currentDoc++];
	}

	private void destroy()
	{
		if( m_cursor == 0 ) return;
		auto conn = m_db.lockConnection();
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

		if( reply.documents.length == 0 ){
			destroy();
		}
	}
}