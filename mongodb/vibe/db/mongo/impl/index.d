module vibe.db.mongo.impl.index;

/**
	Implements the MongoDB standard API for the Index Management specification.

	Standards: https://github.com/mongodb/specifications/blob/0c6e56141c867907aacf386e0cbe56d6562a0614/source/index-management.rst#standard-api
*/
mixin template MongoCollectionIndexStandardAPIImpl()
{
	/**
		Creates or updates an index.

		Note that the overload taking an associative array of field orders
		will be removed. Since the order of fields matters, it is
		only suitable for single-field indices.
	*/
	void ensureIndex(scope const(Tuple!(string, int))[] field_orders, IndexFlags flags = IndexFlags.none, Duration expire_time = 0.seconds)
	@safe {
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
		if (flags & IndexFlags.unique) doc["unique"] = true;
		if (flags & IndexFlags.dropDuplicates) doc["dropDups"] = true;
		if (flags & IndexFlags.background) doc["background"] = true;
		if (flags & IndexFlags.sparse) doc["sparse"] = true;
		if (flags & IndexFlags.expireAfterSeconds) doc["expireAfterSeconds"] = expire_time.total!"seconds";
		database["system.indexes"].insert(doc);
	}

	/// ditto
	deprecated("Use the overload taking an array of field_orders instead.")
	void ensureIndex(int[string] field_orders, IndexFlags flags = IndexFlags.none, ulong expireAfterSeconds = 0)
	@safe {
		Tuple!(string, int)[] orders;
		foreach (k, v; field_orders)
			orders ~= tuple(k, v);
		ensureIndex(orders, flags, expireAfterSeconds.seconds);
	}

	/**
		Drops or removes the specified index from the collection.
	*/
	void dropIndex(string name)
	@safe {
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

	/**
		Creates indexes on the collection.
	*/
	void createIndex(T)(T query) 
	@safe {
		static struct Indexes {
			T key;
		}

		static struct CMD {
			string createIndexes;
			Indexes indexes;
		}

		CMD cmd;
		cmd.createIndexes = m_name;
		cmd.indexes.key = query;
		auto reply = database.runCommand(cmd);
		enforce(reply["ok"].get!double == 1, "createIndex command failed: "~reply["errmsg"].opt!string);
	}

	/**
		Returns an array that holds a list of documents that identify and describe the existing indexes on the collection. 
	*/
	MongoCursor!R getIndexes(T = Bson, R = Bson)() 
	@safe {
		static struct CMD {
			string listIndexes;
		}

		CMD cmd;
		cmd.listIndexes = m_name;

		auto reply = database.runCommand(cmd);
		enforce(reply["ok"].get!double == 1, "getIndexes command failed: "~reply["errmsg"].opt!string);
		return MongoCursor!R(m_client, reply["cursor"]["ns"].get!string, reply["cursor"]["id"].get!long, reply["cursor"]["firstBatch"].get!(Bson[]));
	}
}