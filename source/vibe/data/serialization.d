/**
	Generic serialization framework.

	This module provides general means for implementing (de-)serialization with
	a standardized behavior.

	Serializers are implemented in terms of struct with template methods that
	get called by the serialization framework:

	---
	struct ExampleSerializer {
		enum isSupportedValueType(T) = is(T == string) || is(T == typeof(null));

		// serialization
		auto getSerializedResult();
		void beginWriteDictionary(T)();
		void endWriteDictionary(T)();
		void beginWriteDictionaryEntry(T)(string name);
		void endWriteDictionaryEntry(T)();
		void beginWriteArray(T)(size_t length);
		void endWriteArray(T)();
		void beginWriteArrayEntry(T)();
		void endWriteArrayEntry(T)();
		void writeValue(T)(T value);

		// deserialization
		void readDictionary(T)(scope void delegate(string) entry_callback);
		void readArray(T)(scope void delegate(size_t) size_callback, scope void delegate() entry_callback);
		void readValue(T)();
		bool tryReadNull();
	}
	---

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.data.serialization;

import vibe.internal.meta.uda;

import std.array : Appender, appender;
import std.conv : to;
import std.datetime : Date, DateTime, SysTime;
import std.exception : enforce;
import std.traits;
import std.typetuple;


/**
	Serializes a value with the given serializer.

	The serializer must have a value result for the first form
	to work. Otherwise, use the range based form.

	See_Also: vibe.data.json.JsonSerializer, vibe.data.json.JsonStringSerializer, vibe.data.bson.BsonSerializer
*/
auto serialize(Serializer, T, ARGS...)(T value, ARGS args)
{
	auto serializer = Serializer(args);
	serialize(serializer, value);
	return serializer.getSerializedResult();
}
/// ditto
void serialize(Serializer, T)(ref Serializer serializer, T value)
{
	static assert(Serializer.isSupportedValueType!string, "All serializers must support string values.");
	static assert(Serializer.isSupportedValueType!(typeof(null)), "All serializers must support null values.");

    alias Unqual!T TU;

	static if (Serializer.isSupportedValueType!TU) {
		serializer.writeValue!TU(value);
	} else static if (isArray!TU) {
		alias TV = typeof(value[0]);
		serializer.beginWriteArray!TU(value.length);
		foreach (i, ref el; value) {
			serializer.beginWriteArrayEntry!TV(i);
			serialize(serializer, el);
			serializer.endWriteArrayEntry!TV(i);
		}
		serializer.endWriteArray!TU();
	} else static if (isAssociativeArray!TU) {
		alias TK = KeyType!TU;
		alias TV = ValueType!TU;
		serializer.beginWriteDictionary!TU();
		foreach (key, ref el; value) {
			string keyname;
			static if (is(TK == string)) keyname = key;
			else static if (is(TK : real) || is(TK : long) || is(TK == enum)) keyname = key.to!string;
			else static if (isStringSerializable!TK) keyname = key.toString();
			else static assert(false, "Associative array keys must be strings, numbers, enums, or have toString/fromString methods.");
			serializer.beginWriteDictionaryEntry!TV(keyname);
			serialize(serializer, el);
			serializer.endWriteDictionaryEntry!TV(keyname);
		}
		serializer.endWriteDictionary!TU();
	} else static if (isISOExtStringSerializable!TU) {
		serializer.writeValue(value.toISOExtString());
	} else static if (isStringSerializable!TU) {
		serializer.writeValue(value.toString());
	} else static if (is(TU == struct) || is(TU == class)) {
		static if (!hasSerializableFields!T)
			pragma(msg, "Serializing composite type "~T.stringof~" which has no serializable fields");
		static if (is(TU == class)) {
			if (value is null) {
				serialize(serializer, null);
				return;
			}
		}
		serializer.beginWriteDictionary!TU();
		foreach (mname; __traits(allMembers, TU)) {
			static if (isRWPlainField!(TU, mname) || isRWField!(TU, mname)) {
				alias member = TypeTuple!(__traits(getMember, TU, mname))[0];
				static if (!hasAttribute!(member, IgnoreAttribute)) {
					alias typeof(member) TM;
					enum name = getAttribute!(member, NameAttribute)(NameAttribute(underscoreStrip(mname))).name;
					serializer.beginWriteDictionaryEntry!TM(name);
					static if (is(TM == enum) && hasAttribute!(member, ByNameAttribute)) {
						serialize(serializer, __traits(getMember, value, mname).to!string());
					} else {
						serialize(serializer, cast(OriginalType!TM)__traits(getMember, value, mname));
					}
					serializer.endWriteDictionaryEntry!TM(name);
				}
			}
		}
		serializer.endWriteDictionary!TU();
	} else static if (isPointer!TU) {
		if (value is null) {
			serializer.writeValue(null);
			return;
		}
		serialize(serializer, *value);
	} else static if (is(TU == bool) || is(TU : real) || is(TU : long)) {
		return to!TU(deserialize!string(deserializer));
	} else static assert(false, "Unsupported serialization type: " ~ T.stringof);
}

