/**
	MongoCollection class

	Copyright: © 2012-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.collection;

public import vibe.db.mongo.cursor;
public import vibe.db.mongo.connection;
public import vibe.db.mongo.flags;

public import vibe.db.mongo.impl.index;

import vibe.core.log;
import vibe.db.mongo.client;

import core.time;
import std.algorithm : countUntil, find;
import std.array;
import std.conv;
import std.exception;
import std.string;
import std.typecons : Tuple, tuple, Nullable;


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
	@safe {
		assert(client !is null);
		m_client = client;

		auto dotidx = fullPath.indexOf('.');
		assert(dotidx > 0, "The collection name passed to MongoCollection must be of the form \"dbname.collectionname\".");

		m_fullPath = fullPath;
		m_db = m_client.getDatabase(fullPath[0 .. dotidx]);
		m_name = fullPath[dotidx+1 .. $];
	}

	this(ref MongoDatabase db, string name)
	@safe {
		assert(db.client !is null);
		m_client = db.client;
		m_fullPath = db.name ~ "." ~ name;
		m_db = db;
		m_name = name;
	}

	/**
	  Returns: Root database to which this collection belongs.
	 */
	@property MongoDatabase database() @safe { return m_db; }

	/**
	  Returns: Name of this collection (excluding the database name).
	 */
	@property string name() const @safe { return m_name; }

	/**
	  Performs an update operation on documents matching 'selector', updating them with 'update'.

	  Throws: Exception if a DB communication error occurred.
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

	  Throws: Exception if a DB communication error occurred.
	  See_Also: $(LINK http://www.mongodb.org/display/DOCS/Inserting)
	 */
	void insert(T)(T document_or_documents, InsertFlags flags = InsertFlags.None)
	{
		assert(m_client !is null, "Inserting into uninitialized MongoCollection.");
		auto conn = m_client.lockConnection();
		Bson[] docs;
		Bson bdocs = () @trusted { return serializeToBson(document_or_documents); } ();
		if( bdocs.type == Bson.Type.Array ) docs = cast(Bson[])bdocs;
		else docs = () @trusted { return (&bdocs)[0 .. 1]; } ();
		conn.insert(m_fullPath, flags, docs);
	}

	/**
	  Queries the collection for existing documents.

	  If no arguments are passed to find(), all documents of the collection will be returned.

	  See_Also: $(LINK http://www.mongodb.org/display/DOCS/Querying)
	 */
	MongoCursor!R find(R = Bson, T, U)(T query, U returnFieldSelector, QueryFlags flags = QueryFlags.None, int num_skip = 0, int num_docs_per_chunk = 0)
	{
		assert(m_client !is null, "Querying uninitialized MongoCollection.");
		return MongoCursor!R(m_client, m_fullPath, flags, num_skip, num_docs_per_chunk, query, returnFieldSelector);
	}

	/// ditto
	MongoCursor!R find(R = Bson, T)(T query) { return find!R(query, null); }

	/// ditto
	MongoCursor!R find(R = Bson)() { return find!R(Bson.emptyObject, null); }

	/** Queries the collection for existing documents.

		Returns:
			By default, a Bson value of the matching document is returned, or $(D Bson(null))
			when no document matched. For types R that are not Bson, the returned value is either
			of type $(D R), or of type $(Nullable!R), if $(D R) is not a reference/pointer type.

		Throws: Exception if a DB communication error or a query error occurred.
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

	  Throws: Exception if a DB communication error occurred.
	  See_Also: $(LINK http://www.mongodb.org/display/DOCS/Removing)
	 */
	void remove(T)(T selector, DeleteFlags flags = DeleteFlags.None)
	{
		assert(m_client !is null, "Removing from uninitialized MongoCollection.");
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
		if( !ret["ok"].get!double ) throw new Exception("findAndModify failed.");
		return ret["value"];
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
		bopt.opApply(delegate int(string key, Bson value) @safe {
			cmd[key] = value;
			return 0;
		});
		auto ret = database.runCommand(cmd);
		enforce(ret["ok"].get!double != 0, "findAndModifyExt failed: "~ret["errmsg"].opt!string);
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

		Throws Exception if a DB communication error occurred.
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
		enforce(reply["ok"].opt!double == 1 || reply["ok"].opt!int == 1, "Count command failed: "~reply["errmsg"].opt!string);
		switch (reply["n"].type) with (Bson.Type) {
			default: assert(false, "Unsupported data type in BSON reply for COUNT");
			case double_: return cast(ulong)reply["n"].get!double; // v2.x
			case int_: return reply["n"].get!int; // v3.x
			case long_: return reply["n"].get!long; // just in case
		}
	}

	/**
		Calculates aggregate values for the data in a collection.

		Params:
			pipeline = A sequence of data aggregation processes. These can
				either be given as separate parameters, or as a single array
				parameter.

		Returns:
			Returns the list of documents aggregated by the pipeline. The return
			value is either a single `Bson` array value or a `MongoCursor`
			(input range) of the requested document type.

		Throws: Exception if a DB communication error occurred.

		See_Also: $(LINK http://docs.mongodb.org/manual/reference/method/db.collection.aggregate)
	*/
	Bson aggregate(ARGS...)(ARGS pipeline)
	{
		import std.traits : isArray;

		static if (ARGS.length == 1 && isArray!(ARGS[0]))
			auto convPipeline = pipeline;
		else {
			static struct Pipeline { @asArray ARGS pipeline; }

			Bson[] convPipeline = serializeToBson(Pipeline(pipeline))["pipeline"].get!(Bson[]);
		}

		return aggregate(convPipeline, AggregateOptions.init).array.serializeToBson;
	}

	/// ditto
	MongoCursor!R aggregate(R = Bson, S = Bson)(S[] pipeline, AggregateOptions options)
	{
		assert(m_client !is null, "Querying uninitialized MongoCollection.");

		Bson cmd = Bson.emptyObject; // empty object because order is important
		cmd["aggregate"] = Bson(m_name);
		cmd["pipeline"] = serializeToBson(pipeline);
		foreach (string k, v; serializeToBson(options))
		{
			// spec recommends to omit cursor field when explain is true
			if (!options.explain.isNull && options.explain.get && k == "cursor")
				continue;
			cmd[k] = v;
		}
		auto ret = database.runCommand(cmd);
		enforce(ret["ok"].get!double == 1, "Aggregate command failed: "~ret["errmsg"].opt!string);
		R[] existing;
		static if (is(R == Bson))
			existing = ret["cursor"]["firstBatch"].get!(Bson[]);
		else
			existing = ret["cursor"]["firstBatch"].deserializeBson!(R[]);
		return MongoCursor!R(m_client, ret["cursor"]["ns"].get!string, ret["cursor"]["id"].get!long, existing);
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

	/// The same example, but using an array of arguments with custom options
	unittest {
		import vibe.db.mongo.mongo;

		void test() {
			auto db = connectMongoDB("127.0.0.1").getDatabase("test");

			Bson[] args;
			args ~= serializeToBson(["$match": ["status": "A"]]);
			args ~= serializeToBson(["$group": ["_id": Bson("$cust_id"),
					"total": Bson(["$sum": Bson("$amount")])]]);
			args ~= serializeToBson(["$sort": ["total": -1]]);

			AggregateOptions options;
			options.cursor.batchSize = 10; // pre-fetch the first 10 results
			auto results = db["coll"].aggregate(args, options);
		}
	}

	/**
		Returns an input range of all unique values for a certain field for
		records matching the given query.

		Params:
			key = Name of the field for which to collect unique values
			query = The query used to select records

		Returns:
			An input range with items of type `R` (`Bson` by default) is
			returned.
	*/
	auto distinct(R = Bson, Q)(string key, Q query)
	{
		import std.algorithm : map;

		static struct CMD {
			string distinct;
			string key;
			Q query;
		}
		CMD cmd;
		cmd.distinct = m_name;
		cmd.key = key;
		cmd.query = query;
		auto res = m_db.runCommand(cmd);

		enforce(res["ok"].get!double != 0, "Distinct query failed: "~res["errmsg"].opt!string);

		static if (is(R == Bson)) return res["values"].byValue;
		else return res["values"].byValue.map!(b => deserializeBson!R(b));
	}

	///
	unittest {
		import std.algorithm : equal;
		import vibe.db.mongo.mongo;

		void test()
		{
			auto db = connectMongoDB("127.0.0.1").getDatabase("test");
			auto coll = db["collection"];

			coll.drop();
			coll.insert(["a": "first", "b": "foo"]);
			coll.insert(["a": "first", "b": "bar"]);
			coll.insert(["a": "first", "b": "bar"]);
			coll.insert(["a": "second", "b": "baz"]);
			coll.insert(["a": "second", "b": "bam"]);

			auto result = coll.distinct!string("b", ["a": "first"]);

			assert(result.equal(["foo", "bar"]));
		}
	}

	/*
		following MongoDB standard API for the Index Management specification:

		Standards: https://github.com/mongodb/specifications/blob/0c6e56141c867907aacf386e0cbe56d6562a0614/source/index-management.rst#standard-api
	*/

	deprecated("This is a legacy API, call createIndexes instead")
	void ensureIndex(scope const(Tuple!(string, int))[] field_orders, IndexFlags flags = IndexFlags.none, Duration expire_time = 0.seconds)
	@safe {
		IndexModel[1] models;
		IndexOptions options;
		if (flags & IndexFlags.unique) options.unique = true;
		if (flags & IndexFlags.dropDuplicates) options.dropDups = true;
		if (flags & IndexFlags.background) options.background = true;
		if (flags & IndexFlags.sparse) options.sparse = true;
		if (flags & IndexFlags.expireAfterSeconds) options.expireAfter = expire_time;

		models[0].options = options;
		foreach (field; field_orders) {
			models[0].add(field[0], field[1]);
		}
		createIndexes(models);
	}

	deprecated("This is a legacy API, call createIndexes instead. This API is not recommended to be used because of unstable dictionary ordering.")
	void ensureIndex(int[string] field_orders, IndexFlags flags = IndexFlags.none, ulong expireAfterSeconds = 0)
	@safe {
		Tuple!(string, int)[] orders;
		foreach (k, v; field_orders)
			orders ~= tuple(k, v);
		ensureIndex(orders, flags, expireAfterSeconds.seconds);
	}

	/**
		Drops a single index from the collection by the index name.

		Throws: `Exception` if it is attempted to pass in `*`.
		Use dropIndexes() to remove all indexes instead.
	*/
	void dropIndex(string name, DropIndexOptions options = DropIndexOptions.init)
	@safe {
		if (name == "*")
			throw new Exception("Attempted to remove single index with '*'");

		static struct CMD {
			string dropIndexes;
			string index;
		}

		CMD cmd;
		cmd.dropIndexes = m_name;
		cmd.index = name;
		auto reply = database.runCommand(cmd);
		enforce(reply["ok"].get!double == 1, "dropIndex command failed: "~reply["errmsg"].opt!string);
	}

	/// ditto
	void dropIndex(T)(T keys,
		IndexOptions indexOptions = IndexOptions.init,
		DropIndexOptions options = DropIndexOptions.init)
	@safe if (!is(Unqual!T == IndexModel))
	{
		IndexModel model;
		model.keys = serializeToBson(keys);
		model.options = indexOptions;
		dropIndex(model.name, options);
	}

	/// ditto
	void dropIndex(const IndexModel keys,
		DropIndexOptions options = DropIndexOptions.init)
	@safe {
		dropIndex(keys.name, options);
	}

	///
	@safe unittest
	{
		import vibe.db.mongo.mongo;

		void test()
		{
			auto coll = connectMongoDB("127.0.0.1").getCollection("test");
			auto primarykey = IndexModel()
					.add("name", 1)
					.add("primarykey", -1);
			coll.dropIndex(primarykey);
		}
	}

	/// Drops all indexes in the collection.
	void dropIndexes(DropIndexOptions options = DropIndexOptions.init)
	@safe {
		static struct CMD {
			string dropIndexes;
			string index;
		}

		CMD cmd;
		cmd.dropIndexes = m_name;
		cmd.index = "*";
		auto reply = database.runCommand(cmd);
		enforce(reply["ok"].get!double == 1, "dropIndexes command failed: "~reply["errmsg"].opt!string);
	}

	/// Unofficial API extension, more efficient multi-index removal on
	/// MongoDB 4.2+
	void dropIndexes(string[] names, DropIndexOptions options = DropIndexOptions.init)
	@safe {
		MongoConnection conn = m_client.lockConnection();
		if (conn.description.satisfiesVersion(WireVersion.v42)) {
			static struct CMD {
				string dropIndexes;
				string[] index;
			}

			CMD cmd;
			cmd.dropIndexes = m_name;
			cmd.index = names;
			auto reply = database.runCommand(cmd);
			enforce(reply["ok"].get!double == 1, "dropIndexes command failed: "~reply["errmsg"].opt!string);
		} else {
			foreach (name; names)
				dropIndex(name);
		}
	}

	///
	@safe unittest
	{
		import vibe.db.mongo.mongo;

		void test()
		{
			auto coll = connectMongoDB("127.0.0.1").getCollection("test");
			coll.dropIndexes(["name_1_primarykey_-1"]);
		}
	}

	/**
		Convenience method for creating a single index. Calls `createIndexes`

		Supports any kind of document for template parameter T or a IndexModel.

		Params:
			keys = a IndexModel or type with integer or string fields indicating
				index direction or index type.
	*/
	string createIndex(T)(T keys,
		IndexOptions indexOptions = IndexOptions.init,
		CreateIndexOptions options = CreateIndexOptions.init)
	@safe if (!is(Unqual!T == IndexModel))
	{
		IndexModel[1] model;
		model[0].keys = serializeToBson(keys);
		model[0].options = indexOptions;
		return createIndexes(model[], options)[0];
	}

	/// ditto
	string createIndex(const IndexModel keys,
		CreateIndexOptions options = CreateIndexOptions.init)
	@safe {
		IndexModel[1] model;
		model[0] = keys;
		return createIndexes(model[], options)[0];
	}

	///
	@safe unittest
	{
		import vibe.db.mongo.mongo;

		void test()
		{
			auto coll = connectMongoDB("127.0.0.1").getCollection("test");

			// simple ascending name, descending primarykey compound-index
			coll.createIndex(["name": 1, "primarykey": -1]);

			IndexOptions textOptions = {
				// pick language from another field called "idioma"
				languageOverride: "idioma"
			};
			auto textIndex = IndexModel()
					.withOptions(textOptions)
					.add("comments", IndexType.text);
			// more complex text index in DB with independent language
			coll.createIndex(textIndex);
		}
	}

	/**
		Builds one or more indexes in the collection.

		See_Also: $(LINK https://docs.mongodb.com/manual/reference/command/createIndexes/)
	*/
	string[] createIndexes(scope const(IndexModel)[] models,
		CreateIndexesOptions options = CreateIndexesOptions.init)
	@safe {
		string[] keys = new string[models.length];

		MongoConnection conn = m_client.lockConnection();
		if (conn.description.satisfiesVersion(WireVersion.v26)) {
			Bson cmd = Bson.emptyObject;
			cmd["createIndexes"] = m_name;
			Bson[] indexes;
			foreach (model; models) {
				// trusted to support old compilers which think opt_dup has
				// longer lifetime than model.options
				IndexOptions opt_dup = (() @trusted => model.options)();
				enforceWireVersionConstraints(opt_dup, conn.description.maxWireVersion);
				Bson index = serializeToBson(opt_dup);
				index["key"] = model.keys;
				index["name"] = model.name;
				indexes ~= index;
			}
			cmd["indexes"] = Bson(indexes);
			auto reply = database.runCommand(cmd);
			enforce(reply["ok"].get!double == 1, "createIndex command failed: "
				~ reply["errmsg"].opt!string);
		} else {
			foreach (model; models) {
				// trusted to support old compilers which think opt_dup has
				// longer lifetime than model.options
				IndexOptions opt_dup = (() @trusted => model.options)();
				enforceWireVersionConstraints(opt_dup, WireVersion.old);
				Bson doc = serializeToBson(opt_dup);
				doc["v"] = 1;
				doc["key"] = model.keys;
				doc["ns"] = m_fullPath;
				doc["name"] = model.name;
				database["system.indexes"].insert(doc);
			}
		}

		return keys;
	}

	/**
		Returns an array that holds a list of documents that identify and describe the existing indexes on the collection. 
	*/
	MongoCursor!R listIndexes(R = Bson)() 
	@safe {
		MongoConnection conn = m_client.lockConnection();
		if (conn.description.satisfiesVersion(WireVersion.v30)) {
			static struct CMD {
				string listIndexes;
			}

			CMD cmd;
			cmd.listIndexes = m_name;

			auto reply = database.runCommand(cmd);
			enforce(reply["ok"].get!double == 1, "getIndexes command failed: "~reply["errmsg"].opt!string);
			return MongoCursor!R(m_client, reply["cursor"]["ns"].get!string, reply["cursor"]["id"].get!long, reply["cursor"]["firstBatch"].get!(Bson[]));
		} else {
			return database["system.indexes"].find!R();
		}
	}

	///
	@safe unittest
	{
		import vibe.db.mongo.mongo;

		void test()
		{
			auto coll = connectMongoDB("127.0.0.1").getCollection("test");

			foreach (index; coll.listIndexes())
				logInfo("index %s: %s", index["name"].get!string, index);
		}
	}

	deprecated("Please use the standard API name 'listIndexes'") alias getIndexes = listIndexes;

	/**
		Removes a collection or view from the database. The method also removes any indexes associated with the dropped collection.
	*/
	void drop()
	@safe {
		static struct CMD {
			string drop;
		}

		CMD cmd;
		cmd.drop = m_name;
		auto reply = database.runCommand(cmd);
		enforce(reply["ok"].get!double == 1, "drop command failed: "~reply["errmsg"].opt!string);
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
		foreach (usr2; users.find!User()) {
			logInfo("User: %s", usr2.loginName);
		}

		// the same goes for findOne
		Nullable!User qusr = users.findOne!User(["_id": usr.id]);
		if (!qusr.isNull)
			logInfo("User: %s", qusr.get.loginName);
	}
}

