/**
	MongoCollection class

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.collection;

public import vibe.db.mongo.cursor;
public import vibe.db.mongo.connection;

import vibe.core.log;
import vibe.db.mongo.client;

import core.time;
import std.algorithm : countUntil, find;
import std.array;
import std.conv;
import std.exception;
import std.string;
import std.typecons : Tuple, tuple;


/**
  Represents a single collection inside a MongoDB.

  All methods take arbitrary types for Bson arguments. serializeToBson() is implicitly called on
  them before they are send to the database. The following example shows some possible ways
  to specify objects.
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

	  Note that if the `_id` field of the document(s) is not set, typically
	  using `BsonObjectID.generate()`, the server will generate IDs
	  automatically. If you need to know the IDs of the inserted documents,
	  you need to generate them locally.

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

		Params:
			query = MongoDB query expression to identify the matched document
			update = Update expression for the matched document
			returnFieldSelector = Optional map of fields to return in the response

		Throws:
			An `Exception` will be thrown if an error occurs in the
			communication with the database server.

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
		Combines a modify and find operation to a single atomic operation with generic options support.

		Params:
			query = MongoDB query expression to identify the matched document
			update = Update expression for the matched document
			options = Generic BSON object that contains additional options
				fields, such as `"new": true`

		Throws:
			An `Exception` will be thrown if an error occurs in the
			communication with the database server.

		See_Also: $(LINK http://docs.mongodb.org/manual/reference/command/findAndModify)
	 */
	Bson findAndModifyExt(T, U, V)(T query, U update, V options)
	{
		auto bopt = serializeToBson(options);
		assert(bopt.type == Bson.Type.object,
			"The options parameter to findAndModifyExt must be a BSON object.");
		
		Bson cmd = Bson.emptyObject;
		cmd["findAndModify"] = m_name;
		cmd["query"] = serializeToBson(query);
		cmd["update"] = serializeToBson(update);
		foreach (string key, value; bopt)
			cmd[key] = value;
		auto ret = database.runCommand(cmd);
		enforce(ret["ok"].get!double != 0, "findAndModifyExt failed.");
		return ret["value"];
	}

	///
	unittest {
		import vibe.db.mongo.mongo;

		void test()
		{
			auto coll = connectMongoDB("127.0.0.1").getCollection("test");
			coll.findAndModifyExt(["name": "foo"], ["$set": ["value": "bar"]], ["new": true]);
		}
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
		enforce(reply.ok.opt!double == 1 || reply.ok.opt!int == 1, "Count command failed.");
		switch (reply.n.type) with (Bson.Type) {
			default: assert(false, "Unsupported data type in BSON reply for COUNT");
			case double_: return cast(ulong)reply.n.get!double; // v2.x
			case int_: return reply.n.get!int; // v3.x
			case long_: return reply.n.get!long; // just in case
		}
	}

	/**
		Calculates aggregate values for the data in a collection.

		Params:
			pipeline = A sequence of data aggregation processes. These can
				either be given as separate parameters, or as a single array
				parameter.

		Returns: An array of documents returned by the pipeline

		Throws: Exception if a DB communication error occured

		See_Also: $(LINK http://docs.mongodb.org/manual/reference/method/db.collection.aggregate)
	*/
	Bson aggregate(ARGS...)(ARGS pipeline)
	{
		import std.traits;

		static if (ARGS.length == 1 && isArray!(ARGS[0]))
			alias Pipeline = ARGS[0];
		else static struct Pipeline { ARGS args; }

		static struct CMD {
			string aggregate;
			@asArray Pipeline pipeline;
		}

		CMD cmd;
		cmd.aggregate = m_name;
		static if (ARGS.length == 1 && isArray!(ARGS[0]))
			cmd.pipeline = pipeline[0];
		else cmd.pipeline.args = pipeline;
		auto ret = database.runCommand(cmd);
		enforce(ret.ok.get!double == 1, "Aggregate command failed.");
		return ret.result;
	}

	/// Example taken from the MongoDB documentation
	unittest {
		import vibe.db.mongo.mongo;

		void test() {
			auto db = connectMongoDB("127.0.0.1").getDatabase("test");
			auto results = db["coll"].aggregate(
				["$match": ["status": "A"]],
				["$group": ["_id": Bson("$cust_id"),
					"total": Bson(["$sum": Bson("$amount")])]],
				["$sort": ["total": -1]]);
		}
	}

	/// The same example, but using an array of arguments
	unittest {
		import vibe.db.mongo.mongo;

		void test() {
			auto db = connectMongoDB("127.0.0.1").getDatabase("test");

			Bson[] args;
			args ~= serializeToBson(["$match": ["status": "A"]]);
			args ~= serializeToBson(["$group": ["_id": Bson("$cust_id"),
					"total": Bson(["$sum": Bson("$amount")])]]);
			args ~= serializeToBson(["$sort": ["total": -1]]);

			auto results = db["coll"].aggregate(args);
		}
	}

	/**
		Creates or updates an index.

		Note that the overload taking an associative array of field orders is
		scheduled for deprecation. Since the order of fields matters, it is
		only suitable for single-field indices.
	*/
	void ensureIndex(scope const(Tuple!(string, int))[] field_orders, IndexFlags flags = IndexFlags.None, Duration expire_time = 0.seconds)
	{
		// TODO: support 2d indexes

		auto key = Bson.emptyObject;
		auto indexname = appender!string();
		bool first = true;
		foreach (fo; field_orders) {
			if (!first) indexname.put('_');
			else first = false;
			indexname.put(fo[0]);
			indexname.put('_');
			indexname.put(to!string(fo[1]));
			key[fo[0]] = Bson(fo[1]);
		}

		Bson[string] doc;
		doc["v"] = 1;
		doc["key"] = key;
		doc["ns"] = m_fullPath;
		doc["name"] = indexname.data;
		if (flags & IndexFlags.Unique) doc["unique"] = true;
		if (flags & IndexFlags.DropDuplicates) doc["dropDups"] = true;
		if (flags & IndexFlags.Background) doc["background"] = true;
		if (flags & IndexFlags.Sparse) doc["sparse"] = true;
		if (flags & IndexFlags.ExpireAfterSeconds) doc["expireAfterSeconds"] = expire_time.total!"seconds";
		database["system.indexes"].insert(doc);
	}
	/// ditto
	void ensureIndex(int[string] field_orders, IndexFlags flags = IndexFlags.None, ulong expireAfterSeconds = 0)
	{
		Tuple!(string, int)[] orders;
		foreach (k, v; field_orders)
			orders ~= tuple(k, v);
		ensureIndex(orders, flags, expireAfterSeconds.seconds);
	}

	void dropIndex(string name)
	{
		static struct CMD {
			string dropIndexes;
			string index;
		}

		CMD cmd;
		cmd.dropIndexes = m_name;
		cmd.index = name;
		auto reply = database.runCommand(cmd);
		enforce(reply.ok.get!double == 1, "dropIndex command failed.");
	}

	void drop() {
		static struct CMD {
			string drop;
		}

		CMD cmd;
		cmd.drop = m_name;
		auto reply = database.runCommand(cmd);
		enforce(reply.ok.get!double == 1, "drop command failed.");
	}
}

