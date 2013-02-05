/**
  MongoCollection class

Copyright: © 2012 RejectedSoftware e.K.
License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
Authors: Sönke Ludwig
 */
module vibe.db.mongo.collection;

public import vibe.db.mongo.cursor;
public import vibe.db.mongo.connection;

import vibe.db.mongo.client;

import vibe.core.log;

import std.algorithm : countUntil, find;
import std.array;
import std.conv;
import std.exception;
import std.string;


/**
  Represents a single collection inside a MongoDB.

  All methods take arbitrary types for Bson arguments. serializeToBson() is implicitly called on
  them before they are send to the database. The following example shows some possible ways
  to specify objects.

Examples:

---
MongoClient client = connectMongoDB("127.0.0.1");
MongoCollection users = client.getCollection("myapp.users");

// canonical version using a Bson object
users.insert(Bson(["name": Bson("admin"), "password": Bson("secret")]));

// short version using a string[string] AA that is automatically
// serialized to Bson
users.insert(["name": "admin", "password": "secret"]);

// BSON specific types are also serialized automatically
BsonObjectId uid = ...;
Bson usr = users.find(["_id": uid]);

// JSON is another possibility
Json jusr = parseJson("{\"name\": \"admin\", \"password\": \"secret\"}");
users.insert(jusr);
---
 */
struct MongoCollection {
	private {
		MongoClient m_client;
		MongoDatabase m_db;
		string m_name;
		string m_fullPath;
	}

	this(MongoClient client, string fullPath)
	{
		assert(client !is null);
		m_client = client;

		auto dotidx = fullPath.indexOf('.');
		assert(dotidx > 0, "The collection name passed to MongoCollection must be of the form \"dbname.collectionname\".");

		m_fullPath = fullPath;
		m_db = m_client.getDatabase(fullPath[0 .. dotidx]);
		m_name = fullPath[dotidx+1 .. $];
	}

	this(ref MongoDatabase db, string name)
	{ 
		assert(db.client !is null);
		m_client = db.client;
		m_fullPath = db.name ~ "." ~ name;
		m_db = db;
		m_name = name;
	}

	/**
	  Returns: Root database to which this collection belongs.
	 */
	@property MongoDatabase database() { return m_db; }

	/**
	  Returns: Name of this collection (excluding the database name).
	 */
	@property string name() const { return m_name; }

	/**
	  Performs an update operation on documents matching 'selector', updating them with 'update'.

	  Throws: Exception if a DB communication error occured.
	  See_Also: $(LINK http://www.mongodb.org/display/DOCS/Updating)
	 */
	void update(T, U)(T selector, U update, UpdateFlags flags = UpdateFlags.None)
	{
		auto conn = m_client.lockConnection();
		conn.update(m_fullPath, flags, serializeToBson(selector), serializeToBson(update));
	}

	/**
	  Inserts new documents into the collection.

	  Throws: Exception if a DB communication error occured.
	  See_Also: $(LINK http://www.mongodb.org/display/DOCS/Inserting)
	 */
	void insert(T)(T document_or_documents, InsertFlags flags = InsertFlags.None)
	{
		auto conn = m_client.lockConnection();
		Bson[] docs;
		Bson bdocs = serializeToBson(document_or_documents);
		if( bdocs.type == Bson.Type.Array ) docs = cast(Bson[])bdocs;
		else docs ~= bdocs;
		conn.insert(m_fullPath, flags, docs);
	}

	/**
	  Queries the collection for existing documents.

	  If no arguments are passed to find(), all documents of the collection will be returned.

	  Throws: Exception if a DB communication error or a query error occured.
	  See_Also: $(LINK http://www.mongodb.org/display/DOCS/Querying)
	 */
	MongoCursor find(T, U)(T query, U returnFieldSelector, QueryFlags flags = QueryFlags.None, int num_skip = 0, int num_docs_per_chunk = 0)
	{
		auto conn = m_client.lockConnection();
		Reply reply;
		static if( is(typeof(returnFieldSelector is null)) )
			reply = conn.query(m_fullPath, flags, num_skip, num_docs_per_chunk, serializeToBson(query), returnFieldSelector is null ? Bson(null) : serializeToBson(returnFieldSelector));
		else 
			reply = conn.query(m_fullPath, flags, num_skip, num_docs_per_chunk, serializeToBson(query), serializeToBson(returnFieldSelector));
		return MongoCursor(m_client, m_fullPath, num_docs_per_chunk, reply);
	}