/**
  Specifies a level of isolation for read operations. For example, you can use read concern to only read data that has propagated to a majority of nodes in a replica set.

  See_Also: $(LINK https://docs.mongodb.com/manual/reference/read-concern/)
 */
struct ReadConcern {
	///
	enum Level : string {
		/// This is the default read concern level.
		local = "local",
		/// This is the default for reads against secondaries when afterClusterTime and "level" are unspecified. The query returns the the instance’s most recent data.
		available = "available",
		/// Available for replica sets that use WiredTiger storage engine.
		majority = "majority",
		/// Available for read operations on the primary only.
		linearizable = "linearizable"
	}

	/// The level of the read concern.
	string level;
}

/**
  Collation allows users to specify language-specific rules for string comparison, such as rules for letter-case and accent marks.

  See_Also: $(LINK https://docs.mongodb.com/manual/reference/collation/)
 */
struct Collation {
	///
	enum Alternate : string {
		/// Whitespace and punctuation are considered base characters
		nonIgnorable = "non-ignorable",
		/// Whitespace and punctuation are not considered base characters and are only distinguished at strength levels greater than 3
		shifted = "shifted",
	}

	///
	enum MaxVariable : string {
		/// Both whitespaces and punctuation are “ignorable”, i.e. not considered base characters.
		punct = "punct",
		/// Whitespace are “ignorable”, i.e. not considered base characters.
		space = "space"
	}

