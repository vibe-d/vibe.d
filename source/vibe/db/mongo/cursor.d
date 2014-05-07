/**
	MongoDB cursor abstraction

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.cursor;

public import vibe.data.bson;

import vibe.db.mongo.connection;
import vibe.db.mongo.client;

import std.array : array;
import std.algorithm : map, min;
import std.exception;


/**
	Represents a cursor for a MongoDB query.

	Use foreach( doc; cursor ) to iterate over the list of documents.

	This struct uses reference counting to destroy the underlying MongoDB cursor.
*/
struct MongoCursor(Q = Bson, R = Bson, S = Bson) {
	private MongoCursorData!(Q, R, S) m_data;

	package this(MongoClient client, string collection, QueryFlags flags, int nskip, int nret, Q query, S return_field_selector)
	{
		// TODO: avoid memory allocation, if possible
		m_data = new MongoCursorData!(Q, R, S)(client, collection, flags, nskip, nret, query, return_field_selector);
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
		Returns true if there are no more documents for this cursor.

		Throws: An exception if there is a query or communication error.
	*/
	@property bool empty() { return m_data ? m_data.empty() : true; }

	/**
		Returns the current document of the response.

		Use empty and popFront to iterate over the list of documents using an
		input range interface. Note that calling this function is only allowed
		if empty returns false.
	*/
	@property R front() { return m_data.front; }

	/**
		Controls the order that the query returns matching documents.

		This method must be called before beginning iteration, otherwise exeption will be thrown.
		Only the last sort() applied to cursor has any effect.

		Params:
			order = a document that defines the sort order of the result set

		Returns: the same cursor

		Throws:
			An exception if there is a query or communication error.
			Also throws if the method was called after beginning of iteration.

		See_Also: $(LINK http://docs.mongodb.org/manual/reference/method/cursor.sort)
	*/
	MongoCursor sort(T)(T order) {
		m_data.sort(serializeToBson(order));
		return this;
	}

	/**
		Limits the maximum documents that cursor returns.

		This method must be called before beginnig iteration in order to have
		effect. If multiple calls to limit() are made, the one with the lowest
		limit will be chosen.

		Params:
			count = The maximum number number of documents to return. A value
				of zero means unlimited.

		Returns: the same cursor

		See_Also: $(LINK http://docs.mongodb.org/manual/reference/method/cursor.limit)
	*/
	MongoCursor limit(size_t count) {
		m_data.limit(count);
		return this;
	}

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
	int opApply(int delegate(ref R doc) del)
	{
		if (!m_data) return 0;

		while (!m_data.empty) {
			auto doc = m_data.front;
			m_data.popFront();
			if (auto ret = del(doc))
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
	int opApply(int delegate(ref size_t idx, ref R doc) del)
	{
		if (!m_data) return 0;

		while (!m_data.empty) {
			auto idx = m_data.index;
			auto doc = m_data.front;
			m_data.popFront();
			if (auto ret = del(idx, doc))
				return ret;
		}
		return 0;
	}
}


/**
	Internal class exposed through MongoCursor.
*/
private class MongoCursorData(Q, R, S) {
	private {
		int m_refCount = 1;
		MongoClient m_client;
		string m_collection;
		long m_cursor;
		QueryFlags m_flags;
		int m_nskip;
		int m_nret;
		Q m_query;
		S m_returnFieldSelector;
		Bson m_sort = Bson(null);
		int m_offset;
		size_t m_currentDoc = 0;
		R[] m_documents;
		bool m_iterationStarted = false;
		size_t m_limit = 0;
		bool m_needDestroy = false;
	}

	this(MongoClient client, string collection, QueryFlags flags, int nskip, int nret, Q query, S return_field_selector)
	{
		m_client = client;
		m_collection = collection;
		m_flags = flags;
		m_nskip = nskip;
		m_nret = nret;
		m_query = query;
		m_returnFieldSelector = return_field_selector;
	}

	@property bool empty()
	{
		if (!m_iterationStarted) startIterating();
		if (m_limit > 0 && m_currentDoc >= m_limit) {
			destroy();
			return true;
		}
		if( m_currentDoc < m_documents.length )
			return false;
		if( m_cursor == 0 )
			return true;

		auto conn = m_client.lockConnection();
		conn.getMore!R(m_collection, m_nret, m_cursor, &handleReply, &handleDocument);
		return m_currentDoc >= m_documents.length;
	}

	@property size_t index()
	{
		return m_offset + m_currentDoc;
	}

	@property R front()
	{
		if (!m_iterationStarted) startIterating();
		assert(!empty(), "Cursor has no more data.");
		return m_documents[m_currentDoc];
	}

	void sort(Bson order)
	{
		assert(!m_iterationStarted, "Cursor cannot be modified after beginning iteration");
		m_sort = order;
	}

	void limit(size_t count) {
		// A limit() value of 0 (e.g. “.limit(0)”) is equivalent to setting no limit.
		if (count > 0) {
			if (m_nret == 0 || m_nret > count)
				m_nret = min(count, 1024);

			if (m_limit == 0 || m_limit > count)
				m_limit = count;
		}
	}

	void popFront()
	{
		if (!m_iterationStarted) startIterating();
		assert(!empty(), "Cursor has no more data.");
		m_currentDoc++;
	}

	private void startIterating() {
		auto conn = m_client.lockConnection();

		ubyte[256] selector_buf = void;
		ubyte[256] query_buf = void;

		Bson selector = serializeToBson(m_returnFieldSelector, selector_buf);

		Bson query;
		static if (is(Q == Bson)) {
			query = m_query;
		} else {
			query = serializeToBson(m_query, query_buf);
		}

		Bson full_query;

		if (!query["query"].isNull() || !query["$query"].isNull()) {
			// TODO: emit deprecation warning
			full_query = query;
		} else {
			full_query = Bson.emptyObject;
			full_query["$query"] = query;
		}

		if (!m_sort.isNull()) full_query["orderby"] = m_sort;

		conn.query!R(m_collection, m_flags, m_nskip, m_nret, full_query, selector, &handleReply, &handleDocument);

		m_iterationStarted = true;
	}

	private void destroy()
	{
		if (m_cursor == 0) return;
		auto conn = m_client.lockConnection();
		conn.killCursors((&m_cursor)[0 .. 1]);
		m_cursor = 0;
	}

	private void handleReply(long cursor, ReplyFlags flags, int first_doc, int num_docs)
	{
		// FIXME: use MongoDB exceptions
		enforce(!(flags & ReplyFlags.CursorNotFound), "Invalid cursor handle.");
		enforce(!(flags & ReplyFlags.QueryFailure), "Query failed.");

		m_cursor = cursor;
		m_offset = first_doc;
		m_documents.length = num_docs;
		m_currentDoc = 0;
	}

	private void handleDocument(size_t idx, ref R doc)
	{
		m_documents[idx] = doc;
	}
}
