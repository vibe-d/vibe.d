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
			$(LI Any `Typedef!T` will be serialized as if it were just `T`.)
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

	Field_names:
		By default, the field name of the serialized D type (for `struct` and
		`class` aggregates) is represented as-is in the serialized result. To
		circumvent name clashes with D's keywords, a single trailing underscore of
		any field name is stipped, so that a field name of `version_` results in
		just `"version"` as the serialized value. Names can also be freely
		customized using the `@name` annotation.

		Associative array keys are always represented using their direct string
		representation.

	Serializer_implementation:
		Serializers are implemented in terms of a struct with template methods that
		get called by the serialization framework:

		---
		struct ExampleSerializer {
			enum isSupportedValueType(T) = is(T == string) || is(T == typeof(null));

			// serialization
			auto getSerializedResult();
			void beginWriteDocument(TypeTraits)();
			void endWriteDocument(TypeTraits)();
			void beginWriteDictionary(TypeTraits)();
			void endWriteDictionary(TypeTraits)();
			void beginWriteDictionaryEntry(ElementTypeTraits)(string name);
			void endWriteDictionaryEntry(ElementTypeTraits)(string name);
			void beginWriteArray(TypeTraits)(size_t length);
			void endWriteArray(TypeTraits)();
			void beginWriteArrayEntry(ElementTypeTraits)(size_t index);
			void endWriteArrayEntry(ElementTypeTraits)(size_t index);
			void writeValue(TypeTraits, T)(T value);

			// deserialization
			void readDictionary(TypeTraits)(scope void delegate(string) entry_callback);
			void beginReadDictionaryEntry(ElementTypeTraits)(string);
			void endReadDictionaryEntry(ElementTypeTraits)(string);
			void readArray(TypeTraits)(scope void delegate(size_t) size_callback, scope void delegate() entry_callback);
			void beginReadArrayEntry(ElementTypeTraits)(size_t index);
			void endReadArrayEntry(ElementTypeTraits)(size_t index);
			T readValue(TypeTraits, T)();
			bool tryReadNull(TypeTraits)();
		}
		---

		The `TypeTraits` type passed to the individual methods has the following members:
		$(UL
			$(LI `Type`: The original type of the field to serialize)
			$(LI `Attributes`: User defined attributes attached to the field)
			$(LI `Policy`: An alias to the policy used for the serialization process)
		)

		`ElementTypeTraits` have the following additional members:
		$(UL
			$(LI `ContainerType`: The original type of the enclosing container type)
			$(LI `ContainerAttributes`: User defined attributes attached to the enclosing container)
		)

	Copyright: © 2013-2016 rejectedsoftware e.K.
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
	serializeWithPolicy!(Serializer, DefaultPolicy)(serializer, value);
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
	assert(serialized["value"].get!int == 12);
	assert(serialized["text"].get!string == "Hello");
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
	static if (is(typeof(serializer.beginWriteDocument!T())))
		serializer.beginWriteDocument!T();
	serializeValueImpl!(Serializer, Policy).serializeValue!T(serializer, value);
	static if (is(typeof(serializer.endWriteDocument!T())))
		serializer.endWriteDocument!T();
}
///
version (unittest)
{
}

///
unittest {
	import vibe.data.json;

	template SizePol(T)
		if (__traits(allMembers, T) == TypeTuple!("x", "y"))
	{
		import std.conv;
		import std.array;

		static string toRepresentation(T value) @safe {
			return to!string(value.x) ~ "x" ~ to!string(value.y);
		}

		static T fromRepresentation(string value) {
			string[] fields = value.split('x');
			alias fieldT = typeof(T.x);
			auto x = to!fieldT(fields[0]);
			auto y = to!fieldT(fields[1]);
			return T(x, y);
		}
	}

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
	return deserializeWithPolicy!(Serializer, DefaultPolicy, T)(args);
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
	serialized["value"] = 12;
	serialized["text"] = "Hello";

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
	return deserializeValueImpl!(Serializer, Policy).deserializeValue!T(deserializer);
}

