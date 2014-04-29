/**
	MongoCollection class

	Copyright: © 2012-2014 RejectedSoftware e.K.
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
		assert(m_client !is null, "Updating uninitialized MongoCollection.");
		auto conn = m_client.lockConnection();
		ubyte[256] selector_buf = void, update_buf = void;
		conn.update(m_fullPath, flags, serializeToBson(selector, selector_buf), serializeToBson(update, update_buf));
	}

	/**
	  Inserts new documents into the collection.

	  Throws: Exception if a DB communication error occured.
	  See_Also: $(LINK http://www.mongodb.org/display/DOCS/Inserting)
	 */
	void insert(T)(T document_or_documents, InsertFlags flags = InsertFlags.None)
	{
		assert(m_client !is null, "Inserting into uninitialized MongoCollection.");
		auto conn = m_client.lockConnection();
		Bson[] docs;
		Bson bdocs = serializeToBson(document_or_documents);
		if( bdocs.type == Bson.Type.Array ) docs = cast(Bson[])bdocs;
		else docs = (&bdocs)[0 .. 1];
		conn.insert(m_fullPath, flags, docs);
	}

	/**
	  Queries the collection for existing documents.

	  If no arguments are passed to find(), all documents of the collection will be returned.

	  See_Also: $(LINK http://www.mongodb.org/display/DOCS/Querying)
	 */
	MongoCursor!(T, R, U) find(R = Bson, T, U)(T query, U returnFieldSelector, QueryFlags flags = QueryFlags.None, int num_skip = 0, int num_docs_per_chunk = 0)
	{
		assert(m_client !is null, "Querying uninitialized MongoCollection.");
		return MongoCursor!(T, R, U)(m_client, m_fullPath, flags, num_skip, num_docs_per_chunk, query, returnFieldSelector);
	}

	/// ditto
	MongoCursor!(T, R, typeof(null)) find(R = Bson, T)(T query) { return find!R(query, null); }

	/// ditto
	MongoCursor!(Bson, R, typeof(null)) find(R = Bson)() { return find!R(Bson.emptyObject, null); }

	/** Queries the collection for existing documents.

		Returns:
			By default, a Bson value of the matching document is returned, or $(D Bson(null))
			when no document matched. For types R that are not Bson, the returned value is either
			of type $(D R), or of type $(Nullable!R), if $(D R) is not a reference/pointer type.
		
		Throws: Exception if a DB communication error or a query error occured.
		See_Also: $(LINK http://www.mongodb.org/display/DOCS/Querying)
	 */
	auto findOne(R = Bson, T, U)(T query, U returnFieldSelector, QueryFlags flags = QueryFlags.None)
	{
		import std.traits;
		import std.typecons;

		auto c = find!R(query, returnFieldSelector, flags, 0, 1);
		static if (is(R == Bson)) {
			foreach (doc; c) return doc;
			return Bson(null);
		} else static if (is(R == class) || isPointer!R || isDynamicArray!R || isAssociativeArray!R) {
			foreach (doc; c) return doc;
			return null;
		} else {
			foreach (doc; c) {
				Nullable!R ret;
				ret = doc;
				return ret;
			}
			return Nullable!R.init;
		}
	}
	/// ditto
	auto findOne(R = Bson, T)(T query) { return findOne!R(query, Bson(null)); }

	/**
	  Removes documents from the collection.

	  Throws: Exception if a DB communication error occured.
	  See_Also: $(LINK http://www.mongodb.org/display/DOCS/Removing)
	 */
	void remove(T)(T selector, DeleteFlags flags = DeleteFlags.None)
	{
		assert(m_client !is null, "Removnig from uninitialized MongoCollection.");
		auto conn = m_client.lockConnection();
		ubyte[256] selector_buf = void;
		conn.delete_(m_fullPath, flags, serializeToBson(selector, selector_buf));
	}

	/// ditto
	void remove()() { remove(Bson.emptyObject); }

	/**
	  Combines a modify and find operation to a single atomic operation.

	  Throws Exception if a DB communication error occured.
	  See_Also: $(LINK http://docs.mongodb.org/manual/reference/command/findAndModify)
	 */
	Bson findAndModify(T, U, V)(T query, U update, V returnFieldSelector)
	{
		static struct CMD {
			string findAndModify;
			T query;
			U update;
			V fields;
		}
		CMD cmd;
		cmd.findAndModify = m_name;
		cmd.query = query;
		cmd.update = update;
		cmd.fields = returnFieldSelector;
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
		static struct Empty {}
		static struct CMD {
			string count;
			T query;
			Empty fields;
		}

		CMD cmd;
		cmd.count = m_name;
		cmd.query = query;
		auto reply = database.runCommand(cmd);
		enforce(reply.ok.get!double == 1, "Count command failed.");
		return cast(ulong)reply.n.get!double;
	}

	/**
	  Calculates aggregate values for the data in a collection.

	  Params:
		pipeline = a sequence of data aggregation processes

	  Returns: an array of documents returned by the pipeline

	  Throws: Exception if a DB communication error occured

	  See_Also: $(LINK http://docs.mongodb.org/manual/reference/method/db.collection.aggregate)
	*/
	Bson aggregate(ARGS...)(ARGS pipeline) {
		static struct Pipeline {
			ARGS args;
		}
		static struct CMD {
			string aggregate;
			@asArray Nodes pipeline;
		}

		CMD cmd;
		cmd.aggregate = m_name;
		cmd.pipeline.args = pipeline;
		auto ret = database.runCommand(cmd);
		enforce(ret.ok.get!double == 1, "Aggregate command failed.");
		return ret.result;
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
