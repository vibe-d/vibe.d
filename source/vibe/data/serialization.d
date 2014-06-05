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

	Copyright: © 2013-2014 rejectedsoftware e.K.
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
	serializeImpl!(Serializer, T)(serializer, value);
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

unittest {
	import vibe.data.json;

	// Make sure that immutable(char[]) works just like string
	// (i.e., immutable(char)[]).
	immutable key = "answer";
	auto ints = [key: 42];
	auto serialized = serialize!JsonSerializer(ints);
	assert(serialized[key].get!int == 42);
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
	return deserializeImpl!(T, Serializer)(deserializer);
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


private void serializeImpl(Serializer, T, ATTRIBUTES...)(ref Serializer serializer, T value)
{
	static assert(Serializer.isSupportedValueType!string, "All serializers must support string values.");
	static assert(Serializer.isSupportedValueType!(typeof(null)), "All serializers must support null values.");

	alias Unqual!T TU;

	static if (is(TU == enum)) {
		static if (hasAttributeL!(ByNameAttribute, ATTRIBUTES)) {
			serializeImpl!(Serializer, string)(serializer, value.to!string());
		} else {
			serializeImpl!(Serializer, OriginalType!TU)(serializer, cast(OriginalType!TU)value);
		}
	} else static if (Serializer.isSupportedValueType!TU) {
		serializer.writeValue!TU(value);
	} else static if (isArray!TU) {
		alias TV = typeof(value[0]);
		serializer.beginWriteArray!TU(value.length);
		foreach (i, ref el; value) {
			serializer.beginWriteArrayEntry!TV(i);
			serializeImpl!(Serializer, TV, ATTRIBUTES)(serializer, el);
			serializer.endWriteArrayEntry!TV(i);
		}
		serializer.endWriteArray!TU();
	} else static if (isAssociativeArray!TU) {
		alias TK = KeyType!TU;
		alias TV = ValueType!TU;
		serializer.beginWriteDictionary!TU();
		foreach (key, ref el; value) {
			string keyname;
			static if (is(TK : string)) keyname = key;
			else static if (is(TK : real) || is(TK : long) || is(TK == enum)) keyname = key.to!string;
			else static if (isStringSerializable!TK) keyname = key.toString();
			else static assert(false, "Associative array keys must be strings, numbers, enums, or have toString/fromString methods.");
			serializer.beginWriteDictionaryEntry!TV(keyname);
			serializeImpl!(Serializer, TV, ATTRIBUTES)(serializer, el);
			serializer.endWriteDictionaryEntry!TV(keyname);
		}
		serializer.endWriteDictionary!TU();
	} else static if (isCustomSerializable!T) {
		alias CustomType = typeof(T.init.toRepresentation());
		serializeImpl!(Serializer, CustomType, ATTRIBUTES)(serializer, value.toRepresentation());
	} else static if (isISOExtStringSerializable!TU) {
		serializer.writeValue(value.toISOExtString());
	} else static if (isStringSerializable!TU) {
		serializer.writeValue(value.toString());
	} else static if (is(TU == struct) || is(TU == class)) {
		static if (!hasSerializableFields!TU)
			pragma(msg, "Serializing composite type "~T.stringof~" which has no serializable fields");
		static if (is(TU == class)) {
			if (value is null) {
				serializeImpl!(Serializer, typeof(null))(serializer, null);
				return;
			}
		}
		static if (hasAttributeL!(AsArrayAttribute, ATTRIBUTES)) {
			serializer.beginWriteArray!TU(SerializableFields!TU.length);
			foreach (i, mname; SerializableFields!TU) {
				alias TM = typeof(__traits(getMember, value, mname));
				alias TA = TypeTuple!(__traits(getAttributes, __traits(getMember, T, mname)));
				serializer.beginWriteArrayEntry!TM(i);
				serializeImpl!(Serializer, TM, TA)(serializer, __traits(getMember, value, mname));
				serializer.endWriteArrayEntry!TM(i);
			}
			serializer.endWriteArray!TU();
		} else {
			serializer.beginWriteDictionary!TU();
			foreach (mname; SerializableFields!TU) {
				alias TM = typeof(__traits(getMember, value, mname));
				alias TA = TypeTuple!(__traits(getAttributes, __traits(getMember, T, mname)));
				enum name = getAttribute!(TU, mname, NameAttribute)(NameAttribute(underscoreStrip(mname))).name;
				serializer.beginWriteDictionaryEntry!TM(name);
				serializeImpl!(Serializer, TM, TA)(serializer, __traits(getMember, value, mname));
				serializer.endWriteDictionaryEntry!TM(name);
			}
			serializer.endWriteDictionary!TU();
		}
	} else static if (isPointer!TU) {
		if (value is null) {
			serializer.writeValue(null);
			return;
		}
		serializeImpl!(Serializer, PointerTarget!TU)(serializer, *value);
	} else static if (is(TU == bool) || is(TU : real) || is(TU : long)) {
		serializeImpl!(Serializer, string)(serializer, to!string(value));
	} else static assert(false, "Unsupported serialization type: " ~ T.stringof);
}


private T deserializeImpl(T, Serializer, ATTRIBUTES...)(ref Serializer deserializer)
{
	static assert(Serializer.isSupportedValueType!string, "All serializers must support string values.");
	static assert(Serializer.isSupportedValueType!(typeof(null)), "All serializers must support null values.");

	static if (is(T == enum)) {
		static if (hasAttributeL!(ByNameAttribute, ATTRIBUTES)) {
			return deserializeImpl!(string, Serializer)(deserializer).to!T();
		} else {
			return cast(T)deserializeImpl!(OriginalType!T, Serializer)(deserializer);
		}
	} else static if (Serializer.isSupportedValueType!T) {
		return deserializer.readValue!T();
	} else static if (isStaticArray!T) {
		alias TV = typeof(T.init[0]);
		T ret;
		size_t i = 0;
		deserializer.readArray!T((sz) { assert(sz == 0 || sz == T.length); }, {
			assert(i < T.length);
			ret[i++] = deserializeImpl!(TV, Serializer, ATTRIBUTES)(deserializer);
		});
		return ret;
	} else static if (isDynamicArray!T) {
		alias TV = typeof(T.init[0]);
		//auto ret = appender!T();
		T ret; // Cannot use appender because of DMD BUG 10690/10859/11357
		deserializer.readArray!T((sz) { ret.reserve(sz); }, () {
			ret ~= deserializeImpl!(TV, Serializer, ATTRIBUTES)(deserializer);
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
			ret[key] = deserializeImpl!(TV, Serializer, ATTRIBUTES)(deserializer);
		});
		return ret;
	} else static if (isCustomSerializable!T) {
		alias CustomType = typeof(T.init.toRepresentation());
		return T.fromRepresentation(deserializeImpl!(CustomType, Serializer, ATTRIBUTES)(deserializer));
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

		static if (hasAttributeL!(AsArrayAttribute, ATTRIBUTES)) {
			size_t idx = 0;
			deserializer.readArray!T((sz){}, {
				if (deserializer.tryReadNull()) return;
				static if (hasSerializableFields!T) {
					switch (idx++) {
						default: break;
						foreach (i, mname; SerializableFields!T) {
							alias TM = typeof(__traits(getMember, ret, mname));
							alias TA = TypeTuple!(__traits(getAttributes, __traits(getMember, ret, mname)));
							case i:
								set[i] = true;
								__traits(getMember, ret, mname) = deserializeImpl!(TM, Serializer, TA)(deserializer);
								break;
						}
					}
				} else {
					pragma(msg, "Deserializing composite type "~T.stringof~" which has no serializable fields.");
				}
			});
		} else {
			deserializer.readDictionary!T((name) {
				if (deserializer.tryReadNull()) return;
				static if (hasSerializableFields!T) {
					switch (name) {
						default: break;
						foreach (i, mname; SerializableFields!T) {
							alias TM = typeof(__traits(getMember, ret, mname));
							alias TA = TypeTuple!(__traits(getAttributes, __traits(getMember, ret, mname)));
							enum fname = getAttribute!(T, mname, NameAttribute)(NameAttribute(underscoreStrip(mname))).name;
							case fname:
								set[i] = true;
								__traits(getMember, ret, mname) = deserializeImpl!(TM, Serializer, TA)(deserializer);
								break;
						}
					}
				} else {
					pragma(msg, "Deserializing composite type "~T.stringof~" which has no serializable fields.");
				}
			});
		}
		foreach (i, mname; SerializableFields!T)
			static if (!hasAttribute!(OptionalAttribute, __traits(getMember, T, mname)))
				enforce(set[i], "Missing non-optional field '"~mname~"' of type '"~T.stringof~"'.");
		return ret;
	} else static if (isPointer!T) {
		if (deserializer.isNull()) return null;
		alias PT = PointerTarget!T;
		auto ret = new PT;
		*ret = deserializeImpl!PT(deserializer);
		return ret;
	} else static if (is(T == bool) || is(T : real) || is(T : long)) {
		return to!T(deserializeImpl!string(deserializer));
	} else static assert(false, "Unsupported serialization type: " ~ T.stringof);
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
		// serialized as array of ints
		Color[] colorArray;
		// serialized as array of strings
		@byName Color[] namedColorArray;
	}
}


