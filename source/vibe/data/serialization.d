/**
	Generic serialization framework.

	This module provides general means for implementing (de-)serialization with
	a standardized behavior.

	Supported_types:
		The following rules are applied in order when serializing or
		deserializing a certain type:

		$(OL
			$(LI An $(D enum) type is serialized as its raw value, except if
				$(D @byName) is used, in which case the name of the enum value
				is serialized.)
			$(LI Any type that is specifically supported by the serializer
				is directly serialized. For example, the BSON serializer
				supports $(D BsonObjectID) directly.)
			$(LI Arrays and tuples ($(D std.typecons.Tuple)) are serialized
				using the array serialization functions where each element is
				serialized again according to these rules.)
			$(LI Associative arrays are serialized similar to arrays. The key
				type of the AA must satisfy the $(D isStringSerializable) trait
				and will always be serialized as a string.)
			$(LI Any $(D Nullable!T) will be serialized as either $(D null), or
				as the contained value (subject to these rules again).)
			$(LI Types satisfying the $(D isPolicySerializable) trait for the
				supplied $(D Policy) will be serialized as the value returned
				by the policy $(D toRepresentation) function (again subject to
				these rules).)
			$(LI Types satisfying the $(D isCustomSerializable) trait will be
				serialized as the value returned by their $(D toRepresentation)
				method (again subject to these rules).)
			$(LI Types satisfying the $(D isISOExtSerializable) trait will be
				serialized as a string, as returned by their $(D toISOExtString)
				method. This causes types such as $(D SysTime) to be serialized
				as strings.)
			$(LI Types satisfying the $(D isStringSerializable) trait will be
				serialized as a string, as returned by their $(D toString)
				method.)
			$(LI Struct and class types by default will be serialized as
				associative arrays, where the key is the name of the
				corresponding field (can be overridden using the $(D @name)
				attribute). If the struct/class is annotated with $(D @asArray),
				it will instead be serialized as a flat array of values in the
				order of declaration. Null class references will be serialized
				as $(D null).)
			$(LI Pointer types will be serialized as either $(D null), or as
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
	Serializes a value with the given serializer, representing values according to $(D Policy) when possible.

	The serializer must have a value result for the first form
	to work. Otherwise, use the range based form.

	See_Also: vibe.data.json.JsonSerializer, vibe.data.json.JsonStringSerializer, vibe.data.bson.BsonSerializer
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

	See_Also: vibe.data.json.JsonSerializer, vibe.data.json.JsonStringSerializer, vibe.data.bson.BsonSerializer
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
	Deserializes and returns a serialized value, interpreting values according to $(D Policy) when possible.

	serialized_data can be either an input range or a value containing
	the serialized data, depending on the type of serializer used.

	See_Also: vibe.data.json.JsonSerializer, vibe.data.json.JsonStringSerializer, vibe.data.bson.BsonSerializer
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
			foreach (mname; SerializableFields!TU) {
				alias TMS = TypeTuple!(typeof(__traits(getMember, value, mname)));
				foreach (j, TM; TMS) {
					alias TA = TypeTuple!(__traits(getAttributes, TypeTuple!(__traits(getMember, T, mname))[j]));
					serializer.beginWriteArrayEntry!TM(j);
					serializeImpl!(Serializer, Policy, TM, TA)(serializer, tuple(__traits(getMember, value, mname))[j]);
					serializer.endWriteArrayEntry!TM(j);
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


private T deserializeImpl(T, alias Policy, Serializer, ATTRIBUTES...)(ref Serializer deserializer)
{
	import std.typecons : Nullable;

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
		if (deserializer.isNull()) return null;
		alias PT = PointerTarget!T;
		auto ret = new PT;
		*ret = deserializeImpl!(PT, Policy)(deserializer);
		return ret;
	} else static if (is(T == bool) || is(T : real) || is(T : long)) {
		return to!T(deserializeImpl!(string, Policy)(deserializer));
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
	the policy defines a pair of $(D toRepresentation)/$(D fromRepresentation)
	functions. Any class or struct type that has this trait for the policy supplied to
	$D(serializeWithPolicy) will be serialized by using the return value of the
	policy $(D toRepresentation) function instead of the original value.

	This trait has precedence over $(D isCustomSerializable),
	$(D isISOExtStringSerializable) and $(D isStringSerializable).

	See_Also: vibe.data.serialization.serializeWithPolicy
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

	Constructs a serialization policy that given a type $(D T) will apply the
	first compatible policy $(D toRepresentation) and $(D fromRepresentation)
	functions. Policies are evaluated left-to-right according to
	$(D isPolicySerializable).

	See_Also: vibe.data.serialization.serializeWithPolicy 
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
		void beginWriteDictionary(T)() { result ~= "D("~T.stringof~"){"; }
		void endWriteDictionary(T)() { result ~= "}D("~T.stringof~")"; }
		void beginWriteDictionaryEntry(T)(string name) { result ~= "DE("~T.stringof~","~name~")("; }
		void endWriteDictionaryEntry(T)(string name) { result ~= ")DE("~T.stringof~","~name~")"; }
		void beginWriteArray(T)(size_t length) { result ~= "A("~T.stringof~")["~length.to!string~"]["; }
		void endWriteArray(T)() { result ~= "]A("~T.stringof~")"; }
		void beginWriteArrayEntry(T)(size_t i) { result ~= "AE("~T.stringof~","~i.to!string~")("; }
		void endWriteArrayEntry(T)(size_t i) { result ~= ")AE("~T.stringof~","~i.to!string~")"; }
		void writeValue(T)(T value) {
			if (is(T == typeof(null))) result ~= "null";
			else {
				assert(isSupportedValueType!T);
				result ~= "V("~T.stringof~")("~value.to!string~")";
			}
		}

		// deserialization
		void readDictionary(T)(scope void delegate(string) entry_callback)
		{
			enum prefix = "D("~T.stringof~"){";
			assert(result.startsWith(prefix));
			result  = result[prefix.length .. $];
			while (true) {
				// ...
				assert(false);
			}
		}

		void readArray(T)(scope void delegate(size_t) size_callback, scope void delegate() entry_callback)
		{
			enum prefix = "A("~T.stringof~")[";
			assert(result.startsWith(prefix));
			result  = result[prefix.length .. $];
			assert(false);
		}

		void readValue(T)()
		{
			assert(false);
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

	assert(serialize!TestSerializer("hello") == "V(string)(hello)");
	assert(serialize!TestSerializer(12) == "V(int)(12)");
	assert(serialize!TestSerializer(12.0) == "V(string)(12)");
	assert(serialize!TestSerializer(12.0f) == "V(float)(12)");
	assert(serialize!TestSerializer(null) == "null");
	assert(serialize!TestSerializer(["hello", "world"]) ==
		"A(string[])[2][AE(string,0)(V(string)(hello))AE(string,0)AE(string,1)(V(string)(world))AE(string,1)]A(string[])");
	assert(serialize!TestSerializer(["hello": "world"]) ==
		"D(string[string]){DE(string,hello)(V(string)(world))DE(string,hello)}D(string[string])");
	assert(serialize!TestSerializer(cast(int*)null) == "null");
	int i = 42;
	assert(serialize!TestSerializer(&i) == "V(int)(42)");
	Nullable!int j;
	assert(serialize!TestSerializer(j) == "null");
	j = 42;
	assert(serialize!TestSerializer(j) == "V(int)(42)");
}

unittest { // basic user defined types
	static struct S { string f; }
	auto s = S("hello");
	assert(serialize!TestSerializer(s) == "D(S){DE(string,f)(V(string)(hello))DE(string,f)}D(S)");

	static class C { string f; }
	C c;
	assert(serialize!TestSerializer(c) == "null");
	c = new C;
	c.f = "hello";
	assert(serialize!TestSerializer(c) == "D(C){DE(string,f)(V(string)(hello))DE(string,f)}D(C)");

	enum E { hello, world }
	assert(serialize!TestSerializer(E.hello) == "V(int)(0)");
	assert(serialize!TestSerializer(E.world) == "V(int)(1)");
}

unittest { // tuple serialization
	static struct S(T...) { T f; }
	auto s = S!(int, string)(42, "hello");
	assert(serialize!TestSerializer(s) ==
		"D(S!(int, string)){DE(Tuple!(int, string),f)(A(Tuple!(int, string))[2][AE(int,0)(V(int)(42))AE(int,0)AE(string,1)(V(string)(hello))AE(string,1)]A(Tuple!(int, string)))DE(Tuple!(int, string),f)}D(S!(int, string))");

	static struct T { @asArray S!(int, string) g; }
	auto t = T(s);
	assert(serialize!TestSerializer(t) ==
		"D(T){DE(S!(int, string),g)(A(S!(int, string))[2][AE(int,0)(V(int)(42))AE(int,0)AE(string,1)(V(string)(hello))AE(string,1)]A(S!(int, string)))DE(S!(int, string),g)}D(T)");
}

unittest { // testing the various UDAs
	enum E { hello, world }
	static struct S {
		@byName E e;
		@ignore int i;
		@optional float f;
	}
	auto s = S(E.world, 42, 1.0f);
	assert(serialize!TestSerializer(s) ==
		"D(S){DE(E,e)(V(string)(world))DE(E,e)DE(float,f)(V(float)(1))DE(float,f)}D(S)");
}

unittest { // custom serialization support
	// iso-ext
	import std.datetime;
	auto t = TimeOfDay(6, 31, 23);
	assert(serialize!TestSerializer(t) == "V(string)(06:31:23)");
	auto d = Date(1964, 1, 23);
	assert(serialize!TestSerializer(d) == "V(string)(1964-01-23)");
	auto dt = DateTime(d, t);
	assert(serialize!TestSerializer(dt) == "V(string)(1964-01-23T06:31:23)");
	auto st = SysTime(dt, UTC());
	assert(serialize!TestSerializer(st) == "V(string)(1964-01-23T06:31:23Z)");

	// string
	struct S1 { int i; string toString() const { return "hello"; } static S1 fromString(string) { return S1.init; } }
	struct S2 { int i; string toString() const { return "hello"; } }
	struct S3 { int i; static S3 fromString(string) { return S3.init; } }
	assert(serialize!TestSerializer(S1.init) == "V(string)(hello)");
	assert(serialize!TestSerializer(S2.init) == "D(S2){DE(int,i)(V(int)(0))DE(int,i)}D(S2)");
	assert(serialize!TestSerializer(S3.init) == "D(S3){DE(int,i)(V(int)(0))DE(int,i)}D(S3)");

	// custom
	struct C1 { int i; float toRepresentation() const { return 1.0f; } static C1 fromRepresentation(float f) { return C1.init; } }
	struct C2 { int i; float toRepresentation() const { return 1.0f; } }
	struct C3 { int i; static C3 fromRepresentation(float f) { return C3.init; } }
	assert(serialize!TestSerializer(C1.init) == "V(float)(1)");
	assert(serialize!TestSerializer(C2.init) == "D(C2){DE(int,i)(V(int)(0))DE(int,i)}D(C2)");
	assert(serialize!TestSerializer(C3.init) == "D(C3){DE(int,i)(V(int)(0))DE(int,i)}D(C3)");
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
