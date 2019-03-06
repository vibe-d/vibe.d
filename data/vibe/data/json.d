/**
	JSON serialization and value handling.

	This module provides the Json struct for reading, writing and manipulating
	JSON values. De(serialization) of arbitrary D types is also supported and
	is recommended for handling JSON in performance sensitive applications.

	Copyright: © 2012-2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.data.json;

///
@safe unittest {
	void manipulateJson(Json j)
	{
		import std.stdio;

		// retrieving the values is done using get()
		assert(j["name"].get!string == "Example");
		assert(j["id"].get!int == 1);

		// semantic conversions can be done using to()
		assert(j["id"].to!string == "1");

		// prints:
		// name: "Example"
		// id: 1
		foreach (key, value; j.byKeyValue)
			writefln("%s: %s", key, value);

		// print out as JSON: {"name": "Example", "id": 1}
		writefln("JSON: %s", j.toString());

		// DEPRECATED: object members can be accessed using member syntax, just like in JavaScript
		//j = Json.emptyObject;
		//j.name = "Example";
		//j.id = 1;
	}
}

/// Constructing `Json` objects
@safe unittest {
	// construct a JSON object {"field1": "foo", "field2": 42, "field3": true}

	// using the constructor
	Json j1 = Json(["field1": Json("foo"), "field2": Json(42), "field3": Json(true)]);

	// using piecewise construction
	Json j2 = Json.emptyObject;
	j2["field1"] = "foo";
	j2["field2"] = 42.0;
	j2["field3"] = true;

	// using serialization
	struct S {
		string field1;
		double field2;
		bool field3;
	}
	Json j3 = S("foo", 42, true).serializeToJson();

	// using serialization, converting directly to a JSON string
	string j4 = S("foo", 32, true).serializeToJsonString();
}


public import vibe.data.serialization;

public import std.json : JSONException;
import std.algorithm;
import std.array;
import std.bigint;
import std.conv;
import std.datetime;
import std.exception;
import std.format;
import std.json : JSONValue, JSON_TYPE;
import std.range;
import std.string;
import std.traits;
import std.typecons : Tuple;
import std.uuid;

/******************************************************************************/
/* public types                                                               */
/******************************************************************************/

/**
	Represents a single JSON value.

	Json values can have one of the types defined in the Json.Type enum. They
	behave mostly like values in ECMA script in the way that you can
	transparently perform operations on them. However, strict typechecking is
	done, so that operations between differently typed JSON values will throw
	a JSONException. Additionally, an explicit cast or using get!() or to!() is
	required to convert a JSON value to the corresponding static D type.
*/
align(8) // ensures that pointers stay on 64-bit boundaries on x64 so that they get scanned by the GC
struct Json {
@safe:

	static assert(!hasElaborateDestructor!BigInt && !hasElaborateCopyConstructor!BigInt,
		"struct Json is missing required ~this and/or this(this) members for BigInt.");

	private {
		// putting all fields in a union results in many false pointers leading to
		// memory leaks and, worse, std.algorithm.swap triggering an assertion
		// because of internal pointers. This crude workaround seems to fix
		// the issues.
		enum m_size = max((BigInt.sizeof+(void*).sizeof), 2);
		// NOTE : DMD 2.067.1 doesn't seem to init void[] correctly on its own.
		// Explicity initializing it works around this issue. Using a void[]
		// array here to guarantee that it's scanned by the GC.
		void[m_size] m_data = (void[m_size]).init;

		static assert(m_data.offsetof == 0, "m_data must be the first struct member.");
		static assert(BigInt.alignof <= 8, "Json struct alignment of 8 isn't sufficient to store BigInt.");

		ref inout(T) getDataAs(T)() inout @trusted {
			static assert(T.sizeof <= m_data.sizeof);
			return (cast(inout(T)[1])m_data[0 .. T.sizeof])[0];
		}

		@property ref inout(BigInt) m_bigInt() inout { return getDataAs!BigInt(); }
		@property ref inout(long) m_int() inout { return getDataAs!long(); }
		@property ref inout(double) m_float() inout { return getDataAs!double(); }
		@property ref inout(bool) m_bool() inout { return getDataAs!bool(); }
		@property ref inout(string) m_string() inout { return getDataAs!string(); }
		@property ref inout(Json[string]) m_object() inout { return getDataAs!(Json[string])(); }
		@property ref inout(Json[]) m_array() inout { return getDataAs!(Json[])(); }

		Type m_type = Type.undefined;

		version (VibeJsonFieldNames) {
			string m_name;
		}
	}

	/** Represents the run time type of a JSON value.
	*/
	enum Type {
		undefined,  /// A non-existent value in a JSON object
		null_,      /// Null value
		bool_,      /// Boolean value
		int_,       /// 64-bit integer value
		bigInt,     /// BigInt values
		float_,     /// 64-bit floating point value
		string,     /// UTF-8 string
		array,      /// Array of JSON values
		object,     /// JSON object aka. dictionary from string to Json

		Undefined = undefined,  /// Compatibility alias - will be deprecated soon
		Null = null_,           /// Compatibility alias - will be deprecated soon
		Bool = bool_,           /// Compatibility alias - will be deprecated soon
		Int = int_,             /// Compatibility alias - will be deprecated soon
		Float = float_,         /// Compatibility alias - will be deprecated soon
		String = string,        /// Compatibility alias - will be deprecated soon
		Array = array,          /// Compatibility alias - will be deprecated soon
		Object = object         /// Compatibility alias - will be deprecated soon
	}

	/// New JSON value of Type.Undefined
	static @property Json undefined() { return Json(); }

	/// New JSON value of Type.Object
	static @property Json emptyObject() { return Json(cast(Json[string])null); }

	/// New JSON value of Type.Array
	static @property Json emptyArray() { return Json(cast(Json[])null); }

	version(JsonLineNumbers) int line;

	/**
		Constructor for a JSON object.
	*/
	this(typeof(null)) @trusted { m_type = Type.null_; }
	/// ditto
	this(bool v) @trusted { m_type = Type.bool_; m_bool = v; }
	/// ditto
	this(byte v) { this(cast(long)v); }
	/// ditto
	this(ubyte v) { this(cast(long)v); }
	/// ditto
	this(short v) { this(cast(long)v); }
	/// ditto
	this(ushort v) { this(cast(long)v); }
	/// ditto
	this(int v) { this(cast(long)v); }
	/// ditto
	this(uint v) { this(cast(long)v); }
	/// ditto
	this(long v) @trusted { m_type = Type.int_; m_int = v; }
	/// ditto
	this(BigInt v) @trusted { m_type = Type.bigInt; initBigInt(); m_bigInt = v; }
	/// ditto
	this(double v) @trusted { m_type = Type.float_; m_float = v; }
	/// ditto
	this(string v) @trusted { m_type = Type.string; m_string = v; }
	/// ditto
	this(Json[] v) @trusted { m_type = Type.array; m_array = v; }
	/// ditto
	this(Json[string] v) @trusted { m_type = Type.object; m_object = v; }

	// used internally for UUID serialization support
	private this(UUID v) { this(v.toString()); }

	/**
		Converts a std.json.JSONValue object to a vibe Json object.
	 */
	this(in JSONValue value)
	@safe {
		final switch (value.type) {
			case JSON_TYPE.NULL: this = null; break;
			case JSON_TYPE.OBJECT:
				this = emptyObject;
				() @trusted {
					foreach (string k, ref const JSONValue v; value.object)
						this[k] = Json(v);
				} ();
				break;
			case JSON_TYPE.ARRAY:
				this = (() @trusted => Json(value.array.map!(a => Json(a)).array))();
				break;
			case JSON_TYPE.STRING: this = value.str; break;
			case JSON_TYPE.INTEGER: this = value.integer; break;
			case JSON_TYPE.UINTEGER: this = BigInt(value.uinteger); break;
			case JSON_TYPE.FLOAT: this = value.floating; break;
			case JSON_TYPE.TRUE: this = true; break;
			case JSON_TYPE.FALSE: this = false; break;
		}
	}


	/**
		Allows assignment of D values to a JSON value.
	*/
	ref Json opAssign(Json v)
	{
		if (v.type != Type.bigInt)
			runDestructors();
		auto old_type = m_type;
		m_type = v.m_type;
		final switch(m_type){
			case Type.undefined: m_string = null; break;
			case Type.null_: m_string = null; break;
			case Type.bool_: m_bool = v.m_bool; break;
			case Type.int_: m_int = v.m_int; break;
			case Type.bigInt:
				if (old_type != Type.bigInt)
					initBigInt();
				m_bigInt = v.m_bigInt;
				break;
			case Type.float_: m_float = v.m_float; break;
			case Type.string: m_string = v.m_string; break;
			case Type.array: opAssign(v.m_array); break;
			case Type.object: opAssign(v.m_object); break;
		}
		return this;
	}
	/// ditto
	void opAssign(typeof(null)) { runDestructors(); m_type = Type.null_; m_string = null; }
	/// ditto
	bool opAssign(bool v) { runDestructors(); m_type = Type.bool_; m_bool = v; return v; }
	/// ditto
	int opAssign(int v) { runDestructors(); m_type = Type.int_; m_int = v; return v; }
	/// ditto
	long opAssign(long v) { runDestructors(); m_type = Type.int_; m_int = v; return v; }
	/// ditto
	BigInt opAssign(BigInt v)
	{
		if (m_type != Type.bigInt)
			initBigInt();
		m_type = Type.bigInt;
		m_bigInt = v;
		return v;
	}
	/// ditto
	double opAssign(double v) { runDestructors(); m_type = Type.float_; m_float = v; return v; }
	/// ditto
	string opAssign(string v) { runDestructors(); m_type = Type.string; m_string = v; return v; }
	/// ditto
	Json[] opAssign(Json[] v) {
		runDestructors();
		m_type = Type.array;
		m_array = v;
		version (VibeJsonFieldNames) {
			foreach (idx, ref av; m_array)
				av.m_name = format("%s[%s]", m_name, idx);
		}
		return v;
	}
	/// ditto
	Json[string] opAssign(Json[string] v)
	{
		runDestructors();
		m_type = Type.object;
		m_object = v;
		version (VibeJsonFieldNames) { foreach (key, ref av; m_object) av.m_name = format("%s.%s", m_name, key); }
		return v;
	}

	// used internally for UUID serialization support
	private UUID opAssign(UUID v) { opAssign(v.toString()); return v; }

	/**
		Allows removal of values from Type.Object Json objects.
	*/
	void remove(string item) { checkType!(Json[string])(); m_object.remove(item); }

	/**
		The current type id of this JSON object.
	*/
	@property Type type() const @safe { return m_type; }

	/**
		Clones a JSON value recursively.
	*/
	Json clone()
	const {
		final switch (m_type) {
			case Type.undefined: return Json.undefined;
			case Type.null_: return Json(null);
			case Type.bool_: return Json(m_bool);
			case Type.int_: return Json(m_int);
			case Type.bigInt: return Json(m_bigInt);
			case Type.float_: return Json(m_float);
			case Type.string: return Json(m_string);
			case Type.array:
				Json[] ret;
				foreach (v; this.byValue) ret ~= v.clone();

				return Json(ret);
			case Type.object:
				auto ret = Json.emptyObject;
				foreach (name, v; this.byKeyValue) ret[name] = v.clone();
				return ret;
		}
	}

	/**
		Allows direct indexing of array typed JSON values.
	*/
	ref inout(Json) opIndex(size_t idx) inout { checkType!(Json[])(); return m_array[idx]; }

	///
	unittest {
		Json value = Json.emptyArray;
		value ~= 1;
		value ~= true;
		value ~= "foo";
		assert(value[0] == 1);
		assert(value[1] == true);
		assert(value[2] == "foo");
	}


