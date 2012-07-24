/**
	MongoCollection class

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.collection;

public import vibe.db.mongo.cursor;
public import vibe.db.mongo.connection;

import vibe.db.mongo.db;

import std.algorithm : countUntil;


/**
	Represents a single collection inside a MongoDB.

	All methods take arbitrary types for Bson arguments. serializeToBson() is implicitly called on
	them before they are send to the database. The following example shows some possible ways
	to specify objects.

	Examples:

	---
	MongoDB db = connectMongoDB("127.0.0.1");
	MongoCollection users = m_db["myapp.users"];

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
		MongoDB m_db;
		string m_collection;
	}

	this(MongoDB db, string collection_name)
	{
		assert(db !is null);
		m_db = db;
		m_collection = collection_name;
	}

	/**
		Performs an update operation on documents matching 'selector', updating them with 'update'.

		Throws: Exception if a DB communication error occured.
		See_Also: $(LINK http://www.mongodb.org/display/DOCS/Updating)
	*/
	void update(T, U)(T selector, U update, UpdateFlags flags = UpdateFlags.None)
	{
		auto conn = m_db.lockConnection();
		conn.update(m_collection, flags, serializeToBson(selector), serializeToBson(update));
	}

	/**
		Inserts new documents into the collection.

		Throws: Exception if a DB communication error occured.
		See_Also: $(LINK http://www.mongodb.org/display/DOCS/Inserting)
	*/
	void insert(T)(T document_or_documents, InsertFlags flags = InsertFlags.None)
	{
		auto conn = m_db.lockConnection();
		Bson[] docs;
		Bson bdocs = serializeToBson(document_or_documents);
		if( bdocs.type == Bson.Type.Array ) docs = cast(Bson[])bdocs;
		else docs ~= bdocs;
		conn.insert(m_collection, flags, docs);
	}

	/**
		Queries the collection for existing documents.

		Throws: Exception if a DB communication error or a query error occured.
		See_Also: $(LINK http://www.mongodb.org/display/DOCS/Querying)
	*/
	MongoCursor find(T, U = typeof(null))(T query, U returnFieldSelector = null, QueryFlags flags = QueryFlags.None, int num_skip = 0, int num_docs_per_chunk = 0)
	{
		auto conn = m_db.lockConnection();
		auto reply = conn.query(m_collection, flags, num_skip, num_docs_per_chunk, serializeToBson(query), returnFieldSelector is null ? Bson(null) : serializeToBson(returnFieldSelector));
		return MongoCursor(m_db, m_collection, num_docs_per_chunk, reply);
	}

	/**
		Queries the collection for existing documents.

		Returns: the first match or null
		Throws: Exception if a DB communication error or a query error occured.
		See_Also: $(LINK http://www.mongodb.org/display/DOCS/Querying)
	*/
	Bson findOne(T, U = typeof(null))(T query, U returnFieldSelector = null, QueryFlags flags = QueryFlags.None)
	{
		auto c = find(query, returnFieldSelector, flags, 0, 1);
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
		auto conn = m_db.lockConnection();
		conn.delete_(m_collection, flags, serializeToBson(selector));
	}

	/**
		Combines a modify and find operation to a single atomic operation.

		Throws Exception if a DB communication error occured.
		See_Also: $(LINK http://www.mongodb.org/display/DOCS/findAndModify+Command)
	*/
	Bson findAndModify(T, U, V)(T query, U update, V returnFieldSelector = null)
	{
		auto cidx = m_collection.countUntil('.');
		string dbstr = m_collection[0 .. cidx];
		string collstr = m_collection[cidx+1 .. $];
		Bson[string] cmd;
		cmd["findAndModify"] = Bson(collstr);
		cmd["query"] = serializeToBson(query);
		cmd["update"] = serializeToBson(update);
		if( returnFieldSelector != null )
			cmd["fields"] = serializeToBson(returnFieldSelector);
		return m_db.runCommand(dbstr, cmd);
	}
}