	/**
	  The ICU locale

	  See_Also: See_Also: $(LINK https://docs.mongodb.com/manual/reference/collation-locales-defaults/#collation-languages-locales) for a list of supported locales.

	  To specify simple binary comparison, specify locale value of "simple".
	 */
	string locale;
	/// The level of comparison to perform. Corresponds to ICU Comparison Levels.
	@embedNullable Nullable!int strength;
	/// Flag that determines whether to include case comparison at strength level 1 or 2.
	@embedNullable Nullable!bool caseLevel;
	/// A flag that determines sort order of case differences during tertiary level comparisons.
	@embedNullable Nullable!string caseFirst;
	/// Flag that determines whether to compare numeric strings as numbers or as strings.
	@embedNullable Nullable!bool numericOrdering;
	/// Field that determines whether collation should consider whitespace and punctuation as base characters for purposes of comparison.
	@embedNullable Nullable!Alternate alternate;
	/// Field that determines up to which characters are considered ignorable when `alternate: "shifted"`. Has no effect if `alternate: "non-ignorable"`
	@embedNullable Nullable!MaxVariable maxVariable;
	/**
	  Flag that determines whether strings with diacritics sort from back of the string, such as with some French dictionary ordering.

	  If `true` compare from back to front, otherwise front to back.
	 */
	@embedNullable Nullable!bool backwards;
	/// Flag that determines whether to check if text require normalization and to perform normalization. Generally, majority of text does not require this normalization processing.
	@embedNullable Nullable!bool normalization;
}