///
unittest {
	import vibe.data.json;

	struct Test {
		int value;
		string text;
	}

	Test test;
	test.value = 12;
	test.text = "Hello";

	Json serialized = serialize!JsonSerializer(test);
	assert(serialized.value.get!int == 12);
	assert(serialized.text.get!string == "Hello");
}


/**
	Deserializes and returns a serialized value.

	serialized_data can be either an input range or a value containing
	the serialized data, depending on the type of serializer used.

	See_Also: vibe.data.json.JsonSerializer, vibe.data.json.JsonStringSerializer, vibe.data.bson.BsonSerializer
*/
T deserialize(Serializer, T, ARGS...)(ARGS args)
{
	auto deserializer = Serializer(args);
	return deserialize!T(deserializer);
}
/// ditto
private T deserialize(T, Serializer)(ref Serializer deserializer)
{
	static assert(Serializer.isSupportedValueType!string, "All serializers must support string values.");
	static assert(Serializer.isSupportedValueType!(typeof(null)), "All serializers must support null values.");

	static if (Serializer.isSupportedValueType!T) {
		return deserializer.readValue!T();
	} else static if (isStaticArray!T) {
		alias TV = typeof(T.init[0]);
		T ret;
		size_t i = 0;
		deserializer.readArray!T((sz) { assert(sz == 0 || sz == T.length); }, {
			assert(i < T.length);
			ret[i++] = deserialize!TV(deserializer);
		});
		return ret;
	} else static if (isDynamicArray!T) {
		alias TV = typeof(T.init[0]);
		//auto ret = appender!T();
		T ret; // Cannot use appender because of DMD BUG 10690/10859/11357
		deserializer.readArray!T((sz) { ret.reserve(sz); }, () {
			ret ~= deserialize!TV(deserializer);
		});
		return ret;//cast(T)ret.data;
	} else static if (isAssociativeArray!T) {
		alias TK = KeyType!T;
		alias TV = ValueType!T;
		T ret;
		deserializer.readDictionary!T((name) {
			TK key;
			static if (is(TK == string)) key = name;
			else static if (is(TK : real) || is(TK : long) || is(TK == enum)) key = name.to!TK;
			else static if (isStringSerializable!TK) key = TK.fromString(name);
			else static assert(false, "Associative array keys must be strings, numbers, enums, or have toString/fromString methods.");
			ret[key] = deserialize!TV(deserializer);
		});
		return ret;
	} else static if (isISOExtStringSerializable!T) {
		return T.fromISOExtString(deserializer.readValue!string());
	} else static if (isStringSerializable!T) {
		return T.fromString(deserializer.readValue!string());
	} else static if (is(T == struct) || is(T == class)) {
		static if (is(T == class)) {
			if (deserializer.tryReadNull()) return null;
		}

		bool[__traits(allMembers, T).length] set;
		string name;
		T ret;
		static if (is(T == class)) ret = new T;
		deserializer.readDictionary!T((name) {
			if (deserializer.tryReadNull()) return;
			static if (hasSerializableFields!T) {
				switch (name) {
					default: break;
					foreach (i, mname; __traits(allMembers, T)) {
						static if (isRWPlainField!(T, mname) || isRWField!(T, mname)) {
							alias member = TypeTuple!(__traits(getMember, T, mname))[0];
							static if (!hasAttribute!(member, IgnoreAttribute)) {
								alias TM = typeof(__traits(getMember, ret, mname));
								enum fname = getAttribute!(member)(NameAttribute(underscoreStrip(mname))).name;
								case fname:
									set[i] = true;
									static if (is(TM == enum) && hasAttribute!(member, ByNameAttribute)) {
										__traits(getMember, ret, mname) = deserialize!string(deserializer).to!TM();
									} else {
										__traits(getMember, ret, mname) = cast(TM)deserialize!(OriginalType!TM)(deserializer);
									}
									break;
							}
						}
					}
				}
			} else {
				pragma(msg, "Deserializing composite type "~T.stringof~" which has no serializable fields.");
			}
		});
		foreach (i, mname; __traits(allMembers, T))
			static if (isRWPlainField!(T, mname) || isRWField!(T, mname)) {
				alias member = TypeTuple!(__traits(getMember, T, mname))[0];
				static if (!hasAttribute!(member, IgnoreAttribute) && !hasAttribute!(member, OptionalAttribute))
					enforce(set[i], "Missing non-optional field '"~mname~"' of type '"~T.stringof~"'.");
			}
		return ret;
	} else static if (isPointer!T) {
		if (deserializer.isNull()) return null;
		alias PT = PointerTarget!T;
		auto ret = new PT;
		*ret = deserialize!PT(deserializer);
		return ret;
	} else static if (is(T == bool) || is(T : real) || is(T : long)) {
		return to!T(deserialize!string(deserializer));
	} else static assert(false, "Unsupported serialization type: " ~ T.stringof);
}

