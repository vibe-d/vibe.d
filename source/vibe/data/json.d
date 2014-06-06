/**
	JSON serialization and value handling.

	This module provides the Json struct for reading, writing and manipulating JSON values in a seamless,
	JavaScript like way. De(serialization) of arbitrary D types is also supported.

	Examples:

	---
	void manipulateJson(Json j)
	{
		// object members can be accessed using member syntax, just like in JavaScript
		j = Json.emptyObject;
		j.name = "Example";
		j.id = 1;

		// retrieving the values is done using get()
		assert(j["name"].get!string == "Example");
		assert(j["id"].get!int == 1);

		// semantic conversions can be done using to()
		assert(j.id.to!string == "1");

		// prints:
		// name: "Example"
		// id: 1
		foreach( string key, value; j ){
			writefln("%s: %s", key, value);
		}

		// print out as JSON: {"name": "Example", "id": 1}
		writefln("JSON: %s", j.toString());
	}
	---

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.data.json;

public import vibe.data.serialization;

public import std.json : JSONException;
import std.algorithm : equal, min;
import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.format;
import std.string;
import std.range;
import std.traits;


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
struct Json {
	private {
		// putting all fields in a union results in many false pointers leading to
		// memory leaks and, worse, std.algorithm.swap triggering an assertion
		// because of internal pointers. This crude workaround seems to fix
		// the issues.
		void*[2] m_data;
		ref inout(T) getDataAs(T)() inout { static assert(T.sizeof <= m_data.sizeof); return *cast(inout(T)*)m_data.ptr; }
		@property ref inout(long) m_int() inout { return getDataAs!long(); }
		@property ref inout(double) m_float() inout { return getDataAs!double(); }
		@property ref inout(bool) m_bool() inout { return getDataAs!bool(); }
		@property ref inout(string) m_string() inout { return getDataAs!string(); }
		@property ref inout(Json[string]) m_object() inout { return getDataAs!(Json[string])(); }
		@property ref inout(Json[]) m_array() inout { return getDataAs!(Json[])(); }

		Type m_type = Type.undefined;

		version (VibeJsonFieldNames) {
			uint m_magic = 0x1337f00d; // works around Appender bug (DMD BUG 10690/10859/11357)
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
	this(typeof(null)) { m_type = Type.null_; }
	/// ditto
	this(bool v) { m_type = Type.bool_; m_bool = v; }
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
	this(long v) { m_type = Type.int_; m_int = v; }
	/// ditto
	this(double v) { m_type = Type.float_; m_float = v; }
	/// ditto
	this(string v) { m_type = Type.string; m_string = v; }
	/// ditto
	this(Json[] v) { m_type = Type.array; m_array = v; }
	/// ditto
	this(Json[string] v) { m_type = Type.object; m_object = v; }

	/**
		Allows assignment of D values to a JSON value.
	*/
	ref Json opAssign(Json v)
	{
		m_type = v.m_type;
		final switch(m_type){
			case Type.undefined: m_string = null; break;
			case Type.null_: m_string = null; break;
			case Type.bool_: m_bool = v.m_bool; break;
			case Type.int_: m_int = v.m_int; break;
			case Type.float_: m_float = v.m_float; break;
			case Type.string: m_string = v.m_string; break;
			case Type.array: opAssign(v.m_array); break;
			case Type.object: opAssign(v.m_object); break;
		}
		return this;
	}
	/// ditto
	void opAssign(typeof(null)) { m_type = Type.null_; m_string = null; }
	/// ditto
	bool opAssign(bool v) { m_type = Type.bool_; m_bool = v; return v; }
	/// ditto
	int opAssign(int v) { m_type = Type.int_; m_int = v; return v; }
	/// ditto
	long opAssign(long v) { m_type = Type.int_; m_int = v; return v; }
	/// ditto
	double opAssign(double v) { m_type = Type.float_; m_float = v; return v; }
	/// ditto
	string opAssign(string v) { m_type = Type.string; m_string = v; return v; }
	/// ditto
	Json[] opAssign(Json[] v)
	{
		m_type = Type.array;
		m_array = v;
		version (VibeJsonFieldNames) { if (m_magic == 0x1337f00d) { foreach (idx, ref av; m_array) av.m_name = format("%s[%s]", m_name, idx); } else m_name = null; }
		return v;
	}
	/// ditto
	Json[string] opAssign(Json[string] v)
	{
		m_type = Type.object;
		m_object = v;
		version (VibeJsonFieldNames) { if (m_magic == 0x1337f00d) { foreach (key, ref av; m_object) av.m_name = format("%s.%s", m_name, key); } else m_name = null; }
		return v;
	}

	/**
		Allows removal of values from Type.Object Json objects.
	*/
	void remove(string item) { checkType!(Json[string])(); m_object.remove(item); }

	/**
		The current type id of this JSON object.
	*/
	@property Type type() const { return m_type; }

	/**
		Allows direct indexing of array typed JSON values.
	*/
	ref inout(Json) opIndex(size_t idx) inout { checkType!(Json[])(); return m_array[idx]; }

	/**
		Allows direct indexing of object typed JSON values using a string as
		the key.
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
		assert(m_object !is null);
		assert(key in m_object, "Failed to insert key '"~key~"' into AA!?");
		m_object[key].m_type = Type.undefined; // DMDBUG: AAs are teh $H1T!!!11
		assert(m_object[key].type == Type.undefined);
		m_object[key].m_string = key;
		version (VibeJsonFieldNames) m_object[key].m_name = format("%s.%s", m_name, key);
		return m_object[key];
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
	const {
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
	int opApply(int delegate(ref Json obj) del)
	{
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
	int opApply(int delegate(ref const Json obj) del)
	const {
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
	int opApply(int delegate(ref size_t idx, ref Json obj) del)
	{
		checkType!(Json[])("opApply");
		foreach( idx, ref v; m_array )
			if( auto ret = del(idx, v) )
				return ret;
		return 0;
	}
	/// ditto
	int opApply(int delegate(ref size_t idx, ref const Json obj) del)
	const {
		checkType!(Json[])("opApply");
		foreach( idx, ref v; m_array )
			if( auto ret = del(idx, v) )
				return ret;
		return 0;
	}
	/// ditto
	int opApply(int delegate(ref string idx, ref Json obj) del)
	{
		checkType!(Json[string])("opApply");
		foreach( idx, ref v; m_object )
			if( v.type != Type.undefined )
				if( auto ret = del(idx, v) )
					return ret;
		return 0;
	}
	/// ditto
	int opApply(int delegate(ref string idx, ref const Json obj) del)
	const {
		checkType!(Json[string])("opApply");
		foreach( idx, ref v; m_object )
			if( v.type != Type.undefined )
				if( auto ret = del(idx, v) )
					return ret;
		return 0;
	}

	/**
		Converts the JSON value to the corresponding D type - types must match exactly.
	*/
	inout(T) opCast(T)() inout { return get!T; }
	/// ditto
	@property inout(T) get(T)()
	inout {
		checkType!T();
		static if (is(T == bool)) return m_bool;
		else static if (is(T == double)) return m_float;
		else static if (is(T == float)) return cast(T)m_float;
		else static if (is(T == long)) return m_int;
		else static if (is(T == ulong)) return cast(ulong)m_int;
		else static if (is(T : long)){ enforceJson(m_int <= T.max && m_int >= T.min); return cast(T)m_int; }
		else static if (is(T == string)) return m_string;
		else static if (is(T == Json[])) return m_array;
		else static if (is(T == Json[string])) return m_object;
		else static assert("JSON can only be casted to (bool, long, double, string, Json[] or Json[string]. Not "~T.stringof~".");
	}
	/// ditto
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
	*/
	@property inout(T) to(T)()
	inout {
		static if( is(T == bool) ){
			final switch( m_type ){
				case Type.undefined: return false;
				case Type.null_: return false;
				case Type.bool_: return m_bool;
				case Type.int_: return m_int != 0;
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
				case Type.float_: return m_float;
				case Type.string: return .to!float(cast(string)m_string);
				case Type.array: return float.init;
				case Type.object: return float.init;
			}
		}
		else static if( is(T == long) ){
			final switch( m_type ){
				case Type.undefined: return 0;
				case Type.null_: return 0;
				case Type.bool_: return m_bool ? 1 : 0;
				case Type.int_: return m_int;
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
		} else static assert("JSON can only be casted to (bool, long, double, string, Json[] or Json[string]. Not "~T.stringof~".");
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
			checkType!(long, double)("unary "~op);
			if( m_type == Type.int_ ) mixin("return Json("~op~"m_int);");
			else if( m_type == Type.float_ ) mixin("return Json("~op~"m_float);");
			else assert(false);
		} else static assert("Unsupported operator '"~op~"' for type JSON.");
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
			checkType!(long, double)(op);
			if( m_type == Type.Int ) return Json(m_int + other.m_int);
			else if( m_type == Type.float_ ) return Json(m_float + other.m_float);
			else assert(false);
		} else static if( op == "-" ){
			checkType!(long, double)(op);
			if( m_type == Type.Int ) return Json(m_int - other.m_int);
			else if( m_type == Type.float_ ) return Json(m_float - other.m_float);
			else assert(false);
		} else static if( op == "*" ){
			checkType!(long, double)(op);
			if( m_type == Type.Int ) return Json(m_int * other.m_int);
			else if( m_type == Type.float_ ) return Json(m_float * other.m_float);
			else assert(false);
		} else static if( op == "/" ){
			checkType!(long, double)(op);
			if( m_type == Type.Int ) return Json(m_int / other.m_int);
			else if( m_type == Type.float_ ) return Json(m_float / other.m_float);
			else assert(false);
		} else static if( op == "%" ){
			checkType!(long, double)(op);
			if( m_type == Type.Int ) return Json(m_int % other.m_int);
			else if( m_type == Type.float_ ) return Json(m_float % other.m_float);
			else assert(false);
		} else static if( op == "~" ){
			checkType!(string, Json[])(op);
			if( m_type == Type.string ) return Json(m_string ~ other.m_string);
			else if (m_type == Type.array) return Json(m_array ~ other.m_array);
			else assert(false);
		} else static assert("Unsupported operator '"~op~"' for type JSON.");
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
		} else static assert("Unsupported operator '"~op~"' for type JSON.");
	}
	/// ditto
	void opOpAssign(string op)(Json other)
		if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op =="~")
	{
		enforceJson(m_type == other.m_type || op == "~" && m_type == Type.array,
				"Binary operation '"~op~"=' between "~.to!string(m_type)~" and "~.to!string(other.m_type)~" JSON objects.");
		static if( op == "+" ){
			if( m_type == Type.int_ ) m_int += other.m_int;
			else if( m_type == Type.float_ ) m_float += other.m_float;
			else enforceJson(false, "'+=' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "-" ){
			if( m_type == Type.int_ ) m_int -= other.m_int;
			else if( m_type == Type.float_ ) m_float -= other.m_float;
			else enforceJson(false, "'-=' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "*" ){
			if( m_type == Type.int_ ) m_int *= other.m_int;
			else if( m_type == Type.float_ ) m_float *= other.m_float;
			else enforceJson(false, "'*=' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "/" ){
			if( m_type == Type.int_ ) m_int /= other.m_int;
			else if( m_type == Type.float_ ) m_float /= other.m_float;
			else enforceJson(false, "'/=' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "%" ){
			if( m_type == Type.int_ ) m_int %= other.m_int;
			else if( m_type == Type.float_ ) m_float %= other.m_float;
			else enforceJson(false, "'%=' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "~" ){
			if (m_type == Type.string) m_string ~= other.m_string;
			else if (m_type == Type.array) {
				if (other.m_type == Type.array) m_array ~= other.m_array;
				else m_array ~= other;
			} else enforceJson(false, "'~=' only allowed for string and array types, not "~.to!string(m_type)~".");
		} else static assert("Unsupported operator '"~op~"=' for type JSON.");
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
	Json opBinary(string op)(long other) const { checkType!long(); mixin("return Json(m_int "~op~" other);"); }
	/// ditto
	Json opBinary(string op)(double other) const { checkType!double(); mixin("return Json(m_float "~op~" other);"); }
	/// ditto
	Json opBinary(string op)(string other) const { checkType!string(); mixin("return Json(m_string "~op~" other);"); }
	/// ditto
	Json opBinary(string op)(Json[] other) { checkType!(Json[])(); mixin("return Json(m_array "~op~" other);"); }
	/// ditto
	Json opBinaryRight(string op)(bool other) const { checkType!bool(); mixin("return Json(other "~op~" m_bool);"); }
	/// ditto
	Json opBinaryRight(string op)(long other) const { checkType!long(); mixin("return Json(other "~op~" m_int);"); }
	/// ditto
	Json opBinaryRight(string op)(double other) const { checkType!double(); mixin("return Json(other "~op~" m_float);"); }
	/// ditto
	Json opBinaryRight(string op)(string other) const if(op == "~") { checkType!string(); return Json(other ~ m_string); }
	/// ditto
	inout(Json)* opBinaryRight(string op)(string other) inout if(op == "in") {
		checkType!(Json[string])();
		auto pv = other in m_object;
		if( !pv ) return null;
		if( pv.type == Type.undefined ) return null;
		return pv;
	}
	/// ditto
	Json opBinaryRight(string op)(Json[] other) { checkType!(Json[])(); mixin("return Json(other "~op~" m_array);"); }

	/**
		Allows to access existing fields of a JSON object using dot syntax.
	*/
	@property const(Json) opDispatch(string prop)() const { return opIndex(prop); }
	/// ditto
	@property ref Json opDispatch(string prop)() { return opIndex(prop); }

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
	bool opEquals(long v) const { return m_type == Type.int_ && m_int == v; }
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
		else static if( is(T == Json[]) ) return Type.array;
		else static if( is(T == Json[string]) ) return Type.object;
		else static assert(false, "Unsupported JSON type '"~T.stringof~"'. Only bool, long, double, string, Json[] and Json[string] are allowed.");
	}

	/**
		Returns the JSON object as a string.

		For large JSON values use writeJsonString instead as this function will store the whole string
		in memory, whereas writeJsonString writes it out bit for bit.

		See_Also: writeJsonString, toPrettyString
	*/
	string toString()
	const {
		auto ret = appender!string();
		writeJsonString(ret, this);
		return ret.data;
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
	const {
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

	/*invariant()
	{
		assert(m_type >= Type.Undefined && m_type <= Type.Object);
	}*/
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
Json parseJson(R)(ref R range, int* line = null)
	if( is(R == string) )
{
	Json ret;
	enforceJson(!range.empty, "JSON string is empty.");

	skipWhitespace(range, line);

	version(JsonLineNumbers){
		import vibe.core.log;
		int curline = line ? *line : 0;
		scope(failure) logError("Error in line: %d", curline);
	}

	switch( range.front ){
		case 'f':
			enforceJson(range[1 .. $].startsWith("alse"), "Expected 'false', got '"~range[0 .. min(5, $)]~"'.");
			range.popFrontN(5);
			ret = false;
			break;
		case 'n':
			enforceJson(range[1 .. $].startsWith("ull"), "Expected 'null', got '"~range[0 .. min(4, $)]~"'.");
			range.popFrontN(4);
			ret = null;
			break;
		case 't':
			enforceJson(range[1 .. $].startsWith("rue"), "Expected 'true', got '"~range[0 .. min(4, $)]~"'.");
			range.popFrontN(4);
			ret = true;
			break;
		case '0': .. case '9'+1:
		case '-':
			bool is_float;
			auto num = skipNumber(range, is_float);
			if( is_float ) ret = to!double(num);
			else ret = to!long(num);
			break;
		case '\"':
			ret = skipJsonString(range);
			break;
		case '[':
			Json[] arr;
			range.popFront();
			while(true) {
				skipWhitespace(range, line);
				enforceJson(!range.empty);
				if(range.front == ']') break;
				arr ~= parseJson(range, line);
				skipWhitespace(range, line);
				enforceJson(!range.empty && (range.front == ',' || range.front == ']'), "Expected ']' or ','.");
				if( range.front == ']' ) break;
				else range.popFront();
			}
			range.popFront();
			ret = arr;
			break;
		case '{':
			Json[string] obj;
			range.popFront();
			while(true) {
				skipWhitespace(range, line);
				enforceJson(!range.empty);
				if(range.front == '}') break;
				string key = skipJsonString(range);
				skipWhitespace(range, line);
				enforceJson(range.startsWith(":"), "Expected ':' for key '" ~ key ~ "'");
				range.popFront();
				skipWhitespace(range, line);
				Json itm = parseJson(range, line);
				obj[key] = itm;
				skipWhitespace(range, line);
				enforceJson(!range.empty && (range.front == ',' || range.front == '}'), "Expected '}' or ',' - got '"~range[0]~"'.");
				if( range.front == '}' ) break;
				else range.popFront();
			}
			range.popFront();
			ret = obj;
			break;
		default:
			enforceJson(false, "Expected valid json token, got '"~to!string(range.length)~range[0 .. min(12, $)]~"'.");
	}

	assert(ret.type != Json.Type.undefined);
	version(JsonLineNumbers) ret.line = curline;
	return ret;
}

/**
	Parses the given JSON string and returns the corresponding Json object.

	Throws a JSONException if any parsing error occurs.
*/
Json parseJsonString(string str)
{
	auto strcopy = str;
	try {
		auto ret = parseJson(strcopy);
		enforceJson(strcopy.strip().length == 0, "Expected end of string after JSON value.");
		return ret;
	} catch (Exception e) {
		throw new JSONException(format("JSON format error at byte %s: %s", str.length - strcopy.length, e.msg));
	}
}

unittest {
	assert(parseJsonString("null") == Json(null));
	assert(parseJsonString("true") == Json(true));
	assert(parseJsonString("false") == Json(false));
	assert(parseJsonString("1") == Json(1));
	assert(parseJsonString("2.0") == Json(2.0));
	assert(parseJsonString("\"test\"") == Json("test"));
	assert(parseJsonString("[1, 2, 3]") == Json([Json(1), Json(2), Json(3)]));
	assert(parseJsonString("{\"a\": 1}") == Json(["a": Json(1)]));
	assert(parseJsonString(`"\\\/\b\f\n\r\t\u1234"`).get!string == "\\/\b\f\n\r\t\u1234");
}


/**
	Serializes the given value to JSON.

	The following types of values are supported:

	$(DL
		$(DT Json)            $(DD Used as-is)
		$(DT null)            $(DD Converted to Json.Type.Null)
		$(DT bool)            $(DD Converted to Json.Type.Bool)
		$(DT float, double)   $(DD Converted to Json.Type.Double)
		$(DT short, ushort, int, uint, long, ulong) $(DD Converted to Json.Type.Int)
		$(DT string)          $(DD Converted to Json.Type.String)
		$(DT T[])             $(DD Converted to Json.Type.Array)
		$(DT T[string])       $(DD Converted to Json.Type.Object)
		$(DT struct)          $(DD Converted to Json.Type.Object)
		$(DT class)           $(DD Converted to Json.Type.Object or Json.Type.Null)
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
	the type will be used for serialization (i.e. toJson overrides toString).
*/
Json serializeToJson(T)(T value)
{
	version (VibeOldSerialization) {
		return serializeToJsonOld(value);
	} else {
		return serialize!JsonSerializer(value);
	}
}
/// ditto
void serializeToJson(R, T)(R destination, T value)
	if (isOutputRange!(R, char) || isOutputRange!(R, ubyte))
{
	serialize!(JsonStringSerializer!R)(value, destination);
}

/// private
Json serializeToJsonOld(T)(T value)
{
	alias Unqual!T TU;
	static if (is(TU == Json)) return value;
	else static if (is(TU == typeof(null))) return Json(null);
	else static if (is(TU == bool)) return Json(value);
	else static if (is(TU == float)) return Json(cast(double)value);
	else static if (is(TU == double)) return Json(value);
	else static if (is(TU == DateTime)) return Json(value.toISOExtString());
	else static if (is(TU == SysTime)) return Json(value.toISOExtString());
	else static if (is(TU == Date)) return Json(value.toISOExtString());
	else static if (is(TU : long)) return Json(cast(long)value);
	else static if (is(TU : string)) return Json(value);
	else static if (isArray!T) {
		auto ret = new Json[value.length];
		foreach (i; 0 .. value.length)
			ret[i] = serializeToJson(value[i]);
		return Json(ret);
	} else static if (isAssociativeArray!TU) {
		Json[string] ret;
		alias KeyType!T TK;
		foreach (key, value; value) {
			static if(is(TK == string)) {
				ret[key] = serializeToJson(value);
			} else static if (is(TK == enum)) {
				ret[to!string(key)] = serializeToJson(value);
			} else static if (isStringSerializable!(TK)) {
				ret[key.toString()] = serializeToJson(value);
			} else static assert("AA key type %s not supported for JSON serialization.");
		}
		return Json(ret);
	} else static if (isJsonSerializable!TU) {
		return value.toJson();
	} else static if (isStringSerializable!TU) {
		return Json(value.toString());
	} else static if (is(TU == struct)) {
		Json[string] ret;
		foreach (m; __traits(allMembers, T)) {
			static if (isRWField!(TU, m)) {
				auto mv = __traits(getMember, value, m);
				ret[underscoreStrip(m)] = serializeToJson(mv);
			}
		}
		return Json(ret);
	} else static if(is(TU == class)) {
		if (value is null) return Json(null);
		Json[string] ret;
		foreach (m; __traits(allMembers, T)) {
			static if (isRWField!(TU, m)) {
				auto mv = __traits(getMember, value, m);
				ret[underscoreStrip(m)] = serializeToJson(mv);
			}
		}
		return Json(ret);
	} else static if (isPointer!TU) {
		if (value is null) return Json(null);
		return serializeToJson(*value);
	} else {
		static assert(false, "Unsupported type '"~T.stringof~"' for JSON serialization.");
	}
}


/**
	Deserializes a JSON value into the destination variable.

	The same types as for serializeToJson() are supported and handled inversely.
*/
void deserializeJson(T)(ref T dst, Json src)
{
	dst = deserializeJson!T(src);
}
/// ditto
T deserializeJson(T)(Json src)
{
	version (VibeOldSerialization) {
		return deserializeJsonOld!T(src);
	} else {
		return deserialize!(JsonSerializer, T)(src);
	}
}
/// ditto
T deserializeJson(T, R)(R input)
	if (isInputRange!R && !is(R == Json))
{
	return deserialize!(JsonStringSerializer!R, T)(input);
}

/// private
T deserializeJsonOld(T)(Json src)
{
	static if( is(T == struct) || isSomeString!T || isIntegral!T || isFloatingPoint!T ) 
		if( src.type == Json.Type.null_ ) return T.init;
	static if (is(T == Json)) return src;
	else static if (is(T == typeof(null))) { return null; }
	else static if (is(T == bool)) return src.get!bool;
	else static if (is(T == float)) return src.to!float;   // since doubles are frequently serialized without
	else static if (is(T == double)) return src.to!double; // a decimal point, we allow conversions here
	else static if (is(T == DateTime)) return DateTime.fromISOExtString(src.get!string);
	else static if (is(T == SysTime)) return SysTime.fromISOExtString(src.get!string);
	else static if (is(T == Date)) return Date.fromISOExtString(src.get!string);
	else static if (is(T : long)) return cast(T)src.get!long;
	else static if (is(T : string)) return cast(T)src.get!string;
	else static if (isArray!T) {
		alias typeof(T.init[0]) TV;
		auto dst = new Unqual!TV[src.length];
		foreach (size_t i, v; src)
			dst[i] = deserializeJson!(Unqual!TV)(v);
		return cast(T)dst;
	} else static if( isAssociativeArray!T ) {
		alias typeof(T.init.values[0]) TV;
		alias KeyType!T TK;
		Unqual!TV[TK] dst;
		foreach (string key, value; src) {
			static if (is(TK == string)) {
				dst[key] = deserializeJson!(Unqual!TV)(value);
			} else static if (is(TK == enum)) { 
				dst[to!(TK)(key)] = deserializeJson!(Unqual!TV)(value);
			} else static if (isStringSerializable!TK) {
				auto dsk = TK.fromString(key);
				dst[dsk] = deserializeJson!(Unqual!TV)(value);
			} else static assert("AA key type %s not supported for JSON serialization.");
		}
		return dst;
	} else static if (isJsonSerializable!T) {
		return T.fromJson(src);
	} else static if (isStringSerializable!T) {
		return T.fromString(src.get!string);
	} else static if (is(T == struct)) {
		T dst;
		foreach (m; __traits(allMembers, T)) {
			static if (isRWPlainField!(T, m) || isRWField!(T, m)) {
				alias typeof(__traits(getMember, dst, m)) TM;
				__traits(getMember, dst, m) = deserializeJson!TM(src[underscoreStrip(m)]);
			}
		}
		return dst;
	} else static if (is(T == class)) {
		if (src.type == Json.Type.null_) return null;
		auto dst = new T;
		foreach (m; __traits(allMembers, T)) {
			static if (isRWPlainField!(T, m) || isRWField!(T, m)) {
				alias typeof(__traits(getMember, dst, m)) TM;
				__traits(getMember, dst, m) = deserializeJson!TM(src[underscoreStrip(m)]);
			}
		}
		return dst;
	} else static if (isPointer!T) {
		if (src.type == Json.Type.null_) return null;
		alias typeof(*T.init) TD;
		dst = new TD;
		*dst = deserializeJson!TD(src);
		return dst;
	} else {
		static assert(false, "Unsupported type '"~T.stringof~"' for JSON serialization.");
	}
}

unittest {
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

unittest
{
	assert(uint.max == serializeToJson(uint.max).deserializeJson!uint);
	assert(ulong.max == serializeToJson(ulong.max).deserializeJson!ulong);
}

unittest {
	static struct A { int value; static A fromJson(Json val) { return A(val.get!int); } Json toJson() const { return Json(value); } }
	static struct C { int value; static C fromString(string val) { return C(val.to!int); } string toString() const { return value.to!string; } }
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
	static struct C { int value; static C fromString(string val) { return C(val.to!int); } string toString() const { return value.to!string; } }
	enum Color { Red, Green, Blue }
	{
		static class T {
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


/**
	Serializer for a plain Json representation.

	See_Also: vibe.data.serialization.serialize, vibe.data.serialization.deserialize, serializeToJson, deserializeJson
*/
struct JsonSerializer {
	template isJsonBasicType(T) { enum isJsonBasicType = is(T : long) || is(T : double) || is(T == string) || is(T == typeof(null)) || isJsonSerializable!T; }
	
	template isSupportedValueType(T) { enum isSupportedValueType = isJsonBasicType!T || is(T == Json); }

	private {
		Json m_current;
		Json[] m_compositeStack;
	}

	this(Json data) { m_current = data; }

	@disable this(this);

	//
	// serialization
	//
	Json getSerializedResult() { return m_current; }
	void beginWriteDictionary(T)() { m_compositeStack ~= Json.emptyObject; }
	void endWriteDictionary(T)() { m_current = m_compositeStack[$-1]; m_compositeStack.length--; }
	void beginWriteDictionaryEntry(T)(string name) {}
	void endWriteDictionaryEntry(T)(string name) { m_compositeStack[$-1][name] = m_current; }

	void beginWriteArray(T)(size_t) { m_compositeStack ~= Json.emptyArray; }
	void endWriteArray(T)() { m_current = m_compositeStack[$-1]; m_compositeStack.length--; }
	void beginWriteArrayEntry(T)(size_t) {}
	void endWriteArrayEntry(T)(size_t) { m_compositeStack[$-1] ~= m_current; }

	void writeValue(T)(T value)
	{
		static if (is(T == Json)) m_current = value;
		else static if (isJsonSerializable!T) m_current = value.toJson();
		else m_current = Json(value);
	}

	//
	// deserialization
	//
	void readDictionary(T)(scope void delegate(string) field_handler)
	{
		enforceJson(m_current.type == Json.Type.object);
		auto old = m_current;
		foreach (string key, value; m_current) {
			m_current = value;
			field_handler(key);
		}
		m_current = old;
	}

	void readArray(T)(scope void delegate(size_t) size_callback, scope void delegate() entry_callback)
	{
		enforceJson(m_current.type == Json.Type.array);
		auto old = m_current;
		size_callback(m_current.length);
		foreach (ent; old) {
			m_current = ent;
			entry_callback();
		}
		m_current = old;
	}

	T readValue(T)()
	{
		static if (is(T == Json)) return m_current;
		else static if (isJsonSerializable!T) return T.fromJson(m_current);
		else static if (is(T == float) || is(T == double)) return m_current.type == Json.Type.float_ ? cast(T)m_current.get!double : cast(T)m_current.get!long;
		else return m_current.get!T();
	}

	bool tryReadNull() { return m_current.type == Json.Type.null_; }
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

	template isJsonBasicType(T) { enum isJsonBasicType = is(T : long) || is(T : real) || is(T == string) || is(T == typeof(null)) || isJsonSerializable!T; }
	
	template isSupportedValueType(T) { enum isSupportedValueType = isJsonBasicType!T || is(T == Json); }

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

		void beginWriteDictionary(T)() { startComposite(); m_range.put('{'); }
		void endWriteDictionary(T)() { endComposite(); m_range.put("}"); }
		void beginWriteDictionaryEntry(T)(string name)
		{
			startCompositeEntry();
			m_range.put('"');
			m_range.jsonEscape(name);
			static if (pretty) m_range.put(`": `);
			else m_range.put(`":`);
		}
		void endWriteDictionaryEntry(T)(string name) {}

		void beginWriteArray(T)(size_t) { startComposite(); m_range.put('['); }
		void endWriteArray(T)() { endComposite(); m_range.put(']'); }
		void beginWriteArrayEntry(T)(size_t) { startCompositeEntry(); }
		void endWriteArrayEntry(T)(size_t) {}

		void writeValue(T)(T value)
		{
			static if (is(T == typeof(null))) m_range.put("null");
			else static if (is(T == bool)) m_range.put(value ? "true" : "false");
			else static if (is(T : long)) m_range.formattedWrite("%s", value);
			else static if (is(T : real)) m_range.formattedWrite("%s", value);
			else static if (is(T == string)) {
				m_range.put('"');
				m_range.jsonEscape(value);
				m_range.put('"');
			}
			else static if (is(T == Json)) m_range.writeJsonString(value);
			else static if (isJsonSerializable!T) m_range.writeJsonString!(R, pretty)(value.toJson(), m_level);
			else static assert(false, "Unsupported type: " ~ T.stringof);
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

		void readDictionary(T)(scope void delegate(string) entry_callback)
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
				enforceJson(!m_range.empty && m_range.front == ':');
				m_range.popFront();

				entry_callback(name);
			}
		}

		void readArray(T)(scope void delegate(size_t) size_callback, scope void delegate() entry_callback)
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

		T readValue(T)()
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
				auto num = m_range.skipNumber(is_float);
				enforceJson(!is_float, "Expecing integer number.");
				return to!T(num);
			} else static if (is(T : real)) {
				bool is_float;
				auto num = m_range.skipNumber(is_float);
				return to!T(num);
			}
			else static if (is(T == string)) return m_range.skipJsonString(&m_line);
			else static if (is(T == Json)) return m_range.parseJson(&m_line);
			else static if (isJsonSerializable!T) return T.fromJson(m_range.parseJson(&m_line));
			else static assert(false, "Unsupported type: " ~ T.stringof);
		}

		bool tryReadNull()
		{
			m_range.skipWhitespace(&m_line);
			if (m_range.front != 'n') return false;
			static if (is(R == string)) {
				import vibe.core.log;
				logInfo("%s", m_range[0 .. min(4, $)]);
			}
			foreach (ch; "null") {
				enforceJson(m_range.front == ch, "Expecting 'null'.");
				m_range.popFront();
			}
			assert(m_range.empty || m_range.front != 'l');
			return true;
		}
	}
}



/**
	Writes the given JSON object as a JSON string into the destination range.

	This function will convert the given JSON value to a string without adding
	any white space between tokens (no newlines, no indentation and no padding).
	The output size is thus minimized, at the cost of bad human readability.

	Params:
		dst   = References the string output range to which the result is written.
		json  = Specifies the JSON value that is to be stringified.

	See_Also: Json.toString, writePrettyJsonString
*/
void writeJsonString(R, bool pretty = false)(ref R dst, in Json json, size_t level = 0)
//	if( isOutputRange!R && is(ElementEncodingType!R == char) )
{
	final switch( json.type ){
		case Json.Type.undefined: dst.put("undefined"); break;
		case Json.Type.null_: dst.put("null"); break;
		case Json.Type.bool_: dst.put(cast(bool)json ? "true" : "false"); break;
		case Json.Type.int_: formattedWrite(dst, "%d", json.get!long); break;
		case Json.Type.float_: formattedWrite(dst, "%.16g", json.get!double); break;
		case Json.Type.string:
			dst.put('\"');
			jsonEscape(dst, cast(string)json);
			dst.put('\"');
			break;
		case Json.Type.array:
			dst.put('[');
			bool first = true;
			foreach (ref const Json e; json) {
				if( e.type == Json.Type.undefined ) continue;
				if( !first ) dst.put(",");
				first = false;
				static if (pretty) {
					dst.put('\n');
					foreach (tab; 0 .. level+1) dst.put('\t');
				}
				writeJsonString!(R, pretty)(dst, e, level+1);
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
			foreach( string k, ref const Json e; json ){
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
	a.a = Json.emptyArray;
	a.b = Json.emptyArray;
	a.b ~= Json(1);
	a.b ~= Json.emptyObject;

	assert(a.toString() == `{"a":[],"b":[1,{}]}`);
	assert(a.toPrettyString() ==
`{
	"a": [],
	"b": [
		1,
		{}
	]
}`);
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


/// private
private void jsonEscape(R)(ref R dst, string s)
{
	foreach( ch; s ){
		switch(ch){
			default: dst.put(ch); break;
			case '\\': dst.put("\\\\"); break;
			case '\r': dst.put("\\r"); break;
			case '\n': dst.put("\\n"); break;
			case '\t': dst.put("\\t"); break;
			case '\"': dst.put("\\\""); break;
		}
	}
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

/// private
private string skipNumber(R)(ref R s, out bool is_float)
{
	// TODO: make this work with input ranges
	size_t idx = 0;
	is_float = false;
	if (s[idx] == '-') idx++;
	if (s[idx] == '0') idx++;
	else {
		enforceJson(isDigit(s[idx++]), "Digit expected at beginning of number.");
		while( idx < s.length && isDigit(s[idx]) ) idx++;
	}

	if( idx < s.length && s[idx] == '.' ){
		idx++;
		is_float = true;
		while( idx < s.length && isDigit(s[idx]) ) idx++;
	}

	if( idx < s.length && (s[idx] == 'e' || s[idx] == 'E') ){
		idx++;
		is_float = true;
		if( idx < s.length && (s[idx] == '+' || s[idx] == '-') ) idx++;
		enforceJson( idx < s.length && isDigit(s[idx]), "Expected exponent." ~ s[0 .. idx]);
		idx++;
		while( idx < s.length && isDigit(s[idx]) ) idx++;
	}

	string ret = s[0 .. idx];
	s = s[idx .. $];
	return ret;
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

private bool isDigit(dchar ch) { return ch >= '0' && ch <= '9'; }

private string underscoreStrip(string field_name)
{
	if( field_name.length < 1 || field_name[$-1] != '_' ) return field_name;
	else return field_name[0 .. $-1];
}

/// private
package template isJsonSerializable(T) { enum isJsonSerializable = is(typeof(T.init.toJson()) == Json) && is(typeof(T.fromJson(Json())) == T); }

private void enforceJson(string file = __FILE__, size_t line = __LINE__)(bool cond, lazy string message = "JSON exception")
{
	static if (__VERSION__ >= 2065) enforceEx!JSONException(cond, message, file, line);
	else if (!cond) throw new JSONException(message);
}
