/**
	MongoDB index API definitions.

	Copyright: © 2020-2022 Jan Jurzitza
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Jurzitza
*/
module vibe.db.mongo.impl.index;

@safe:

import core.time;

import std.array;
import std.typecons;

import vibe.db.mongo.collection;
import vibe.data.bson;

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

struct IndexModel
{
	Bson keys = Bson.emptyObject;
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
	ref IndexModel add(string field, int direction) return
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
	ref IndexModel add(string field, string type) return
	@safe {
		// bson objects keep order
		keys[field] = Bson(type);
		return this;
	}

	/**
		Sets the options member of this IndexModel.

		Returns: this IndexModel instance (caller)
	*/
	ref IndexModel withOptions(IndexOptions options) return
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