	/**
		Allows direct indexing of object typed JSON values using a string as
		the key.

		Returns an object of `Type.undefined` if the key was not found.
	*/
	const(Json) opIndex(string key)
	const {
		checkType!(Json[string])();
		if( auto pv = key in m_object ) return *pv;
		Json ret = Json.undefined;
		ret.m_string = key;
		version (VibeJsonFieldNames) ret.m_name = format("%s.%s", m_name, key);
		return ret;
	}
	/// ditto
	ref Json opIndex(string key)
	{
		checkType!(Json[string])();
		if( auto pv = key in m_object )
			return *pv;
		if (m_object is null) {
			m_object = ["": Json.init];
			m_object.remove("");
		}
		m_object[key] = Json.init;
		auto nv = key in m_object;
		assert(m_object !is null);
		assert(nv !is null, "Failed to insert key '"~key~"' into AA!?");
		nv.m_type = Type.undefined;
		assert(nv.type == Type.undefined);
		nv.m_string = key;
		version (VibeJsonFieldNames) nv.m_name = format("%s.%s", m_name, key);
		return *nv;
	}

	///
	unittest {
		Json value = Json.emptyObject;
		value["a"] = 1;
		value["b"] = true;
		value["c"] = "foo";
		assert(value["a"] == 1);
		assert(value["b"] == true);
		assert(value["c"] == "foo");
		assert(value["not-existing"].type() == Type.undefined);
	}

	/**
		Returns a slice of a JSON array.
	*/
	inout(Json[]) opSlice() inout { checkType!(Json[])(); return m_array; }
	///
	inout(Json[]) opSlice(size_t from, size_t to) inout { checkType!(Json[])(); return m_array[from .. to]; }

	/**
		Returns the number of entries of string, array or object typed JSON values.
	*/
	@property size_t length()
	const @trusted {
		checkType!(string, Json[], Json[string])("property length");
		switch(m_type){
			case Type.string: return m_string.length;
			case Type.array: return m_array.length;
			case Type.object: return m_object.length;
			default: assert(false);
		}
	}

	/**
		Allows foreach iterating over JSON objects and arrays.
	*/
	int opApply(scope int delegate(ref Json obj) del)
	@system {
		checkType!(Json[], Json[string])("opApply");
		if( m_type == Type.array ){
			foreach( ref v; m_array )
				if( auto ret = del(v) )
					return ret;
			return 0;
		} else {
			foreach( ref v; m_object )
				if( v.type != Type.undefined )
					if( auto ret = del(v) )
						return ret;
			return 0;
		}
	}
	/// ditto
	int opApply(scope int delegate(ref const Json obj) del)
	const @system {
		checkType!(Json[], Json[string])("opApply");
		if( m_type == Type.array ){
			foreach( ref v; m_array )
				if( auto ret = del(v) )
					return ret;
			return 0;
		} else {
			foreach( ref v; m_object )
				if( v.type != Type.undefined )
					if( auto ret = del(v) )
						return ret;
			return 0;
		}
	}
	/// ditto
	int opApply(scope int delegate(ref size_t idx, ref Json obj) del)
	@system {
		checkType!(Json[])("opApply");
		foreach( idx, ref v; m_array )
			if( auto ret = del(idx, v) )
				return ret;
		return 0;
	}
	/// ditto
	int opApply(scope int delegate(ref size_t idx, ref const Json obj) del)
	const @system {
		checkType!(Json[])("opApply");
		foreach( idx, ref v; m_array )
			if( auto ret = del(idx, v) )
				return ret;
		return 0;
	}
	/// ditto
	int opApply(scope int delegate(ref string idx, ref Json obj) del)
	@system {
		checkType!(Json[string])("opApply");
		foreach( idx, ref v; m_object )
			if( v.type != Type.undefined )
				if( auto ret = del(idx, v) )
					return ret;
		return 0;
	}
	/// ditto
	int opApply(scope int delegate(ref string idx, ref const Json obj) del)
	const @system {
		checkType!(Json[string])("opApply");
		foreach( idx, ref v; m_object )
			if( v.type != Type.undefined )
				if( auto ret = del(idx, v) )
					return ret;
		return 0;
	}

	private alias KeyValue = Tuple!(string, "key", Json, "value");

	/// Iterates over all key/value pairs of an object.
	@property auto byKeyValue() @trusted { checkType!(Json[string])("byKeyValue"); return m_object.byKeyValue.map!(kv => KeyValue(kv.key, kv.value)).trustedRange; }
	/// ditto
	@property auto byKeyValue() const @trusted { checkType!(Json[string])("byKeyValue"); return m_object.byKeyValue.map!(kv => const(KeyValue)(kv.key, kv.value)).trustedRange; }
	/// Iterates over all index/value pairs of an array.
	@property auto byIndexValue() { checkType!(Json[])("byIndexValue"); return zip(iota(0, m_array.length), m_array); }
	/// ditto
	@property auto byIndexValue() const { checkType!(Json[])("byIndexValue"); return zip(iota(0, m_array.length), m_array); }
	/// Iterates over all values of an object or array.
	@property auto byValue() @trusted {
		checkType!(Json[], Json[string])("byValue");
		static struct Rng {
			private {
				bool isArray;
				Json[] array;
				typeof(Json.init.m_object.byValue) object;
			}

			bool empty() @trusted { if (isArray) return array.length == 0; else return object.empty; }
			auto front() @trusted { if (isArray) return array[0]; else return object.front; }
			void popFront() @trusted { if (isArray) array = array[1 .. $]; else object.popFront(); }
		}

		if (m_type == Type.array) return Rng(true, m_array);
		else return Rng(false, null, m_object.byValue);
	}
	/// ditto
	@property auto byValue() const @trusted {
		checkType!(Json[], Json[string])("byValue");
		static struct Rng {
		@safe:
			private {
				bool isArray;
				const(Json)[] array;
				typeof(const(Json).init.m_object.byValue) object;
			}

			bool empty() @trusted { if (isArray) return array.length == 0; else return object.empty; }
			auto front() @trusted { if (isArray) return array[0]; else return object.front; }
			void popFront() @trusted { if (isArray) array = array[1 .. $]; else object.popFront(); }
		}

		if (m_type == Type.array) return Rng(true, m_array);
		else return Rng(false, null, m_object.byValue);
	}


	/**
		Converts this Json object to a std.json.JSONValue object
	 */
	T opCast(T)() const @safe
		if (is(T == JSONValue))
	{
		final switch (type) {
			case Json.Type.undefined:
			case Json.Type.null_:
				return JSONValue(null);
			case Json.Type.bool_:
				return JSONValue(get!bool);
			case Json.Type.int_:
				return JSONValue(get!long);
			case Json.Type.bigInt:
				auto bi = get!BigInt;
				if (bi > long.max)
					return JSONValue((() @trusted => cast(ulong)get!BigInt)());
				else
					return JSONValue((() @trusted => cast(long)get!BigInt)());
			case Json.Type.float_:
				return JSONValue(get!double);
			case Json.Type.string:
				return JSONValue(get!string);
			case Json.Type.array:
				JSONValue[] ret;
				foreach (ref const Json e; byValue)
					ret ~= cast(JSONValue)e;
				return JSONValue(ret);
			case Json.Type.object:
				JSONValue[string] ret;
				foreach (string k, ref const Json e; byKeyValue) {
					if( e.type == Json.Type.undefined ) continue;
					ret[k] = cast(JSONValue)e;
				}
				return JSONValue(ret);
		}
	}


	/**
		Converts the JSON value to the corresponding D type - types must match exactly.

		Available_Types:
			$(UL
				$(LI `bool` (`Type.bool_`))
				$(LI `double` (`Type.float_`))
				$(LI `float` (Converted from `double`))
				$(LI `long` (`Type.int_`))
				$(LI `ulong`, `int`, `uint`, `short`, `ushort`, `byte`, `ubyte` (Converted from `long`))
				$(LI `string` (`Type.string`))
				$(LI `Json[]` (`Type.array`))
				$(LI `Json[string]` (`Type.object`))
			)

		See_Also: `opt`, `to`, `deserializeJson`
	*/
	inout(T) opCast(T)() inout if (!is(T == JSONValue)) { return get!T; }
	/// ditto
	@property inout(T) get(T)()
	inout @trusted {
		static if (!is(T : bool) && is(T : long))
			checkType!(long, BigInt)();
		else
			checkType!T();

		static if (is(T == bool)) return m_bool;
		else static if (is(T == double)) return m_float;
		else static if (is(T == float)) return cast(T)m_float;
		else static if (is(T == string)) return m_string;
		else static if (is(T == UUID)) return UUID(m_string);
		else static if (is(T == Json[])) return m_array;
		else static if (is(T == Json[string])) return m_object;
		else static if (is(T == BigInt)) return m_type == Type.bigInt ? m_bigInt : BigInt(m_int);
		else static if (is(T : long)) {
			if (m_type == Type.bigInt) {
				enforceJson(m_bigInt <= T.max && m_bigInt >= T.min, "Integer conversion out of bounds error");
				return cast(T)m_bigInt.toLong();
			} else {
				enforceJson(m_int <= T.max && m_int >= T.min, "Integer conversion out of bounds error");
				return cast(T)m_int;
			}
		}
		else static assert(0, "JSON can only be cast to (bool, long, std.bigint.BigInt, double, string, Json[] or Json[string]. Not "~T.stringof~".");
	}

	/**
		Returns the native type for this JSON if it matches the current runtime type.

		If the runtime type does not match the given native type, the 'def' parameter is returned
		instead.

		See_Also: `get`
	*/
	@property const(T) opt(T)(const(T) def = T.init)
	const {
		if( typeId!T != m_type ) return def;
		return get!T;
	}
	/// ditto
	@property T opt(T)(T def = T.init)
	{
		if( typeId!T != m_type ) return def;
		return get!T;
	}