///
unittest {
	import vibe.data.json;

	struct Test {
		int value;
		string text;
	}

	Json serialized = Json.emptyObject;
	serialized.value = 12;
	serialized.text = "Hello";

	Test test = deserialize!(JsonSerializer, Test)(serialized);
	assert(test.value == 12);
	assert(test.text == "Hello");
}



/**
	Attribute for overriding the field name during (de-)serialization.
*/
NameAttribute name(string name)
{
	return NameAttribute(name);
}
///
unittest {
	struct Test {
		@name("screen-size") int screenSize;
	}
}


/**
	Attribute marking a field as optional during deserialization.
*/
@property OptionalAttribute optional()
{
	return OptionalAttribute();
}
///
unittest {
	struct Test {
		// does not need to be present during deserialization
		@optional int screenSize = 100;
	}
}


/**
	Attribute for marking non-serialized fields.
*/
@property IgnoreAttribute ignore()
{
	return IgnoreAttribute();
}
///
unittest {
	struct Test {
		// is neither serialized not deserialized
		@ignore int screenSize;
	}
}


/**
	Attribute for forcing serialization of enum fields by name instead of by value.
*/
@property ByNameAttribute byName()
{
	return ByNameAttribute();
}
///
unittest {
	enum Color {
		red,
		green,
		blue
	}

	struct Test {
		// serialized as an int (e.g. 1 for Color.green)
		Color color;
		// serialized as a string (e.g. "green" for Color.green)
		@byName Color namedColor;
	}
}


/// 
enum FieldExistence
{
	missing,
	exists,
	defer
}

/// User defined attribute (not intended for direct use)
struct NameAttribute { string name; }
/// ditto
struct OptionalAttribute {}
/// ditto
struct IgnoreAttribute {}
/// ditto
struct ByNameAttribute {}


package template isRWPlainField(T, string M)
{
	static if( !__traits(compiles, typeof(__traits(getMember, T, M))) ){
		enum isRWPlainField = false;
	} else {
		//pragma(msg, T.stringof~"."~M~":"~typeof(__traits(getMember, T, M)).stringof);
		enum isRWPlainField = isRWField!(T, M) && __traits(compiles, *(&__traits(getMember, Tgen!T(), M)) = *(&__traits(getMember, Tgen!T(), M)));
	}
}

package template isRWField(T, string M)
{
	enum isRWField = __traits(compiles, __traits(getMember, Tgen!T(), M) = __traits(getMember, Tgen!T(), M));
	//pragma(msg, T.stringof~"."~M~": "~(isRWField?"1":"0"));
}

package T Tgen(T)(){ return T.init; }

private template hasAttribute(alias decl, T) { enum hasAttribute = findFirstUDA!(T, decl).found; }

private static T getAttribute(alias decl, T)(T default_value)
{
	enum val = findFirstUDA!(T, decl);
	static if (val.found) return val.value;
	else return default_value;
}

private string underscoreStrip(string field_name)
{
	if( field_name.length < 1 || field_name[$-1] != '_' ) return field_name;
	else return field_name[0 .. $-1];
}


private template isISOExtStringSerializable(T) { enum isISOExtStringSerializable = is(typeof(T.init.toISOExtString()) == string) && is(typeof(T.fromISOExtString("")) == T); }

private template hasSerializableFields(T, size_t idx = 0)
{
	static if (idx < __traits(allMembers, T).length) {
		enum mname = __traits(allMembers, T)[idx];
		static if (!isRWPlainField!(T, mname) && !isRWField!(T, mname)) enum hasSerializableFields = hasSerializableFields!(T, idx+1);
		else static if (hasAttribute!(__traits(getMember, T, mname), IgnoreAttribute)) enum hasSerializableFields = hasSerializableFields!(T, idx+1);
		else enum hasSerializableFields = true;
	} else enum hasSerializableFields = false;
}

package template isStringSerializable(T) { enum isStringSerializable = is(typeof(T.init.toString()) == string) && is(typeof(T.fromString("")) == T); }