///
struct CursorInitArguments {
	/// Specifies the initial batch size for the cursor. Or null for server
	/// default value.
	@embedNullable Nullable!int batchSize;
}

/// UDA to unset a nullable field if the server wire version doesn't at least
/// match the given version. (inclusive)
///
/// Use with $(LREF enforceWireVersionConstraints)
struct MinWireVersion
{
	///
	WireVersion v;
}

/// ditto
MinWireVersion since(WireVersion v) @safe { return MinWireVersion(v); }

/// UDA to unset a nullable field if the server wire version is newer than the
/// given version. (inclusive)
///
/// Use with $(LREF enforceWireVersionConstraints)
struct MaxWireVersion
{
	///
	WireVersion v;
}
/// ditto
MaxWireVersion until(WireVersion v) @safe { return MaxWireVersion(v); }

/// Unsets nullable fields not matching the server version as defined per UDAs.
void enforceWireVersionConstraints(T)(ref T field, WireVersion serverVersion)
@safe {
	import std.traits : getUDAs;

	foreach (i, ref v; field.tupleof) {
		enum minV = getUDAs!(field.tupleof[i], MinWireVersion);
		enum maxV = getUDAs!(field.tupleof[i], MaxWireVersion);

		static foreach (min; minV)
			if (serverVersion < min.v)
				v.nullify();

		static foreach (max; maxV)
			if (serverVersion > max.v)
				v.nullify();
	}
}