/**
	Attribute for representing a struct/class as an array instead of an object.

	Usually structs and class objects are serialized as dictionaries mapping
	from field name to value. Using this attribute, they will be serialized
	as a flat array instead. Note that changing the layout will make any
	already serialized data mismatch when this attribute is used.
*/
@property AsArrayAttribute asArray()
{
	return AsArrayAttribute();
}
///
unittest {
	struct Fields {
		int f1;
		string f2;
		double f3;
	}

	struct Test {
		// serialized as name:value pairs ["f1": int, "f2": string, "f3": double]
		Fields object;
		// serialized as a sequential list of values [int, string, double]
		@asArray Fields array;
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
/// ditto
struct AsArrayAttribute {}

/**
	Checks if a given type has a custom serialization representation.

	A class or struct type is custom serializable if it defines a pair of
	$(D toRepresentation)/$(D fromRepresentation) methods. Any class or
	struct type that has this trait will be serialized by using the return
	value of it's $(D toRepresentation) method instead of the original value.

	This trait has precedence over $(D isISOExtStringSerializable) and
	$(D isStringSerializable).
*/
template isCustomSerializable(T)
{
	enum bool isCustomSerializable = is(typeof(T.init.toRepresentation())) && is(typeof(T.fromRepresentation(T.init.toRepresentation())) == T);
}
///
unittest {
	// represented as a single uint when serialized
	static struct S {
		ushort x, y;

		uint toRepresentation() const { return x + (y << 16); }
		static S fromRepresentation(uint i) { return S(i & 0xFFFF, i >> 16); }
	}

	static assert(isCustomSerializable!S);
}


/**
	Checks if a given type has an ISO extended string serialization representation.

	A class or struct type is ISO extended string serializable if it defines a
	pair of $(D toISOExtString)/$(D fromISOExtString) methods. Any class or
	struct type that has this trait will be serialized by using the return
	value of it's $(D toISOExtString) method instead of the original value.

	This is mainly useful for supporting serialization of the the date/time
	types in $(D std.datetime).

	This trait has precedence over $(D isStringSerializable).
*/
template isISOExtStringSerializable(T)
{
	enum bool isISOExtStringSerializable = is(typeof(T.init.toISOExtString()) == string) && is(typeof(T.fromISOExtString("")) == T);
}
///
unittest {
	import std.datetime;

	static assert(isISOExtStringSerializable!DateTime);
	static assert(isISOExtStringSerializable!SysTime);

	// represented as an ISO extended string when serialized
	static struct S {
		// dummy example implementations
		string toISOExtString() const { return ""; }
		static S fromISOExtString(string s) { return S.init; }
	}

	static assert(isISOExtStringSerializable!S);
}


/**
	Checks if a given type has a string serialization representation.

	A class or struct type is string serializable if it defines a pair of
	$(D toString)/$(D fromString) methods. Any class or struct type that
	has this trait will be serialized by using the return value of it's
	$(D toString) method instead of the original value.
*/
template isStringSerializable(T)
{
	enum bool isStringSerializable = is(typeof(T.init.toString()) == string) && is(typeof(T.fromString("")) == T);
}
///
unittest {
	import std.conv;

	// represented as a string when serialized
	static struct S {
		int value;
		
		// dummy example implementations
		string toString() const { return value.to!string(); }
		static S fromString(string s) { return S(s.to!int()); }
	}

	static assert(isStringSerializable!S);
}


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

private template hasAttribute(T, alias decl) { enum hasAttribute = findFirstUDA!(T, decl).found; }

unittest {
	@asArray int i1;
	static assert(hasAttribute!(AsArrayAttribute, i1));
	int i2;
	static assert(!hasAttribute!(AsArrayAttribute, i2));
}

private template hasAttributeL(T, ATTRIBUTES...) {
	static if (ATTRIBUTES.length == 1) {
		enum hasAttributeL = is(typeof(ATTRIBUTES[0]) == T);
	} else static if (ATTRIBUTES.length > 1) {
		enum hasAttributeL = hasAttributeL!(T, ATTRIBUTES[0 .. $/2]) || hasAttributeL!(T, ATTRIBUTES[$/2 .. $]);
	} else {
		enum hasAttributeL = false;
	}
}

unittest {
	static assert(hasAttributeL!(AsArrayAttribute, byName, asArray));
	static assert(!hasAttributeL!(AsArrayAttribute, byName));
}

private static T getAttribute(TT, string mname, T)(T default_value)
{
	enum val = findFirstUDA!(T, __traits(getMember, TT, mname));
	static if (val.found) return val.value;
	else return default_value;
}

private string underscoreStrip(string field_name)
{
	if( field_name.length < 1 || field_name[$-1] != '_' ) return field_name;
	else return field_name[0 .. $-1];
}


private template hasSerializableFields(T, size_t idx = 0)
{
	enum hasSerializableFields = SerializableFields!(T).length > 0;
	/*static if (idx < __traits(allMembers, T).length) {
		enum mname = __traits(allMembers, T)[idx];
		static if (!isRWPlainField!(T, mname) && !isRWField!(T, mname)) enum hasSerializableFields = hasSerializableFields!(T, idx+1);
		else static if (hasAttribute!(IgnoreAttribute, __traits(getMember, T, mname))) enum hasSerializableFields = hasSerializableFields!(T, idx+1);
		else enum hasSerializableFields = true;
	} else enum hasSerializableFields = false;*/
}

private template SerializableFields(COMPOSITE)
{
	alias SerializableFields = FilterSerializableFields!(COMPOSITE, __traits(allMembers, COMPOSITE));
}

private template FilterSerializableFields(COMPOSITE, FIELDS...)
{
	static if (FIELDS.length > 1) {
		alias FilterSerializableFields = TypeTuple!(
			FilterSerializableFields!(COMPOSITE, FIELDS[0 .. $/2]),
			FilterSerializableFields!(COMPOSITE, FIELDS[$/2 .. $]));
	} else static if (FIELDS.length == 1) {
		alias T = COMPOSITE;
		enum mname = FIELDS[0];
		static if (isRWPlainField!(T, mname) || isRWField!(T, mname)) {
			static if (!hasAttribute!(IgnoreAttribute, __traits(getMember, T, mname)))
				alias FilterSerializableFields = TypeTuple!(mname);
			else alias FilterSerializableFields = TypeTuple!();
		} else alias FilterSerializableFields = TypeTuple!();
	} else alias FilterSerializableFields = TypeTuple!();
}
