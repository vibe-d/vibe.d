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
public import vibe.db.mongo.impl.crud;

import vibe.core.log;
import vibe.db.mongo.client;

import core.time;
import std.algorithm : among, countUntil, find, findSplit;
import std.array;
import std.conv;
import std.exception;
import std.meta : AliasSeq;
import std.string;
import std.traits : FieldNameTuple;
import std.typecons : Nullable, tuple, Tuple;


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
	deprecated("Use `replaceOne`, `updateOne` or `updateMany` taking `UpdateOptions` instead, this method breaks in MongoDB 5.1 and onwards.")
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
	deprecated("Use `insertOne` or `insertMany`, this method breaks in MongoDB 5.1 and onwards.")
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
		Inserts the provided document(s). If a document is missing an identifier,
		one is generated automatically by vibe.d.

		See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/method/db.collection.insertOne/#mongodb-method-db.collection.insertOne)

		Standards: $(LINK https://www.mongodb.com/docs/manual/reference/command/insert/)
	*/
	InsertOneResult insertOne(T)(T document, InsertOneOptions options = InsertOneOptions.init)
	{
		assert(m_client !is null, "Querying uninitialized MongoCollection.");

		Bson cmd = Bson.emptyObject; // empty object because order is important
		cmd["insert"] = Bson(m_name);
		auto doc = serializeToBson(document);
		enforce(doc.type == Bson.Type.object, "Can only insert objects into collections");
		InsertOneResult res;
		if ("_id" !in doc.get!(Bson[string]))
		{
			doc["_id"] = Bson(res.insertedId = BsonObjectID.generate);
		}
		cmd["documents"] = Bson([doc]);
		MongoConnection conn = m_client.lockConnection();
		enforceWireVersionConstraints(options, conn.description.maxWireVersion);
		foreach (string k, v; serializeToBson(options).byKeyValue)
			cmd[k] = v;

		database.runCommandChecked(cmd).handleWriteResult(res);
		return res;
	}

	/// ditto
	InsertManyResult insertMany(T)(T[] documents, InsertManyOptions options = InsertManyOptions.init)
	{
		assert(m_client !is null, "Querying uninitialized MongoCollection.");

		Bson cmd = Bson.emptyObject; // empty object because order is important
		cmd["insert"] = Bson(m_name);
		Bson[] arr = new Bson[documents.length];
		BsonObjectID[size_t] insertedIds;
		foreach (i, document; documents)
		{
			auto doc = serializeToBson(document);
			arr[i] = doc;
			enforce(doc.type == Bson.Type.object, "Can only insert objects into collections");
			if ("_id" !in doc.get!(Bson[string]))
			{
				doc["_id"] = Bson(insertedIds[i] = BsonObjectID.generate);
			}
		}
		cmd["documents"] = Bson(arr);
		MongoConnection conn = m_client.lockConnection();
		enforceWireVersionConstraints(options, conn.description.maxWireVersion);
		foreach (string k, v; serializeToBson(options).byKeyValue)
			cmd[k] = v;

		auto res = InsertManyResult(insertedIds);
		database.runCommandChecked(cmd).handleWriteResult!"insertedCount"(res);
		return res;
	}

	/**
		Deletes at most one document matching the query `filter`. The returned
		result identifies how many documents have been deleted.

		See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/method/db.collection.deleteOne/#mongodb-method-db.collection.deleteOne)

		Standards: $(LINK https://www.mongodb.com/docs/manual/reference/command/delete/)
	*/
	DeleteResult deleteOne(T)(T filter, DeleteOptions options = DeleteOptions.init)
	@trusted {
		int limit = 1;
		return deleteImpl([filter], options, (&limit)[0 .. 1]);
	}

	/**
		Deletes all documents matching the query `filter`. The returned result
		identifies how many documents have been deleted.

		See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/method/db.collection.deleteMany/#mongodb-method-db.collection.deleteMany)

		Standards: $(LINK https://www.mongodb.com/docs/manual/reference/command/delete/)
	*/
	DeleteResult deleteMany(T)(T filter, DeleteOptions options = DeleteOptions.init)
	@safe
	if (!is(T == DeleteOptions))
	{
		return deleteImpl([filter], options);
	}

	/**
		Deletes all documents in the collection. The returned result identifies
		how many documents have been deleted.

		Same as calling `deleteMany` with `Bson.emptyObject` as filter.

		Standards: $(LINK https://www.mongodb.com/docs/manual/reference/command/delete/)
	*/
	DeleteResult deleteAll(DeleteOptions options = DeleteOptions.init)
	@safe {
		return deleteImpl([Bson.emptyObject], options);
	}

	/// Implementation helper. It's possible to set custom delete limits with
	/// this method, otherwise it's identical to `deleteOne` and `deleteMany`.
	DeleteResult deleteImpl(T)(T[] queries, DeleteOptions options = DeleteOptions.init, scope int[] limits = null)
	@safe {
		assert(m_client !is null, "Querying uninitialized MongoCollection.");

		alias FieldsMovedIntoChildren = AliasSeq!("limit", "collation", "hint");

		Bson cmd = Bson.emptyObject; // empty object because order is important
		cmd["delete"] = Bson(m_name);

		MongoConnection conn = m_client.lockConnection();
		enforceWireVersionConstraints(options, conn.description.maxWireVersion);
		auto optionsBson = serializeToBson(options);
		foreach (string k, v; optionsBson.byKeyValue)
			if (!k.among!FieldsMovedIntoChildren)
				cmd[k] = v;

		Bson[] deletesBson = new Bson[queries.length];
		foreach (i, q; queries)
		{
			auto deleteBson = Bson.emptyObject;
			deleteBson["q"] = serializeToBson(q);
			foreach (string k, v; optionsBson.byKeyValue)
				if (k.among!FieldsMovedIntoChildren)
					deleteBson[k] = v;
			if (i < limits.length)
				deleteBson["limit"] = Bson(limits[i]);
			else
				deleteBson["limit"] = Bson(0);
			deletesBson[i] = deleteBson;
		}
		cmd["deletes"] = Bson(deletesBson);

		DeleteResult res;
		database.runCommandChecked(cmd).handleWriteResult!"deletedCount"(res);
		return res;
	}

	/**
		Replaces at most single document within the collection based on the
		filter.

		It's recommended to use the ReplaceOptions overload, but UpdateOptions
		can be used as well. Note that the extra options inside UpdateOptions
		may have no effect, possible warnings for this may only be handled by
		MongoDB.

		See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/method/db.collection.replaceOne/#mongodb-method-db.collection.replaceOne)

		Standards: $(LINK https://www.mongodb.com/docs/manual/reference/command/update/)
	*/
	UpdateResult replaceOne(T, U)(T filter, U replacement, ReplaceOptions options)
	@safe {
		UpdateOptions uoptions;
		static foreach (f; FieldNameTuple!ReplaceOptions)
			__traits(getMember, uoptions, f) = __traits(getMember, options, f);
		Bson opts = Bson.emptyObject;
		opts["multi"] = Bson(false);
		return updateImpl([filter], [replacement], [opts], uoptions, true, false);
	}

	/// ditto
	UpdateResult replaceOne(T, U)(T filter, U replacement, UpdateOptions options = UpdateOptions.init)
	@safe {
		Bson opts = Bson.emptyObject;
		opts["multi"] = Bson(false);
		return updateImpl([filter], [replacement], [opts], options, true, false);
	}

	///
	@safe unittest {
		import vibe.db.mongo.mongo;

		void test(BsonObjectID id)
		{
			auto coll = connectMongoDB("127.0.0.1").getCollection("test");

			// replaces the existing document with _id == id to `{_id: id, name: "Bob"}`
			// or if it didn't exist before this will just insert, since we enabled `upsert`
			ReplaceOptions options;
			options.upsert = true;
			coll.replaceOne(
				["_id": id],
				[
					"_id": Bson(id),
					"name": Bson("Bob")
				],
				options
			);
		}
	}

	/**
		Updates at most single document within the collection based on the filter.

		See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/method/db.collection.updateOne/#mongodb-method-db.collection.updateOne)

		Standards: $(LINK https://www.mongodb.com/docs/manual/reference/command/update/)
	*/
	UpdateResult updateOne(T, U)(T filter, U replacement, UpdateOptions options = UpdateOptions.init)
	@safe {
		Bson opts = Bson.emptyObject;
		opts["multi"] = Bson(false);
		return updateImpl([filter], [replacement], [opts], options, false, true);
	}

	/**
		Updates all matching document within the collection based on the filter.

		See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/method/db.collection.updateMany/#mongodb-method-db.collection.updateMany)

		Standards: $(LINK https://www.mongodb.com/docs/manual/reference/command/update/)
	*/
	UpdateResult updateMany(T, U)(T filter, U replacement, UpdateOptions options = UpdateOptions.init)
	@safe {
		Bson opts = Bson.emptyObject;
		opts["multi"] = Bson(true);
		return updateImpl([filter], [replacement], [opts], options, false, true);
	}

	/// Implementation helper. It's possible to set custom per-update object
	/// options with this method, otherwise it's identical to `replaceOne`,
	/// `updateOne` and `updateMany`.
	UpdateResult updateImpl(T, U, O)(T[] queries, U[] documents, O[] perUpdateOptions, UpdateOptions options = UpdateOptions.init,
		bool mustBeDocument = false, bool mustBeModification = false)
	@safe
	in(queries.length == documents.length && documents.length == perUpdateOptions.length,
		"queries, documents and perUpdateOptions must have same length")
	{
		assert(m_client !is null, "Querying uninitialized MongoCollection.");

		alias FieldsMovedIntoChildren = AliasSeq!("arrayFilters",
			"collation",
			"hint",
			"upsert");

		Bson cmd = Bson.emptyObject; // empty object because order is important
		cmd["update"] = Bson(m_name);

		MongoConnection conn = m_client.lockConnection();
		enforceWireVersionConstraints(options, conn.description.maxWireVersion);
		auto optionsBson = serializeToBson(options);
		foreach (string k, v; optionsBson.byKeyValue)
			if (!k.among!FieldsMovedIntoChildren)
				cmd[k] = v;

		Bson[] updatesBson = new Bson[queries.length];
		foreach (i, q; queries)
		{
			auto updateBson = Bson.emptyObject;
			auto qbson = serializeToBson(q);
			updateBson["q"] = qbson;
			auto ubson = serializeToBson(documents[i]);
			if (mustBeDocument)
			{
				if (ubson.type != Bson.Type.object)
					assert(false, "Passed in non-document into a place where only replacements are expected. "
						~ "Maybe you want to call updateOne or updateMany instead?");

				foreach (string k, v; ubson.byKeyValue)
				{
					if (k.startsWith("$"))
						assert(false, "Passed in atomic modifiers (" ~ k
							~ ") into a place where only replacements are expected. "
							~ "Maybe you want to call updateOne or updateMany instead?");
					debug {} // server checks that the rest is consistent (only $ or only non-$ allowed)
					else break; // however in debug mode we check the full document, as we can give better error messages to the dev
				}
			}
			if (mustBeModification)
			{
				if (ubson.type == Bson.Type.object)
				{
					bool anyDollar = false;
					foreach (string k, v; ubson.byKeyValue)
					{
						if (k.startsWith("$"))
							anyDollar = true;
						debug {} // server checks that the rest is consistent (only $ or only non-$ allowed)
						else break; // however in debug mode we check the full document, as we can give better error messages to the dev
						// also nice side effect: if this is an empty document, this also matches the assert(false) branch.
					}

					if (!anyDollar)
						assert(false, "Passed in a regular document into a place where only updates are expected. "
							~ "Maybe you want to call replaceOne instead? "
							~ "(this update call would otherwise replace the entire matched object with the passed in update object)");
				}
			}
			updateBson["u"] = ubson;
			foreach (string k, v; optionsBson.byKeyValue)
				if (k.among!FieldsMovedIntoChildren)
					updateBson[k] = v;
			foreach (string k, v; perUpdateOptions[i].byKeyValue)
				updateBson[k] = v;
			updatesBson[i] = updateBson;
		}
		cmd["updates"] = Bson(updatesBson);

		auto res = database.runCommandChecked(cmd);
		auto ret = UpdateResult(
			res["n"].to!long,
			res["nModified"].to!long,
		);
		res.handleWriteResult(ret);
		auto upserted = res["upserted"].opt!(Bson[]);
		if (upserted.length)
		{
			ret.upsertedIds.length = upserted.length;
			foreach (i, upsert; upserted)
			{
				ret.upsertedIds[i] = upsert["_id"].get!BsonObjectID;
			}
		}
		return ret;
	}

	deprecated("Use the overload taking `FindOptions` instead, this method breaks in MongoDB 5.1 and onwards. Note: using a `$query` / `query` member to override the query arguments is no longer supported in the new overload.")
	MongoCursor!R find(R = Bson, T, U)(T query, U returnFieldSelector, QueryFlags flags, int num_skip = 0, int num_docs_per_chunk = 0)
	{
		assert(m_client !is null, "Querying uninitialized MongoCollection.");
		return MongoCursor!R(m_client, m_fullPath, flags, num_skip, num_docs_per_chunk, query, returnFieldSelector);
	}

	///
	@safe deprecated unittest {
		import vibe.db.mongo.mongo;

		void test()
		{
			auto coll = connectMongoDB("127.0.0.1").getCollection("test");
			// find documents with status == "A"
			auto x = coll.find(["status": "A"], ["status": true], QueryFlags.none);
			foreach (item; x)
			{
				// only for legacy overload
			}
		}
	}

	/**
	  Queries the collection for existing documents, limiting what fields are
	  returned by the database. (called projection)

	  See_Also:
	  - Querying: $(LINK http://www.mongodb.org/display/DOCS/Querying)
	  - Projection: $(LINK https://www.mongodb.com/docs/manual/tutorial/project-fields-from-query-results/#std-label-projections)
	  - $(LREF findOne)
	 */
	MongoCursor!R find(R = Bson, T, U)(T query, U projection, FindOptions options = FindOptions.init)
	if (!is(U == FindOptions))
	{
		options.projection = serializeToBson(projection);
		return find!R(query, options);
	}

	///
	@safe unittest {
		import vibe.db.mongo.mongo;

		void test()
		{
			auto coll = connectMongoDB("127.0.0.1").getCollection("test");
			// find documents with status == "A", return list of {"item":..., "status":...}
			coll.find(["status": "A"], ["item": 1, "status": 1]);
		}
	}

	/**
	  Queries the collection for existing documents.

	  If no arguments are passed to find(), all documents of the collection will be returned.

	  See_Also:
	  - $(LINK http://www.mongodb.org/display/DOCS/Querying)
	  - $(LREF findOne)
	 */
	MongoCursor!R find(R = Bson, Q)(Q query, FindOptions options = FindOptions.init)
	{
		return MongoCursor!R(m_client, m_db.name, m_name, query, options);
	}

	///
	@safe unittest {
		import vibe.db.mongo.mongo;

		void test()
		{
			auto coll = connectMongoDB("127.0.0.1").getCollection("test");
			// find documents with status == "A"
			coll.find(["status": "A"]);
		}
	}

	/**
	  Queries all documents of the collection.

	  See_Also:
	  - $(LINK http://www.mongodb.org/display/DOCS/Querying)
	  - $(LREF findOne)
	 */
	MongoCursor!R find(R = Bson)() { return find!R(Bson.emptyObject, FindOptions.init); }
	/// ditto
	MongoCursor!R find(R = Bson)(FindOptions options) { return find!R(Bson.emptyObject, options); }

	///
	@safe unittest {
		import vibe.db.mongo.mongo;

		void test()
		{
			auto coll = connectMongoDB("127.0.0.1").getCollection("test");
			// find all documents in the "test" collection.
			coll.find();
		}
	}

	deprecated("Use the overload taking `FindOptions` instead, this method breaks in MongoDB 5.1 and onwards. Note: using a `$query` / `query` member to override the query arguments is no longer supported in the new overload.")
	auto findOne(R = Bson, T, U)(T query, U returnFieldSelector, QueryFlags flags)
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

	/** Queries the collection for existing documents.

		Returns:
			By default, a Bson value of the matching document is returned, or $(D Bson(null))
			when no document matched. For types R that are not Bson, the returned value is either
			of type $(D R), or of type $(Nullable!R), if $(D R) is not a reference/pointer type.

			The projection parameter limits what fields are returned by the database,
			see projection documentation linked below.

		Throws: Exception if a DB communication error or a query error occurred.

		See_Also:
		- Querying: $(LINK http://www.mongodb.org/display/DOCS/Querying)
		- Projection: $(LINK https://www.mongodb.com/docs/manual/tutorial/project-fields-from-query-results/#std-label-projections)
		- $(LREF find)
	 */
	auto findOne(R = Bson, T, U)(T query, U projection, FindOptions options = FindOptions.init)
	if (!is(U == FindOptions))
	{
		options.projection = serializeToBson(projection);
		return findOne!(R, T)(query, options);
	}

	///
	@safe unittest {
		import vibe.db.mongo.mongo;

		void test()
		{
			auto coll = connectMongoDB("127.0.0.1").getCollection("test");
			// find documents with status == "A"
			auto x = coll.findOne(["status": "A"], ["status": true, "otherField": true]);
			// x now only contains _id (implicit, unless you make it `false`), status and otherField
		}
	}

	/** Queries the collection for existing documents.

		Returns:
			By default, a Bson value of the matching document is returned, or $(D Bson(null))
			when no document matched. For types R that are not Bson, the returned value is either
			of type $(D R), or of type $(Nullable!R), if $(D R) is not a reference/pointer type.

		Throws: Exception if a DB communication error or a query error occurred.
		See_Also:
		- $(LINK http://www.mongodb.org/display/DOCS/Querying)
		- $(LREF find)
	 */
	auto findOne(R = Bson, T)(T query, FindOptions options = FindOptions.init)
	{
		import std.traits;
		import std.typecons;

		options.limit = 1;
		auto c = find!R(query, options);
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

	/**
	  Removes documents from the collection.

	  Throws: Exception if a DB communication error occurred.
	  See_Also: $(LINK http://www.mongodb.org/display/DOCS/Removing)
	 */
	deprecated("Use `deleteOne` or `deleteMany` taking DeleteOptions instead, this method breaks in MongoDB 5.1 and onwards.")
	void remove(T)(T selector, DeleteFlags flags = DeleteFlags.None)
	{
		assert(m_client !is null, "Removing from uninitialized MongoCollection.");
		auto conn = m_client.lockConnection();
		ubyte[256] selector_buf = void;
		conn.delete_(m_fullPath, flags, serializeToBson(selector, selector_buf));
	}

	/// ditto
	deprecated("Use `deleteMany` taking `DeleteOptions` instead, this method breaks in MongoDB 5.1 and onwards.")
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
		auto ret = database.runCommandChecked(cmd);
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
		auto ret = database.runCommandChecked(cmd);
		return ret["value"];
	}

	///
	@safe unittest {
		import vibe.db.mongo.mongo;

		void test()
		{
			auto coll = connectMongoDB("127.0.0.1").getCollection("test");
			coll.findAndModifyExt(["name": "foo"], ["$set": ["value": "bar"]], ["new": true]);
		}
	}

	deprecated("deprecated since MongoDB v4.0, use countDocuments or estimatedDocumentCount instead")
	ulong count(T)(T query)
	{
		return countImpl!T(query);
	}

	private ulong countImpl(T)(T query)
	{
		Bson cmd = Bson.emptyObject;
		cmd["count"] = m_name;
		cmd["query"] = serializeToBson(query);
		auto reply = database.runCommandChecked(cmd);
		switch (reply["n"].type) with (Bson.Type) {
			default: assert(false, "Unsupported data type in BSON reply for COUNT");
			case double_: return cast(ulong)reply["n"].get!double; // v2.x
			case int_: return reply["n"].get!int; // v3.x
			case long_: return reply["n"].get!long; // just in case
		}
	}

	/**
		Returns the count of documents that match the query for a collection or
		view.

		The method wraps the `$group` aggregation stage with a `$sum` expression
		to perform the count.

		Throws Exception if a DB communication error occurred.

		See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/method/db.collection.countDocuments/)
	*/
	ulong countDocuments(T)(T filter, CountOptions options = CountOptions.init)
	{
		// https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#count-api-details
		Bson[] pipeline = [Bson(["$match": serializeToBson(filter)])];
		if (!options.skip.isNull)
			pipeline ~= Bson(["$skip": Bson(options.skip.get)]);
		if (!options.limit.isNull)
			pipeline ~= Bson(["$limit": Bson(options.limit.get)]);
		pipeline ~= Bson(["$group": Bson([
			"_id": Bson(1),
			"n": Bson(["$sum": Bson(1)])
		])]);
		AggregateOptions aggOptions;
		foreach (i, field; options.tupleof)
		{
			enum name = CountOptions.tupleof[i].stringof;
			static if (name != "filter" && name != "skip" && name != "limit")
				__traits(getMember, aggOptions, name) = field;
		}
		auto reply = aggregate(pipeline, aggOptions);
		return reply.empty ? 0 : reply.front["n"].to!long;
	}

	/**
		Returns the count of all documents in a collection or view.

		Throws Exception if a DB communication error occurred.

		See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/method/db.collection.estimatedDocumentCount/)
	*/
	ulong estimatedDocumentCount(EstimatedDocumentCountOptions options = EstimatedDocumentCountOptions.init)
	{
		// https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#count-api-details
		MongoConnection conn = m_client.lockConnection();
		if (conn.description.satisfiesVersion(WireVersion.v49)) {
			Bson[] pipeline = [
				Bson(["$collStats": Bson(["count": Bson.emptyObject])]),
				Bson(["$group": Bson([
					"_id": Bson(1),
					"n": Bson(["$sum": Bson("$count")])
				])])
			];
			AggregateOptions aggOptions;
			aggOptions.maxTimeMS = options.maxTimeMS;
			auto reply = aggregate(pipeline, aggOptions).front;
			return reply["n"].to!long;
		} else {
			return countImpl(null);
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
	Bson aggregate(ARGS...)(ARGS pipeline) @safe
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
	MongoCursor!R aggregate(R = Bson, S = Bson)(S[] pipeline, AggregateOptions options) @safe
	{
		assert(m_client !is null, "Querying uninitialized MongoCollection.");

		Bson cmd = Bson.emptyObject; // empty object because order is important
		cmd["aggregate"] = Bson(m_name);
		cmd["$db"] = Bson(m_db.name);
		cmd["pipeline"] = serializeToBson(pipeline);
		MongoConnection conn = m_client.lockConnection();
		enforceWireVersionConstraints(options, conn.description.maxWireVersion);
		foreach (string k, v; serializeToBson(options).byKeyValue)
		{
			// spec recommends to omit cursor field when explain is true
			if (!options.explain.isNull && options.explain.get && k == "cursor")
				continue;
			cmd[k] = v;
		}
		return MongoCursor!R(m_client, cmd,
			!options.batchSize.isNull ? options.batchSize.get : 0,
			!options.maxAwaitTimeMS.isNull ? options.maxAwaitTimeMS.get.msecs
				: !options.maxTimeMS.isNull ? options.maxTimeMS.get.msecs
				: Duration.max);
	}

	/// Example taken from the MongoDB documentation
	@safe unittest {
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
	@safe unittest {
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
			fieldName = Name of the field for which to collect unique values
			query = The query used to select records
			options = Options to apply

		Returns:
			An input range with items of type `R` (`Bson` by default) is
			returned.
	*/
	auto distinct(R = Bson, Q)(string fieldName, Q query, DistinctOptions options = DistinctOptions.init)
	{
		assert(m_client !is null, "Querying uninitialized MongoCollection.");

		Bson cmd = Bson.emptyObject; // empty object because order is important
		cmd["distinct"] = Bson(m_name);
		cmd["key"] = Bson(fieldName);
		cmd["query"] = serializeToBson(query);
		MongoConnection conn = m_client.lockConnection();
		enforceWireVersionConstraints(options, conn.description.maxWireVersion);
		foreach (string k, v; serializeToBson(options).byKeyValue)
			cmd[k] = v;

		import std.algorithm : map;

		auto res = m_db.runCommandChecked(cmd);
		static if (is(R == Bson)) return res["values"].byValue;
		else return res["values"].byValue.map!(b => deserializeBson!R(b));
	}

	///
	@safe unittest {
		import std.algorithm : equal;
		import vibe.db.mongo.mongo;

		void test()
		{
			auto db = connectMongoDB("127.0.0.1").getDatabase("test");
			auto coll = db["collection"];

			coll.drop();
			coll.insertOne(["a": "first", "b": "foo"]);
			coll.insertOne(["a": "first", "b": "bar"]);
			coll.insertOne(["a": "first", "b": "bar"]);
			coll.insertOne(["a": "second", "b": "baz"]);
			coll.insertOne(["a": "second", "b": "bam"]);

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
		database.runCommandChecked(cmd);
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
		database.runCommandChecked(cmd);
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
			database.runCommandChecked(cmd);
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
		CreateIndexesOptions options = CreateIndexesOptions.init,
		string file = __FILE__, size_t line = __LINE__)
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
				enforceWireVersionConstraints(opt_dup, conn.description.maxWireVersion, file, line);
				Bson index = serializeToBson(opt_dup);
				index["key"] = model.keys;
				index["name"] = model.name;
				indexes ~= index;
			}
			cmd["indexes"] = Bson(indexes);
			database.runCommandChecked(cmd);
		} else {
			foreach (model; models) {
				// trusted to support old compilers which think opt_dup has
				// longer lifetime than model.options
				IndexOptions opt_dup = (() @trusted => model.options)();
				enforceWireVersionConstraints(opt_dup, WireVersion.old, file, line);
				Bson doc = serializeToBson(opt_dup);
				doc["v"] = 1;
				doc["key"] = model.keys;
				doc["ns"] = m_fullPath;
				doc["name"] = model.name;
				database["system.indexes"].insertOne(doc);
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
			Bson command = Bson.emptyObject;
			command["listIndexes"] = Bson(m_name);
			command["$db"] = Bson(m_db.name);
			return MongoCursor!R(m_client, command);
		} else {
			throw new MongoDriverException("listIndexes not supported on MongoDB <3.0");
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
		database.runCommandChecked(cmd);
	}
}

///
@safe unittest {
	import vibe.data.bson;
	import vibe.data.json;
	import vibe.db.mongo.mongo;

	void test()
	{
		MongoClient client = connectMongoDB("127.0.0.1");
		MongoCollection users = client.getCollection("myapp.users");

		// canonical version using a Bson object
		users.insertOne(Bson(["name": Bson("admin"), "password": Bson("secret")]));

		// short version using a string[string] AA that is automatically
		// serialized to Bson
		users.insertOne(["name": "admin", "password": "secret"]);

		// BSON specific types are also serialized automatically
		auto uid = BsonObjectID.fromString("507f1f77bcf86cd799439011");
		Bson usr = users.findOne(["_id": uid]);

		// JSON is another possibility
		Json jusr = parseJsonString(`{"name": "admin", "password": "secret"}`);
		users.insertOne(jusr);
	}
}

/// Using the type system to define a document "schema"
@safe unittest {
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
		users.insertOne(usr);

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
  See_Also: $(LINK https://docs.mongodb.com/manual/reference/write-concern/)
 */
struct WriteConcern {
	/**
		If true, wait for the the write operation to get committed to the

		See_Also: $(LINK http://docs.mongodb.org/manual/core/write-concern/#journaled)
	*/
	@embedNullable @name("j")
	Nullable!bool journal;

	/**
		When an integer, specifies the number of nodes that should acknowledge
		the write and MUST be greater than or equal to 0.

		When a string, indicates tags. "majority" is defined, but users could
		specify other custom error modes.
	*/
	@embedNullable
	Nullable!Bson w;

	/**
		If provided, and the write concern is not satisfied within the specified
		timeout (in milliseconds), the server will return an error for the
		operation.

		See_Also: $(LINK http://docs.mongodb.org/manual/core/write-concern/#timeouts)
	*/
	@embedNullable @name("wtimeout")
	Nullable!long wtimeoutMS;
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

/// UDA to warn when a nullable field is set and the server wire version matches
/// the given version. (inclusive)
///
/// Use with $(LREF enforceWireVersionConstraints)
struct DeprecatedSinceWireVersion
{
	///
	WireVersion v;
}

/// ditto
DeprecatedSinceWireVersion deprecatedSince(WireVersion v) @safe { return DeprecatedSinceWireVersion(v); }

/// UDA to throw a MongoException when a nullable field is set and the server
/// wire version doesn't match the version. (inclusive)
///
/// Use with $(LREF enforceWireVersionConstraints)
struct ErrorBeforeWireVersion
{
	///
	WireVersion v;
}

/// ditto
ErrorBeforeWireVersion errorBefore(WireVersion v) @safe { return ErrorBeforeWireVersion(v); }

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
void enforceWireVersionConstraints(T)(ref T field, int serverVersion,
	string file = __FILE__, size_t line = __LINE__)
@safe {
	import std.traits : getUDAs;

	string exception;

	foreach (i, ref v; field.tupleof) {
		enum minV = getUDAs!(field.tupleof[i], MinWireVersion);
		enum maxV = getUDAs!(field.tupleof[i], MaxWireVersion);
		enum deprecateV = getUDAs!(field.tupleof[i], DeprecatedSinceWireVersion);
		enum errorV = getUDAs!(field.tupleof[i], ErrorBeforeWireVersion);

		static foreach (depr; deprecateV)
			if (serverVersion >= depr.v && !v.isNull)
				logInfo("User-set field '%s' is deprecated since MongoDB %s (from %s:%s)",
					T.tupleof[i].stringof, depr.v, file, line);

		static foreach (err; errorV)
			if (serverVersion < err.v && !v.isNull)
				exception ~= format("User-set field '%s' is not supported before MongoDB %s\n",
					T.tupleof[i].stringof, err.v);

		static foreach (min; minV)
			if (serverVersion < min.v)
				v.nullify();

		static foreach (max; maxV)
			if (serverVersion > max.v)
				v.nullify();
	}

	if (exception.length)
		throw new MongoException(exception ~ "from " ~ file ~ ":" ~ line.to!string);
}

///
@safe unittest
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
