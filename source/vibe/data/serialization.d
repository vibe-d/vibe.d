/**
	Generic serialization framework.

	This module provides general means for implementing (de-)serialization with
	a standardized behavior.

	Supported_types:
		The following rules are applied in order when serializing or
		deserializing a certain type:

		$(OL
			$(LI An `enum` type is serialized as its raw value, except if
				`@byName` is used, in which case the name of the enum value
				is serialized.)
			$(LI Any type that is specifically supported by the serializer
				is directly serialized. For example, the BSON serializer
				supports `BsonObjectID` directly.)
			$(LI Arrays and tuples (`std.typecons.Tuple`) are serialized
				using the array serialization functions where each element is
				serialized again according to these rules.)
			$(LI Associative arrays are serialized similar to arrays. The key
				type of the AA must satisfy the `isStringSerializable` trait
				and will always be serialized as a string.)
			$(LI Any `Nullable!T` will be serialized as either `null`, or
				as the contained value (subject to these rules again).)
			$(LI Any `BitFlags!T` value will be serialized as `T[]`)
			$(LI Types satisfying the `isPolicySerializable` trait for the
				supplied `Policy` will be serialized as the value returned
				by the policy `toRepresentation` function (again subject to
				these rules).)
			$(LI Types satisfying the `isCustomSerializable` trait will be
				serialized as the value returned by their `toRepresentation`
				method (again subject to these rules).)
			$(LI Types satisfying the `isISOExtStringSerializable` trait will be
				serialized as a string, as returned by their `toISOExtString`
				method. This causes types such as `SysTime` to be serialized
				as strings.)
			$(LI Types satisfying the `isStringSerializable` trait will be
				serialized as a string, as returned by their `toString`
				method.)
			$(LI Struct and class types by default will be serialized as
				associative arrays, where the key is the name of the
				corresponding field (can be overridden using the `@name`
				attribute). If the struct/class is annotated with `@asArray`,
				it will instead be serialized as a flat array of values in the
				order of declaration. Null class references will be serialized
				as `null`.)
			$(LI Pointer types will be serialized as either `null`, or as
				the value they point to.)
			$(LI Built-in integers and floating point values, as well as
				boolean values will be converted to strings, if the serializer
				doesn't support them directly.)
		)

		Note that no aliasing detection is performed, so that pointers, class
		references and arrays referencing the same memory will be serialized
		as multiple copies. When in turn deserializing the data, they will also
		end up as separate copies in memory.

	Serializer_implementation:
		Serializers are implemented in terms of a struct with template methods that
		get called by the serialization framework:

		---
		struct ExampleSerializer {
			enum isSupportedValueType(T) = is(T == string) || is(T == typeof(null));

			// serialization
			auto getSerializedResult();
			void beginWriteDictionary(T)();
			void endWriteDictionary(T)();
			void beginWriteDictionaryEntry(T)(string name);
			void endWriteDictionaryEntry(T)(string name);
			void beginWriteArray(T)(size_t length);
			void endWriteArray(T)();
			void beginWriteArrayEntry(T)(size_t index);
			void endWriteArrayEntry(T)(size_t index);
			void writeValue(T)(T value);

			// deserialization
			void readDictionary(T)(scope void delegate(string) entry_callback);
			void readArray(T)(scope void delegate(size_t) size_callback, scope void delegate() entry_callback);
			T readValue(T)();
			bool tryReadNull();
		}
		---

	Copyright: © 2013-2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.data.serialization;

import vibe.internal.meta.traits;
import vibe.internal.meta.uda;

import std.array : Appender, appender;
import std.conv : to;
import std.exception : enforce;
import std.traits;
import std.typetuple;


/**
	Serializes a value with the given serializer.

	The serializer must have a value result for the first form
	to work. Otherwise, use the range based form.

	See_Also: `vibe.data.json.JsonSerializer`, `vibe.data.json.JsonStringSerializer`, `vibe.data.bson.BsonSerializer`
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
	serializeImpl!(Serializer, DefaultPolicy, T)(serializer, value);
}

/** Note that there is a convenience function `vibe.data.json.serializeToJson`
	that can be used instead of manually invoking `serialize`.
*/
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
	Serializes a value with the given serializer, representing values according to `Policy` when possible.

	The serializer must have a value result for the first form
	to work. Otherwise, use the range based form.

	See_Also: `vibe.data.json.JsonSerializer`, `vibe.data.json.JsonStringSerializer`, `vibe.data.bson.BsonSerializer`
*/
auto serializeWithPolicy(Serializer, alias Policy, T, ARGS...)(T value, ARGS args)
{
	auto serializer = Serializer(args);
	serializeWithPolicy!(Serializer, Policy)(serializer, value);
	return serializer.getSerializedResult();
}
/// ditto
void serializeWithPolicy(Serializer, alias Policy, T)(ref Serializer serializer, T value)
{
	serializeImpl!(Serializer, Policy, T)(serializer, value);
}
///
version (unittest)
{
	template SizePol(T)
	{
		import std.conv;
		import std.array;

		string toRepresentation(T value) {
			return to!string(value.x) ~ "x" ~ to!string(value.y);
		}

		T fromRepresentation(string value) {
			string[] fields = value.split('x');
			alias fieldT = typeof(T.x);
			auto x = to!fieldT(fields[0]);
			auto y = to!fieldT(fields[1]);
			return T(x, y);
		}
	}
}