///
unittest {
	import vibe.data.bson;
	import vibe.data.json;
	import vibe.db.mongo.mongo;

	void test()
	{
		MongoClient client = connectMongoDB("127.0.0.1");
		MongoCollection users = client.getCollection("myapp.users");

		// canonical version using a Bson object
		users.insert(Bson(["name": Bson("admin"), "password": Bson("secret")]));

		// short version using a string[string] AA that is automatically
		// serialized to Bson
		users.insert(["name": "admin", "password": "secret"]);

		// BSON specific types are also serialized automatically
		auto uid = BsonObjectID.fromString("507f1f77bcf86cd799439011");
		Bson usr = users.findOne(["_id": uid]);

		// JSON is another possibility
		Json jusr = parseJsonString(`{"name": "admin", "password": "secret"}`);
		users.insert(jusr);
	}
}

/// Using the type system to define a document "schema"
unittest {
	import vibe.db.mongo.mongo;
	import vibe.data.serialization : name;
	import std.typecons : Nullable;

	// Nested object within a "User" document
	struct Address {
		string name;
		string street;
		int zipCode;
	}

	// The document structure of the "myapp.users" collection
	struct User {
		@name("_id") BsonObjectID id; // represented as "_id" in the database
		string loginName;
		string password;
		Address address;
	}

	void test()
	{
		MongoClient client = connectMongoDB("127.0.0.1");
		MongoCollection users = client.getCollection("myapp.users");

		// D values are automatically serialized to the internal BSON format
		// upon insertion - see also vibe.data.serialization
		User usr;
		usr.id = BsonObjectID.generate();
		usr.loginName = "admin";
		usr.password = "secret";
		users.insert(usr);

		// find supports direct de-serialization of the returned documents
		foreach (usr; users.find!User()) {
			logInfo("User: %s", usr.loginName);
		}

		// the same goes for findOne
		Nullable!User qusr = users.findOne!User(["_id": usr.id]);
		if (!qusr.isNull)
			logInfo("User: %s", qusr.loginName);
	}
}

enum IndexFlags {
	None = 0,
	Unique = 1<<0,
	DropDuplicates = 1<<2,
	Background = 1<<3,
	Sparse = 1<<4,
	ExpireAfterSeconds = 1<<5
}