///
unittest
{
	struct SomeMongoCommand
	{
		@embedNullable @since(WireVersion.v34)
		Nullable!int a;

		@embedNullable @until(WireVersion.v30)
		Nullable!int b;
	}

	SomeMongoCommand cmd;
	cmd.a = 1;
	cmd.b = 2;
	assert(!cmd.a.isNull);
	assert(!cmd.b.isNull);

	SomeMongoCommand test = cmd;
	enforceWireVersionConstraints(test, WireVersion.v30);
	assert(test.a.isNull);
	assert(!test.b.isNull);

	test = cmd;
	enforceWireVersionConstraints(test, WireVersion.v32);
	assert(test.a.isNull);
	assert(test.b.isNull);

	test = cmd;
	enforceWireVersionConstraints(test, WireVersion.v34);
	assert(!test.a.isNull);
	assert(test.b.isNull);
}

/**
  Represents available options for an aggregate call

  See_Also: $(LINK https://docs.mongodb.com/manual/reference/method/db.collection.aggregate/)

  Standards: $(LINK https://github.com/mongodb/specifications/blob/0c6e56141c867907aacf386e0cbe56d6562a0614/source/crud/crud.rst#api)
 */
struct AggregateOptions {
	// non-optional since 3.6
	// get/set by `batchSize`, undocumented in favor of that field
	CursorInitArguments cursor;