///
unittest {
	import vibe.data.json;

	static struct SizeI {
		int x;
		int y;
	}
	SizeI sizeI = SizeI(1,2);
	Json serializedI = serializeWithPolicy!(JsonSerializer, SizePol)(sizeI);
	assert(serializedI.get!string == "1x2");

	static struct SizeF {
		float x;
		float y;
	}
	SizeF sizeF = SizeF(0.1f,0.2f);
	Json serializedF = serializeWithPolicy!(JsonSerializer, SizePol)(sizeF);
	assert(serializedF.get!string == "0.1x0.2");
}


/**
	Deserializes and returns a serialized value.

	serialized_data can be either an input range or a value containing
	the serialized data, depending on the type of serializer used.

	See_Also: `vibe.data.json.JsonSerializer`, `vibe.data.json.JsonStringSerializer`, `vibe.data.bson.BsonSerializer`
*/
T deserialize(Serializer, T, ARGS...)(ARGS args)
{
	auto deserializer = Serializer(args);
	return deserializeImpl!(T, DefaultPolicy, Serializer)(deserializer);
}

/** Note that there is a convenience function `vibe.data.json.deserializeJson`
	that can be used instead of manually invoking `deserialize`.
*/
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
	Deserializes and returns a serialized value, interpreting values according to `Policy` when possible.

	serialized_data can be either an input range or a value containing
	the serialized data, depending on the type of serializer used.

	See_Also: `vibe.data.json.JsonSerializer`, `vibe.data.json.JsonStringSerializer`, `vibe.data.bson.BsonSerializer`
*/
T deserializeWithPolicy(Serializer, alias Policy, T, ARGS...)(ARGS args)
{
	auto deserializer = Serializer(args);
	return deserializeImpl!(T, Policy, Serializer)(deserializer);
}

///
unittest {
	import vibe.data.json;

	static struct SizeI {
		int x;
		int y;
	}

	Json serializedI = "1x2";
	SizeI sizeI = deserializeWithPolicy!(JsonSerializer, SizePol, SizeI)(serializedI);
	assert(sizeI.x == 1);
	assert(sizeI.y == 2);

	static struct SizeF {
		float x;
		float y;
	}
	Json serializedF = "0.1x0.2";
	SizeF sizeF = deserializeWithPolicy!(JsonSerializer, SizePol, SizeF)(serializedF);
	assert(sizeF.x == 0.1f);
	assert(sizeF.y == 0.2f);
}