///
unittest {
	import vibe.data.json;

	template SizePol(T)
		if (__traits(allMembers, T) == TypeTuple!("x", "y"))
	{
		import std.conv;
		import std.array;

		static string toRepresentation(T value)
		@safe {
			return to!string(value.x) ~ "x" ~ to!string(value.y);
		}

		static T fromRepresentation(string value)
		@safe {
			string[] fields = value.split('x');
			alias fieldT = typeof(T.x);
			auto x = to!fieldT(fields[0]);
			auto y = to!fieldT(fields[1]);
			return T(x, y);
		}
	}

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

private template serializeValueImpl(Serializer, alias Policy) {
	alias _Policy = Policy;
	static assert(Serializer.isSupportedValueType!string, "All serializers must support string values.");
	static assert(Serializer.isSupportedValueType!(typeof(null)), "All serializers must support null values.");

	// work around https://issues.dlang.org/show_bug.cgi?id=16528
	static if (isSafeSerializer!Serializer) {
		void serializeValue(T, ATTRIBUTES...)(ref Serializer ser, T value) @safe { serializeValueDeduced!(T, ATTRIBUTES)(ser, value); }
	} else {
		void serializeValue(T, ATTRIBUTES...)(ref Serializer ser, T value) { serializeValueDeduced!(T, ATTRIBUTES)(ser, value); }
	}

	private void serializeValueDeduced(T, ATTRIBUTES...)(ref Serializer ser, T value)
	{
		import std.typecons : BitFlags, Nullable, Tuple, Typedef, TypedefType, tuple;

		alias TU = Unqual!T;

		alias Traits = .Traits!(TU, _Policy, ATTRIBUTES);

		static if (isPolicySerializable!(Policy, TU)) {
			alias CustomType = typeof(Policy!TU.toRepresentation(TU.init));
			ser.serializeValue!(CustomType, ATTRIBUTES)(Policy!TU.toRepresentation(value));
		} else static if (is(TU == enum)) {
			static if (hasPolicyAttributeL!(ByNameAttribute, Policy, ATTRIBUTES)) {
				ser.serializeValue!(string)(value.to!string());
			} else {
				ser.serializeValue!(OriginalType!TU)(cast(OriginalType!TU)value);
			}
		} else static if (Serializer.isSupportedValueType!TU) {
			static if (is(TU == typeof(null))) ser.writeValue!Traits(null);
			else ser.writeValue!(Traits, TU)(value);
		} else static if (/*isInstanceOf!(Tuple, TU)*/is(T == Tuple!TPS, TPS...)) {
			import std.algorithm.searching: all;
			static if (all!"!a.empty"([TU.fieldNames]) &&
					   !hasPolicyAttributeL!(AsArrayAttribute, Policy, ATTRIBUTES)) {
				static if (__traits(compiles, ser.beginWriteDictionary!TU(0))) {
					auto nfields = value.length;
					ser.beginWriteDictionary!Traits(nfields);
				} else {
					ser.beginWriteDictionary!Traits();
				}
				foreach (i, TV; TU.Types) {
					alias STraits = SubTraits!(Traits, TV);
					ser.beginWriteDictionaryEntry!STraits(underscoreStrip(TU.fieldNames[i]));
					ser.serializeValue!(TV, ATTRIBUTES)(value[i]);
					ser.endWriteDictionaryEntry!STraits(underscoreStrip(TU.fieldNames[i]));
				}
				static if (__traits(compiles, ser.endWriteDictionary!TU(0))) {
					ser.endWriteDictionary!Traits(nfields);
				} else {
					ser.endWriteDictionary!Traits();
				}
			} else static if (TU.Types.length == 1) {
				ser.serializeValue!(typeof(value[0]), ATTRIBUTES)(value[0]);
			} else {
				ser.beginWriteArray!Traits(value.length);
				foreach (i, TV; T.Types) {
					alias STraits = SubTraits!(Traits, TV);
					ser.beginWriteArrayEntry!STraits(i);
					ser.serializeValue!(TV, ATTRIBUTES)(value[i]);
					ser.endWriteArrayEntry!STraits(i);
				}
				ser.endWriteArray!Traits();
			}
		} else static if (isArray!TU) {
			alias TV = typeof(value[0]);
			alias STraits = SubTraits!(Traits, TV);
			ser.beginWriteArray!Traits(value.length);
			foreach (i, ref el; value) {
				ser.beginWriteArrayEntry!STraits(i);
				ser.serializeValue!(TV, ATTRIBUTES)(el);
				ser.endWriteArrayEntry!STraits(i);
			}
			ser.endWriteArray!Traits();
		} else static if (isAssociativeArray!TU) {
			alias TK = KeyType!TU;
			alias TV = ValueType!TU;
			alias STraits = SubTraits!(Traits, TV);

			static if (__traits(compiles, ser.beginWriteDictionary!TU(0))) {
				auto nfields = value.length;
				ser.beginWriteDictionary!Traits(nfields);
			} else {
				ser.beginWriteDictionary!Traits();
			}
			foreach (key, ref el; value) {
				string keyname;
				static if (is(TK : string)) keyname = key;
				else static if (is(TK : real) || is(TK : long) || is(TK == enum)) keyname = key.to!string;
				else static if (isStringSerializable!TK) keyname = key.toString();
				else static assert(false, "Associative array keys must be strings, numbers, enums, or have toString/fromString methods.");
				ser.beginWriteDictionaryEntry!STraits(keyname);
				ser.serializeValue!(TV, ATTRIBUTES)(el);
				ser.endWriteDictionaryEntry!STraits(keyname);
			}
			static if (__traits(compiles, ser.endWriteDictionary!TU(0))) {
				ser.endWriteDictionary!Traits(nfields);
			} else {
				ser.endWriteDictionary!Traits();
			}
		} else static if (/*isInstanceOf!(Nullable, TU)*/is(T == Nullable!TPS, TPS...)) {
			if (value.isNull()) ser.serializeValue!(typeof(null))(null);
			else ser.serializeValue!(typeof(value.get()), ATTRIBUTES)(value.get());
		} else static if (isInstanceOf!(Typedef, TU)) {
			ser.serializeValue!(TypedefType!TU, ATTRIBUTES)(cast(TypedefType!TU)value);
		} else static if (is(TU == BitFlags!E, E)) {
			alias STraits = SubTraits!(Traits, E);

			size_t cnt = 0;
			foreach (v; EnumMembers!E)
				if (value & v)
					cnt++;

			ser.beginWriteArray!Traits(cnt);
			cnt = 0;
			foreach (v; EnumMembers!E)
				if (value & v) {
					ser.beginWriteArrayEntry!STraits(cnt);
					ser.serializeValue!(E, ATTRIBUTES)(v);
					ser.endWriteArrayEntry!STraits(cnt);
					cnt++;
				}
			ser.endWriteArray!Traits();
		} else static if (isCustomSerializable!TU) {
			alias CustomType = typeof(T.init.toRepresentation());
			ser.serializeValue!(CustomType, ATTRIBUTES)(value.toRepresentation());
		} else static if (isISOExtStringSerializable!TU) {
			ser.serializeValue!(string, ATTRIBUTES)(value.toISOExtString());
		} else static if (isStringSerializable!TU) {
			ser.serializeValue!(string, ATTRIBUTES)(value.toString());
		} else static if (is(TU == struct) || is(TU == class)) {
			static if (!hasSerializableFields!(TU, Policy))
				pragma(msg, "Serializing composite type "~T.stringof~" which has no serializable fields");
			static if (is(TU == class)) {
				if (value is null) {
					ser.serializeValue!(typeof(null))(null);
					return;
				}
			}
			static auto safeGetMember(string mname)(ref T val) @safe {
				static if (__traits(compiles, __traits(getMember, val, mname))) {
					return __traits(getMember, val, mname);
				} else {
					pragma(msg, "Warning: Getter for "~fullyQualifiedName!T~"."~mname~" is not @safe");
					return () @trusted { return __traits(getMember, val, mname); } ();
				}
			}
			static if (hasPolicyAttributeL!(AsArrayAttribute, Policy, ATTRIBUTES)) {
				enum nfields = getExpandedFieldCount!(TU, SerializableFields!(TU, Policy));
				ser.beginWriteArray!Traits(nfields);
				size_t fcount = 0;
				foreach (mname; SerializableFields!(TU, Policy)) {
					alias TMS = TypeTuple!(typeof(__traits(getMember, value, mname)));
					foreach (j, TM; TMS) {
						alias TA = TypeTuple!(__traits(getAttributes, TypeTuple!(__traits(getMember, T, mname))[j]));
						alias STraits = SubTraits!(Traits, TM, TA);
						ser.beginWriteArrayEntry!STraits(fcount);
						static if (!isBuiltinTuple!(T, mname))
							ser.serializeValue!(TM, TA)(safeGetMember!mname(value));
						else
							ser.serializeValue!(TM, TA)(tuple(__traits(getMember, value, mname))[j]);
						ser.endWriteArrayEntry!STraits(fcount);
						fcount++;
					}
				}
				ser.endWriteArray!Traits();
			} else {
				static if (__traits(compiles, ser.beginWriteDictionary!Traits(0))) {
					enum nfields = getExpandedFieldCount!(TU, SerializableFields!(TU, Policy));
					ser.beginWriteDictionary!Traits(nfields);
				} else {
					ser.beginWriteDictionary!Traits();
				}
				foreach (mname; SerializableFields!(TU, Policy)) {
					alias TM = TypeTuple!(typeof(__traits(getMember, TU, mname)));
					alias TA = TypeTuple!(__traits(getAttributes, TypeTuple!(__traits(getMember, T, mname))[0]));
					enum name = getPolicyAttribute!(TU, mname, NameAttribute, Policy)(NameAttribute!DefaultPolicy(underscoreStrip(mname))).name;
					static if (!isBuiltinTuple!(T, mname)) {
						auto vt = safeGetMember!mname(value);
					} else {
						auto vt = tuple!TM(__traits(getMember, value, mname));
					}
					alias STraits = SubTraits!(Traits, typeof(vt), TA);
					ser.beginWriteDictionaryEntry!STraits(name);
					ser.serializeValue!(typeof(vt), TA)(vt);
					ser.endWriteDictionaryEntry!STraits(name);
				}
				static if (__traits(compiles, ser.endWriteDictionary!Traits(0))) {
					ser.endWriteDictionary!Traits(nfields);
				} else {
					ser.endWriteDictionary!Traits();
				}
			}
		} else static if (isPointer!TU) {
			if (value is null) {
				ser.writeValue!Traits(null);
				return;
			}
			ser.serializeValue!(PointerTarget!TU)(*value);
		} else static if (is(TU == bool) || is(TU : real) || is(TU : long)) {
			ser.serializeValue!(string, ATTRIBUTES)(to!string(value));
		} else static assert(false, "Unsupported serialization type: " ~ T.stringof);
	}
}

private struct Traits(T, alias POL, ATTRIBUTES...)
{
	alias Type = T;
	alias Policy = POL;
	alias Attributes = TypeTuple!ATTRIBUTES;
}

private struct SubTraits(Traits, T, A...)
{
	alias Type = Unqual!T;
	alias Attributes = TypeTuple!A;
	alias Policy = Traits.Policy;
	alias ContainerType = Traits.Type;
	alias ContainerAttributes = Traits.Attributes;
}

private template deserializeValueImpl(Serializer, alias Policy) {
	alias _Policy = Policy;
	static assert(Serializer.isSupportedValueType!string, "All serializers must support string values.");
	static assert(Serializer.isSupportedValueType!(typeof(null)), "All serializers must support null values.");

	// work around https://issues.dlang.org/show_bug.cgi?id=16528
	static if (isSafeDeserializer!Serializer) {
		T deserializeValue(T, ATTRIBUTES...)(ref Serializer ser) @safe { return deserializeValueDeduced!(T, ATTRIBUTES)(ser); }
	} else {
		T deserializeValue(T, ATTRIBUTES...)(ref Serializer ser) { return deserializeValueDeduced!(T, ATTRIBUTES)(ser); }
	}

	T deserializeValueDeduced(T, ATTRIBUTES...)(ref Serializer ser) if(!isMutable!T)
	{
		import std.algorithm.mutation : move;
		auto ret = deserializeValue!(Unqual!T, ATTRIBUTES)(ser);
		return () @trusted { return cast(T)ret.move; } ();
	}

	T deserializeValueDeduced(T, ATTRIBUTES...)(ref Serializer ser) if(isMutable!T)
	{
		import std.typecons : BitFlags, Nullable, Typedef, TypedefType, Tuple;

		alias Traits = .Traits!(T, _Policy, ATTRIBUTES);

		static if (isPolicySerializable!(Policy, T)) {
			alias CustomType = typeof(Policy!T.toRepresentation(T.init));
			return Policy!T.fromRepresentation(ser.deserializeValue!(CustomType, ATTRIBUTES));
		} else static if (is(T == enum)) {
			static if (hasPolicyAttributeL!(ByNameAttribute, Policy, ATTRIBUTES)) {
				return ser.deserializeValue!(string, ATTRIBUTES).to!T();
			} else {
				return cast(T)ser.deserializeValue!(OriginalType!T);
			}
		} else static if (Serializer.isSupportedValueType!T) {
			return ser.readValue!(Traits, T)();
		} else static if (/*isInstanceOf!(Tuple, TU)*/is(T == Tuple!TPS, TPS...)) {
			enum fieldsCount = T.Types.length;
			import std.algorithm.searching: all;
			static if (all!"!a.empty"([T.fieldNames]) &&
					   !hasPolicyAttributeL!(AsArrayAttribute, Policy, ATTRIBUTES)) {
				T ret;
				bool[fieldsCount] set;
				ser.readDictionary!Traits((name) {
					switch (name) {
						default: break;
						foreach (i, TV; T.Types) {
							enum fieldName = underscoreStrip(T.fieldNames[i]);
							alias STraits = SubTraits!(Traits, TV);
							case fieldName: {
								ser.beginReadDictionaryEntry!STraits(fieldName);
								ret[i] = ser.deserializeValue!(TV, ATTRIBUTES);
								ser.endReadDictionaryEntry!STraits(fieldName);
								set[i] = true;
							} break;
						}
					}
				});
				foreach (i, fieldName; T.fieldNames)
					enforce(set[i], "Missing tuple field '"~fieldName~"' of type '"~T.Types[i].stringof~"' ("~Policy.stringof~").");
				return ret;
			} else static if (fieldsCount == 1) {
				return T(ser.deserializeValue!(T.Types[0], ATTRIBUTES)());
			} else {
				T ret;
				size_t currentField = 0;
				ser.readArray!Traits((sz) { assert(sz == 0 || sz == fieldsCount); }, {
					switch (currentField++) {
						default: break;
						foreach (i, TV; T.Types) {
							alias STraits = SubTraits!(Traits, TV);
							case i: {
								ser.beginReadArrayEntry!STraits(i);
								ret[i] = ser.deserializeValue!(TV, ATTRIBUTES);
								ser.endReadArrayEntry!STraits(i);
							} break;
						}
					}
				});
				enforce(currentField == fieldsCount, "Missing tuple field(s) - expected '"~fieldsCount.stringof~"', received '"~currentField.stringof~"' ("~Policy.stringof~").");
				return ret;
			}
		} else static if (isStaticArray!T) {
			alias TV = typeof(T.init[0]);
			alias STraits = SubTraits!(Traits, TV);
			T ret;
			size_t i = 0;
			ser.readArray!Traits((sz) { assert(sz == 0 || sz == T.length); }, {
				assert(i < T.length);
				ser.beginReadArrayEntry!STraits(i);
				ret[i] = ser.deserializeValue!(TV, ATTRIBUTES);
				ser.endReadArrayEntry!STraits(i);
				i++;
			});
			return ret;
		} else static if (isDynamicArray!T) {
			alias TV = typeof(T.init[0]);
			alias STraits = SubTraits!(Traits, TV);
			//auto ret = appender!T();
			T ret; // Cannot use appender because of DMD BUG 10690/10859/11357
			ser.readArray!Traits((sz) @safe { ret.reserve(sz); }, () @safe {
				size_t i = ret.length;
				ser.beginReadArrayEntry!STraits(i);
				static if (__traits(compiles, () @safe { ser.deserializeValue!(TV, ATTRIBUTES); }))
					ret ~= ser.deserializeValue!(TV, ATTRIBUTES);
				else // recursive array https://issues.dlang.org/show_bug.cgi?id=16528
					ret ~= (() @trusted => ser.deserializeValue!(TV, ATTRIBUTES))();
				ser.endReadArrayEntry!STraits(i);
			});
			return ret;//cast(T)ret.data;
		} else static if (isAssociativeArray!T) {
			alias TK = KeyType!T;
			alias TV = ValueType!T;
			alias STraits = SubTraits!(Traits, TV);

			T ret;
			ser.readDictionary!Traits((name) @safe {
				TK key;
				static if (is(TK == string) || (is(TK == enum) && is(OriginalType!TK == string))) key = cast(TK)name;
				else static if (is(TK : real) || is(TK : long) || is(TK == enum)) key = name.to!TK;
				else static if (isStringSerializable!TK) key = TK.fromString(name);
				else static assert(false, "Associative array keys must be strings, numbers, enums, or have toString/fromString methods.");
				ser.beginReadDictionaryEntry!STraits(name);
				ret[key] = ser.deserializeValue!(TV, ATTRIBUTES);
				ser.endReadDictionaryEntry!STraits(name);
			});
			return ret;
		} else static if (isInstanceOf!(Nullable, T)) {
			if (ser.tryReadNull!Traits()) return T.init;
			return T(ser.deserializeValue!(typeof(T.init.get()), ATTRIBUTES));
		} else static if (isInstanceOf!(Typedef, T)) {
			return T(ser.deserializeValue!(TypedefType!T, ATTRIBUTES));
		} else static if (is(T == BitFlags!E, E)) {
			alias STraits = SubTraits!(Traits, E);
			T ret;
			size_t i = 0;
			ser.readArray!Traits((sz) {}, {
				ser.beginReadArrayEntry!STraits(i);
				ret |= ser.deserializeValue!(E, ATTRIBUTES);
				ser.endReadArrayEntry!STraits(i);
				i++;
			});
			return ret;
		} else static if (isCustomSerializable!T) {
			alias CustomType = typeof(T.init.toRepresentation());
			return T.fromRepresentation(ser.deserializeValue!(CustomType, ATTRIBUTES));
		} else static if (isISOExtStringSerializable!T) {
			return T.fromISOExtString(ser.readValue!(Traits, string)());
		} else static if (isStringSerializable!T) {
			return T.fromString(ser.readValue!(Traits, string)());
		} else static if (is(T == struct) || is(T == class)) {
			static if (is(T == class)) {
				if (ser.tryReadNull!Traits()) return null;
			}

			T ret;
			string name;
			bool[getExpandedFieldsData!(T, SerializableFields!(T, Policy)).length] set;
			static if (is(T == class)) ret = new T;

			void safeSetMember(string mname, U)(ref T value, U fval)
			@safe {
				static if (__traits(compiles, () @safe { __traits(getMember, value, mname) = fval; }))
					__traits(getMember, value, mname) = fval;
				else {
					pragma(msg, "Warning: Setter for "~fullyQualifiedName!T~"."~mname~" is not @safe");
					() @trusted { __traits(getMember, value, mname) = fval; } ();
				}
			}

			static if (hasPolicyAttributeL!(AsArrayAttribute, Policy, ATTRIBUTES)) {
				size_t idx = 0;
				ser.readArray!Traits((sz){}, {
					static if (hasSerializableFields!(T, Policy)) {
						switch (idx++) {
							default: break;
							foreach (i, FD; getExpandedFieldsData!(T, SerializableFields!(T, Policy))) {
								enum mname = FD[0];
								enum msindex = FD[1];
								alias MT = TypeTuple!(__traits(getMember, T, mname));
								alias MTI = MT[msindex];
								alias TMTI = typeof(MTI);
								alias TMTIA = TypeTuple!(__traits(getAttributes, MTI));
								alias STraits = SubTraits!(Traits, TMTI, TMTIA);

							case i:
								static if (hasPolicyAttribute!(OptionalAttribute, Policy, MTI))
									if (ser.tryReadNull!STraits()) return;
								set[i] = true;
								ser.beginReadArrayEntry!STraits(i);
								static if (!isBuiltinTuple!(T, mname)) {
									safeSetMember!mname(ret, ser.deserializeValue!(TMTI, TMTIA));
								} else {
									__traits(getMember, ret, mname)[msindex] = ser.deserializeValue!(TMTI, TMTIA);
								}
								ser.endReadArrayEntry!STraits(i);
								break;
							}
						}
					} else {
						pragma(msg, "Deserializing composite type "~T.stringof~" which has no serializable fields.");
					}
				});
			} else {
				ser.readDictionary!Traits((name) {
					static if (hasSerializableFields!(T, Policy)) {
						switch (name) {
							default: break;
							foreach (i, mname; SerializableFields!(T, Policy)) {
								alias TM = TypeTuple!(typeof(__traits(getMember, T, mname)));
								alias TA = TypeTuple!(__traits(getAttributes, TypeTuple!(__traits(getMember, T, mname))[0]));
								alias STraits = SubTraits!(Traits, TM, TA);
								enum fname = getPolicyAttribute!(T, mname, NameAttribute, Policy)(NameAttribute!DefaultPolicy(underscoreStrip(mname))).name;
								case fname:
									static if (hasPolicyAttribute!(OptionalAttribute, Policy, TypeTuple!(__traits(getMember, T, mname))[0]))
										if (ser.tryReadNull!STraits()) return;
									set[i] = true;
									ser.beginReadDictionaryEntry!STraits(fname);
									static if (!isBuiltinTuple!(T, mname)) {
										safeSetMember!mname(ret, ser.deserializeValue!(TM, TA));
									} else {
										__traits(getMember, ret, mname) = ser.deserializeValue!(Tuple!TM, TA);
									}
									ser.endReadDictionaryEntry!STraits(fname);
									break;
							}
						}
					} else {
						pragma(msg, "Deserializing composite type "~T.stringof~" which has no serializable fields.");
					}
				});
			}
			foreach (i, mname; SerializableFields!(T, Policy))
				static if (!hasPolicyAttribute!(OptionalAttribute, Policy, TypeTuple!(__traits(getMember, T, mname))[0]))
					enforce(set[i], "Missing non-optional field '"~mname~"' of type '"~T.stringof~"' ("~Policy.stringof~").");
			return ret;
		} else static if (isPointer!T) {
			if (ser.tryReadNull!Traits()) return null;
			alias PT = PointerTarget!T;
			auto ret = new PT;
			*ret = ser.deserializeValue!(PT, ATTRIBUTES);
			return ret;
		} else static if (is(T == bool) || is(T : real) || is(T : long)) {
			return to!T(ser.deserializeValue!string());
		} else static assert(false, "Unsupported serialization type: " ~ T.stringof);
	}
}


/**
	Attribute for overriding the field name during (de-)serialization.

	Note that without the `@name` attribute there is a shorter alternative
	for using names that collide with a D keyword. A single trailing
	underscore will automatically be stripped when determining a field
	name.
*/
NameAttribute!Policy name(alias Policy = DefaultPolicy)(string name)
{
	return NameAttribute!Policy(name);
}
///
unittest {
	struct CustomPolicy {}

	struct Test {
		// serialized as "screen-size":
		@name("screen-size") int screenSize;

		// serialized as "print-size" by default,
		// but as "PRINTSIZE" if CustomPolicy is used for serialization.
		@name("print-size")
		@name!CustomPolicy("PRINTSIZE")
		int printSize;

		// serialized as "version"
		int version_;
	}
}


/**
	Attribute marking a field as optional during deserialization.
*/
@property OptionalAttribute!Policy optional(alias Policy = DefaultPolicy)()
{
	return OptionalAttribute!Policy();
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
@property IgnoreAttribute!Policy ignore(alias Policy = DefaultPolicy)()
{
	return IgnoreAttribute!Policy();
}
///
unittest {
	struct Test {
		// is neither serialized not deserialized
		@ignore int screenSize;
	}
}
///
unittest {
	template CustomPolicy(T) {
		// ...
	}

	struct Test {
		// not (de)serialized for serializeWithPolicy!(Test, CustomPolicy)
		// but for other policies or when serialized without a policy
		@ignore!CustomPolicy int screenSize;
	}
}


/**
	Attribute for forcing serialization of enum fields by name instead of by value.
*/
@property ByNameAttribute!Policy byName(alias Policy = DefaultPolicy)()
{
	return ByNameAttribute!Policy();
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
@property AsArrayAttribute!Policy asArray(alias Policy = DefaultPolicy)()
{
	return AsArrayAttribute!Policy();
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
struct NameAttribute(alias POLICY) { alias Policy = POLICY; string name; }
/// ditto
struct OptionalAttribute(alias POLICY) { alias Policy = POLICY; }
/// ditto
struct IgnoreAttribute(alias POLICY) { alias Policy = POLICY; }
/// ditto
struct ByNameAttribute(alias POLICY) { alias Policy = POLICY; }
/// ditto
struct AsArrayAttribute(alias POLICY) { alias Policy = POLICY; }

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

	// represented as a string when serialized
	static struct S {
		int value;

		// dummy example implementations
		string toString() const { return value.to!string(); }
		static S fromString(string s) { return S(s.to!int()); }
	}

	static assert(isStringSerializable!S);
}


/** Default policy (performs no customization).
*/
template DefaultPolicy(T)
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

private template isBuiltinTuple(T, string member)
{
    alias TM = AliasSeq!(typeof(__traits(getMember, T.init, member)));
    static if (TM.length > 1) enum isBuiltinTuple = true;
    else static if (is(typeof(__traits(getMember, T.init, member)) == TM[0]))
        enum isBuiltinTuple = false;
    else enum isBuiltinTuple = true; // single-element tuple
}

// heuristically determines @safe'ty of the serializer by testing readValue and writeValue for type int
private template isSafeSerializer(S)
{
	alias T = Traits!(int, DefaultPolicy);
	static if (__traits(hasMember, S, "writeValue"))
		enum isSafeSerializer = __traits(compiles, (S s) @safe { s.writeValue!T(42); });
	else static assert(0, "Serializer is missing required writeValue method");
}

// heuristically determines @safe'ty of the deserializer by testing readValue and writeValue for type int
private template isSafeDeserializer(S)
{
	alias T = Traits!(int, DefaultPolicy);
	static if (__traits(hasMember, S, "readValue"))
		enum isSafeDeserializer = __traits(compiles, (S s) @safe { s.readValue!(T, int)(); });
	else static assert(0, "Deserializer is missing required readValue method");
}

private template hasAttribute(T, alias decl) { enum hasAttribute = findFirstUDA!(T, decl).found; }

unittest {
	@asArray int i1;
	static assert(hasAttribute!(AsArrayAttribute!DefaultPolicy, i1));
	int i2;
	static assert(!hasAttribute!(AsArrayAttribute!DefaultPolicy, i2));
}

private template hasPolicyAttribute(alias T, alias POLICY, alias decl)
{
	enum hasPolicyAttribute = hasAttribute!(T!POLICY, decl) || hasAttribute!(T!DefaultPolicy, decl);
}

unittest {
	template CP(T) {}
	@asArray!CP int i1;
	@asArray int i2;
	int i3;
	static assert(hasPolicyAttribute!(AsArrayAttribute, CP, i1));
	static assert(hasPolicyAttribute!(AsArrayAttribute, CP, i2));
	static assert(!hasPolicyAttribute!(AsArrayAttribute, CP, i3));
	static assert(!hasPolicyAttribute!(AsArrayAttribute, DefaultPolicy, i1));
	static assert(hasPolicyAttribute!(AsArrayAttribute, DefaultPolicy, i2));
	static assert(!hasPolicyAttribute!(AsArrayAttribute, DefaultPolicy, i3));
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
	static assert(hasAttributeL!(AsArrayAttribute!DefaultPolicy, byName, asArray));
	static assert(!hasAttributeL!(AsArrayAttribute!DefaultPolicy, byName));
}

private template hasPolicyAttributeL(alias T, alias POLICY, ATTRIBUTES...)
{
	enum hasPolicyAttributeL = hasAttributeL!(T!POLICY, ATTRIBUTES) || hasAttributeL!(T!DefaultPolicy, ATTRIBUTES);
}

private static T getAttribute(TT, string mname, T)(T default_value)
{
	enum val = findFirstUDA!(T, __traits(getMember, TT, mname));
	static if (val.found) return val.value;
	else return default_value;
}

private static auto getPolicyAttribute(TT, string mname, alias Attribute, alias Policy)(Attribute!DefaultPolicy default_value)
{
	enum val = findFirstUDA!(Attribute!Policy, TypeTuple!(__traits(getMember, TT, mname))[0]);
	static if (val.found) return val.value;
	else {
		enum val2 = findFirstUDA!(Attribute!DefaultPolicy, TypeTuple!(__traits(getMember, TT, mname))[0]);
		static if (val2.found) return val2.value;
		else return default_value;
	}
}

private string underscoreStrip(string field_name)
@safe nothrow @nogc {
	if( field_name.length < 1 || field_name[$-1] != '_' ) return field_name;
	else return field_name[0 .. $-1];
}


private template hasSerializableFields(T, alias POLICY, size_t idx = 0)
{
	enum hasSerializableFields = SerializableFields!(T, POLICY).length > 0;
	/*static if (idx < __traits(allMembers, T).length) {
		enum mname = __traits(allMembers, T)[idx];
		static if (!isRWPlainField!(T, mname) && !isRWField!(T, mname)) enum hasSerializableFields = hasSerializableFields!(T, idx+1);
		else static if (hasAttribute!(IgnoreAttribute, __traits(getMember, T, mname))) enum hasSerializableFields = hasSerializableFields!(T, idx+1);
		else enum hasSerializableFields = true;
	} else enum hasSerializableFields = false;*/
}

private template SerializableFields(COMPOSITE, alias POLICY)
{
	alias SerializableFields = FilterSerializableFields!(COMPOSITE, POLICY, __traits(allMembers, COMPOSITE));
}

private template FilterSerializableFields(COMPOSITE, alias POLICY, FIELDS...)
{
	static if (FIELDS.length > 1) {
		alias FilterSerializableFields = TypeTuple!(
			FilterSerializableFields!(COMPOSITE, POLICY, FIELDS[0 .. $/2]),
			FilterSerializableFields!(COMPOSITE, POLICY, FIELDS[$/2 .. $]));
	} else static if (FIELDS.length == 1) {
		alias T = COMPOSITE;
		enum mname = FIELDS[0];
		static if (isRWPlainField!(T, mname) || isRWField!(T, mname)) {
			alias Tup = TypeTuple!(__traits(getMember, COMPOSITE, FIELDS[0]));
			static if (Tup.length != 1) {
				alias FilterSerializableFields = TypeTuple!(mname);
			} else {
				static if (!hasPolicyAttribute!(IgnoreAttribute, POLICY, __traits(getMember, T, mname)))
				{
					alias FilterSerializableFields = TypeTuple!(mname);
				} else alias FilterSerializableFields = TypeTuple!();
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

private template getExpandedFieldsData(T, FIELDS...)
{
	import std.meta : aliasSeqOf, staticMap;
	import std.range : repeat, zip, iota;

	enum subfieldsCount(alias F) = TypeTuple!(__traits(getMember, T, F)).length;
	alias processSubfield(alias F) = aliasSeqOf!(zip(repeat(F), iota(subfieldsCount!F)));
	alias getExpandedFieldsData = staticMap!(processSubfield, FIELDS);
}

/******************************************************************************/
/* General serialization unit testing                                         */
/******************************************************************************/

version (unittest) {
	static assert(isSafeSerializer!TestSerializer);
	static assert(isSafeDeserializer!TestSerializer);

	private struct TestSerializer {
		import std.array, std.conv, std.string;

		string result;

		enum isSupportedValueType(T) = is(T == string) || is(T == typeof(null)) || is(T == float) || is (T == int);

		string getSerializedResult() @safe { return result; }
		void beginWriteDictionary(Traits)() { result ~= "D("~Traits.Type.mangleof~"){"; }
		void endWriteDictionary(Traits)() { result ~= "}D("~Traits.Type.mangleof~")"; }
		void beginWriteDictionaryEntry(Traits)(string name) { result ~= "DE("~Traits.Type.mangleof~","~name~")("; }
		void endWriteDictionaryEntry(Traits)(string name) { result ~= ")DE("~Traits.Type.mangleof~","~name~")"; }
		void beginWriteArray(Traits)(size_t length) { result ~= "A("~Traits.Type.mangleof~")["~length.to!string~"]["; }
		void endWriteArray(Traits)() { result ~= "]A("~Traits.Type.mangleof~")"; }
		void beginWriteArrayEntry(Traits)(size_t i) { result ~= "AE("~Traits.Type.mangleof~","~i.to!string~")("; }
		void endWriteArrayEntry(Traits)(size_t i) { result ~= ")AE("~Traits.Type.mangleof~","~i.to!string~")"; }
		void writeValue(Traits, T)(T value) {
			if (is(T == typeof(null))) result ~= "null";
			else {
				assert(isSupportedValueType!T);
				result ~= "V("~T.mangleof~")("~value.to!string~")";
			}
		}

		// deserialization
		void readDictionary(Traits)(scope void delegate(string) @safe entry_callback)
		{
			skip("D("~Traits.Type.mangleof~"){");
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
			skip("}D("~Traits.Type.mangleof~")");
		}

		void beginReadDictionaryEntry(Traits)(string name) {}
		void endReadDictionaryEntry(Traits)(string name) {}

		void readArray(Traits)(scope void delegate(size_t) @safe size_callback, scope void delegate() @safe entry_callback)
		{
			skip("A("~Traits.Type.mangleof~")[");
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
			skip("]A("~Traits.Type.mangleof~")");

			assert(i == cnt);
		}

		void beginReadArrayEntry(Traits)(size_t index) {}
		void endReadArrayEntry(Traits)(size_t index) {}

		T readValue(Traits, T)()
		{
			skip("V("~T.mangleof~")(");
			auto idx = result.indexOf(')');
			assert(idx >= 0);
			auto ret = result[0 .. idx].to!T;
			result = result[idx+1 .. $];
			return ret;
		}

		void skip(string prefix)
		@safe {
			assert(result.startsWith(prefix), prefix ~ " vs. " ~result);
			result = result[prefix.length .. $];
		}

		bool tryReadNull(Traits)()
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
	string mangleOfAA = (string[string]).mangleof;
	test(["hello": "world"], "D(" ~ mangleOfAA ~ "){DE(Aya,hello)(V(Aya)(world))DE(Aya,hello)}D(" ~ mangleOfAA ~ ")");
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
	const s = S!(int, string)(42, "hello");

	const ss = serialize!TestSerializer(s);
	const es = "D("~Sm~"){DE("~Tum~",f)(A("~Tum~")[2][AE(i,0)(V(i)(42))AE(i,0)AE(Aya,1)(V(Aya)(hello))AE(Aya,1)]A("~Tum~"))DE("~Tum~",f)}D("~Sm~")";
	assert(ss == es);

	const dss = deserialize!(TestSerializer, typeof(s))(ss);
	assert(dss == s);

	static struct T { @asArray S!(int, string) g; }
	enum Tm = T.mangleof;
	const t = T(s);

	const st = serialize!TestSerializer(t);
	const et = "D("~Tm~"){DE("~Sm~",g)(A("~Sm~")[2][AE(i,0)(V(i)(42))AE(i,0)AE(Aya,1)(V(Aya)(hello))AE(Aya,1)]A("~Sm~"))DE("~Sm~",g)}D("~Tm~")";
	assert(st == et);

	const dst = deserialize!(TestSerializer, typeof(t))(st);
	assert(dst == t);
}

unittest { // named tuple serialization
	import std.typecons : tuple;

	static struct I {
		int i;
	}

	static struct S {
		int x;
		string s_;
	}

	static struct T {
		@asArray
		typeof(tuple!(FieldNameTuple!I)(I.init.tupleof)) tuple1AsArray;

		@name(fullyQualifiedName!I)
		typeof(tuple!(FieldNameTuple!I)(I.init.tupleof)) tuple1AsDictionary;

		@asArray
		typeof(tuple!(FieldNameTuple!S)(S.init.tupleof)) tuple2AsArray;

		@name(fullyQualifiedName!S)
		typeof(tuple!(FieldNameTuple!S)(S.init.tupleof)) tuple2AsDictionary;
	}

	const i = I(42);
	const s = S(42, "hello");
	const T t = { i.tupleof, i.tupleof, s.tupleof, s.tupleof };

	const st = serialize!TestSerializer(t);

	enum Tm = T.mangleof;
	enum TuIm = typeof(T.tuple1AsArray).mangleof;
	enum TuSm = typeof(T.tuple2AsArray).mangleof;

	const et =
		"D("~Tm~")"~
		"{"~
			"DE("~TuIm~",tuple1AsArray)"~
			"("~
				"V(i)(42)"~
			")"~
			"DE("~TuIm~",tuple1AsArray)"~
			"DE("~TuIm~","~fullyQualifiedName!I~")"~
			"("~
				"D("~TuIm~")"~
				"{"~
					"DE(i,i)"~
					"("~
						"V(i)(42)"~
					")"~
					"DE(i,i)"~
				"}"~
				"D("~TuIm~")"~
			")"~
			"DE("~TuIm~","~fullyQualifiedName!I~")"~
			"DE("~TuSm~",tuple2AsArray)"~
			"("~
				"A("~TuSm~")[2]"~
				"["~
					"AE(i,0)"~
					"("~
						"V(i)(42)"~
					")"~
					"AE(i,0)"~
					"AE(Aya,1)"~
					"("~
						"V(Aya)(hello)"~
					")"~
					"AE(Aya,1)"~
				"]"~
				"A("~TuSm~")"~
			")"~
			"DE("~TuSm~",tuple2AsArray)"~
			"DE("~TuSm~","~fullyQualifiedName!S~")"~
			"("~
				"D("~TuSm~")"~
				"{"~
					"DE(i,x)"~
					"("~
						"V(i)(42)"~
					")"~
					"DE(i,x)"~
					"DE(Aya,s)"~
					"("~
						"V(Aya)(hello)"~
					")"~
					"DE(Aya,s)"~
				"}"~
				"D("~TuSm~")"~
			")"~
			"DE("~TuSm~","~fullyQualifiedName!S~")"~
		"}"~
		"D("~Tm~")";
	assert(st == et);

	const dst = deserialize!(TestSerializer, typeof(t))(st);
	assert(dst == t);
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
}

@safe unittest { // custom serialization support
	// string
	static struct S1 { int i; string toString() const @safe { return "hello"; } static S1 fromString(string) @safe { return S1.init; } }
	static struct S2 { int i; string toString() const { return "hello"; } }
	enum S2m = S2.mangleof;
	static struct S3 { int i; static S3 fromString(string) { return S3.init; } }
	enum S3m = S3.mangleof;
	assert(serialize!TestSerializer(S1.init) == "V(Aya)(hello)");
	assert(serialize!TestSerializer(S2.init) == "D("~S2m~"){DE(i,i)(V(i)(0))DE(i,i)}D("~S2m~")");
	assert(serialize!TestSerializer(S3.init) == "D("~S3m~"){DE(i,i)(V(i)(0))DE(i,i)}D("~S3m~")");

	// custom
	static struct C1 { int i; float toRepresentation() const @safe { return 1.0f; } static C1 fromRepresentation(float f) @safe { return C1.init; } }
	static struct C2 { int i; float toRepresentation() const { return 1.0f; } }
	enum C2m = C2.mangleof;
	static struct C3 { int i; static C3 fromRepresentation(float f) { return C3.init; } }
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

@safe unittest // Make sure serializing through properties still works
{
	import vibe.data.json;

	static struct S
	{
		@safe:
		public int i;
		private int privateJ;

		@property int j() @safe { return privateJ; }
		@property void j(int j) @safe { privateJ = j; }
	}

	auto s = S(1, 2);
	assert(s.serializeToJson().deserializeJson!S() == s);
}

@safe unittest // Immutable data deserialization
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

	enum Fi_ser = "A("~Flagsm~")[0][]A("~Flagsm~")";
	assert(serialize!TestSerializer(Flags.init) == Fi_ser);

	enum Fac_ser = "A("~Flagsm~")[2][AE("~Flagm~",0)(V(i)(1))AE("~Flagm~",0)AE("~Flagm~",1)(V(i)(4))AE("~Flagm~",1)]A("~Flagsm~")";
	assert(serialize!TestSerializer(Flags(Flag.a, Flag.c)) == Fac_ser);

	struct S { @byName Flags f; }
	enum Sm = S.mangleof;
	enum Sac_ser = "D("~Sm~"){DE("~Flagsm~",f)(A("~Flagsm~")[2][AE("~Flagm~",0)(V(Aya)(a))AE("~Flagm~",0)AE("~Flagm~",1)(V(Aya)(c))AE("~Flagm~",1)]A("~Flagsm~"))DE("~Flagsm~",f)}D("~Sm~")";

	assert(serialize!TestSerializer(S(Flags(Flag.a, Flag.c))) == Sac_ser);

	assert(deserialize!(TestSerializer, Flags)(Fi_ser) == Flags.init);
	assert(deserialize!(TestSerializer, Flags)(Fac_ser) == Flags(Flag.a, Flag.c));
	assert(deserialize!(TestSerializer, S)(Sac_ser) == S(Flags(Flag.a, Flag.c)));
}

@safe unittest { // issue #1182
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

@safe unittest { // issue #1352 - ingore per policy
	struct P1 {}
	struct P2 {}

	struct T {
		@ignore int a = 5;
		@ignore!P1 @ignore!P2 int b = 6;
		@ignore!P1 c = 7;
		int d = 8;
	}

	auto t = T(1, 2, 3, 4);
	auto Tm = T.mangleof;
	auto t_ser_plain = "D("~Tm~"){DE(i,b)(V(i)(2))DE(i,b)DE(i,c)(V(i)(3))DE(i,c)DE(i,d)(V(i)(4))DE(i,d)}D("~Tm~")";
	auto t_ser_p1 = "D("~Tm~"){DE(i,d)(V(i)(4))DE(i,d)}D("~Tm~")";
	auto t_ser_p2 = "D("~Tm~"){DE(i,c)(V(i)(3))DE(i,c)DE(i,d)(V(i)(4))DE(i,d)}D("~Tm~")";

	{
		auto serialized_plain = serialize!TestSerializer(t);
		assert(serialized_plain == t_ser_plain);
		assert(deserialize!(TestSerializer, T)(serialized_plain) == T(5, 2, 3, 4));
	}

	{
		auto serialized_p1 = serializeWithPolicy!(TestSerializer, P1)(t);
		assert(serialized_p1 == t_ser_p1, serialized_p1);
		assert(deserializeWithPolicy!(TestSerializer, P1, T)(serialized_p1) == T(5, 6, 7, 4));
	}

	{
		auto serialized_p2 = serializeWithPolicy!(TestSerializer, P2)(t);
		assert(serialized_p2 == t_ser_p2);
		assert(deserializeWithPolicy!(TestSerializer, P2, T)(serialized_p2) == T(5, 6, 3, 4));
	}
}

unittest {
	import std.conv : to;
	import std.string : toLower, toUpper;

	template P(T) if (is(T == enum)) {
		@safe:
		static string toRepresentation(T v) { return v.to!string.toLower(); }
		static T fromRepresentation(string str) { return str.toUpper().to!T; }
	}


	enum E {
		RED,
		GREEN
	}

	assert(P!E.fromRepresentation("green") == E.GREEN);
	static assert(isPolicySerializable!(P, E));

	auto ser_red = "V(Aya)(red)";
	assert(serializeWithPolicy!(TestSerializer, P)(E.RED) == ser_red, serializeWithPolicy!(TestSerializer, P)(E.RED));
	assert(deserializeWithPolicy!(TestSerializer, P, E)(ser_red) == E.RED);

	import vibe.data.json : Json, JsonSerializer;
	assert(serializeWithPolicy!(JsonSerializer, P)(E.RED) == Json("red"));
}

unittest {
	static struct R { int y; }
	static struct Custom {
		@safe:
		int x;
		R toRepresentation() const { return R(x); }
		static Custom fromRepresentation(R r) { return Custom(r.y); }
	}

	auto c = Custom(42);
	auto Rn = R.mangleof;
	auto ser = serialize!TestSerializer(c);
	assert(ser == "D("~Rn~"){DE(i,y)(V(i)(42))DE(i,y)}D("~Rn~")");
	auto deser = deserialize!(TestSerializer, Custom)(ser);
	assert(deser.x == 42);
}

unittest {
	import std.typecons : Typedef;
	alias T = Typedef!int;
	auto ser = serialize!TestSerializer(T(42));
	assert(ser == "V(i)(42)", ser);
	auto deser = deserialize!(TestSerializer, T)(ser);
	assert(deser == 42);
}

@safe unittest {
	static struct Foo { Foo[] foos; }
	Foo f;
	string ser = serialize!TestSerializer(f);
	assert(deserialize!(TestSerializer, Foo)(ser) == f);
}

@system unittest {
	static struct SystemSerializer {
		TestSerializer ser;
		alias ser this;
		this(string s) { ser.result = s; }
		T readValue(Traits, T)() @system { return ser.readValue!(Traits, T); }
		void writeValue(Traits, T)(T value) @system { ser.writeValue!(Traits, T)(value); }
		void readDictionary(Traits)(scope void delegate(string) @system entry_callback) { ser.readDictionary!Traits((s) @trusted { entry_callback(s); }); }
		void readArray(Traits)(scope void delegate(size_t) @system size_callback, scope void delegate() @system entry_callback) { ser.readArray!Traits((s) @trusted { size_callback(s); }, () @trusted { entry_callback(); }); }
	}

	static struct Bar { Bar[] foos; int i; }
	Bar f;
	string ser = serialize!SystemSerializer(f);
	assert(deserialize!(SystemSerializer, Bar)(ser) == f);
}

@safe unittest {
	static struct S { @name("+foo") int bar; }
	auto Sn = S.mangleof;
	auto s = S(42);
	string ser = serialize!TestSerializer(s);
	assert(ser == "D("~Sn~"){DE(i,+foo)(V(i)(42))DE(i,+foo)}D("~Sn~")", ser);
	auto deser = deserialize!(TestSerializer, S)(ser);
	assert(deser.bar == 42);
}

@safe unittest {
	static struct S { int bar_; }
	auto Sn = S.mangleof;
	auto s = S(42);
	string ser = serialize!TestSerializer(s);
	assert(ser == "D("~Sn~"){DE(i,bar)(V(i)(42))DE(i,bar)}D("~Sn~")", ser);
	auto deser = deserialize!(TestSerializer, S)(ser);
	assert(deser.bar_ == 42);
}

@safe unittest { // issue 1941
	static struct Bar { Bar[] foos; int i; }
	Bar b1 = {[{null, 2}], 1};
	auto s = serialize!TestSerializer(b1);
	auto b = deserialize!(TestSerializer, Bar)(s);
	assert(b.i == 1);
	assert(b.foos.length == 1);
	assert(b.foos[0].i == 2);
}

unittest { // issue 1991 - @system property getters/setters does not compile
	static class A {
		@property @name("foo") {
			string fooString() const { return "a"; }
			void fooString(string a) {  }
		}
	}

	auto a1 = new A;
	auto b = serialize!TestSerializer(a1);
	auto a2 = deserialize!(TestSerializer, A)(b);
}

unittest { // issue #2110 - single-element tuples
	static struct F { int field; }

	{
		static struct S { typeof(F.init.tupleof) fields; }
		auto b = serialize!TestSerializer(S(42));
		auto a = deserialize!(TestSerializer, S)(b);
		assert(a.fields[0] == 42);
	}

	{
		static struct T { @asArray typeof(F.init.tupleof) fields; }
		auto b = serialize!TestSerializer(T(42));
		auto a = deserialize!(TestSerializer, T)(b);
		assert(a.fields[0] == 42);
	}
}
