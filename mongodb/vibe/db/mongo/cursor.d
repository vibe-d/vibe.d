/**
	MongoDB cursor abstraction

	Copyright: © 2012-2014 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.cursor;

public import vibe.data.bson;
public import vibe.db.mongo.impl.crud;

import vibe.core.log;

import vibe.db.mongo.connection;
import vibe.db.mongo.client;

import core.time;
import std.array : array;
import std.algorithm : map, max, min, skipOver;
import std.exception;
import std.range : chain;


/**
	Represents a cursor for a MongoDB query.

	Use foreach( doc; cursor ) to iterate over the list of documents.

	This struct uses reference counting to destroy the underlying MongoDB cursor.
*/
struct MongoCursor(DocType = Bson) {
	private IMongoCursorData!DocType m_data;

	deprecated("Old (MongoDB <3.6) style cursor iteration no longer supported")
	package this(Q, S)(MongoClient client, string collection, QueryFlags flags, int nskip, int nret, Q query, S return_field_selector)
	{
		// TODO: avoid memory allocation, if possible
		m_data = new MongoQueryCursor!(Q, DocType, S)(client, collection, flags, nskip, nret, query, return_field_selector);
	}

	deprecated("Old (MongoDB <3.6) style cursor iteration no longer supported")
	package this(MongoClient client, string collection, long cursor, DocType[] existing_documents)
	{
		// TODO: avoid memory allocation, if possible
		m_data = new MongoGenericCursor!DocType(client, collection, cursor, existing_documents);
	}

	this(Q)(MongoClient client, string database, string collection, Q query, FindOptions options)
	{
		Bson command = Bson.emptyObject;
		command["find"] = Bson(collection);
		command["$db"] = Bson(database);
		static if (is(Q == Bson))
			command["filter"] = query;
		else
			command["filter"] = serializeToBson(query);

		MongoConnection conn = client.lockConnection();
		enforceWireVersionConstraints(options, conn.description.maxWireVersion);

		// https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/find_getmore_killcursors_commands.rst#mapping-op_query-behavior-to-the-find-command-limit-and-batchsize-fields
		bool singleBatch;
		if (!options.limit.isNull && options.limit.get < 0)
		{
			singleBatch = true;
			options.limit = -options.limit.get;
			options.batchSize = cast(int)options.limit.get;
		}
		if (!options.batchSize.isNull && options.batchSize.get < 0)
		{
			singleBatch = true;
			options.batchSize = -options.batchSize.get;
		}
		if (singleBatch)
			command["singleBatch"] = Bson(true);

		// https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/find_getmore_killcursors_commands.rst#semantics-of-maxtimems-for-a-driver
		bool allowMaxTime = true;
		if (options.cursorType == CursorType.tailable
			|| options.cursorType == CursorType.tailableAwait)
			command["tailable"] = Bson(true);
		else
		{
			options.maxAwaitTimeMS.nullify();
			allowMaxTime = false;
		}

		if (options.cursorType == CursorType.tailableAwait)
			command["awaitData"] = Bson(true);
		else
		{
			options.maxAwaitTimeMS.nullify();
			allowMaxTime = false;
		}

		// see table: https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/find_getmore_killcursors_commands.rst#find
		auto optionsBson = serializeToBson(options);
		foreach (string key, value; optionsBson.byKeyValue)
			command[key] = value;

		this(client, command,
			options.batchSize.isNull ? 0 : options.batchSize.get,
			!options.maxAwaitTimeMS.isNull ? options.maxAwaitTimeMS.get.msecs
				: allowMaxTime && !options.maxTimeMS.isNull ? options.maxTimeMS.get.msecs
				: Duration.max);
	}

	this(MongoClient client, Bson command, int batchSize = 0, Duration getMoreMaxTime = Duration.max)
	{
		// TODO: avoid memory allocation, if possible
		m_data = new MongoFindCursor!DocType(client, command, batchSize, getMoreMaxTime);
	}

	this(this)
	{
		if( m_data ) m_data.refCount++;
	}