private void serializeImpl(Serializer, alias Policy, T, ATTRIBUTES...)(ref Serializer serializer, T value)
{
	import std.typecons : Nullable, Tuple, tuple;
	static if (__VERSION__ >= 2067) import std.typecons : BitFlags;

	static assert(Serializer.isSupportedValueType!string, "All serializers must support string values.");
	static assert(Serializer.isSupportedValueType!(typeof(null)), "All serializers must support null values.");

	alias TU = Unqual!T;

	static if (is(TU == enum)) {
		static if (hasAttributeL!(ByNameAttribute, ATTRIBUTES)) {
			serializeImpl!(Serializer, Policy, string)(serializer, value.to!string());
		} else {
			serializeImpl!(Serializer, Policy, OriginalType!TU)(serializer, cast(OriginalType!TU)value);
		}
	} else static if (Serializer.isSupportedValueType!TU) {
		static if (is(TU == typeof(null))) serializer.writeValue!TU(null);
		else serializer.writeValue!TU(value);
	} else static if (/*isInstanceOf!(Tuple, TU)*/is(T == Tuple!TPS, TPS...)) {
		static if (TU.Types.length == 1) {
			serializeImpl!(Serializer, Policy, typeof(value[0]), ATTRIBUTES)(serializer, value[0]);
		} else {
			serializer.beginWriteArray!TU(value.length);
			foreach (i, TV; T.Types) {
				serializer.beginWriteArrayEntry!TV(i);
				serializeImpl!(Serializer, Policy, TV, ATTRIBUTES)(serializer, value[i]);
				serializer.endWriteArrayEntry!TV(i);
			}
			serializer.endWriteArray!TU();
		}
	} else static if (isArray!TU) {
		alias TV = typeof(value[0]);
		serializer.beginWriteArray!TU(value.length);
		foreach (i, ref el; value) {
			serializer.beginWriteArrayEntry!TV(i);
			serializeImpl!(Serializer, Policy, TV, ATTRIBUTES)(serializer, el);
			serializer.endWriteArrayEntry!TV(i);
		}
		serializer.endWriteArray!TU();
	} else static if (isAssociativeArray!TU) {
		alias TK = KeyType!TU;
		alias TV = ValueType!TU;
		static if (__traits(compiles, serializer.beginWriteDictionary!TU(0))) {
			auto nfields = value.length;
			serializer.beginWriteDictionary!TU(nfields);
		} else {
			serializer.beginWriteDictionary!TU();
		}
		foreach (key, ref el; value) {
			string keyname;
			static if (is(TK : string)) keyname = key;
			else static if (is(TK : real) || is(TK : long) || is(TK == enum)) keyname = key.to!string;
			else static if (isStringSerializable!TK) keyname = key.toString();
			else static assert(false, "Associative array keys must be strings, numbers, enums, or have toString/fromString methods.");
			serializer.beginWriteDictionaryEntry!TV(keyname);
			serializeImpl!(Serializer, Policy, TV, ATTRIBUTES)(serializer, el);
			serializer.endWriteDictionaryEntry!TV(keyname);
		}
		static if (__traits(compiles, serializer.endWriteDictionary!TU(0))) {
			serializer.endWriteDictionary!TU(nfields);
		} else {
			serializer.endWriteDictionary!TU();
		}
	} else static if (/*isInstanceOf!(Nullable, TU)*/is(T == Nullable!TPS, TPS...)) {
		if (value.isNull()) serializeImpl!(Serializer, Policy, typeof(null))(serializer, null);
		else serializeImpl!(Serializer, Policy, typeof(value.get()), ATTRIBUTES)(serializer, value.get());
	} else static if (__VERSION__ >= 2067 && is(T == BitFlags!E, E)) {
		size_t cnt = 0;
		foreach (v; EnumMembers!E)
			if (value & v)
				cnt++;

		serializer.beginWriteArray!(E[])(cnt);
		cnt = 0;
		foreach (v; EnumMembers!E)
			if (value & v) {
				serializer.beginWriteArrayEntry!E(cnt);
				serializeImpl!(Serializer, Policy, E, ATTRIBUTES)(serializer, v);
				serializer.endWriteArrayEntry!E(cnt);
				cnt++;
			}
		serializer.endWriteArray!(E[])();
	} else static if (isPolicySerializable!(Policy, TU)) {
		alias CustomType = typeof(Policy!TU.toRepresentation(TU.init));
		serializeImpl!(Serializer, Policy, CustomType, ATTRIBUTES)(serializer, Policy!TU.toRepresentation(value));
	} else static if (isCustomSerializable!TU) {
		alias CustomType = typeof(T.init.toRepresentation());
		serializeImpl!(Serializer, Policy, CustomType, ATTRIBUTES)(serializer, value.toRepresentation());
	} else static if (isISOExtStringSerializable!TU) {
		serializer.writeValue(value.toISOExtString());
	} else static if (isStringSerializable!TU) {
		serializer.writeValue(value.toString());
	} else static if (is(TU == struct) || is(TU == class)) {
		static if (!hasSerializableFields!TU)
			pragma(msg, "Serializing composite type "~T.stringof~" which has no serializable fields");
		static if (is(TU == class)) {
			if (value is null) {
				serializeImpl!(Serializer, Policy, typeof(null))(serializer, null);
				return;
			}
		}
		static if (hasAttributeL!(AsArrayAttribute, ATTRIBUTES)) {
			enum nfields = getExpandedFieldCount!(TU, SerializableFields!TU);
			serializer.beginWriteArray!TU(nfields);
			size_t fcount = 0;
			foreach (mname; SerializableFields!TU) {
				alias TMS = TypeTuple!(typeof(__traits(getMember, value, mname)));
				foreach (j, TM; TMS) {
					alias TA = TypeTuple!(__traits(getAttributes, TypeTuple!(__traits(getMember, T, mname))[j]));
					serializer.beginWriteArrayEntry!TM(fcount);
					serializeImpl!(Serializer, Policy, TM, TA)(serializer, tuple(__traits(getMember, value, mname))[j]);
					serializer.endWriteArrayEntry!TM(fcount);
					fcount++;
				}
			}
			serializer.endWriteArray!TU();
		} else {
			static if (__traits(compiles, serializer.beginWriteDictionary!TU(0))) {
				enum nfields = getExpandedFieldCount!(TU, SerializableFields!TU);
				serializer.beginWriteDictionary!TU(nfields);
			} else {
				serializer.beginWriteDictionary!TU();
			}
			foreach (mname; SerializableFields!TU) {
				alias TM = TypeTuple!(typeof(__traits(getMember, value, mname)));
				static if (TM.length == 1) {
					alias TA = TypeTuple!(__traits(getAttributes, __traits(getMember, T, mname)));
					enum name = getAttribute!(TU, mname, NameAttribute)(NameAttribute(underscoreStrip(mname))).name;
					auto vt = __traits(getMember, value, mname);
					serializer.beginWriteDictionaryEntry!(typeof(vt))(name);
					serializeImpl!(Serializer, Policy, typeof(vt), TA)(serializer, vt);
					serializer.endWriteDictionaryEntry!(typeof(vt))(name);
				} else {
					alias TA = TypeTuple!(); // FIXME: support attributes for tuples somehow
					enum name = underscoreStrip(mname);
					auto vt = tuple(__traits(getMember, value, mname));
					serializer.beginWriteDictionaryEntry!(typeof(vt))(name);
					serializeImpl!(Serializer, Policy, typeof(vt), TA)(serializer, vt);
					serializer.endWriteDictionaryEntry!(typeof(vt))(name);
				}
			}
			static if (__traits(compiles, serializer.endWriteDictionary!TU(0))) {
				serializer.endWriteDictionary!TU(nfields);
			} else {
				serializer.endWriteDictionary!TU();
			}
		}
	} else static if (isPointer!TU) {
		if (value is null) {
			serializer.writeValue(null);
			return;
		}
		serializeImpl!(Serializer, Policy, PointerTarget!TU)(serializer, *value);
	} else static if (is(TU == bool) || is(TU : real) || is(TU : long)) {
		serializeImpl!(Serializer, Policy, string)(serializer, to!string(value));
	} else static assert(false, "Unsupported serialization type: " ~ T.stringof);
}

