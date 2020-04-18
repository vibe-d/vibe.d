module vibe.db.mongo.impl.index;

@safe:

import core.time;

import std.array;
import std.typecons;
import std.traits : Unqual;

import vibe.db.mongo.collection;
import vibe.db.mongo.connection;
import vibe.db.mongo.mongo;

/**
	Implements the MongoDB standard API for the Index Management specification.

	Standards: https://github.com/mongodb/specifications/blob/0c6e56141c867907aacf386e0cbe56d6562a0614/source/index-management.rst#standard-api
*/
mixin template MongoCollectionIndexStandardAPIImpl()
{
	deprecated("This is a legacy API, call createIndexes instead")
	void ensureIndex(scope const(Tuple!(string, int))[] field_orders, IndexFlags flags = IndexFlags.none, Duration expire_time = 0.seconds)
	@safe {
		scope IndexModel[] models = new IndexModel[field_orders.length];
		IndexOptions options;
		if (flags & IndexFlags.unique) options.unique = true;
		if (flags & IndexFlags.dropDuplicates) options.dropDups = true;
		if (flags & IndexFlags.background) options.background = true;
		if (flags & IndexFlags.sparse) options.sparse = true;
		if (flags & IndexFlags.expireAfterSeconds) options.expireAfter = expire_time;

		foreach (field; field_orders) {
			models ~= IndexModel().add(field[0], field[1]).withOptions(options);
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
				IndexOptions opt_dup = model.options;
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
				IndexOptions opt_dup = model.options;
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

	deprecated("Please use the standard API name 'listIndexes'") alias getIndexes = listIndexes;
}

deprecated("Use CreateIndexOptions instead")
enum IndexFlags {
	none = 0,
	unique = 1<<0,
	dropDuplicates = 1<<2,
	background = 1<<3,
	sparse = 1<<4,
	expireAfterSeconds = 1<<5,

	None = none, /// Deprecated compatibility alias, use `none` instead.
	Unique = unique, /// Deprecated compatibility alias, use `unique` instead.
	DropDuplicates = dropDuplicates, /// Deprecated compatibility alias, use `dropDuplicates` instead.
	Background = background, /// Deprecated compatibility alias, use `background` instead.
	Sparse = sparse, /// Deprecated compatibility alias, use `sparse` instead.
	ExpireAfterSeconds = expireAfterSeconds, /// Deprecated compatibility alias, use `expireAfterSeconds` instead.
}

// workaround for old dmd versions
private enum Bson bsonEmptyObject = Bson(Bson.Type.object, cast(ubyte[]) [5,0,0,0,0]);

struct IndexModel
{
	Bson keys = bsonEmptyObject;
	IndexOptions options;

	/**
		Adds a single field or multikey index with a direction.

		Call this method multiple times with different fields to create a
		compound index.

		Params:
		  field = the name of the field to index
		  direction = `1` for ascending or `-1` for descending

		Returns: this IndexModel instance (caller)
	*/
	ref IndexModel add(string field, int direction)
	@safe {
		// bson objects keep order
		keys[field] = Bson(direction);
		return this;
	}

	/**
		Adds an index with a given index type. Use `IndexType` for a type-safe
		setting of the string.

		Params:
		  field = the name of the field to index
		  type = the index type to use

		Returns: this IndexModel instance (caller)
	*/
	ref IndexModel add(string field, string type)
	@safe {
		// bson objects keep order
		keys[field] = Bson(type);
		return this;
	}

	/**
		Sets the options member of this IndexModel.

		Returns: this IndexModel instance (caller)
	*/
	ref IndexModel withOptions(IndexOptions options)
	@safe {
		this.options = options;
		return this;
	}

	string name() const
	@property @safe {
		if (options.name.length)
		{
			return options.name;
		}
		else
		{
			auto indexname = appender!string();
			bool first = true;
			foreach (string key, value; keys.byKeyValue) {
				if (!first) indexname.put('_');
				else first = false;
				indexname.put(key);
				indexname.put('_');

				if (value.type == Bson.Type.string)
					indexname.put(value.get!string);
				else
					indexname.put(value.toString());
			}
			return indexname.data;
		}
	}
}

/**
	Specifies the different index types which are available for index creation.

	See_Also: $(LINK https://docs.mongodb.com/manual/indexes/#index-types)
*/
enum IndexType : string
{
	/**
		Legacy 2D plane index used in MongoDB 2.2 and earlier. Doesn't support
		GeoJSON objects. Uses planar geometry to return results.

		See_Also: $(LINK https://docs.mongodb.com/manual/core/2d/)
	*/
	legacy2D = "2d",

	/**
		2D sphere index that calculates geometries on an earth-like sphere.
		Supports storing as GeoJSON objects.

		See_Also: $(LINK https://docs.mongodb.com/manual/core/2dsphere/)
	*/
	sphere2D = "2dsphere",

	/**
		A geoHaystack index is a special index that is optimized to return
		results over small areas. geoHaystack indexes improve performance on
		queries that use flat geometry.

		See_Also: $(LINK https://docs.mongodb.com/manual/core/geohaystack/)
	*/
	geoHaystack = "geoHaystack",

	/**
		Creates a text index which supports searching for string content in a
		collection. These text indexes do not store language-specific stop words
		and stem the words in a collection to only store root words.

		See_Also: $(LINK https://docs.mongodb.com/manual/core/index-text/)
	*/
	text = "text",

	/**
		To support hash based sharding, MongoDB provides a hashed index type,
		which indexes the hash of the value of a field. These indexes have a
		more random distribution of values along their range, but only support
		equality matches and cannot support range-based queries.

		See_Also: $(LINK https://docs.mongodb.com/manual/core/index-hashed/)
	*/
	hashed = "hashed",
}

/**
	See_Also: $(LINK https://docs.mongodb.com/manual/reference/command/createIndexes/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/0c6e56141c867907aacf386e0cbe56d6562a0614/source/index-management.rst#common-api-components)
*/
struct IndexOptions
{
	/**
		Specifying true directs MongoDB to build the index in the background.
		Background builds do not block operations on the collection.
		Since MongoDB 4.2 indices are built on the background by default.
		In MongoDB 4.0 and before, this defaults to `false`.
	*/
	@embedNullable @until(WireVersion.v42)
	Nullable!bool background;

	/**
		Specifies the length in time, in seconds, for documents to remain in a
		collection.
	*/
	@embedNullable Nullable!int expireAfterSeconds;

	void expireAfter(Duration d)
	@safe {
		expireAfterSeconds = cast(int)d.total!"seconds";
	}

	/**
		Optionally specify a specific name for the index outside of the default
		generated name. If none is provided then the name is generated in the
		format "[field]_[direction]"
	*/
	@ignore string name;

	/**
		Tells the index to only reference documents with the specified field in
		the index.
	*/
	@embedNullable Nullable!bool sparse;

	/**
		Allows configuring the storage engine on a per-index basis.
	*/
	@embedNullable @since(WireVersion.v30)
	Nullable!Bson storageEngine;

	/**
		Forces the index to be unique.
	*/
	@embedNullable Nullable!bool unique;

	/**
		Creates a unique index on a field that may have duplicates.
	*/
	@embedNullable @until(WireVersion.v26)
	Nullable!bool dropDups;

	/**
		Specifies the index version number, either 0 or 1.
	*/
	@embedNullable @(.name("v")) @until(WireVersion.v26)
	Nullable!int version_;

	/**
		Default language for text indexes. Is "english" if none is provided.
	*/
	@embedNullable @(.name("default_language"))
	Nullable!string defaultLanguage;

	/**
		Specifies the field in the document to override the language.
	*/
	@embedNullable @(.name("language_override"))
	Nullable!string languageOverride;

	/**
		Sets the text index version number.

		MongoDB 2.4 can only support version 1.

		MongoDB 2.6 and higher may support version 1 or 2.
	*/
	@embedNullable @since(WireVersion.v26)
	Nullable!int textIndexVersion;

	/**
		Specifies fields in the index and their corresponding weight values.
	*/
	@embedNullable Nullable!Bson weights;

	/**
		Sets the 2dsphere index version number.

		MongoDB 2.4 can only support version 1.

		MongoDB 2.6 and higher may support version 1 or 2.

		MongoDB 3.2 and higher may support version 2 or 3.
	*/
	@embedNullable @(.name("2dsphereIndexVersion")) @since(WireVersion.v26)
	Nullable!int _2dsphereIndexVersion;

	/**
		For 2d indexes, the number of precision of the stored geo hash value of
		the location data.
	*/
	@embedNullable Nullable!int bits;

	/**
		For 2d indexes, the upper inclusive boundary for the longitude and
		latitude values.
	*/
	@embedNullable Nullable!double max;

	/**
		For 2d indexes, the lower inclusive boundary for the longitude and
		latitude values.
	*/
	@embedNullable Nullable!double min;

	/**
		For geoHaystack indexes, specify the number of units within which to
		group the location values; i.e. group in the same bucket those location
		values that are within the specified number of units to each other.

		The value must be greater than 0.
	*/
	@embedNullable Nullable!double bucketSize;

	/**
		If specified, the index only references documents that match the filter
		expression. See
		$(LINK2 https://docs.mongodb.com/manual/core/index-partial/, Partial Indexes)
		for more information.
	*/
	@embedNullable @since(WireVersion.v32)
	Nullable!Bson partialFilterExpression;

	/**
		Collation allows users to specify language-specific rules for string
		comparison, such as rules for letter-case and accent marks.
	*/
	@embedNullable @since(WireVersion.v34)
	Nullable!Collation collation;

	/**
		Allows users to include or exclude specific field paths from a wildcard
		index using the `{ "$**": 1 }` key pattern.
	*/
	@embedNullable @since(WireVersion.v42)
	Nullable!Bson wildcardProjection;
}

/// Standards: $(LINK https://github.com/mongodb/specifications/blob/0c6e56141c867907aacf386e0cbe56d6562a0614/source/index-management.rst#common-api-components)
struct CreateIndexOptions
{
	/**
		The maximum amount of time to allow the index build to take before
		returning an error. (not implemented)
	*/
	@embedNullable Nullable!long maxTimeMS;
}

/// Same as $(LREF CreateIndexOptions)
alias CreateIndexesOptions = CreateIndexOptions;

/// Standards: $(LINK https://github.com/mongodb/specifications/blob/f4020bdb6ec093fcd259984e6ff6f42356b17d0e/source/index-management.rst#standard-api)
struct DropIndexOptions
{
	/**
		The maximum amount of time to allow the index drop to take before
		returning an error. (not implemented)
	*/
	@embedNullable Nullable!long maxTimeMS;
}

/// Same as $(LREF DropIndexOptions)
alias DropIndexesOptions = DropIndexOptions;