	~this() @safe
	{
		import core.memory : GC;

		if (m_data && --m_data.refCount == 0) {
			if (m_data.alive) {
				// avoid InvalidMemoryOperation errors in case the cursor was
				// leaked to the GC
				if(GC.inFinalizer) {
					logError("MongoCursor instance that has not been fully processed leaked to the GC!");
				} else {
					try m_data.killCursors();
					catch (MongoException e) {
						logWarn("MongoDB failed to kill cursors: %s", e.msg);
						logDiagnostic("%s", (() @trusted => e.toString)());
					}
				}
			}
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

		This method must be called before starting to iterate, or an exception
		will be thrown. If multiple calls to $(D sort()) are issued, only
		the last one will have an effect.

		Params:
			order = A BSON object convertible value that defines the sort order
				of the result. This BSON object must be structured according to
				the MongoDB documentation (see below).

		Returns: Reference to the modified original cursor instance.

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

		This method must be called before beginning iteration in order to have
		effect. If multiple calls to limit() are made, the one with the lowest
		limit will be chosen.

		Params:
			count = The maximum number number of documents to return. A value
				of zero means unlimited.

		Returns: the same cursor

		See_Also: $(LINK http://docs.mongodb.org/manual/reference/method/cursor.limit)
	*/
	MongoCursor limit(long count)
	{
		m_data.limit(count);
		return this;
	}

	/**
		Skips a given number of elements at the beginning of the cursor.

		This method must be called before beginning iteration in order to have
		effect. If multiple calls to skip() are made, the one with the maximum
		number will be chosen.

		Params:
			count = The number of documents to skip.

		Returns: the same cursor

		See_Also: $(LINK http://docs.mongodb.org/manual/reference/method/cursor.skip)
	*/
	MongoCursor skip(long count)
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
				coll.insertOne(["i": i]);

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
			private IMongoCursorData!DocType data;
			@property bool empty() { return data.empty; }
			@property Tuple!(long, DocType) front() { return tuple(data.index, data.front); }
			void popFront() { data.popFront(); }
		}
		return Rng(m_data);
	}
}

/// Actual iteration implementation details for MongoCursor. Abstracted using an
/// interface because we still have code for legacy (<3.6) MongoDB servers,
/// which may still used with the old legacy overloads.
private interface IMongoCursorData(DocType) {
	@property bool alive() @safe nothrow;
	bool empty() @safe; /// Range implementation
	long index() @safe; /// Range implementation
	DocType front() @safe; /// Range implementation
	void popFront() @safe; /// Range implementation
	/// Before iterating, specify a MongoDB sort order
	void sort(Bson order) @safe;
	/// Before iterating, specify maximum number of returned items
	void limit(long count) @safe;
	/// Before iterating, skip the specified number of items (when sorted)
	void skip(long count) @safe;
	/// Kills the MongoDB cursor, further iteration attempts will result in
	/// errors. Call this in the destructor.
	void killCursors() @safe;
	/// Define an reference count property on the class, which is returned by
	/// reference with this method.
	ref int refCount() @safe;
}


/**
	Deprecated query internals exposed through MongoCursor.
*/
private deprecated abstract class LegacyMongoCursorData(DocType) : IMongoCursorData!DocType {
	private {
		int m_refCount = 1;
		MongoClient m_client;
		string m_collection;
		long m_cursor;
		long m_nskip;
		int m_nret;
		Bson m_sort = Bson(null);
		int m_offset;
		size_t m_currentDoc = 0;
		DocType[] m_documents;
		bool m_iterationStarted = false;
		long m_limit = 0;
	}

	@property bool alive() @safe nothrow { return m_cursor != 0; }

	final bool empty()
	@safe {
		if (!m_iterationStarted) startIterating();
		if (m_limit > 0 && index >= m_limit) {
			killCursors();
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

	final long index()
	@safe {
		return m_offset + m_currentDoc;
	}

	final DocType front()
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

	final void limit(long count)
	@safe {
		// A limit() value of 0 (e.g. “.limit(0)”) is equivalent to setting no limit.
		if (count > 0) {
			if (m_nret == 0 || m_nret > count)
				m_nret = cast(int)min(count, 1024);

			if (m_limit == 0 || m_limit > count)
				m_limit = count;
		}
	}

	final void skip(long count)
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

	final void killCursors()
	@safe {
		if (m_cursor == 0) return;
		auto conn = m_client.lockConnection();
		conn.killCursors(m_collection, () @trusted { return (&m_cursor)[0 .. 1]; } ());
		m_cursor = 0;
	}

	final void handleReply(long cursor, ReplyFlags flags, int first_doc, int num_docs)
	{
		enforce!MongoDriverException(!(flags & ReplyFlags.CursorNotFound), "Invalid cursor handle.");
		enforce!MongoDriverException(!(flags & ReplyFlags.QueryFailure), "Query failed. Does the database exist?");

		m_cursor = cursor;
		m_offset = first_doc;
		m_documents.length = num_docs;
		m_currentDoc = 0;
	}

	final void handleDocument(size_t idx, ref DocType doc)
	{
		m_documents[idx] = doc;
	}

	final ref int refCount() { return m_refCount; }
}

/**
	Find + getMore internals exposed through MongoCursor. Unifies the old
	LegacyMongoCursorData approach, so it can be used both for find queries and
	for custom commands.
*/
private class MongoFindCursor(DocType) : IMongoCursorData!DocType {
	private {
		int m_refCount = 1;
		MongoClient m_client;
		Bson m_findQuery;
		string m_database;
		string m_ns;
		string m_collection;
		long m_cursor;
		int m_batchSize;
		Duration m_maxTime;
		long m_totalReceived;
		size_t m_readDoc;
		size_t m_insertDoc;
		DocType[] m_documents;
		bool m_iterationStarted = false;
		long m_queryLimit;
	}

	this(MongoClient client, Bson command, int batchSize = 0, Duration getMoreMaxTime = Duration.max)
	{
		m_client = client;
		m_findQuery = command;
		m_batchSize = batchSize;
		m_maxTime = getMoreMaxTime;
		m_database = command["$db"].opt!string;
	}

	@property bool alive() @safe nothrow { return m_cursor != 0; }

	bool empty()
	@safe {
		if (!m_iterationStarted) startIterating();
		if (m_queryLimit > 0 && index >= m_queryLimit) {
			killCursors();
			return true;
		}
		if( m_readDoc < m_documents.length )
			return false;
		if( m_cursor == 0 )
			return true;

		auto conn = m_client.lockConnection();
		conn.getMore!DocType(m_cursor, m_database, m_collection, m_batchSize,
			&handleReply, &handleDocument, m_maxTime);
		return m_readDoc >= m_documents.length;
	}

	final long index()
	@safe {
		assert(m_totalReceived >= m_documents.length);
		return m_totalReceived - m_documents.length + m_readDoc;
	}

	final DocType front()
	@safe {
		if (!m_iterationStarted) startIterating();
		assert(!empty(), "Cursor has no more data.");
		return m_documents[m_readDoc];
	}

	final void sort(Bson order)
	@safe {
		assert(!m_iterationStarted, "Cursor cannot be modified after beginning iteration");
		m_findQuery["sort"] = order;
	}

	final void limit(long count)
	@safe {
		assert(!m_iterationStarted, "Cursor cannot be modified after beginning iteration");
		m_findQuery["limit"] = Bson(count);
	}

	final void skip(long count)
	@safe {
		assert(!m_iterationStarted, "Cursor cannot be modified after beginning iteration");
		m_findQuery["skip"] = Bson(count);
	}

	final void popFront()
	@safe {
		if (!m_iterationStarted) startIterating();
		assert(!empty(), "Cursor has no more data.");
		m_readDoc++;
	}

	private void startIterating()
	@safe {
		auto conn = m_client.lockConnection();
		m_totalReceived = 0;
		m_queryLimit = m_findQuery["limit"].opt!long(0);
		conn.startFind!DocType(m_findQuery, &handleReply, &handleDocument);
		m_iterationStarted = true;
	}

	final void killCursors()
	@safe {
		if (m_cursor == 0) return;
		auto conn = m_client.lockConnection();
		conn.killCursors(m_ns, () @trusted { return (&m_cursor)[0 .. 1]; } ());
		m_cursor = 0;
	}

	final void handleReply(long id, string ns, size_t count)
	{
		m_cursor = id;
		m_ns = ns;
		// The qualified collection name is reported here, but when requesting
		// data, we need to send the database name and the collection name
		// separately, so we have to remove the database prefix:
		ns.skipOver(m_database.chain("."));
		m_collection = ns;
		m_documents.length = count;
		m_readDoc = 0;
		m_insertDoc = 0;
	}

	final void handleDocument(ref DocType doc)
	{
		m_documents[m_insertDoc++] = doc;
		m_totalReceived++;
	}

	final ref int refCount() { return m_refCount; }
}

/**
	Internal class implementing MongoCursorData for find queries
 */
private deprecated class MongoQueryCursor(Q, R, S) : LegacyMongoCursorData!R {
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

		conn.query!R(m_collection, m_flags, cast(int)m_nskip, cast(int)m_nret, full_query, selector, &handleReply, &handleDocument);

		m_iterationStarted = true;
	}
}

/**
	Internal class implementing MongoCursorData for already initialized generic cursors
 */
private deprecated class MongoGenericCursor(DocType) : LegacyMongoCursorData!DocType {
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