private T deserializeImpl(T, alias Policy, Serializer, ATTRIBUTES...)(ref Serializer deserializer) if(!isMutable!T)
{
	return cast(T) deserializeImpl!(Unqual!T, Policy, Serializer, ATTRIBUTES)(deserializer);
}

private T deserializeImpl(T, alias Policy, Serializer, ATTRIBUTES...)(ref Serializer deserializer) if(isMutable!T) 
{
	import std.typecons : Nullable;
	static if (__VERSION__ >= 2067) import std.typecons : BitFlags;

	static assert(Serializer.isSupportedValueType!string, "All serializers must support string values.");
	static assert(Serializer.isSupportedValueType!(typeof(null)), "All serializers must support null values.");

	static if (is(T == enum)) {
		static if (hasAttributeL!(ByNameAttribute, ATTRIBUTES)) {
			return deserializeImpl!(string, Policy, Serializer)(deserializer).to!T();
		} else {
			return cast(T)deserializeImpl!(OriginalType!T, Policy, Serializer)(deserializer);
		}
	} else static if (Serializer.isSupportedValueType!T) {
		return deserializer.readValue!T();
	} else static if (isStaticArray!T) {
		alias TV = typeof(T.init[0]);
		T ret;
		size_t i = 0;
		deserializer.readArray!T((sz) { assert(sz == 0 || sz == T.length); }, {
			assert(i < T.length);
			ret[i++] = deserializeImpl!(TV, Policy, Serializer, ATTRIBUTES)(deserializer);
		});
		return ret;
	} else static if (isDynamicArray!T) {
		alias TV = typeof(T.init[0]);
		//auto ret = appender!T();
		T ret; // Cannot use appender because of DMD BUG 10690/10859/11357
		deserializer.readArray!T((sz) { ret.reserve(sz); }, () {
			ret ~= deserializeImpl!(TV, Policy, Serializer, ATTRIBUTES)(deserializer);
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
			ret[key] = deserializeImpl!(TV, Policy, Serializer, ATTRIBUTES)(deserializer);
		});
		return ret;
	} else static if (isInstanceOf!(Nullable, T)) {
		if (deserializer.tryReadNull()) return T.init;
		return T(deserializeImpl!(typeof(T.init.get()), Policy, Serializer, ATTRIBUTES)(deserializer));
	} else static if (__VERSION__ >= 2067 && is(T == BitFlags!E, E)) {
		T ret;
		deserializer.readArray!(E[])((sz) {}, {
			ret |= deserializeImpl!(E, Policy, Serializer, ATTRIBUTES)(deserializer);
		});
		return ret;
	} else static if (isPolicySerializable!(Policy, T)) {
		alias CustomType = typeof(Policy!T.toRepresentation(T.init));
		return Policy!T.fromRepresentation(deserializeImpl!(CustomType, Policy, Serializer, ATTRIBUTES)(deserializer));
	} else static if (isCustomSerializable!T) {
		alias CustomType = typeof(T.init.toRepresentation());
		return T.fromRepresentation(deserializeImpl!(CustomType, Policy, Serializer, ATTRIBUTES)(deserializer));
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
				static if (hasSerializableFields!T) {
					switch (idx++) {
						default: break;
						foreach (i, mname; SerializableFields!T) {
							alias TM = typeof(__traits(getMember, ret, mname));
							alias TA = TypeTuple!(__traits(getAttributes, __traits(getMember, ret, mname)));
							case i:
								static if (hasAttribute!(OptionalAttribute, __traits(getMember, T, mname)))
									if (deserializer.tryReadNull()) return;
								set[i] = true;
								__traits(getMember, ret, mname) = deserializeImpl!(TM, Policy, Serializer, TA)(deserializer);
								break;
						}
					}
				} else {
					pragma(msg, "Deserializing composite type "~T.stringof~" which has no serializable fields.");
				}
			});
		} else {
			deserializer.readDictionary!T((name) {
				static if (hasSerializableFields!T) {
					switch (name) {
						default: break;
						foreach (i, mname; SerializableFields!T) {
							alias TM = typeof(__traits(getMember, ret, mname));
							alias TA = TypeTuple!(__traits(getAttributes, __traits(getMember, ret, mname)));
							enum fname = getAttribute!(T, mname, NameAttribute)(NameAttribute(underscoreStrip(mname))).name;
							case fname:
								static if (hasAttribute!(OptionalAttribute, __traits(getMember, T, mname)))
									if (deserializer.tryReadNull()) return;
								set[i] = true;
								__traits(getMember, ret, mname) = deserializeImpl!(TM, Policy, Serializer, TA)(deserializer);
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
		if (deserializer.tryReadNull()) return null;
		alias PT = PointerTarget!T;
		auto ret = new PT;
		*ret = deserializeImpl!(PT, Policy, Serializer)(deserializer);
		return ret;
	} else static if (is(T == bool) || is(T : real) || is(T : long)) {
		return to!T(deserializeImpl!(string, Policy, Serializer)(deserializer));
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

	import vibe.data.json;
	static assert(is(typeof(serializeToJson(Test()))));
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
	`toRepresentation`/`fromRepresentation` methods. Any class or
	struct type that has this trait will be serialized by using the return
	value of it's `toRepresentation` method instead of the original value.

	This trait has precedence over `isISOExtStringSerializable` and
	`isStringSerializable`.
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
	pair of `toISOExtString`/`fromISOExtString` methods. Any class or
	struct type that has this trait will be serialized by using the return
	value of it's `toISOExtString` method instead of the original value.

	This is mainly useful for supporting serialization of the the date/time
	types in `std.datetime`.

	This trait has precedence over `isStringSerializable`.
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
	`toString`/`fromString` methods. Any class or struct type that
	has this trait will be serialized by using the return value of it's
	`toString` method instead of the original value.
*/
template isStringSerializable(T)
{
	enum bool isStringSerializable = is(typeof(T.init.toString()) == string) && is(typeof(T.fromString("")) == T);
}
///
unittest {
	import std.conv;

	// represented as the boxed value when serialized
	static struct Box(T) {
		T value;
	}

	template BoxPol(S)
	{
		auto toRepresentation(S s) {
			return s.value;
		}

		S fromRepresentation(typeof(S.init.value) v) {
			return S(v);
		}
	}
	static assert(isPolicySerializable!(BoxPol, Box!int));
}

private template DefaultPolicy(T)
{
}

/**
	Checks if a given policy supports custom serialization for a given type.

	A class or struct type is custom serializable according to a policy if
	the policy defines a pair of `toRepresentation`/`fromRepresentation`
	functions. Any class or struct type that has this trait for the policy supplied to
	`serializeWithPolicy` will be serialized by using the return value of the
	policy `toRepresentation` function instead of the original value.

	This trait has precedence over `isCustomSerializable`,
	`isISOExtStringSerializable` and `isStringSerializable`.

	See_Also: `vibe.data.serialization.serializeWithPolicy`
*/
template isPolicySerializable(alias Policy, T)
{
	enum bool isPolicySerializable = is(typeof(Policy!T.toRepresentation(T.init))) &&
		is(typeof(Policy!T.fromRepresentation(Policy!T.toRepresentation(T.init))) == T);
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

/**
	Chains serialization policy.

	Constructs a serialization policy that given a type `T` will apply the
	first compatible policy `toRepresentation` and `fromRepresentation`
	functions. Policies are evaluated left-to-right according to
	`isPolicySerializable`.

	See_Also: `vibe.data.serialization.serializeWithPolicy`
*/
template ChainedPolicy(alias Primary, Fallbacks...)
{
	static if (Fallbacks.length == 0) {
		alias ChainedPolicy = Primary;
	} else {
		alias ChainedPolicy = ChainedPolicy!(ChainedPolicyImpl!(Primary, Fallbacks[0]), Fallbacks[1..$]);
	}
}
///
unittest {
	import std.conv;

	// To be represented as the boxed value when serialized
	static struct Box(T) {
		T value;
	}
	// Also to berepresented as the boxed value when serialized, but has
	// a different way to access the value.
	static struct Box2(T) {
		private T v;
		ref T get() {
			return v;
		}
	}
	template BoxPol(S)
	{
		auto toRepresentation(S s) {
			return s.value;
		}

		S fromRepresentation(typeof(toRepresentation(S.init)) v) {
			return S(v);
		}
	}
	template Box2Pol(S)
	{
		auto toRepresentation(S s) {
			return s.get();
		}

		S fromRepresentation(typeof(toRepresentation(S.init)) v) {
			S s;
			s.get() = v;
			return s;
		}
	}
	alias ChainPol = ChainedPolicy!(BoxPol, Box2Pol);
	static assert(!isPolicySerializable!(BoxPol, Box2!int));
	static assert(!isPolicySerializable!(Box2Pol, Box!int));
	static assert(isPolicySerializable!(ChainPol, Box!int));
	static assert(isPolicySerializable!(ChainPol, Box2!int));
}

private template ChainedPolicyImpl(alias Primary, alias Fallback)
{
	template Pol(T)
	{
		static if (isPolicySerializable!(Primary, T)) {
			alias toRepresentation = Primary!T.toRepresentation;
			alias fromRepresentation = Primary!T.fromRepresentation;
		} else {
			alias toRepresentation = Fallback!T.toRepresentation;
			alias fromRepresentation = Fallback!T.fromRepresentation;
		}
	}
	alias ChainedPolicyImpl = Pol;
}

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
			alias Tup = TypeTuple!(__traits(getMember, COMPOSITE, FIELDS[0]));
			static if (Tup.length != 1) {
				alias FilterSerializableFields = TypeTuple!(mname);
			} else {
				static if (!hasAttribute!(IgnoreAttribute, __traits(getMember, T, mname)))
					alias FilterSerializableFields = TypeTuple!(mname);
				else alias FilterSerializableFields = TypeTuple!();
			}
		} else alias FilterSerializableFields = TypeTuple!();
	} else alias FilterSerializableFields = TypeTuple!();
}

private size_t getExpandedFieldCount(T, FIELDS...)()
{
	size_t ret = 0;
	foreach (F; FIELDS) ret += TypeTuple!(__traits(getMember, T, F)).length;
	return ret;
}

/******************************************************************************/
/* General serialization unit testing                                         */
/******************************************************************************/

version (unittest) {
	private struct TestSerializer {
		import std.array, std.conv, std.string;

		string result;

		enum isSupportedValueType(T) = is(T == string) || is(T == typeof(null)) || is(T == float) || is (T == int);

		string getSerializedResult() { return result; }
		void beginWriteDictionary(T)() { result ~= "D("~T.mangleof~"){"; }
		void endWriteDictionary(T)() { result ~= "}D("~T.mangleof~")"; }
		void beginWriteDictionaryEntry(T)(string name) { result ~= "DE("~T.mangleof~","~name~")("; }
		void endWriteDictionaryEntry(T)(string name) { result ~= ")DE("~T.mangleof~","~name~")"; }
		void beginWriteArray(T)(size_t length) { result ~= "A("~T.mangleof~")["~length.to!string~"]["; }
		void endWriteArray(T)() { result ~= "]A("~T.mangleof~")"; }
		void beginWriteArrayEntry(T)(size_t i) { result ~= "AE("~T.mangleof~","~i.to!string~")("; }
		void endWriteArrayEntry(T)(size_t i) { result ~= ")AE("~T.mangleof~","~i.to!string~")"; }
		void writeValue(T)(T value) {
			if (is(T == typeof(null))) result ~= "null";
			else {
				assert(isSupportedValueType!T);
				result ~= "V("~T.mangleof~")("~value.to!string~")";
			}
		}

		// deserialization
		void readDictionary(T)(scope void delegate(string) entry_callback)
		{
			skip("D("~T.mangleof~"){");
			while (result.startsWith("DE(")) {
				result = result[3 .. $];
				auto idx = result.indexOf(',');
				auto idx2 = result.indexOf(")(");
				assert(idx > 0 && idx2 > idx);
				auto t = result[0 .. idx];
				auto n = result[idx+1 .. idx2];
				result = result[idx2+2 .. $];
				entry_callback(n);
				skip(")DE("~t~","~n~")");
			}
			skip("}D("~T.mangleof~")");
		}

		void readArray(T)(scope void delegate(size_t) size_callback, scope void delegate() entry_callback)
		{
			skip("A("~T.mangleof~")[");
			auto bidx = result.indexOf("][");
			assert(bidx > 0);
			auto cnt = result[0 .. bidx].to!size_t;
			result = result[bidx+2 .. $];

			size_t i = 0;
			while (result.startsWith("AE(")) {
				result = result[3 .. $];
				auto idx = result.indexOf(',');
				auto idx2 = result.indexOf(")(");
				assert(idx > 0 && idx2 > idx);
				auto t = result[0 .. idx];
				auto n = result[idx+1 .. idx2];
				result = result[idx2+2 .. $];
				assert(n == i.to!string);
				entry_callback();
				skip(")AE("~t~","~n~")");
				i++;
			}
			skip("]A("~T.mangleof~")");

			assert(i == cnt);
		}

		T readValue(T)()
		{
			skip("V("~T.mangleof~")(");
			auto idx = result.indexOf(')');
			assert(idx >= 0);
			auto ret = result[0 .. idx].to!T;
			result = result[idx+1 .. $];
			return ret;
		}

		void skip(string prefix)
		{
			assert(result.startsWith(prefix), result);
			result = result[prefix.length .. $];
		}

		bool tryReadNull()
		{
			if (result.startsWith("null")) {
				result = result[4 .. $];
				return true;
			} else return false;
		}
	}
}

unittest { // basic serialization behavior
	import std.typecons : Nullable;

	static void test(T)(T value, string expected) {
		assert(serialize!TestSerializer(value) == expected, serialize!TestSerializer(value));
		static if (isPointer!T) {
			if (value) assert(*deserialize!(TestSerializer, T)(expected) == *value);
			else assert(deserialize!(TestSerializer, T)(expected) is null);
		} else static if (is(T == Nullable!U, U)) {
			if (value.isNull()) assert(deserialize!(TestSerializer, T)(expected).isNull);
			else assert(deserialize!(TestSerializer, T)(expected) == value);
		} else assert(deserialize!(TestSerializer, T)(expected) == value);
	}

	test("hello", "V(Aya)(hello)");
	test(12, "V(i)(12)");
	test(12.0, "V(Aya)(12)");
	test(12.0f, "V(f)(12)");
	assert(serialize!TestSerializer(null) ==  "null");
	test(["hello", "world"], "A(AAya)[2][AE(Aya,0)(V(Aya)(hello))AE(Aya,0)AE(Aya,1)(V(Aya)(world))AE(Aya,1)]A(AAya)");
	test(["hello": "world"], "D(HAyaAya){DE(Aya,hello)(V(Aya)(world))DE(Aya,hello)}D(HAyaAya)");
	test(cast(int*)null, "null");
	int i = 42;
	test(&i, "V(i)(42)");
	Nullable!int j;
	test(j, "null");
	j = 42;
	test(j, "V(i)(42)");
}

unittest { // basic user defined types
	static struct S { string f; }
	enum Sm = S.mangleof;
	auto s = S("hello");
	enum s_ser = "D("~Sm~"){DE(Aya,f)(V(Aya)(hello))DE(Aya,f)}D("~Sm~")";
	assert(serialize!TestSerializer(s) == s_ser, serialize!TestSerializer(s));
	assert(deserialize!(TestSerializer, S)(s_ser) == s);

	static class C { string f; }
	enum Cm = C.mangleof;
	C c;
	assert(serialize!TestSerializer(c) == "null");
	c = new C;
	c.f = "hello";
	enum c_ser = "D("~Cm~"){DE(Aya,f)(V(Aya)(hello))DE(Aya,f)}D("~Cm~")";
	assert(serialize!TestSerializer(c) == c_ser);
	assert(deserialize!(TestSerializer, C)(c_ser).f == c.f);

	enum E { hello, world }
	assert(serialize!TestSerializer(E.hello) == "V(i)(0)");
	assert(serialize!TestSerializer(E.world) == "V(i)(1)");
}

unittest { // tuple serialization
	import std.typecons : Tuple;

	static struct S(T...) { T f; }
	enum Sm = S!(int, string).mangleof;
	enum Tum = Tuple!(int, string).mangleof;
	auto s = S!(int, string)(42, "hello");
	assert(serialize!TestSerializer(s) ==
		"D("~Sm~"){DE("~Tum~",f)(A("~Tum~")[2][AE(i,0)(V(i)(42))AE(i,0)AE(Aya,1)(V(Aya)(hello))AE(Aya,1)]A("~Tum~"))DE("~Tum~",f)}D("~Sm~")");

	static struct T { @asArray S!(int, string) g; }
	enum Tm = T.mangleof;
	auto t = T(s);
	assert(serialize!TestSerializer(t) ==
		"D("~Tm~"){DE("~Sm~",g)(A("~Sm~")[2][AE(i,0)(V(i)(42))AE(i,0)AE(Aya,1)(V(Aya)(hello))AE(Aya,1)]A("~Sm~"))DE("~Sm~",g)}D("~Tm~")");
}

unittest { // testing the various UDAs
	enum E { hello, world }
	enum Em = E.mangleof;
	static struct S {
		@byName E e;
		@ignore int i;
		@optional float f;
	}
	enum Sm = S.mangleof;
	auto s = S(E.world, 42, 1.0f);
	assert(serialize!TestSerializer(s) ==
		"D("~Sm~"){DE("~Em~",e)(V(Aya)(world))DE("~Em~",e)DE(f,f)(V(f)(1))DE(f,f)}D("~Sm~")");
}

unittest { // custom serialization support
	// iso-ext
	import std.datetime;
	auto t = TimeOfDay(6, 31, 23);
	assert(serialize!TestSerializer(t) == "V(Aya)(06:31:23)");
	auto d = Date(1964, 1, 23);
	assert(serialize!TestSerializer(d) == "V(Aya)(1964-01-23)");
	auto dt = DateTime(d, t);
	assert(serialize!TestSerializer(dt) == "V(Aya)(1964-01-23T06:31:23)");
	auto st = SysTime(dt, UTC());
	assert(serialize!TestSerializer(st) == "V(Aya)(1964-01-23T06:31:23Z)");

	// string
	struct S1 { int i; string toString() const { return "hello"; } static S1 fromString(string) { return S1.init; } }
	struct S2 { int i; string toString() const { return "hello"; } }
	enum S2m = S2.mangleof;
	struct S3 { int i; static S3 fromString(string) { return S3.init; } }
	enum S3m = S3.mangleof;
	assert(serialize!TestSerializer(S1.init) == "V(Aya)(hello)");
	assert(serialize!TestSerializer(S2.init) == "D("~S2m~"){DE(i,i)(V(i)(0))DE(i,i)}D("~S2m~")");
	assert(serialize!TestSerializer(S3.init) == "D("~S3m~"){DE(i,i)(V(i)(0))DE(i,i)}D("~S3m~")");

	// custom
	struct C1 { int i; float toRepresentation() const { return 1.0f; } static C1 fromRepresentation(float f) { return C1.init; } }
	struct C2 { int i; float toRepresentation() const { return 1.0f; } }
	enum C2m = C2.mangleof;
	struct C3 { int i; static C3 fromRepresentation(float f) { return C3.init; } }
	enum C3m = C3.mangleof;
	assert(serialize!TestSerializer(C1.init) == "V(f)(1)");
	assert(serialize!TestSerializer(C2.init) == "D("~C2m~"){DE(i,i)(V(i)(0))DE(i,i)}D("~C2m~")");
	assert(serialize!TestSerializer(C3.init) == "D("~C3m~"){DE(i,i)(V(i)(0))DE(i,i)}D("~C3m~")");
}

unittest // Testing corner case: member function returning by ref
{
	import vibe.data.json;

	static struct S
	{
		int i;
		ref int foo() { return i; }
	}

	static assert(__traits(compiles, { S().serializeToJson(); }));
	static assert(__traits(compiles, { Json().deserializeJson!S(); }));

	auto s = S(1);
	assert(s.serializeToJson().deserializeJson!S() == s);
}

unittest // Testing corner case: Variadic template constructors and methods
{
	import vibe.data.json;

	static struct S
	{
		int i;
		this(Args...)(Args args) {}
		int foo(Args...)(Args args) { return i; }
		ref int bar(Args...)(Args args) { return i; }
	}

	static assert(__traits(compiles, { S().serializeToJson(); }));
	static assert(__traits(compiles, { Json().deserializeJson!S(); }));

	auto s = S(1);
	assert(s.serializeToJson().deserializeJson!S() == s);
}

unittest // Make sure serializing through properties still works
{
	import vibe.data.json;

	static struct S
	{
		public int i;
		private int privateJ;

		@property int j() { return privateJ; }
		@property void j(int j) { privateJ = j; }
	}

	auto s = S(1, 2);
	assert(s.serializeToJson().deserializeJson!S() == s);
}

unittest // Immutable data deserialization
{
	import vibe.data.json;
	
	static struct S {
		int a;
	}
	static class C {
		immutable(S)[] arr;
	}
	
	auto c = new C;
	c.arr ~= S(10);
	auto d = c.serializeToJson().deserializeJson!(immutable C);
	static assert(is(typeof(d) == immutable C));
	assert(d.arr == c.arr);
}

static if (__VERSION__ >= 2067)
unittest { // test BitFlags serialization
	import std.typecons : BitFlags;

	enum Flag {
		a = 1<<0,
		b = 1<<1,
		c = 1<<2
	}
	enum Flagm = Flag.mangleof;

	alias Flags = BitFlags!Flag;
	enum Flagsm = Flags.mangleof;

	enum Fi_ser = "A(A"~Flagm~")[0][]A(A"~Flagm~")";
	assert(serialize!TestSerializer(Flags.init) == Fi_ser);

	enum Fac_ser = "A(A"~Flagm~")[2][AE("~Flagm~",0)(V(i)(1))AE("~Flagm~",0)AE("~Flagm~",1)(V(i)(4))AE("~Flagm~",1)]A(A"~Flagm~")";
	assert(serialize!TestSerializer(Flags(Flag.a, Flag.c)) == Fac_ser);

	struct S { @byName Flags f; }
	enum Sm = S.mangleof;
	enum Sac_ser = "D("~Sm~"){DE("~Flagsm~",f)(A(A"~Flagm~")[2][AE("~Flagm~",0)(V(Aya)(a))AE("~Flagm~",0)AE("~Flagm~",1)(V(Aya)(c))AE("~Flagm~",1)]A(A"~Flagm~"))DE("~Flagsm~",f)}D("~Sm~")";

	assert(serialize!TestSerializer(S(Flags(Flag.a, Flag.c))) == Sac_ser);

	assert(deserialize!(TestSerializer, Flags)(Fi_ser) == Flags.init);
	assert(deserialize!(TestSerializer, Flags)(Fac_ser) == Flags(Flag.a, Flag.c));
	assert(deserialize!(TestSerializer, S)(Sac_ser) == S(Flags(Flag.a, Flag.c)));
}

unittest { // issue #1182
	struct T {
		int x;
		string y;
	}
	struct S {
		@asArray T t;
	}

	auto s = S(T(42, "foo"));
	enum Sm = S.mangleof;
	enum Tm = T.mangleof;
	enum s_ser = "D("~Sm~"){DE("~Tm~",t)(A("~Tm~")[2][AE(i,0)(V(i)(42))AE(i,0)AE(Aya,1)(V(Aya)(foo))AE(Aya,1)]A("~Tm~"))DE("~Tm~",t)}D("~Sm~")";

	auto serialized = serialize!TestSerializer(s);
	assert(serialized == s_ser, serialized);
	assert(deserialize!(TestSerializer, S)(serialized) == s);
}
