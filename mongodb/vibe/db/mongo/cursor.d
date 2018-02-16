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
import std.algorithm : map, max, min;
import std.exception;

deprecated alias MongoCursor(Q, R = Bson, S = Bson) = MongoCursor!R;

/**
	Represents a cursor for a MongoDB query.

	Use foreach( doc; cursor ) to iterate over the list of documents.

	This struct uses reference counting to destroy the underlying MongoDB cursor.
*/
struct MongoCursor(DocType = Bson) {
	private MongoCursorData!DocType m_data;

	package this(Q, S)(MongoClient client, string collection, QueryFlags flags, int nskip, int nret, Q query, S return_field_selector)
	{
		// TODO: avoid memory allocation, if possible
		m_data = new MongoFindCursor!(Q, DocType, S)(client, collection, flags, nskip, nret, query, return_field_selector);
	}

	package this(MongoClient client, string collection, long cursor, DocType[] existing_documents)
	{
		// TODO: avoid memory allocation, if possible
		m_data = new MongoGenericCursor!DocType(client, collection, cursor, existing_documents);
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
	@property DocType front() { return m_data.front; }

	/**
		Controls the order in which the query returns matching documents.

		This method must be called before starting to iterate, or an exeption
		will be thrown. If multiple calls to $(D sort()) are issued, only
		the last one will have an effect.

		Params:
			order = A BSON object convertible value that defines the sort order
				of the result. This BSON object must be structured according to
				the MongoDB documentation (see below).

		Returns: Reference to the modified original curser instance.

		Throws:
			An exception if there is a query or communication error.
			Also throws if the method was called after beginning of iteration.

		See_Also: $(LINK http://docs.mongodb.org/manual/reference/method/cursor.sort)
	*/
	MongoCursor sort(T)(T order)
	{
		m_data.sort(() @trusted { return serializeToBson(order); } ());
		return this;
	}

	///
	@safe unittest {
		import vibe.core.log;
		import vibe.db.mongo.mongo;

		void test()
		@safe {
			auto db = connectMongoDB("127.0.0.1").getDatabase("test");
			auto coll = db["testcoll"];

			// find all entries in reverse date order
			foreach (entry; coll.find().sort(["date": -1]))
				() @safe { logInfo("Entry: %s", entry); } ();

			// the same, but using a struct to avoid memory allocations
			static struct Order { int date; }
			foreach (entry; coll.find().sort(Order(-1)))
				logInfo("Entry: %s", entry);
		}
	}

	/**
		Limits the number of documents that the cursor returns.

		This method must be called before beginnig iteration in order to have
		effect. If multiple calls to limit() are made, the one with the lowest
		limit will be chosen.

		Params:
			count = The maximum number number of documents to return. A value
				of zero means unlimited.

		Returns: the same cursor

		See_Also: $(LINK http://docs.mongodb.org/manual/reference/method/cursor.limit)
	*/
	MongoCursor limit(size_t count)
	{
		m_data.limit(count);
		return this;
	}

	/**
		Skips a given number of elements at the beginning of the cursor.

		This method must be called before beginnig iteration in order to have
		effect. If multiple calls to skip() are made, the one with the maximum
		number will be chosen.

		Params:
			count = The number of documents to skip.

		Returns: the same cursor

		See_Also: $(LINK http://docs.mongodb.org/manual/reference/method/cursor.skip)
	*/
	MongoCursor skip(int count)
	{
		m_data.skip(count);
		return this;
	}

	@safe unittest {
		import vibe.core.log;
		import vibe.db.mongo.mongo;

		void test()
		@safe {
			auto db = connectMongoDB("127.0.0.1").getDatabase("test");
			auto coll = db["testcoll"];

			try { coll.drop(); } catch (Exception) {}

			for (int i = 0; i < 10000; i++)
				coll.insert(["i": i]);

			static struct Order { int i; }
			auto data = coll.find().sort(Order(1)).skip(2000).limit(2000).array;

			assert(data.length == 2000);
			assert(data[0]["i"].get!int == 2000);
			assert(data[$ - 1]["i"].get!int == 3999);
		}
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
	auto byPair()
	{
		import std.typecons : Tuple, tuple;
		static struct Rng {
			private MongoCursorData!DocType data;
			@property bool empty() { return data.empty; }
			@property Tuple!(size_t, DocType) front() { return tuple(data.index, data.front); }
			void popFront() { data.popFront(); }
		}
		return Rng(m_data);
	}
}


/**
	Internal class exposed through MongoCursor.
*/
private abstract class MongoCursorData(DocType) {
	private {
		int m_refCount = 1;
		MongoClient m_client;
		string m_collection;
		long m_cursor;
		int m_nskip;
		int m_nret;
		Bson m_sort = Bson(null);
		int m_offset;
		size_t m_currentDoc = 0;
		DocType[] m_documents;
		bool m_iterationStarted = false;
		size_t m_limit = 0;
		bool m_needDestroy = false;
	}

	final @property bool empty()
	@safe {
		if (!m_iterationStarted) startIterating();
		if (m_limit > 0 && index >= m_limit) {
			destroy();
			return true;
		}
		if( m_currentDoc < m_documents.length )
			return false;
		if( m_cursor == 0 )
			return true;

		auto conn = m_client.lockConnection();
		conn.getMore!DocType(m_collection, m_nret, m_cursor, &handleReply, &handleDocument);
		return m_currentDoc >= m_documents.length;
	}

	final @property size_t index()
	@safe {
		return m_offset + m_currentDoc;
	}

	final @property DocType front()
	@safe {
		if (!m_iterationStarted) startIterating();
		assert(!empty(), "Cursor has no more data.");
		return m_documents[m_currentDoc];
	}

	final void sort(Bson order)
	@safe {
		assert(!m_iterationStarted, "Cursor cannot be modified after beginning iteration");
		m_sort = order;
	}

	final void limit(size_t count)
	@safe {
		// A limit() value of 0 (e.g. “.limit(0)”) is equivalent to setting no limit.
		if (count > 0) {
			if (m_nret == 0 || m_nret > count)
				m_nret = min(count, 1024);

			if (m_limit == 0 || m_limit > count)
				m_limit = count;
		}
	}

	final void skip(int count)
	@safe {
		// A skip() value of 0 (e.g. “.skip(0)”) is equivalent to setting no skip.
		m_nskip = max(m_nskip, count);
	}

	final void popFront()
	@safe {
		if (!m_iterationStarted) startIterating();
		assert(!empty(), "Cursor has no more data.");
		m_currentDoc++;
	}

	abstract void startIterating() @safe;

	final private void destroy()
	@safe {
		if (m_cursor == 0) return;
		auto conn = m_client.lockConnection();
		conn.killCursors(() @trusted { return (&m_cursor)[0 .. 1]; } ());
		m_cursor = 0;
	}

	final private void handleReply(long cursor, ReplyFlags flags, int first_doc, int num_docs)
	{
		enforce!MongoDriverException(!(flags & ReplyFlags.CursorNotFound), "Invalid cursor handle.");
		enforce!MongoDriverException(!(flags & ReplyFlags.QueryFailure), "Query failed. Does the database exist?");

		m_cursor = cursor;
		m_offset = first_doc;
		m_documents.length = num_docs;
		m_currentDoc = 0;
	}

	final private void handleDocument(size_t idx, ref DocType doc)
	{
		m_documents[idx] = doc;
	}
}

/**
	Internal class implementing MongoCursorData for find queries
 */
private class MongoFindCursor(Q, R, S) : MongoCursorData!R {
	private {
		QueryFlags m_flags;
		Q m_query;
		S m_returnFieldSelector;
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

	override void startIterating()
	@safe {
		auto conn = m_client.lockConnection();

		ubyte[256] selector_buf = void;
		ubyte[256] query_buf = void;

		Bson selector = () @trusted { return serializeToBson(m_returnFieldSelector, selector_buf); } ();

		Bson query;
		static if (is(Q == Bson)) {
			query = m_query;
		} else {
			query = () @trusted { return serializeToBson(m_query, query_buf); } ();
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
}

/**
	Internal class implementing MongoCursorData for already initialized generic cursors
 */
private class MongoGenericCursor(DocType) : MongoCursorData!DocType {
	this(MongoClient client, string collection, long cursor, DocType[] existing_documents)
	{
		m_client = client;
		m_collection = collection;
		m_cursor = cursor;
		m_iterationStarted = true;
		m_documents = existing_documents;
	}

	override void startIterating()
	@safe {
		assert(false, "Calling startIterating on an opaque already initialized cursor");
	}
}