	/**
		Converts the JSON value to the corresponding D type - types are converted as necessary.

		Automatically performs conversions between strings and numbers. See
		`get` for the list of available types. For converting/deserializing
		JSON to complex data types see `deserializeJson`.

		See_Also: `get`, `deserializeJson`
	*/
	@property inout(T) to(T)()
	inout {
		static if( is(T == bool) ){
			final switch( m_type ){
				case Type.undefined: return false;
				case Type.null_: return false;
				case Type.bool_: return m_bool;
				case Type.int_: return m_int != 0;
				case Type.bigInt: return m_bigInt != 0;
				case Type.float_: return m_float != 0;
				case Type.string: return m_string.length > 0;
				case Type.array: return m_array.length > 0;
				case Type.object: return m_object.length > 0;
			}
		} else static if( is(T == double) ){
			final switch( m_type ){
				case Type.undefined: return T.init;
				case Type.null_: return 0;
				case Type.bool_: return m_bool ? 1 : 0;
				case Type.int_: return m_int;
				case Type.bigInt: return bigIntToLong();
				case Type.float_: return m_float;
				case Type.string: return .to!double(cast(string)m_string);
				case Type.array: return double.init;
				case Type.object: return double.init;
			}
		} else static if( is(T == float) ){
			final switch( m_type ){
				case Type.undefined: return T.init;
				case Type.null_: return 0;
				case Type.bool_: return m_bool ? 1 : 0;
				case Type.int_: return m_int;
				case Type.bigInt: return bigIntToLong();
				case Type.float_: return m_float;
				case Type.string: return .to!float(cast(string)m_string);
				case Type.array: return float.init;
				case Type.object: return float.init;
			}
		} else static if( is(T == long) ){
			final switch( m_type ){
				case Type.undefined: return 0;
				case Type.null_: return 0;
				case Type.bool_: return m_bool ? 1 : 0;
				case Type.int_: return m_int;
				case Type.bigInt: return cast(long)bigIntToLong();
				case Type.float_: return cast(long)m_float;
				case Type.string: return .to!long(m_string);
				case Type.array: return 0;
				case Type.object: return 0;
			}
		} else static if( is(T : long) ){
			final switch( m_type ){
				case Type.undefined: return 0;
				case Type.null_: return 0;
				case Type.bool_: return m_bool ? 1 : 0;
				case Type.int_: return cast(T)m_int;
				case Type.bigInt: return cast(T)bigIntToLong();
				case Type.float_: return cast(T)m_float;
				case Type.string: return cast(T).to!long(cast(string)m_string);
				case Type.array: return 0;
				case Type.object: return 0;
			}
		} else static if( is(T == string) ){
			switch( m_type ){
				default: return toString();
				case Type.string: return m_string;
			}
		} else static if( is(T == Json[]) ){
			switch( m_type ){
				default: return Json([this]);
				case Type.array: return m_array;
			}
		} else static if( is(T == Json[string]) ){
			switch( m_type ){
				default: return Json(["value": this]);
				case Type.object: return m_object;
			}
		} else static if( is(T == BigInt) ){
			final switch( m_type ){
				case Type.undefined: return BigInt(0);
				case Type.null_: return BigInt(0);
				case Type.bool_: return BigInt(m_bool ? 1 : 0);
				case Type.int_: return BigInt(m_int);
				case Type.bigInt: return m_bigInt;
				case Type.float_: return BigInt(cast(long)m_float);
				case Type.string: return BigInt(.to!long(m_string));
				case Type.array: return BigInt(0);
				case Type.object: return BigInt(0);
			}
		} else static if (is(T == JSONValue)) {
			return cast(JSONValue)this;
		} else static assert(0, "JSON can only be cast to (bool, long, std.bigint.BigInt, double, string, Json[] or Json[string]. Not "~T.stringof~".");
	}