	/// ditto
	MongoCursor find(T)(T query) { return find(query, null); }

	/// ditto
	MongoCursor find()() { return find(Bson.EmptyObject, null); }

	/**
	  Queries the collection for existing documents.

	  Returns: the first match or null
	  Throws: Exception if a DB communication error or a query error occured.
	  See_Also: $(LINK http://www.mongodb.org/display/DOCS/Querying)
	 */
	Bson findOne(T, U)(T query, U returnFieldSelector, QueryFlags flags = QueryFlags.None)
	{
		auto c = find(query, returnFieldSelector, flags, 0, 1);
		foreach( doc; c ) return doc;
		return Bson(null);
	}
	/// ditto
	Bson findOne(T)(T query)
	{
		auto c = find(query, null, QueryFlags.None, 0, 1);
		foreach( doc; c ) return doc;
		return Bson(null);
	}

	/**
	  Removes documents from the collection.

	  Throws: Exception if a DB communication error occured.
	  See_Also: $(LINK http://www.mongodb.org/display/DOCS/Removing)
	 */
	void remove(T)(T selector, DeleteFlags flags = DeleteFlags.None)
	{
		auto conn = m_client.lockConnection();
		conn.delete_(m_fullPath, flags, serializeToBson(selector));
	}

	/// ditto
	void remove()() { remove(Bson.EmptyObject); }

	/**
	  Combines a modify and find operation to a single atomic operation.

	  Throws Exception if a DB communication error occured.
	  See_Also: $(LINK http://docs.mongodb.org/manual/reference/command/findAndModify)
	 */
	Bson findAndModify(T, U, V)(T query, U update, V returnFieldSelector)
	{
		Bson cmd = Bson.EmptyObject;
		cmd["findAndModify"] = Bson(m_name);
		cmd["query"] = serializeToBson(query);
		cmd["update"] = serializeToBson(update);
		if( returnFieldSelector != null )
			cmd["fields"] = serializeToBson(returnFieldSelector);
		auto ret = database.runCommand(cmd);
		if( !ret.ok.get!double ) throw new Exception("findAndModify failed.");
		return ret.value;
	}

	/// ditto
	Bson findAndModify(T, U)(T query, U update)
	{
		return findAndModify(query, update, null);
	}

	/**
	  Counts the results of the specified query expression.

	  Throws Exception if a DB communication error occured.
See_Also: $(LINK http://www.mongodb.org/display/DOCS/Advanced+Queries#AdvancedQueries-{{count%28%29}})
	 */
	ulong count(T)(T query)
	{
		Bson cmd = Bson.EmptyObject;
		cmd["count"] = Bson(m_name);
		cmd["query"] = serializeToBson(query);
		cmd["fields"] = Bson.EmptyObject;
		auto reply = database.runCommand(cmd);
		enforce(reply.ok.get!double == 1, "Count command failed.");
		return cast(ulong)reply.n.get!double;
	}

	void ensureIndex(int[string] field_orders, IndexFlags flags = IndexFlags.None)
	{
		// TODO: support 2d indexes

		auto indexname = appender!string();
		bool first = true;
		foreach( f, d; field_orders ){
			if( !first ) indexname.put('_');
			else first = false;
			indexname.put(f);
			indexname.put('_');
			indexname.put(to!string(d));
		}

		Bson[string] doc;
		doc["v"] = 1;
		doc["key"] = serializeToBson(field_orders);
		doc["ns"] = m_fullPath;
		doc["name"] = indexname.data;
		if( flags & IndexFlags.Unique ) doc["unique"] = true;
		if( flags & IndexFlags.DropDuplicates ) doc["dropDups"] = true;
		if( flags & IndexFlags.Background ) doc["background"] = true;
		if( flags & IndexFlags.Sparse ) doc["sparse"] = true;
		database["system.indexes"].insert(doc);
	}

	void dropIndex(string name)
	{
		assert(false);
	}
}

enum IndexFlags {
	None = 0,
	Unique = 1<<0,
	DropDuplicates = 1<<2,
	Background = 1<<3,
	Sparse = 1<<4
}