	/// Specifies the initial batch size for the cursor.
	ref inout(Nullable!int) batchSize()
	@property inout @safe pure nothrow @nogc @ignore {
		return cursor.batchSize;
	}

	// undocumented because this field isn't a spec field because it is
	// out-of-scope for a driver
	@embedNullable Nullable!bool explain;

	/**
		Enables writing to temporary files. When set to true, aggregation
		operations can write data to the _tmp subdirectory in the dbPath
		directory.
	*/
	@embedNullable Nullable!bool allowDiskUse;

	/**
		Specifies a time limit in milliseconds for processing operations on a
		cursor. If you do not specify a value for maxTimeMS, operations will not
		time out.
	*/
	@embedNullable Nullable!long maxTimeMS;

	/**
		If true, allows the write to opt-out of document level validation.
		This only applies when the $out or $merge stage is specified.
	*/
	@embedNullable Nullable!bool bypassDocumentValidation;

	/**
		Specifies the read concern. Only compatible with a write stage. (e.g.
		`$out`, `$merge`)

		Aggregate commands do not support the $(D ReadConcern.Level.linearizable)
		level.

		Standards: $(LINK https://github.com/mongodb/specifications/blob/7745234f93039a83ae42589a6c0cdbefcffa32fa/source/read-write-concern/read-write-concern.rst)
	*/
	@embedNullable Nullable!ReadConcern readConcern;

	/// Specifies a collation.
	@embedNullable Nullable!Collation collation;

	/**
		The index to use for the aggregation. The index is on the initial
		collection / view against which the aggregation is run.

		The hint does not apply to $lookup and $graphLookup stages.

		Specify the index either by the index name as a string or the index key
		pattern. If specified, then the query system will only consider plans
		using the hinted index.
	 */
	@embedNullable Nullable!Bson hint;

	/**
		Users can specify an arbitrary string to help trace the operation
		through the database profiler, currentOp, and logs.
	*/
	@embedNullable Nullable!string comment;
}