	/**
		Performs unary operations on the JSON value.

		The following operations are supported for each type:

		$(DL
			$(DT Null)   $(DD none)
			$(DT Bool)   $(DD ~)
			$(DT Int)    $(DD +, -, ++, --)
			$(DT Float)  $(DD +, -, ++, --)
			$(DT String) $(DD none)
			$(DT Array)  $(DD none)
			$(DT Object) $(DD none)
		)
	*/
	Json opUnary(string op)()
	const {
		static if( op == "~" ){
			checkType!bool();
			return Json(~m_bool);
		} else static if( op == "+" || op == "-" || op == "++" || op == "--" ){
			checkType!(BigInt, long, double)("unary "~op);
			if( m_type == Type.int_ ) mixin("return Json("~op~"m_int);");
			else if( m_type == Type.bigInt ) mixin("return Json("~op~"m_bigInt);");
			else if( m_type == Type.float_ ) mixin("return Json("~op~"m_float);");
			else assert(false);
		} else static assert(0, "Unsupported operator '"~op~"' for type JSON.");
	}
	/**
		Performs binary operations between JSON values.

		The two JSON values must be of the same run time type or a JSONException
		will be thrown. Only the operations listed are allowed for each of the
		types.

		$(DL
			$(DT Null)   $(DD none)
			$(DT Bool)   $(DD &&, ||)
			$(DT Int)    $(DD +, -, *, /, %)
			$(DT Float)  $(DD +, -, *, /, %)
			$(DT String) $(DD ~)
			$(DT Array)  $(DD ~)
			$(DT Object) $(DD in)
		)
	*/
	Json opBinary(string op)(ref const(Json) other)
	const {
		enforceJson(m_type == other.m_type, "Binary operation '"~op~"' between "~.to!string(m_type)~" and "~.to!string(other.m_type)~" JSON objects.");
		static if( op == "&&" ){
			checkType!(bool)(op);
			return Json(m_bool && other.m_bool);
		} else static if( op == "||" ){
			checkType!(bool)(op);
			return Json(m_bool || other.m_bool);
		} else static if( op == "+" ){
			checkType!(BigInt, long, double)(op);
			if( m_type == Type.int_ ) return Json(m_int + other.m_int);
			else if( m_type == Type.bigInt ) return Json(() @trusted { return m_bigInt + other.m_bigInt; } ());
			else if( m_type == Type.float_ ) return Json(m_float + other.m_float);
			else assert(false);
		} else static if( op == "-" ){
			checkType!(BigInt, long, double)(op);
			if( m_type == Type.int_ ) return Json(m_int - other.m_int);
			else if( m_type == Type.bigInt ) return Json(() @trusted { return m_bigInt - other.m_bigInt; } ());
			else if( m_type == Type.float_ ) return Json(m_float - other.m_float);
			else assert(false);
		} else static if( op == "*" ){
			checkType!(BigInt, long, double)(op);
			if( m_type == Type.int_ ) return Json(m_int * other.m_int);
			else if( m_type == Type.bigInt ) return Json(() @trusted { return m_bigInt * other.m_bigInt; } ());
			else if( m_type == Type.float_ ) return Json(m_float * other.m_float);
			else assert(false);
		} else static if( op == "/" ){
			checkType!(BigInt, long, double)(op);
			if( m_type == Type.int_ ) return Json(m_int / other.m_int);
			else if( m_type == Type.bigInt ) return Json(() @trusted { return m_bigInt / other.m_bigInt; } ());
			else if( m_type == Type.float_ ) return Json(m_float / other.m_float);
			else assert(false);
		} else static if( op == "%" ){
			checkType!(BigInt, long, double)(op);
			if( m_type == Type.int_ ) return Json(m_int % other.m_int);
			else if( m_type == Type.bigInt ) return Json(() @trusted { return m_bigInt % other.m_bigInt; } ());
			else if( m_type == Type.float_ ) return Json(m_float % other.m_float);
			else assert(false);
		} else static if( op == "~" ){
			checkType!(string, Json[])(op);
			if( m_type == Type.string ) return Json(m_string ~ other.m_string);
			else if (m_type == Type.array) return Json(m_array ~ other.m_array);
			else assert(false);
		} else static assert(0, "Unsupported operator '"~op~"' for type JSON.");
	}
	/// ditto
	Json opBinary(string op)(Json other)
		if( op == "~" )
	{
		static if( op == "~" ){
			checkType!(string, Json[])(op);
			if( m_type == Type.string ) return Json(m_string ~ other.m_string);
			else if( m_type == Type.array ) return Json(m_array ~ other.m_array);
			else assert(false);
		} else static assert(0, "Unsupported operator '"~op~"' for type JSON.");
	}
	/// ditto
	void opOpAssign(string op)(Json other)
		if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op =="~")
	{
		enforceJson(m_type == other.m_type || op == "~" && m_type == Type.array,
				"Binary operation '"~op~"=' between "~.to!string(m_type)~" and "~.to!string(other.m_type)~" JSON objects.");
		static if( op == "+" ){
			if( m_type == Type.int_ ) m_int += other.m_int;
			else if( m_type == Type.bigInt ) m_bigInt += other.m_bigInt;
			else if( m_type == Type.float_ ) m_float += other.m_float;
			else enforceJson(false, "'+=' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "-" ){
			if( m_type == Type.int_ ) m_int -= other.m_int;
			else if( m_type == Type.bigInt ) m_bigInt -= other.m_bigInt;
			else if( m_type == Type.float_ ) m_float -= other.m_float;
			else enforceJson(false, "'-=' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "*" ){
			if( m_type == Type.int_ ) m_int *= other.m_int;
			else if( m_type == Type.bigInt ) m_bigInt *= other.m_bigInt;
			else if( m_type == Type.float_ ) m_float *= other.m_float;
			else enforceJson(false, "'*=' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "/" ){
			if( m_type == Type.int_ ) m_int /= other.m_int;
			else if( m_type == Type.bigInt ) m_bigInt /= other.m_bigInt;
			else if( m_type == Type.float_ ) m_float /= other.m_float;
			else enforceJson(false, "'/=' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "%" ){
			if( m_type == Type.int_ ) m_int %= other.m_int;
			else if( m_type == Type.bigInt ) m_bigInt %= other.m_bigInt;
			else if( m_type == Type.float_ ) m_float %= other.m_float;
			else enforceJson(false, "'%=' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "~" ){
			if (m_type == Type.string) m_string ~= other.m_string;
			else if (m_type == Type.array) {
				if (other.m_type == Type.array) m_array ~= other.m_array;
				else appendArrayElement(other);
			} else enforceJson(false, "'~=' only allowed for string and array types, not "~.to!string(m_type)~".");
		} else static assert(0, "Unsupported operator '"~op~"=' for type JSON.");
	}
	/// ditto
	void opOpAssign(string op, T)(T other)
		if (!is(T == Json) && is(typeof(Json(other))))
	{
		opOpAssign!op(Json(other));
	}
	/// ditto
	Json opBinary(string op)(bool other) const { checkType!bool(); mixin("return Json(m_bool "~op~" other);"); }
	/// ditto
	Json opBinary(string op)(long other) const
	{
		checkType!(long, BigInt)();
		if (m_type == Type.bigInt)
			mixin("return Json(m_bigInt "~op~" other);");
		else
			mixin("return Json(m_int "~op~" other);");
	}
	/// ditto
	Json opBinary(string op)(BigInt other) const
	{
		checkType!(long, BigInt)();
		if (m_type == Type.bigInt)
			mixin("return Json(m_bigInt "~op~" other);");
		else
			mixin("return Json(m_int "~op~" other);");
	}
	/// ditto
	Json opBinary(string op)(double other) const { checkType!double(); mixin("return Json(m_float "~op~" other);"); }
	/// ditto
	Json opBinary(string op)(string other) const { checkType!string(); mixin("return Json(m_string "~op~" other);"); }
	/// ditto
	Json opBinary(string op)(Json[] other) { checkType!(Json[])(); mixin("return Json(m_array "~op~" other);"); }
	/// ditto
	Json opBinaryRight(string op)(bool other) const { checkType!bool(); mixin("return Json(other "~op~" m_bool);"); }
	/// ditto
	Json opBinaryRight(string op)(long other) const
	{
		checkType!(long, BigInt)();
		if (m_type == Type.bigInt)
			mixin("return Json(other "~op~" m_bigInt);");
		else
			mixin("return Json(other "~op~" m_int);");
	}
	/// ditto
	Json opBinaryRight(string op)(BigInt other) const
	{
		checkType!(long, BigInt)();
		if (m_type == Type.bigInt)
			mixin("return Json(other "~op~" m_bigInt);");
		else
			mixin("return Json(other "~op~" m_int);");
	}
	/// ditto
	Json opBinaryRight(string op)(double other) const { checkType!double(); mixin("return Json(other "~op~" m_float);"); }
	/// ditto
	Json opBinaryRight(string op)(string other) const if(op == "~") { checkType!string(); return Json(other ~ m_string); }
	/// ditto
	Json opBinaryRight(string op)(Json[] other) { checkType!(Json[])(); mixin("return Json(other "~op~" m_array);"); }


	/** Checks wheter a particular key is set and returns a pointer to it.

		For field that don't exist or have a type of `Type.undefined`,
		the `in` operator will return `null`.
	*/
	inout(Json)* opBinaryRight(string op)(string other) inout
		if(op == "in")
	{
		checkType!(Json[string])();
		auto pv = other in m_object;
		if (!pv) return null;
		if (pv.type == Type.undefined) return null;
		return pv;
	}

	///
	unittest {
		auto j = Json.emptyObject;
		j["a"] = "foo";
		j["b"] = Json.undefined;

		assert("a" in j);
		assert(("a" in j).get!string == "foo");
		assert("b" !in j);
		assert("c" !in j);
	}


	/**
	 * The append operator will append arrays. This method always appends it's argument as an array element, so nested arrays can be created.
	 */
	void appendArrayElement(Json element)
	{
		enforceJson(m_type == Type.array, "'appendArrayElement' only allowed for array types, not "~.to!string(m_type)~".");
		m_array ~= element;
	}

	/**
		Compares two JSON values for equality.

		If the two values have different types, they are considered unequal.
		This differs with ECMA script, which performs a type conversion before
		comparing the values.
	*/

	bool opEquals(ref const Json other)
	const {
		if( m_type != other.m_type ) return false;
		final switch(m_type){
			case Type.undefined: return false;
			case Type.null_: return true;
			case Type.bool_: return m_bool == other.m_bool;
			case Type.int_: return m_int == other.m_int;
			case Type.bigInt: return m_bigInt == other.m_bigInt;
			case Type.float_: return m_float == other.m_float;
			case Type.string: return m_string == other.m_string;
			case Type.array: return m_array == other.m_array;
			case Type.object: return m_object == other.m_object;
		}
	}
	/// ditto
	bool opEquals(const Json other) const { return opEquals(other); }
	/// ditto
	bool opEquals(typeof(null)) const { return m_type == Type.null_; }
	/// ditto
	bool opEquals(bool v) const { return m_type == Type.bool_ && m_bool == v; }
	/// ditto
	bool opEquals(int v) const { return (m_type == Type.int_ && m_int == v) || (m_type == Type.bigInt && m_bigInt == v); }
	/// ditto
	bool opEquals(long v) const { return (m_type == Type.int_ && m_int == v) || (m_type == Type.bigInt && m_bigInt == v); }
	/// ditto
	bool opEquals(BigInt v) const { return (m_type == Type.int_ && m_int == v) || (m_type == Type.bigInt && m_bigInt == v); }
	/// ditto
	bool opEquals(double v) const { return m_type == Type.float_ && m_float == v; }
	/// ditto
	bool opEquals(string v) const { return m_type == Type.string && m_string == v; }

	/**
		Compares two JSON values.

		If the types of the two values differ, the value with the smaller type
		id is considered the smaller value. This differs from ECMA script, which
		performs a type conversion before comparing the values.

		JSON values of type Object cannot be compared and will throw an
		exception.
	*/
	int opCmp(ref const Json other)
	const {
		if( m_type != other.m_type ) return m_type < other.m_type ? -1 : 1;
		final switch(m_type){
			case Type.undefined: return 0;
			case Type.null_: return 0;
			case Type.bool_: return m_bool < other.m_bool ? -1 : m_bool == other.m_bool ? 0 : 1;
			case Type.int_: return m_int < other.m_int ? -1 : m_int == other.m_int ? 0 : 1;
			case Type.bigInt: return () @trusted { return m_bigInt < other.m_bigInt; } () ? -1 : m_bigInt == other.m_bigInt ? 0 : 1;
			case Type.float_: return m_float < other.m_float ? -1 : m_float == other.m_float ? 0 : 1;
			case Type.string: return m_string < other.m_string ? -1 : m_string == other.m_string ? 0 : 1;
			case Type.array: return m_array < other.m_array ? -1 : m_array == other.m_array ? 0 : 1;
			case Type.object:
				enforceJson(false, "JSON objects cannot be compared.");
				assert(false);
		}
	}

	alias opDollar = length;

	/**
		Returns the type id corresponding to the given D type.
	*/
	static @property Type typeId(T)() {
		static if( is(T == typeof(null)) ) return Type.null_;
		else static if( is(T == bool) ) return Type.bool_;
		else static if( is(T == double) ) return Type.float_;
		else static if( is(T == float) ) return Type.float_;
		else static if( is(T : long) ) return Type.int_;
		else static if( is(T == string) ) return Type.string;
		else static if( is(T == UUID) ) return Type.string;
		else static if( is(T == Json[]) ) return Type.array;
		else static if( is(T == Json[string]) ) return Type.object;
		else static if( is(T == BigInt) ) return Type.bigInt;
		else static assert(false, "Unsupported JSON type '"~T.stringof~"'. Only bool, long, std.bigint.BigInt, double, string, Json[] and Json[string] are allowed.");
	}

	/**
		Returns the JSON object as a string.

		For large JSON values use writeJsonString instead as this function will store the whole string
		in memory, whereas writeJsonString writes it out bit for bit.

		See_Also: writeJsonString, toPrettyString
	*/
	string toString()
	const @trusted {
		// DMD BUG: this should actually be all @safe, but for some reason
		// @safe inference for writeJsonString doesn't work.
		auto ret = appender!string();
		writeJsonString(ret, this);
		return ret.data;
	}
	/// ditto
	void toString(scope void delegate(const(char)[]) @safe sink, FormatSpec!char fmt)
	@trusted {
		// DMD BUG: this should actually be all @safe, but for some reason
		// @safe inference for writeJsonString doesn't work.
		static struct DummyRangeS {
			void delegate(const(char)[]) @safe sink;
			void put(const(char)[] str) @safe { sink(str); }
			void put(char ch) @trusted { sink((&ch)[0 .. 1]); }
		}
		auto r = DummyRangeS(sink);
		writeJsonString(r, this);
	}
	/// ditto
	void toString(scope void delegate(const(char)[]) @system sink, FormatSpec!char fmt)
	@system {
		// DMD BUG: this should actually be all @safe, but for some reason
		// @safe inference for writeJsonString doesn't work.
		static struct DummyRange {
			void delegate(const(char)[]) sink;
			@trusted:
			void put(const(char)[] str) { sink(str); }
			void put(char ch) { sink((&ch)[0 .. 1]); }
		}
		auto r = DummyRange(sink);
		writeJsonString(r, this);
	}

	/**
		Returns the JSON object as a "pretty" string.

		---
		auto json = Json(["foo": Json("bar")]);
		writeln(json.toPrettyString());

		// output:
		// {
		//     "foo": "bar"
		// }
		---

		Params:
			level = Specifies the base amount of indentation for the output. Indentation  is always
				done using tab characters.

		See_Also: writePrettyJsonString, toString
	*/
	string toPrettyString(int level = 0)
	const @trusted {
		auto ret = appender!string();
		writePrettyJsonString(ret, this, level);
		return ret.data;
	}

	private void checkType(TYPES...)(string op = null)
	const {
		bool matched = false;
		foreach (T; TYPES) if (m_type == typeId!T) matched = true;
		if (matched) return;

		string name;
		version (VibeJsonFieldNames) {
			if (m_name.length) name = m_name ~ " of type " ~ m_type.to!string;
			else name = "JSON of type " ~ m_type.to!string;
		} else name = "JSON of type " ~ m_type.to!string;

		string expected;
		static if (TYPES.length == 1) expected = typeId!(TYPES[0]).to!string;
		else {
			foreach (T; TYPES) {
				if (expected.length > 0) expected ~= ", ";
				expected ~= typeId!T.to!string;
			}
		}

		if (!op.length) throw new JSONException(format("Got %s, expected %s.", name, expected));
		else throw new JSONException(format("Got %s, expected %s for %s.", name, expected, op));
	}

	private void initBigInt()
	@trusted {
		BigInt[1] init_;
		// BigInt is a struct, and it has a special BigInt.init value, which differs from null.
		// m_data has no special initializer and when it tries to first access to BigInt
		// via m_bigInt(), we should explicitly initialize m_data with BigInt.init
		m_data[0 .. BigInt.sizeof] = cast(void[])init_;
	}

	private void runDestructors()
	{
		if (m_type != Type.bigInt) return;

		BigInt init_;
		// After swaping, init_ contains the real number from Json, and it
		// will be destroyed when this function is finished.
		// m_bigInt now contains static BigInt.init value and destruction may
		// be ommited for it.
		swap(init_, m_bigInt);
	}

	private long bigIntToLong() inout
	{
		assert(m_type == Type.bigInt, format("Converting non-bigInt type with bitIntToLong!?: %s", cast(Type)m_type));
		enforceJson(m_bigInt >= long.min && m_bigInt <= long.max, "Number out of range while converting BigInt("~format("%d", m_bigInt)~") to long.");
		return m_bigInt.toLong();
	}

	/*invariant()
	{
		assert(m_type >= Type.Undefined && m_type <= Type.Object);
	}*/
}

@safe unittest { // issue #1234 - @safe toString
	auto j = Json(true);
	j.toString((str) @safe {}, FormatSpec!char("s"));
	assert(j.toString() == "true");
}


/******************************************************************************/
/* public functions                                                           */
/******************************************************************************/

/**
	Parses the given range as a JSON string and returns the corresponding Json object.

	The range is shrunk during parsing, leaving any remaining text that is not part of
	the JSON contents.

	Throws a JSONException if any parsing error occured.
*/
Json parseJson(R)(ref R range, int* line = null, string filename = null)
	if( is(R == string) )
{
	Json ret;
	enforceJson(!range.empty, "JSON string is empty.", filename, 0);

	skipWhitespace(range, line);

	enforceJson(!range.empty, "JSON string contains only whitespaces.", filename, 0);

	version(JsonLineNumbers) {
		int curline = line ? *line : 0;
	}

	bool minus = false;
	switch( range.front ){
		case 'f':
			enforceJson(range[1 .. $].startsWith("alse"), "Expected 'false', got '"~range[0 .. min(5, $)]~"'.", filename, line);
			range.popFrontN(5);
			ret = false;
			break;
		case 'n':
			enforceJson(range[1 .. $].startsWith("ull"), "Expected 'null', got '"~range[0 .. min(4, $)]~"'.", filename, line);
			range.popFrontN(4);
			ret = null;
			break;
		case 't':
			enforceJson(range[1 .. $].startsWith("rue"), "Expected 'true', got '"~range[0 .. min(4, $)]~"'.", filename, line);
			range.popFrontN(4);
			ret = true;
			break;

		case '-':
		case '0': .. case '9':
			bool is_long_overflow;
			bool is_float;
			auto num = skipNumber(range, is_float, is_long_overflow);
			if( is_float ) {
				ret = to!double(num);
			} else if (is_long_overflow) {
				ret = () @trusted { return BigInt(num.to!string); } ();
			} else {
				ret = to!long(num);
			}
			break;
		case '\"':
			ret = skipJsonString(range);
			break;
		case '[':
			auto arr = appender!(Json[]);
			range.popFront();
			while (true) {
				skipWhitespace(range, line);
				enforceJson(!range.empty, "Missing ']' before EOF.", filename, line);
				if(range.front == ']') break;
				arr ~= parseJson(range, line, filename);
				skipWhitespace(range, line);
				enforceJson(!range.empty, "Missing ']' before EOF.", filename, line);
				enforceJson(range.front == ',' || range.front == ']',
					format("Expected ']' or ',' - got '%s'.", range.front), filename, line);
				if( range.front == ']' ) break;
				else range.popFront();
			}
			range.popFront();
			ret = arr.data;
			break;
		case '{':
			Json[string] obj;
			range.popFront();
			while (true) {
				skipWhitespace(range, line);
				enforceJson(!range.empty, "Missing '}' before EOF.", filename, line);
				if(range.front == '}') break;
				string key = skipJsonString(range);
				skipWhitespace(range, line);
				enforceJson(range.startsWith(":"), "Expected ':' for key '" ~ key ~ "'", filename, line);
				range.popFront();
				skipWhitespace(range, line);
				Json itm = parseJson(range, line, filename);
				obj[key] = itm;
				skipWhitespace(range, line);
				enforceJson(!range.empty, "Missing '}' before EOF.", filename, line);
				enforceJson(range.front == ',' || range.front == '}',
					format("Expected '}' or ',' - got '%s'.", range.front), filename, line);
				if (range.front == '}') break;
				else range.popFront();
			}
			range.popFront();
			ret = obj;
			break;
		default:
			enforceJson(false, format("Expected valid JSON token, got '%s'.", range[0 .. min(12, $)]), filename, line);
			assert(false);
	}

	assert(ret.type != Json.Type.undefined);
	version(JsonLineNumbers) ret.line = curline;
	return ret;
}

/**
	Parses the given JSON string and returns the corresponding Json object.

	Throws a JSONException if any parsing error occurs.
*/
Json parseJsonString(string str, string filename = null)
@safe {
	auto strcopy = str;
	int line = 0;
	auto ret = parseJson(strcopy, () @trusted { return &line; } (), filename);
	enforceJson(strcopy.strip().length == 0, "Expected end of string after JSON value.", filename, line);
	return ret;
}

@safe unittest {
	// These currently don't work at compile time
	assert(parseJsonString("17559991181826658461") == Json(BigInt(17559991181826658461UL)));
	assert(parseJsonString("99999999999999999999999999") == () @trusted { return Json(BigInt("99999999999999999999999999")); } ());
	auto json = parseJsonString(`{"hey": "This is @à test éhééhhéhéé !%/??*&?\ud83d\udcec"}`);
	assert(json.toPrettyString() == parseJsonString(json.toPrettyString()).toPrettyString());

	bool test() {
		assert(parseJsonString("null") == Json(null));
		assert(parseJsonString("true") == Json(true));
		assert(parseJsonString("false") == Json(false));
		assert(parseJsonString("1") == Json(1));
		assert(parseJsonString("2.0") == Json(2.0));
		assert(parseJsonString("\"test\"") == Json("test"));
		assert(parseJsonString("[1, 2, 3]") == Json([Json(1), Json(2), Json(3)]));
		assert(parseJsonString("{\"a\": 1}") == Json(["a": Json(1)]));
		assert(parseJsonString(`"\\\/\b\f\n\r\t\u1234"`).get!string == "\\/\b\f\n\r\t\u1234");

		return true;
	}

	// Run at compile time and runtime
	assert(test());
	static assert(test());
}

@safe unittest {
	bool test() {
		try parseJsonString(" \t\n ");
		catch (Exception e) assert(e.msg.endsWith("JSON string contains only whitespaces."));
		try parseJsonString(`{"a": 1`);
		catch (Exception e) assert(e.msg.endsWith("Missing '}' before EOF."));
		try parseJsonString(`{"a": 1 x`);
		catch (Exception e) assert(e.msg.endsWith("Expected '}' or ',' - got 'x'."));
		try parseJsonString(`[1`);
		catch (Exception e) assert(e.msg.endsWith("Missing ']' before EOF."));
		try parseJsonString(`[1 x`);
		catch (Exception e) assert(e.msg.endsWith("Expected ']' or ',' - got 'x'."));

		return true;
	}

	// Run at compile time and runtime
	assert(test());
	static assert(test());
}

/**
	Serializes the given value to JSON.

	The following types of values are supported:

	$(DL
		$(DT `Json`)            $(DD Used as-is)
		$(DT `null`)            $(DD Converted to `Json.Type.null_`)
		$(DT `bool`)            $(DD Converted to `Json.Type.bool_`)
		$(DT `float`, `double`)   $(DD Converted to `Json.Type.float_`)
		$(DT `short`, `ushort`, `int`, `uint`, `long`, `ulong`) $(DD Converted to `Json.Type.int_`)
		$(DT `BigInt`)          $(DD Converted to `Json.Type.bigInt`)
		$(DT `string`)          $(DD Converted to `Json.Type.string`)
		$(DT `T[]`)             $(DD Converted to `Json.Type.array`)
		$(DT `T[string]`)       $(DD Converted to `Json.Type.object`)
		$(DT `struct`)          $(DD Converted to `Json.Type.object`)
		$(DT `class`)           $(DD Converted to `Json.Type.object` or `Json.Type.null_`)
	)

	All entries of an array or an associative array, as well as all R/W properties and
	all public fields of a struct/class are recursively serialized using the same rules.

	Fields ending with an underscore will have the last underscore stripped in the
	serialized output. This makes it possible to use fields with D keywords as their name
	by simply appending an underscore.

	The following methods can be used to customize the serialization of structs/classes:

	---
	Json toJson() const;
	static T fromJson(Json src);

	string toString() const;
	static T fromString(string src);
	---

	The methods will have to be defined in pairs. The first pair that is implemented by
	the type will be used for serialization (i.e. `toJson` overrides `toString`).

	See_Also: `deserializeJson`, `vibe.data.serialization`
*/
Json serializeToJson(T)(T value)
{
	return serialize!JsonSerializer(value);
}
/// ditto
void serializeToJson(R, T)(R destination, T value)
	if (isOutputRange!(R, char) || isOutputRange!(R, ubyte))
{
	serialize!(JsonStringSerializer!R)(value, destination);
}
/// ditto
string serializeToJsonString(T)(T value)
{
	auto ret = appender!string;
	serializeToJson(ret, value);
	return ret.data;
}

///
@safe unittest {
	struct Foo {
		int number;
		string str;
	}

	Foo f;

	f.number = 12;
	f.str = "hello";

	string json = serializeToJsonString(f);
	assert(json == `{"number":12,"str":"hello"}`);
	Json jsonval = serializeToJson(f);
	assert(jsonval.type == Json.Type.object);
	assert(jsonval["number"] == Json(12));
	assert(jsonval["str"] == Json("hello"));
}


/**
	Serializes the given value to a pretty printed JSON string.

	See_also: `serializeToJson`, `vibe.data.serialization`
*/
void serializeToPrettyJson(R, T)(R destination, T value)
	if (isOutputRange!(R, char) || isOutputRange!(R, ubyte))
{
	serialize!(JsonStringSerializer!(R, true))(value, destination);
}
/// ditto
string serializeToPrettyJson(T)(T value)
{
	auto ret = appender!string;
	serializeToPrettyJson(ret, value);
	return ret.data;
}

///
@safe unittest {
	struct Foo {
		int number;
		string str;
	}

	Foo f;
	f.number = 12;
	f.str = "hello";

	string json = serializeToPrettyJson(f);
	assert(json ==
`{
	"number": 12,
	"str": "hello"
}`);
}


/**
	Deserializes a JSON value into the destination variable.

	The same types as for `serializeToJson()` are supported and handled inversely.

	See_Also: `serializeToJson`, `serializeToJsonString`, `vibe.data.serialization`
*/
void deserializeJson(T)(ref T dst, Json src)
{
	dst = deserializeJson!T(src);
}
/// ditto
T deserializeJson(T)(Json src)
{
	return deserialize!(JsonSerializer, T)(src);
}
/// ditto
T deserializeJson(T, R)(R input)
	if (!is(R == Json) && isInputRange!R)
{
	return deserialize!(JsonStringSerializer!R, T)(input);
}

///
@safe unittest {
	struct Foo {
		int number;
		string str;
	}
	Foo f = deserializeJson!Foo(`{"number": 12, "str": "hello"}`);
	assert(f.number == 12);
	assert(f.str == "hello");
}

@safe unittest {
	import std.stdio;
	enum Foo : string { k = "test" }
	enum Boo : int { l = 5 }
	static struct S { float a; double b; bool c; int d; string e; byte f; ubyte g; long h; ulong i; float[] j; Foo k; Boo l; }
	immutable S t = {1.5, -3.0, true, int.min, "Test", -128, 255, long.min, ulong.max, [1.1, 1.2, 1.3], Foo.k, Boo.l};
	S u;
	deserializeJson(u, serializeToJson(t));
	assert(t.a == u.a);
	assert(t.b == u.b);
	assert(t.c == u.c);
	assert(t.d == u.d);
	assert(t.e == u.e);
	assert(t.f == u.f);
	assert(t.g == u.g);
	assert(t.h == u.h);
	assert(t.i == u.i);
	assert(t.j == u.j);
	assert(t.k == u.k);
	assert(t.l == u.l);
}

@safe unittest
{
	assert(uint.max == serializeToJson(uint.max).deserializeJson!uint);
	assert(ulong.max == serializeToJson(ulong.max).deserializeJson!ulong);
}

unittest {
	static struct A { int value; static A fromJson(Json val) @safe { return A(val.get!int); } Json toJson() const @safe { return Json(value); } }
	static struct C { int value; static C fromString(string val) @safe { return C(val.to!int); } string toString() const @safe { return value.to!string; } }
	static struct D { int value; }

	assert(serializeToJson(const A(123)) == Json(123));
	assert(serializeToJson(A(123))       == Json(123));
	assert(serializeToJson(const C(123)) == Json("123"));
	assert(serializeToJson(C(123))       == Json("123"));
	assert(serializeToJson(const D(123)) == serializeToJson(["value": 123]));
	assert(serializeToJson(D(123))       == serializeToJson(["value": 123]));
}

unittest {
	auto d = Date(2001,1,1);
	deserializeJson(d, serializeToJson(Date.init));
	assert(d == Date.init);
	deserializeJson(d, serializeToJson(Date(2001,1,1)));
	assert(d == Date(2001,1,1));
	struct S { immutable(int)[] x; }
	S s;
	deserializeJson(s, serializeToJson(S([1,2,3])));
	assert(s == S([1,2,3]));
	struct T {
		@optional S s;
		@optional int i;
		@optional float f_; // underscore strip feature
		@optional double d;
		@optional string str;
	}
	auto t = T(S([1,2,3]));
	deserializeJson(t, parseJsonString(`{ "s" : null, "i" : null, "f" : null, "d" : null, "str" : null }`));
	assert(text(t) == text(T()));
}

unittest {
	static class C {
		@safe:
		int a;
		private int _b;
		@property int b() const { return _b; }
		@property void b(int v) { _b = v; }

		@property int test() const { return 10; }

		void test2() {}
	}
	C c = new C;
	c.a = 1;
	c.b = 2;

	C d;
	deserializeJson(d, serializeToJson(c));
	assert(c.a == d.a);
	assert(c.b == d.b);
}

unittest {
	static struct C { @safe: int value; static C fromString(string val) { return C(val.to!int); } string toString() const { return value.to!string; } }
	enum Color { Red, Green, Blue }
	{
		static class T {
			@safe:
			string[Color] enumIndexedMap;
			string[C] stringableIndexedMap;
			this() {
				enumIndexedMap = [ Color.Red : "magenta", Color.Blue : "deep blue" ];
								stringableIndexedMap = [ C(42) : "forty-two" ];
			}
		}

		T original = new T;
		original.enumIndexedMap[Color.Green] = "olive";
		T other;
		deserializeJson(other, serializeToJson(original));
		assert(serializeToJson(other) == serializeToJson(original));
	}
	{
		static struct S {
			string[Color] enumIndexedMap;
			string[C] stringableIndexedMap;
		}

		S *original = new S;
		original.enumIndexedMap = [ Color.Red : "magenta", Color.Blue : "deep blue" ];
		original.enumIndexedMap[Color.Green] = "olive";
				original.stringableIndexedMap = [ C(42) : "forty-two" ];
		S other;
		deserializeJson(other, serializeToJson(original));
		assert(serializeToJson(other) == serializeToJson(original));
	}
}

unittest {
	import std.typecons : Nullable;

	struct S { Nullable!int a, b; }
	S s;
	s.a = 2;

	auto j = serializeToJson(s);
	assert(j["a"].type == Json.Type.int_);
	assert(j["b"].type == Json.Type.null_);

	auto t = deserializeJson!S(j);
	assert(!t.a.isNull() && t.a == 2);
	assert(t.b.isNull());
}

unittest { // #840
	int[2][2] nestedArray = 1;
	assert(nestedArray.serializeToJson.deserializeJson!(typeof(nestedArray)) == nestedArray);
}

unittest { // #1109
	static class C {
		@safe:
		int mem;
		this(int m) { mem = m; }
		static C fromJson(Json j) { return new C(j.get!int-1); }
		Json toJson() const { return Json(mem+1); }
	}
	const c = new C(13);
	assert(serializeToJson(c) == Json(14));
	assert(deserializeJson!C(Json(14)).mem == 13);
}

unittest { // const and mutable json
	Json j = Json(1);
	const k = Json(2);
	assert(serializeToJson(j) == Json(1));
	assert(serializeToJson(k) == Json(2));
}

unittest { // issue #1660 - deserialize AA whose key type is string-based enum
	enum Foo: string
	{
		Bar = "bar",
		Buzz = "buzz"
	}

	struct S {
		int[Foo] f;
	}

	const s = S([Foo.Bar: 2000]);
	assert(serializeToJson(s)["f"] == Json([Foo.Bar: Json(2000)]));

	auto j = Json.emptyObject;
	j["f"] = [Foo.Bar: Json(2000)];
	assert(deserializeJson!S(j).f == [Foo.Bar: 2000]);
}

unittest {
	struct V {
		UUID v;
	}

	const u = UUID("318d7a61-e41b-494e-90d3-0a99f5531bfe");
	const s = `{"v":"318d7a61-e41b-494e-90d3-0a99f5531bfe"}`;
	auto j = Json(["v": Json(u)]);

	const v = V(u);

	assert(serializeToJson(v) == j);

	j = Json.emptyObject;
	j["v"] = u;
	assert(deserializeJson!V(j).v == u);

	assert(serializeToJsonString(v) == s);
	assert(deserializeJson!V(s).v == u);
}

/**
	Serializer for a plain Json representation.

	See_Also: vibe.data.serialization.serialize, vibe.data.serialization.deserialize, serializeToJson, deserializeJson
*/
struct JsonSerializer {
	template isJsonBasicType(T) { enum isJsonBasicType = std.traits.isNumeric!T || isBoolean!T || isSomeString!T || is(T == typeof(null)) || is(T == UUID) || isJsonSerializable!T; }

	template isSupportedValueType(T) { enum isSupportedValueType = isJsonBasicType!T || is(T == Json) || is (T == JSONValue); }

	private {
		Json m_current;
		Json[] m_compositeStack;
	}

	this(Json data) @safe { m_current = data; }

	@disable this(this);

	//
	// serialization
	//
	Json getSerializedResult() @safe { return m_current; }
	void beginWriteDictionary(Traits)() { m_compositeStack ~= Json.emptyObject; }
	void endWriteDictionary(Traits)() { m_current = m_compositeStack[$-1]; m_compositeStack.length--; }
	void beginWriteDictionaryEntry(Traits)(string name) {}
	void endWriteDictionaryEntry(Traits)(string name) { m_compositeStack[$-1][name] = m_current; }

	void beginWriteArray(Traits)(size_t) { m_compositeStack ~= Json.emptyArray; }
	void endWriteArray(Traits)() { m_current = m_compositeStack[$-1]; m_compositeStack.length--; }
	void beginWriteArrayEntry(Traits)(size_t) {}
	void endWriteArrayEntry(Traits)(size_t) { m_compositeStack[$-1].appendArrayElement(m_current); }

	void writeValue(Traits, T)(in T value)
		if (!is(T == Json))
	{
		static if (is(T == JSONValue)) {
			m_current = Json(value);
		} else static if (isJsonSerializable!T) {
			static if (!__traits(compiles, () @safe { return value.toJson(); } ()))
				pragma(msg, "Non-@safe toJson/fromJson methods are deprecated - annotate "~T.stringof~".toJson() with @safe.");
			m_current = () @trusted { return value.toJson(); } ();
		} else static if (isSomeString!T && !is(T == string)) {
			writeValue!Traits(value.to!string);
		} else m_current = Json(value);
	}

	void writeValue(Traits, T)(Json value) if (is(T == Json)) { m_current = value; }
	void writeValue(Traits, T)(in Json value) if (is(T == Json)) { m_current = value.clone; }

	//
	// deserialization
	//
	void readDictionary(Traits)(scope void delegate(string) @safe field_handler)
	{
		enforceJson(m_current.type == Json.Type.object, "Expected JSON object, got "~m_current.type.to!string);
		auto old = m_current;
		foreach (string key, value; m_current.get!(Json[string])) {
			if (value.type == Json.Type.undefined) {
				continue;
			}

			m_current = value;
			field_handler(key);
		}
		m_current = old;
	}

	void beginReadDictionaryEntry(Traits)(string name) {}
	void endReadDictionaryEntry(Traits)(string name) {}

	void readArray(Traits)(scope void delegate(size_t) @safe size_callback, scope void delegate() @safe entry_callback)
	{
		enforceJson(m_current.type == Json.Type.array, "Expected JSON array, got "~m_current.type.to!string);
		auto old = m_current;
		size_callback(m_current.length);
		foreach (ent; old.get!(Json[])) {
			m_current = ent;
			entry_callback();
		}
		m_current = old;
	}

	void beginReadArrayEntry(Traits)(size_t index) {}
	void endReadArrayEntry(Traits)(size_t index) {}

	T readValue(Traits, T)()
	@safe {
		static if (is(T == Json)) return m_current;
		else static if (is(T == JSONValue)) return cast(JSONValue)m_current;
		else static if (isJsonSerializable!T) {
			static if (!__traits(compiles, () @safe { return T.fromJson(m_current); } ()))
				pragma(msg, "Non-@safe toJson/fromJson methods are deprecated - annotate "~T.stringof~".fromJson() with @safe.");
			return () @trusted { return T.fromJson(m_current); } ();
		} else static if (is(T == float) || is(T == double)) {
			switch (m_current.type) {
				default: return cast(T)m_current.get!long;
				case Json.Type.null_: goto case;
				case Json.Type.undefined: return T.nan;
				case Json.Type.float_: return cast(T)m_current.get!double;
				case Json.Type.bigInt: return cast(T)m_current.bigIntToLong();
			}
		} else static if (is(T == const(char)[])) {
			return readValue!(Traits, string);
		} else static if (isSomeString!T && !is(T == string)) {
			return readValue!(Traits, string).to!T;
		} else static if (is(T == string)) {
			if (m_current.type == Json.Type.array) { // legacy support for pre-#2150 serialization results
				return () @trusted { // appender
					auto r = appender!string;
					foreach (s; m_current.get!(Json[]))
						r.put(s.get!string());
					return r.data;
				} ();
			} else return m_current.get!T();
		} else return m_current.get!T();
	}

	bool tryReadNull(Traits)() { return m_current.type == Json.Type.null_; }
}

unittest {
	struct T {
		@optional string a;
	}

	auto obj = Json.emptyObject;
	obj["a"] = Json.undefined;
	assert(obj.deserializeJson!T.a == "");
}

/**
	Serializer for a range based plain JSON string representation.

	See_Also: vibe.data.serialization.serialize, vibe.data.serialization.deserialize, serializeToJson, deserializeJson
*/
struct JsonStringSerializer(R, bool pretty = false)
	if (isInputRange!R || isOutputRange!(R, char))
{
	private {
		R m_range;
		size_t m_level = 0;
	}

	template isJsonBasicType(T) { enum isJsonBasicType = std.traits.isNumeric!T || isBoolean!T || isSomeString!T || is(T == typeof(null)) || is(T == UUID) || isJsonSerializable!T; }

	template isSupportedValueType(T) { enum isSupportedValueType = isJsonBasicType!T || is(T == Json) || is(T == JSONValue); }

	this(R range)
	{
		m_range = range;
	}

	@disable this(this);

	//
	// serialization
	//
	static if (isOutputRange!(R, char)) {
		private {
			bool m_firstInComposite;
		}

		void getSerializedResult() {}

		void beginWriteDictionary(Traits)() { startComposite(); m_range.put('{'); }
		void endWriteDictionary(Traits)() { endComposite(); m_range.put("}"); }
		void beginWriteDictionaryEntry(Traits)(string name)
		{
			startCompositeEntry();
			m_range.put('"');
			m_range.jsonEscape(name);
			static if (pretty) m_range.put(`": `);
			else m_range.put(`":`);
		}
		void endWriteDictionaryEntry(Traits)(string name) {}

		void beginWriteArray(Traits)(size_t) { startComposite(); m_range.put('['); }
		void endWriteArray(Traits)() { endComposite(); m_range.put(']'); }
		void beginWriteArrayEntry(Traits)(size_t) { startCompositeEntry(); }
		void endWriteArrayEntry(Traits)(size_t) {}

		void writeValue(Traits, T)(in T value)
		{
			static if (is(T == typeof(null))) m_range.put("null");
			else static if (is(T == bool)) m_range.put(value ? "true" : "false");
			else static if (is(T : long)) m_range.formattedWrite("%s", value);
			else static if (is(T == BigInt)) () @trusted { m_range.formattedWrite("%d", value); } ();
			else static if (is(T : real)) value == value ? m_range.formattedWrite("%.16g", value) : m_range.put("null");
			else static if (is(T : const(char)[])) {
				m_range.put('"');
				m_range.jsonEscape(value);
				m_range.put('"');
			} else static if (isSomeString!T) writeValue!Traits(value.to!string); // TODO: avoid memory allocation
			else static if (is(T == UUID)) writeValue!Traits(value.toString());
			else static if (is(T == Json)) m_range.writeJsonString(value);
			else static if (is(T == JSONValue)) m_range.writeJsonString(Json(value));
			else static if (isJsonSerializable!T) {
				static if (!__traits(compiles, () @safe { return value.toJson(); } ()))
					pragma(msg, "Non-@safe toJson/fromJson methods are deprecated - annotate "~T.stringof~".toJson() with @safe.");
				m_range.writeJsonString!(R, pretty)(() @trusted { return value.toJson(); } (), m_level);
			} else static assert(false, "Unsupported type: " ~ T.stringof);
		}

		private void startComposite()
		{
			static if (pretty) m_level++;
			m_firstInComposite = true;
		}

		private void startCompositeEntry()
		{
			if (!m_firstInComposite) {
				m_range.put(',');
			} else {
				m_firstInComposite = false;
			}
			static if (pretty) indent();
		}

		private void endComposite()
		{
			static if (pretty) {
				m_level--;
				if (!m_firstInComposite) indent();
			}
			m_firstInComposite = false;
		}

		private void indent()
		{
			m_range.put('\n');
			foreach (i; 0 .. m_level) m_range.put('\t');
		}
	}

	//
	// deserialization
	//
	static if (isInputRange!(R)) {
		private {
			int m_line = 0;
		}

		void readDictionary(Traits)(scope void delegate(string) @safe entry_callback)
		{
			m_range.skipWhitespace(&m_line);
			enforceJson(!m_range.empty && m_range.front == '{', "Expecting object.");
			m_range.popFront();
			bool first = true;
			while(true) {
				m_range.skipWhitespace(&m_line);
				enforceJson(!m_range.empty, "Missing '}'.");
				if (m_range.front == '}') {
					m_range.popFront();
					break;
				} else if (!first) {
					enforceJson(m_range.front == ',', "Expecting ',' or '}', not '"~m_range.front.to!string~"'.");
					m_range.popFront();
					m_range.skipWhitespace(&m_line);
				} else first = false;

				auto name = m_range.skipJsonString(&m_line);

				m_range.skipWhitespace(&m_line);
				enforceJson(!m_range.empty && m_range.front == ':', "Expecting ':', not '"~m_range.front.to!string~"'.");
				m_range.popFront();

				entry_callback(name);
			}
		}

		void beginReadDictionaryEntry(Traits)(string name) {}
		void endReadDictionaryEntry(Traits)(string name) {}

		void readArray(Traits)(scope void delegate(size_t) @safe size_callback, scope void delegate() @safe entry_callback)
		{
			m_range.skipWhitespace(&m_line);
			enforceJson(!m_range.empty && m_range.front == '[', "Expecting array.");
			m_range.popFront();
			bool first = true;
			while(true) {
				m_range.skipWhitespace(&m_line);
				enforceJson(!m_range.empty, "Missing ']'.");
				if (m_range.front == ']') {
					m_range.popFront();
					break;
				} else if (!first) {
					enforceJson(m_range.front == ',', "Expecting ',' or ']'.");
					m_range.popFront();
				} else first = false;

				entry_callback();
			}
		}

		void beginReadArrayEntry(Traits)(size_t index) {}
		void endReadArrayEntry(Traits)(size_t index) {}

		T readValue(Traits, T)()
		{
			m_range.skipWhitespace(&m_line);
			static if (is(T == typeof(null))) { enforceJson(m_range.take(4).equal("null"), "Expecting 'null'."); return null; }
			else static if (is(T == bool)) {
				bool ret = m_range.front == 't';
				string expected = ret ? "true" : "false";
				foreach (ch; expected) {
					enforceJson(m_range.front == ch, "Expecting 'true' or 'false'.");
					m_range.popFront();
				}
				return ret;
			} else static if (is(T : long)) {
				bool is_float;
				bool is_long_overflow;
				auto num = m_range.skipNumber(is_float, is_long_overflow);
				enforceJson(!is_float, "Expecting integer number.");
				enforceJson(!is_long_overflow, num.to!string~" is too big for long.");
				return to!T(num);
			} else static if (is(T : BigInt)) {
				bool is_float;
				bool is_long_overflow;
				auto num = m_range.skipNumber(is_float, is_long_overflow);
				enforceJson(!is_float, "Expecting integer number.");
				return BigInt(num);
			} else static if (is(T : real)) {
				bool is_float;
				bool is_long_overflow;
				auto num = m_range.skipNumber(is_float, is_long_overflow);
				return to!T(num);
			}
			else static if (is(T == string) || is(T == const(char)[])) {
				if (!m_range.empty && m_range.front == '[') {
					return () @trusted { // appender
						auto ret = appender!string();
						readArray!Traits((sz) {}, () @trusted {
							ret.put(m_range.skipJsonString(&m_line));
						});
						return ret.data;
					} ();
				} else return m_range.skipJsonString(&m_line);
			}
			else static if (isSomeString!T) return readValue!(Traits, string).to!T;
			else static if (is(T == UUID)) return UUID(readValue!(Traits, string)());
			else static if (is(T == Json)) return m_range.parseJson(&m_line);
			else static if (is(T == JSONValue)) return cast(JSONValue)m_range.parseJson(&m_line);
			else static if (isJsonSerializable!T) {
				static if (!__traits(compiles, () @safe { return T.fromJson(Json.init); } ()))
					pragma(msg, "Non-@safe toJson/fromJson methods are deprecated - annotate "~T.stringof~".fromJson() with @safe.");
				return () @trusted { return T.fromJson(m_range.parseJson(&m_line)); } ();
			} else static assert(false, "Unsupported type: " ~ T.stringof);
		}

		bool tryReadNull(Traits)()
		{
			m_range.skipWhitespace(&m_line);
			if (m_range.front != 'n') return false;
			foreach (ch; "null") {
				enforceJson(m_range.front == ch, "Expecting 'null'.");
				m_range.popFront();
			}
			assert(m_range.empty || m_range.front != 'l');
			return true;
		}
	}
}

/// Cloning JSON arrays
unittest
{
	Json value = Json([ Json([ Json.emptyArray ]), Json.emptyArray ]).clone;

	assert(value.length == 2);
	assert(value[0].length == 1);
	assert(value[0][0].length == 0);
}

unittest
{
	assert(serializeToJsonString(double.nan) == "null");
	assert(serializeToJsonString(Json()) == "null");
	assert(serializeToJsonString(Json(["bar":Json("baz"),"foo":Json()])) == `{"bar":"baz"}`);

	struct Foo{Json bar = Json();}
	Foo f;
	assert(serializeToJsonString(f) == `{"bar":null}`);
}

/**
	Writes the given JSON object as a JSON string into the destination range.

	This function will convert the given JSON value to a string without adding
	any white space between tokens (no newlines, no indentation and no padding).
	The output size is thus minimized, at the cost of bad human readability.

	Params:
		dst   = References the string output range to which the result is written.
		json  = Specifies the JSON value that is to be stringified.
		level = Specifies the base amount of indentation for the output. Indentation is always
				done using tab characters.

	See_Also: Json.toString, writePrettyJsonString
*/
void writeJsonString(R, bool pretty = false)(ref R dst, in Json json, size_t level = 0)
@safe //	if( isOutputRange!R && is(ElementEncodingType!R == char) )
{
	final switch( json.type ){
		case Json.Type.undefined: dst.put("null"); break;
		case Json.Type.null_: dst.put("null"); break;
		case Json.Type.bool_: dst.put(json.get!bool ? "true" : "false"); break;
		case Json.Type.int_: formattedWrite(dst, "%d", json.get!long); break;
		case Json.Type.bigInt: () @trusted { formattedWrite(dst, "%d", json.get!BigInt); } (); break;
		case Json.Type.float_:
			auto d = json.get!double;
			if (d != d)
				dst.put("null"); // JSON has no NaN value so set null
			else
				formattedWrite(dst, "%.16g", json.get!double);
			break;
		case Json.Type.string:
			dst.put('\"');
			jsonEscape(dst, json.get!string);
			dst.put('\"');
			break;
		case Json.Type.array:
			dst.put('[');
			bool first = true;
			foreach (ref const Json e; json.byValue) {
				if( !first ) dst.put(",");
				first = false;
				static if (pretty) {
					dst.put('\n');
					foreach (tab; 0 .. level+1) dst.put('\t');
				}
				if (e.type == Json.Type.undefined) dst.put("null");
				else writeJsonString!(R, pretty)(dst, e, level+1);
			}
			static if (pretty) {
				if (json.length > 0) {
					dst.put('\n');
					foreach (tab; 0 .. level) dst.put('\t');
				}
			}
			dst.put(']');
			break;
		case Json.Type.object:
			dst.put('{');
			bool first = true;
			foreach (string k, ref const Json e; json.byKeyValue) {
				if( e.type == Json.Type.undefined ) continue;
				if( !first ) dst.put(',');
				first = false;
				static if (pretty) {
					dst.put('\n');
					foreach (tab; 0 .. level+1) dst.put('\t');
				}
				dst.put('\"');
				jsonEscape(dst, k);
				dst.put(pretty ? `": ` : `":`);
				writeJsonString!(R, pretty)(dst, e, level+1);
			}
			static if (pretty) {
				if (json.length > 0) {
					dst.put('\n');
					foreach (tab; 0 .. level) dst.put('\t');
				}
			}
			dst.put('}');
			break;
	}
}

unittest {
	auto a = Json.emptyObject;
	a["a"] = Json.emptyArray;
	a["b"] = Json.emptyArray;
	a["b"] ~= Json(1);
	a["b"] ~= Json.emptyObject;

	assert(a.toString() == `{"a":[],"b":[1,{}]}` || a.toString() == `{"b":[1,{}],"a":[]}`);
	assert(a.toPrettyString() ==
`{
	"a": [],
	"b": [
		1,
		{}
	]
}`
		|| a.toPrettyString() == `{
	"b": [
		1,
		{}
	],
	"a": []
}`);
}

unittest { // #735
	auto a = Json.emptyArray;
	a ~= "a";
	a ~= Json();
	a ~= "b";
	a ~= null;
	a ~= "c";
	assert(a.toString() == `["a",null,"b",null,"c"]`);
}

unittest {
	auto a = Json.emptyArray;
	a ~= Json(1);
	a ~= Json(2);
	a ~= Json(3);
	a ~= Json(4);
	a ~= Json(5);

	auto b = Json(a[0..a.length]);
	assert(a == b);

	auto c = Json(a[0..$]);
	assert(a == c);
	assert(b == c);

	auto d = [Json(1),Json(2),Json(3)];
	assert(d == a[0..a.length-2]);
	assert(d == a[0..$-2]);
}

unittest {
	auto j = Json(double.init);

	assert(j.toString == "null"); // A double nan should serialize to null
	j = 17.04f;
	assert(j.toString == "17.04");	// A proper double should serialize correctly

	double d;
	deserializeJson(d, Json.undefined); // Json.undefined should deserialize to nan
	assert(d != d);
	deserializeJson(d, Json(null)); // Json.undefined should deserialize to nan
	assert(d != d);
}
/**
	Writes the given JSON object as a prettified JSON string into the destination range.

	The output will contain newlines and indents to make the output human readable.

	Params:
		dst   = References the string output range to which the result is written.
		json  = Specifies the JSON value that is to be stringified.
		level = Specifies the base amount of indentation for the output. Indentation  is always
				done using tab characters.

	See_Also: Json.toPrettyString, writeJsonString
*/
void writePrettyJsonString(R)(ref R dst, in Json json, int level = 0)
//	if( isOutputRange!R && is(ElementEncodingType!R == char) )
{
	writeJsonString!(R, true)(dst, json, level);
}


/**
	Helper function that escapes all Unicode characters in a JSON string.
*/
string convertJsonToASCII(string json)
{
	auto ret = appender!string;
	jsonEscape!true(ret, json);
	return ret.data;
}


/// private
private void jsonEscape(bool escape_unicode = false, R)(ref R dst, const(char)[] s)
{
	size_t startPos = 0;

	void putInterval(size_t curPos)
	{
		if (curPos > startPos)
			dst.put(s[startPos..curPos]);
		startPos = curPos + 1;
	}

	for (size_t pos = 0; pos < s.length; pos++) {
		immutable(char) ch = s[pos];

		switch (ch) {
			default:
				static if (escape_unicode) {
					if (ch <= 0x20 || ch >= 0x80)
					{
						putInterval(pos);
						import std.utf : decode;
						int len;
						dchar codepoint = decode(s, pos);
						/* codepoint is in BMP */
						if(codepoint < 0x10000)
						{
							dst.formattedWrite("\\u%04X", codepoint);
						}
						/* not in BMP -> construct a UTF-16 surrogate pair */
						else
						{
							int first, last;

							codepoint -= 0x10000;
							first = 0xD800 | ((codepoint & 0xffc00) >> 10);
							last = 0xDC00 | (codepoint & 0x003ff);

							dst.formattedWrite("\\u%04X\\u%04X", first, last);
						}
						startPos = pos;
						pos -= 1;
					}
				}
				else
				{
					if (ch < 0x20)
					{
						putInterval(pos);
						dst.formattedWrite("\\u%04X", ch);
					}
				}
				break;
			case '\\': putInterval(pos); dst.put("\\\\"); break;
			case '\r': putInterval(pos); dst.put("\\r"); break;
			case '\n': putInterval(pos); dst.put("\\n"); break;
			case '\t': putInterval(pos); dst.put("\\t"); break;
			case '\"': putInterval(pos); dst.put("\\\""); break;
			case '/':
				// this avoids the sequence "</" in the output, which is prone
				// to cross site scripting attacks when inserted into web pages
				if (pos > 0 && s[pos-1] == '<')
				{
					putInterval(pos);
					dst.put("\\/");
				}
				break;
		}
	}
	// last interval
	putInterval(s.length);
}

/// private
private string jsonUnescape(R)(ref R range)
{
	auto ret = appender!string();
	while(!range.empty){
		auto ch = range.front;
		switch( ch ){
			case '"': return ret.data;
			case '\\':
				range.popFront();
				enforceJson(!range.empty, "Unterminated string escape sequence.");
				switch(range.front){
					default: enforceJson(false, "Invalid string escape sequence."); break;
					case '"': ret.put('\"'); range.popFront(); break;
					case '\\': ret.put('\\'); range.popFront(); break;
					case '/': ret.put('/'); range.popFront(); break;
					case 'b': ret.put('\b'); range.popFront(); break;
					case 'f': ret.put('\f'); range.popFront(); break;
					case 'n': ret.put('\n'); range.popFront(); break;
					case 'r': ret.put('\r'); range.popFront(); break;
					case 't': ret.put('\t'); range.popFront(); break;
					case 'u':

						dchar decode_unicode_escape() {
							enforceJson(range.front == 'u');
							range.popFront();
							dchar uch = 0;
							foreach( i; 0 .. 4 ){
								uch *= 16;
								enforceJson(!range.empty, "Unicode sequence must be '\\uXXXX'.");
								auto dc = range.front;
								range.popFront();

								if( dc >= '0' && dc <= '9' ) uch += dc - '0';
								else if( dc >= 'a' && dc <= 'f' ) uch += dc - 'a' + 10;
								else if( dc >= 'A' && dc <= 'F' ) uch += dc - 'A' + 10;
								else enforceJson(false, "Unicode sequence must be '\\uXXXX'.");
							}
							return uch;
						}

						auto uch = decode_unicode_escape();

						if(0xD800 <= uch && uch <= 0xDBFF) {
							/* surrogate pair */
							range.popFront(); // backslash '\'
							auto uch2 = decode_unicode_escape();
							enforceJson(0xDC00 <= uch2 && uch2 <= 0xDFFF, "invalid Unicode");
							{
								/* valid second surrogate */
								uch =
									((uch - 0xD800) << 10) +
										(uch2 - 0xDC00) +
										0x10000;
							}
						}
						ret.put(uch);
						break;
				}
				break;
			default:
				ret.put(ch);
				range.popFront();
				break;
		}
	}
	return ret.data;
}

private auto skipNumber(R)(ref R s, out bool is_float, out bool is_long_overflow) @safe
	if (isNarrowString!R)
{
	auto r = s.representation;
	version (assert) auto rEnd = (() @trusted => r.ptr + r.length - 1)();
	auto res = skipNumber(r, is_float, is_long_overflow);
	version (assert) assert(rEnd == (() @trusted => r.ptr + r.length - 1)()); // check nothing taken off the end
	s = s[$ - r.length .. $];
	return res.assumeUTF();
}

/// private
private auto skipNumber(R)(ref R s, out bool is_float, out bool is_long_overflow)
	if (!isNarrowString!R && isForwardRange!R)
{
	auto sOrig = s.save;
	size_t idx = 0;
	is_float = false;
	is_long_overflow = false;
	ulong int_part = 0;
	if (s.front == '-') {
		s.popFront(); ++idx;
	}
	if (s.front == '0') {
		s.popFront(); ++idx;
	}
	else {
		enforceJson(isDigit(s.front), "Digit expected at beginning of number.");
		int_part = s.front - '0';
		s.popFront(); ++idx;
		while( !s.empty && isDigit(s.front) ) {
			if (!is_long_overflow) {
				auto dig = s.front - '0';
				if ((long.max / 10) > int_part || ((long.max / 10) == int_part && (long.max % 10) >= dig)) {
					int_part *= 10;
					int_part += dig;
				}
				else {
					is_long_overflow = true;
				}
			}
			s.popFront(); ++idx;
		}
	}

	if( !s.empty && s.front == '.' ) {
		s.popFront(); ++idx;
		is_float = true;
		while( !s.empty && isDigit(s.front) ) {
			s.popFront(); ++idx;
		}
	}

	if( !s.empty && (s.front == 'e' || s.front == 'E') ) {
		s.popFront(); ++idx;
		is_float = true;
		if( !s.empty && (s.front == '+' || s.front == '-') ) {
			s.popFront(); ++idx;
		}
		enforceJson( !s.empty && isDigit(s.front), "Expected exponent." ~ sOrig.takeExactly(idx).to!string);
		s.popFront(); ++idx;
		while( !s.empty && isDigit(s.front) ) {
			s.popFront(); ++idx;
		}
	}

	return sOrig.takeExactly(idx);
}

unittest
{
	import std.meta : AliasSeq;
	// test for string and for a simple range
	foreach (foo; AliasSeq!(to!string, map!"a")) {
		auto test_1 = foo("9223372036854775806"); // lower then long.max
		auto test_2 = foo("9223372036854775807"); // long.max
		auto test_3 = foo("9223372036854775808"); // greater then long.max
		bool is_float;
		bool is_long_overflow;
		test_1.skipNumber(is_float, is_long_overflow);
		assert(!is_long_overflow);
		test_2.skipNumber(is_float, is_long_overflow);
		assert(!is_long_overflow);
		test_3.skipNumber(is_float, is_long_overflow);
		assert(is_long_overflow);
	}
}

/// private
private string skipJsonString(R)(ref R s, int* line = null)
{
	// TODO: count or disallow any newlines inside of the string
	enforceJson(!s.empty && s.front == '"', "Expected '\"' to start string.");
	s.popFront();
	string ret = jsonUnescape(s);
	enforceJson(!s.empty && s.front == '"', "Expected '\"' to terminate string.");
	s.popFront();
	return ret;
}

/// private
private void skipWhitespace(R)(ref R s, int* line = null)
{
	while (!s.empty) {
		switch (s.front) {
			default: return;
			case ' ', '\t': s.popFront(); break;
			case '\n':
				s.popFront();
				if (!s.empty && s.front == '\r') s.popFront();
				if (line) (*line)++;
				break;
			case '\r':
				s.popFront();
				if (!s.empty && s.front == '\n') s.popFront();
				if (line) (*line)++;
				break;
		}
	}
}

private bool isDigit(dchar ch) @safe nothrow pure { return ch >= '0' && ch <= '9'; }

private string underscoreStrip(string field_name)
@safe nothrow pure {
	if( field_name.length < 1 || field_name[$-1] != '_' ) return field_name;
	else return field_name[0 .. $-1];
}

/// private
package template isJsonSerializable(T) { enum isJsonSerializable = is(typeof(T.init.toJson()) == Json) && is(typeof(T.fromJson(Json())) == T); }

private void enforceJson(string file = __FILE__, size_t line = __LINE__)(bool cond, lazy string message = "JSON exception")
{
	import vibe.internal.exception : enforce;
	enforce!JSONException(cond, message, file, line);
}

private void enforceJson(string file = __FILE__, size_t line = __LINE__)(bool cond, lazy string message, string err_file, int err_line)
{
	import vibe.internal.exception : enforce;
	enforce!JSONException(cond, format("%s(%s): Error: %s", err_file, err_line+1, message), file, line);
}

private void enforceJson(string file = __FILE__, size_t line = __LINE__)(bool cond, lazy string message, string err_file, int* err_line)
{
	enforceJson!(file, line)(cond, message, err_file, err_line ? *err_line : -1);
}

private auto trustedRange(R)(R range)
{
	static struct Rng {
		private R range;
		@property bool empty() @trusted { return range.empty; }
		@property auto front() @trusted { return range.front; }
		void popFront() @trusted { range.popFront(); }
	}
	return Rng(range);
}

// test for vibe.utils.DictionaryList
@safe unittest {
	import vibe.utils.dictionarylist;

	static assert(isCustomSerializable!(DictionaryList!int));

	DictionaryList!(int, false) b;
	b.addField("a", 1);
	b.addField("A", 2);
	auto app = appender!string();
	serializeToJson(app, b);
	assert(app.data == `[{"key":"a","value":1},{"key":"A","value":2}]`, app.data);

	DictionaryList!(int, true, 2) c;
	c.addField("a", 1);
	c.addField("b", 2);
	c.addField("a", 3);
	c.remove("b");
	auto appc = appender!string();
	serializeToJson(appc, c);
	assert(appc.data == `[{"key":"a","value":1},{"key":"a","value":3}]`, appc.data);
}

// make sure Json is usable for CTFE
@safe unittest {
	static assert(is(typeof({
		struct Test {
			Json object_ = Json.emptyObject;
			Json array   = Json.emptyArray;
		}
	})), "CTFE for Json type failed.");

	static Json test() {
		Json j;
		j = Json(42);
		j = Json([Json(true)]);
		j = Json(["foo": Json(null)]);
		j = Json("foo");
		return j;
	}
	enum j = test();
	static assert(j == Json("foo"));
}

@safe unittest { // XSS prevention
	assert(Json("</script>some/path").toString() == `"<\/script>some/path"`);
	assert(serializeToJsonString("</script>some/path") == `"<\/script>some/path"`);
}

@system unittest { // Recursive structures
	static struct Bar { Bar[] foos; int i; }
	auto b = deserializeJson!Bar(`{"i":1,"foos":[{"foos":[],"i":2}]}`);
	assert(b.i == 1);
	assert(b.foos.length == 1);
	assert(b.foos[0].i == 2);
	assert(b.foos[0].foos.length == 0);
}

@safe unittest { // Json <-> std.json.JSONValue
	auto astr = `{
		"null": null,
		"string": "Hello",
		"integer": 123456,
		"uinteger": 18446744073709551614,
		"float": 12.34,
		"object": { "hello": "world" },
		"array": [1, 2, "string"],
		"true": true,
		"false": false
	}`;
	auto a = parseJsonString(astr);

	// test JSONValue -> Json conversion
	assert(Json(cast(JSONValue)a) == a);

	// test Json -> JSONValue conversion
	auto v = cast(JSONValue)a;
	assert(deserializeJson!JSONValue(serializeToJson(v)) == v);

	// test JSON strint <-> JSONValue serialization
	assert(deserializeJson!JSONValue(astr) == v);
	assert(parseJsonString(serializeToJsonString(v)) == a);

	// test using std.conv for the conversion
	import std.conv : to;
	assert(a.to!JSONValue.to!Json == a);
	assert(to!Json(to!JSONValue(a)) == a);
}

@safe unittest { // issue #2150 - serialization of const/mutable strings + wide character strings
	assert(serializeToJson(cast(const(char)[])"foo") == Json("foo"));
	assert(serializeToJson("foo".dup) == Json("foo"));
	assert(deserializeJson!string(Json("foo")) == "foo");
	assert(deserializeJson!string(Json([Json("f"), Json("o"), Json("o")])) == "foo");
	assert(serializeToJsonString(cast(const(char)[])"foo") == "\"foo\"");
	assert(deserializeJson!string("\"foo\"") == "foo");

	assert(serializeToJson(cast(const(wchar)[])"foo"w) == Json("foo"));
	assert(serializeToJson("foo"w.dup) == Json("foo"));
	assert(deserializeJson!wstring(Json("foo")) == "foo");
	assert(deserializeJson!wstring(Json([Json("f"), Json("o"), Json("o")])) == "foo");
	assert(serializeToJsonString(cast(const(wchar)[])"foo"w) == "\"foo\"");
	assert(deserializeJson!wstring("\"foo\"") == "foo");

	assert(serializeToJson(cast(const(dchar)[])"foo"d) == Json("foo"));
	assert(serializeToJson("foo"d.dup) == Json("foo"));
	assert(deserializeJson!dstring(Json("foo")) == "foo");
	assert(deserializeJson!dstring(Json([Json("f"), Json("o"), Json("o")])) == "foo");
	assert(serializeToJsonString(cast(const(dchar)[])"foo"d) == "\"foo\"");
	assert(deserializeJson!dstring("\"foo\"") == "foo");
}
