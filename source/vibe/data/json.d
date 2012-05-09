/**
	JSON serialization and value handling.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.data.json;

public import vibe.stream.stream;

import std.array;
import std.conv;
import std.exception;
import std.string;
import std.range;
import std.traits;


/******************************************************************************/
/* public types                                                               */
/******************************************************************************/

/**
	Represents a single JSON value.

	JSON values can have one of the types defined in the JSON.Type enum. They
	behave mostly like values in ECMA script in the way that you can
	transparently perform operations on them. However, strict typechecking is
	done, so that operations between differently typed JSON values will throw
	an exception. Additionally, an explicit cast or using get!() or to!() is 
	required to convert a JSON value to the corresponding static D type.
*/
struct Json {
	/** Represents the run time type of a JSON value.
	*/
	enum Type {
		Undefined,
		Null,
		Bool,
		Int,
		Float,
		String,
		Array,
		Object
	}

	static @property Json Undefined() { return Json(); }
	static @property Json EmptyObject() { return Json(cast(Json[string])null); }
	static @property Json EmptyArray() { return Json(cast(Json[])null); }

	private {
		union {
			bool m_bool;
			long m_int;
			double m_float;
			string m_string;
			Json[] m_array;
			Json[string] m_object;
		};
		Type m_type = Type.Undefined;
	}
	version(JsonLineNumbers) int line;

	/**
		Constructor for a JSON object.
	*/
	this(typeof(null)) { m_type = Type.Null; }
	/// ditto
	this(bool v) { m_type = Type.Bool; m_bool = v; }
	/// ditto
	this(int v) { m_type = Type.Int; m_int = v; }
	/// ditto
	this(long v) { m_type = Type.Int; m_int = v; }
	/// ditto
	this(double v) { m_type = Type.Float; m_float = v; }
	/// ditto
	this(string v) { m_type = Type.String; m_string = v; }
	/// ditto
	this(Json[] v) { m_type = Type.Array; m_array = v; }
	/// ditto
	this(Json[string] v) { m_type = Type.Object; m_object = v; }

	/**
		Allows assignment of D values to a JSON value.
	*/
	ref Json opAssign(Json v){
		m_type = v.m_type;
		final switch(m_type){
			case Type.Undefined: m_string = null; break;
			case Type.Null: m_string = null; break;
			case Type.Bool: m_bool = v.m_bool; break;
			case Type.Int: m_int = v.m_int; break;
			case Type.Float: m_float = v.m_float; break;
			case Type.String: m_string = v.m_string; break;
			case Type.Array: m_array = v.m_array; break;
			case Type.Object: m_object = v.m_object; break;
		}
		return this;
	}
	/// ditto
	void opAssign(typeof(null)) { m_type = Type.Null; m_string = null; }
	/// ditto
	bool opAssign(bool v) { m_type = Type.Bool; m_bool = v; return v; }
	/// ditto
	int opAssign(int v) { m_type = Type.Int; m_int = v; return v; }
	/// ditto
	long opAssign(long v) { m_type = Type.Int; m_int = v; return v; }
	/// ditto
	double opAssign(double v) { m_type = Type.Float; m_float = v; return v; }
	/// ditto
	string opAssign(string v) { m_type = Type.String; m_string = v; return v; }
	/// ditto
	Json[] opAssign(Json[] v) { m_type = Type.Array; m_array = v; return v; }
	/// ditto
	Json[string] opAssign(Json[string] v) { m_type = Type.Object; m_object = v; return v; }

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
	const(Json) opIndex(string key) const {
		checkType!(Json[string])();
		if( auto pv = key in m_object ) return *pv;
		Json ret = Json.Undefined;
		return ret;
	}
	/// ditto
	ref Json opIndex(string key){
		checkType!(Json[string])();
		if( auto pv = key in m_object )
			return *pv;
		m_object[key] = Json();
		m_object[key].m_type = Type.Undefined; // DMDBUG: AAs are teh $H1T!!!11
		assert(m_object[key].type == Type.Undefined);
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
		switch(m_type){
			case Type.String: return m_string.length;
			case Type.Array: return m_array.length;
			case Type.Object: return m_object.length;
			default:
				enforce(false, "Json.length() can only be called on strings, arrays and objects, not "~.to!string(m_type)~".");
				return 0;
		}
	}

	/**
		Allows foreach iterating over JSON objects and arrays.
	*/
	int opApply(int delegate(ref Json obj) del)
	{
		enforce(m_type == Type.Array || m_type == Type.Object, "opApply may only be called on objects and arrays, not "~.to!string(m_type)~".");
		if( m_type == Type.Array ){
			foreach( ref v; m_array )
				if( auto ret = del(v) )
					return ret;
			return 0;
		} else {
			foreach( ref v; m_object )
				if( v.type != Type.Undefined )
					if( auto ret = del(v) )
						return ret;
			return 0;
		}
	}
	/// ditto
	int opApply(int delegate(ref const Json obj) del)
	const {
		enforce(m_type == Type.Array || m_type == Type.Object, "opApply may only be called on objects and arrays, not "~.to!string(m_type)~".");
		if( m_type == Type.Array ){
			foreach( ref v; m_array )
				if( auto ret = del(v) )
					return ret;
			return 0;
		} else {
			foreach( ref v; m_object )
				if( v.type != Type.Undefined )
					if( auto ret = del(v) )
						return ret;
			return 0;
		}
	}
	/// ditto
	int opApply(int delegate(ref size_t idx, ref Json obj) del)
	{
		enforce(m_type == Type.Array, "opApply may only be called on arrays, not "~.to!string(m_type)~"");
		foreach( idx, ref v; m_array )
			if( auto ret = del(idx, v) )
				return ret;
		return 0;
	}
	/// ditto
	int opApply(int delegate(ref size_t idx, ref const Json obj) del)
	const {
		enforce(m_type == Type.Array, "opApply may only be called on arrays, not "~.to!string(m_type)~".");
		foreach( idx, ref v; m_array )
			if( auto ret = del(idx, v) )
				return ret;
		return 0;
	}
	/// ditto
	int opApply(int delegate(ref string idx, ref Json obj) del)
	{
		enforce(m_type == Type.Object, "opApply may only be called on objects, not "~.to!string(m_type)~".");
		foreach( idx, ref v; m_object )
			if( v.type != Type.Undefined )
				if( auto ret = del(idx, v) )
					return ret;
		return 0;
	}
	/// ditto
	int opApply(int delegate(ref string idx, ref const Json obj) del)
	const {
		enforce(m_type == Type.Object, "opApply may only be called on objects, not "~.to!string(m_type)~".");
		foreach( idx, ref v; m_object )
			if( v.type != Type.Undefined )
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
		static if( is(T == bool) ) return m_bool;
		else static if( is(T == double) ) return m_float;
		else static if( is(T == float) ) return cast(T)m_float;
		else static if( is(T == long) ) return m_int;
		else static if( is(T : long) ){ enforce(m_int <= T.max && m_int >= T.min); return cast(T)m_int; }
		else static if( is(T == string) ) return m_string;
		else static if( is(T == Json[]) ) return m_array;
		else static if( is(T == Json[string]) ) return m_object;
		else static assert("JSON can only be casted to (bool, long, double, string, JSON[] or JSON[string]. Not "~T.stringof~".");
	}
	/// ditto
	@property const(T) opt(T)(const(T) def = T.init) const { try return get!T; catch(Exception) return def; }
	/// ditto
	@property T opt(T)(T def = T.init) { try return get!T; catch(Exception) return def; }

	/**
		Converts the JSON value to the corresponding D type - types are converted as neccessary.
	*/
	@property inout(T) to(T)()
	inout {
		static if( is(T == bool) ){
			final switch( m_type ){
				case Type.Undefined: return false;
				case Type.Null: return false;
				case Type.Bool: return m_bool;
				case Type.Int: return m_int != 0;
				case Type.Float: return m_float != 0;
				case Type.String: return m_string.length > 0;
				case Type.Array: return m_array.length > 0;
				case Type.Object: return m_object.length > 0;
			}
		} else static if( is(T == double) ){
			final switch( m_type ){
				case Type.Undefined: return T.init;
				case Type.Null: return 0;
				case Type.Bool: return m_bool ? 1 : 0;
				case Type.Int: return m_int;
				case Type.Float: return m_float;
				case Type.String: return .to!double(cast(string)m_string);
				case Type.Array: return double.init;
				case Type.Object: return double.init;
			}
		} else static if( is(T == float) ){
			final switch( m_type ){
				case Type.Undefined: return T.init;
				case Type.Null: return 0;
				case Type.Bool: return m_bool ? 1 : 0;
				case Type.Int: return m_int;
				case Type.Float: return m_float;
				case Type.String: return .to!float(cast(string)m_string);
				case Type.Array: return float.init;
				case Type.Object: return float.init;
			}
		}
		else static if( is(T == long) ){
			final switch( m_type ){
				case Type.Undefined: return 0;
				case Type.Null: return 0;
				case Type.Bool: return m_bool ? 1 : 0;
				case Type.Int: return m_int;
				case Type.Float: return cast(long)m_float;
				case Type.String: return .to!long(m_string);
				case Type.Array: return 0;
				case Type.Object: return 0;
			}
		} else static if( is(T : long) ){
			final switch( m_type ){
				case Type.Undefined: return 0;
				case Type.Null: return 0;
				case Type.Bool: return m_bool ? 1 : 0;
				case Type.Int: return cast(T)m_int;
				case Type.Float: return cast(T)m_float;
				case Type.String: return cast(T).to!long(cast(string)m_string);
				case Type.Array: return 0;
				case Type.Object: return 0;
			}
		} else static if( is(T == string) ){
			switch( m_type ){
				default: return toString();
				case Type.String: return m_string;
			}
		} else static if( is(T == Json[]) ){
			switch( m_type ){
				default: return Json([this]);
				case Type.Array: return m_array;
			}
		} else static if( is(T == Json[string]) ){
			switch( m_type ){
				default: return Json(["value": this]);
				case Type.Object: return m_object;
			}
		} else static assert("JSON can only be casted to (bool, long, double, string, JSON[] or JSON[string]. Not "~T.stringof~".");
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
			if( m_type == Type.Int ) mixin("return JSON("~op~"m_int);");
			else if( m_type == Type.Float ) mixin("return JSON("~op~"m_float);");
			else enforce(false, "'"~op~"' only allowed on scalar types, not on "~.to!string(m_type)~".");
		} else static assert("Unsupported operator '"~op~"' for type JSON.");
	}

	/**
		Performs binary operations between JSON values.

		The two JSON values must be of the same run time type or an exception
		will be thrown. Only the operations listed are allowed for each of the
		types.

		$(DL
			$(DT Null)   $(DD none)
			$(DT Bool)   $(DD &&, ||)
			$(DT Int)    $(DD +, -, *, /, %)
			$(DT Float)  $(DD +, -, *, /, %)
			$(DT String) $(DD ~)
			$(DT Array)  $(DD ~)
			$(DT Object) $(DD none)
		)
	*/
	Json opBinary(string op)(ref const(Json) other)
	const {
		enforce(m_type == other.m_type, "Binary operation '"~op~"' between "~.to!string(m_type)~" and "~.to!string(other.m_type)~" JSON objects.");
		static if( op == "&&" ){
			enforce(m_type == Type.Bool, "'&&' only allowed for Type.Bool, not "~.to!string(m_type)~".");
			return Json(m_bool && other.m_bool);
		} else static if( op == "||" ){
			enforce(m_type == Type.Bool, "'||' only allowed for Type.Bool, not "~.to!string(m_type)~".");
			return Json(m_bool || other.m_bool);
		} else static if( op == "+" ){
			if( m_type == Type.Int ) return Json(m_int + other.m_int);
			else if( m_type == Type.Float ) return Json(m_float + other.m_float);
			else enforce(false, "'+' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "-" ){
			if( m_type == Type.Int ) return Json(m_int - other.m_int);
			else if( m_type == Type.Float ) return Json(m_float - other.m_float);
			else enforce(false, "'-' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "*" ){
			if( m_type == Type.Int ) return Json(m_int * other.m_int);
			else if( m_type == Type.Float ) return Json(m_float * other.m_float);
			else enforce(false, "'*' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "/" ){
			if( m_type == Type.Int ) return Json(m_int / other.m_int);
			else if( m_type == Type.Float ) return Json(m_float / other.m_float);
			else enforce(false, "'/' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "%" ){
			if( m_type == Type.Int ) return Json(m_int % other.m_int);
			else if( m_type == Type.Float ) return Json(m_float % other.m_float);
			else enforce(false, "'%' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "~" ){
			if( m_type == Type.String ) return Json(m_string ~ other.m_string);
			else enforce(false, "'~' only allowed for strings, not "~.to!string(m_type)~".");
		} else static assert("Unsupported operator '"~op~"' for type JSON.");
		assert(false);
	}
	/// ditto
	Json opBinary(string op)(Json other)
		if( op == "~" )
	{
		static if( op == "~" ){
			if( m_type == Type.String ) return Json(m_string ~ other.m_string);
			else if( m_type == Type.Array ) return Json(m_array ~ other.m_array);
			else enforce(false, "'~' only allowed for strings and arrays, not "~.to!string(m_type)~".");
		} else static assert("Unsupported operator '"~op~"' for type JSON.");
		assert(false);
	}
	/// ditto
	void opOpAssign(string op)(Json other)
		if( op == "+" || op == "-" || op == "*" ||op == "/" || op == "%" )
	{
		enforce(m_type == other.m_type, "Binary operation '"~op~"' between "~.to!string(m_type)~" and "~.to!string(other.m_type)~" JSON objects.");
		static if( op == "+" ){
			if( m_type == Type.Int ) m_int += other.m_int;
			else if( m_type == Type.Float ) m_float += other.m_float;
			else enforce(false, "'+' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "-" ){
			if( m_type == Type.Int ) m_int -= other.m_int;
			else if( m_type == Type.Float ) m_float -= other.m_float;
			else enforce(false, "'-' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "*" ){
			if( m_type == Type.Int ) m_int *= other.m_int;
			else if( m_type == Type.Float ) m_float *= other.m_float;
			else enforce(false, "'*' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "/" ){
			if( m_type == Type.Int ) m_int /= other.m_int;
			else if( m_type == Type.Float ) m_float /= other.m_float;
			else enforce(false, "'/' only allowed for scalar types, not "~.to!string(m_type)~".");
		} else static if( op == "%" ){
			if( m_type == Type.Int ) m_int %= other.m_int;
			else if( m_type == Type.Float ) m_float %= other.m_float;
			else enforce(false, "'%' only allowed for scalar types, not "~.to!string(m_type)~".");
		} /*else static if( op == "~" ){
			if( m_type == Type.String ) m_string ~= other.m_string;
			else if( m_type == Type.Array ) m_array ~= other.m_array;
			else enforce(false, "'%' only allowed for scalar types, not "~.to!string(m_type)~".");
		}*/ else static assert("Unsupported operator '"~op~"' for type JSON.");
		assert(false);
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
		if( pv.type == Type.Undefined ) return null;
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
			case Type.Undefined: return false;
			case Type.Null: return true;
			case Type.Bool: return m_bool == other.m_bool;
			case Type.Int: return m_int == other.m_int;
			case Type.Float: return m_float == other.m_float;
			case Type.String: return m_string == other.m_string;
			case Type.Array: return m_array == other.m_array;
			case Type.Object: return m_object == other.m_object;
		}
	}
	/// ditto
	bool opEquals(typeof(null)) const { return m_type == Type.Null; }
	bool opEquals(bool v) const { return m_type == Type.Bool && m_bool == v; }
	bool opEquals(long v) const { return m_type == Type.Int && m_int == v; }
	bool opEquals(double v) const { return m_type == Type.Float && m_float == v; }
	bool opEquals(string v) const { return m_type == Type.String && m_string == v; }

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
			case Type.Undefined: return 0;
			case Type.Null: return 0;
			case Type.Bool: return m_bool < other.m_bool ? -1 : m_bool == other.m_bool ? 0 : 1;
			case Type.Int: return m_int < other.m_int ? -1 : m_int == other.m_int ? 0 : 1;
			case Type.Float: return m_float < other.m_float ? -1 : m_float == other.m_float ? 0 : 1;
			case Type.String: return m_string < other.m_string ? -1 : m_string == other.m_string ? 0 : 1;
			case Type.Array: return m_array < other.m_array ? -1 : m_array == other.m_array ? 0 : 1;
			case Type.Object:
				enforce(false, "JSON objects cannot be compared.");
				assert(false);
		}
	}



	/**
		Returns the type id corresponding to the given D type.
	*/
	static @property Type typeId(T)() {
		static if( is(T == typeof(null)) ) return Type.Null;
		else static if( is(T == bool) ) return Type.Bool;
		else static if( is(T == double) ) return Type.Float;
		else static if( is(T == float) ) return Type.Float;
		else static if( is(T : long) ) return Type.Int;
		else static if( is(T == string) ) return Type.String;
		else static if( is(T == Json[]) ) return Type.Array;
		else static if( is(T == Json[string]) ) return Type.Object;
		else static assert(false, "Unsupported JSON type '"~T.stringof~"'. Only bool, long, double, string, JSON[] and JSON[string] are allowed.");
	}

	/**
		Returns the JSON object as a string.

		For large JSON values use toJSON() instead as this function will store the whole string
		in memory, whereas toJSON() writes it out bit for bit.
	*/
	string toString() const {
		auto ret = appender!string();
		toJson(ret, this);
		return ret.data;
	}

	private void checkType(T)()
	const {
		enforce(typeId!T == m_type, "Trying to access JSON of type "~.to!string(m_type)~" as "~T.stringof~".");
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
	Parses the given range as a JSON string and returns the corresponding JSON object.

	Throws an Exception if any parsing error occured.
*/
Json parseJson(R)(ref R range, int* line = null)
	if( is(R == string) )
{
	Json ret;
	enforce(range.length > 0, "JSON string is empty.");

	skipWhitespace(range, line);

	version(JsonLineNumbers) int curline = line ? *line : 0;
	
	switch( range[0] ){
		case 'f':
			enforce(range[1 .. $].startsWith("alse"), "Expected 'false', got '"~range[0 .. 5]~"'.");
			range = range[5 .. $];
			ret = false;
			break;
		case 'n':
			enforce(range[1 .. $].startsWith("ull"), "Expected 'null', got '"~range[0 .. 4]~"'.");
			range = range[4 .. $];
			ret = null;
			break;
		case 't':
			enforce(range[1 .. $].startsWith("rue"), "Expected 'true', got '"~range[0 .. 4]~"'.");
			range = range[4 .. $];
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
			while(true) {
				enforce(range.length > 0);
				if(range[0] == ']') break;
				range = range[1 .. $];
				skipWhitespace(range, line);
				if(range[0] == ']') break;
				arr ~= parseJson(range, line);
				skipWhitespace(range, line);
				enforce(range.length > 0 && (range[0] == ',' || range[0] == ']'), "Expected ']' or ','.");
			}
			range = range[1 .. $];
			ret = arr;
			break;
		case '{':
			Json[string] obj;
			while(true) {
				enforce(range.length > 0);
				if(range[0] == '}') break;
				range = range[1 .. $];
				skipWhitespace(range, line);
				if(range[0] == '}') break;
				string key = skipJsonString(range);
				skipWhitespace(range, line);
				enforce(range.startsWith(":"), "Expected ':' for key '" ~ key ~ "'");
				range = range[1 .. $];
				skipWhitespace(range, line);
				Json itm = parseJson(range, line);
				obj[key] = itm;
				skipWhitespace(range, line);
				enforce(range.length > 0 && (range[0] == ',' || range[0] == '}'), "Expected '}' or ','.");
			}
			range = range[1 .. $];
			ret = obj;
			break;
		default: 
			enforce(false, "Expected valid json token, got '"~range[0 .. 12]~"'.");
	}
	
	assert(ret.type != Json.Type.Undefined);
	version(JsonLineNumbers) ret.line = curline;
	return ret;
}


Json serializeToJson(T)(T value)
{
	static if( is(T == Json) ) return value;
	else static if( is(T == typeof(null)) ) return Json(null);
	else static if( is(T == bool) ) return Json(value);
	else static if( is(T == float) ) return Json(cast(double)value);
	else static if( is(T == double) ) return Json(value);
	else static if( is(T : long) ) return Json(cast(long)value);
	else static if( is(T == string) ) return Json(value);
	else static if( isArray!T ){
		auto ret = new Json[value.length];
		foreach( i; 0 .. value.length )
			ret[i] = serializeToJson(value[i]);
		return Json(ret);
	} else static if( isAssociativeArray!T ){
		Json[string] ret;
		foreach( string key, value; value )
			ret[key] = serializeToJson(value);
		return Json(ret);
	} else static if( is(T == struct) ){
		Json[string] ret;
		foreach( m; __traits(allMembers, T) ){
			static if( __traits(compiles, __traits(getMember, value, m) = __traits(getMember, value, m)) ){
				auto mn = __traits(identifier, m);
				auto mv = __traits(getMember, value, m);
				ret[mn] = serializeToJson(mv);
			}
		}
		return Json(ret);
	} else static if( is(T == class) ){
		if( value is null ) return Json(null);
		Json[string] ret;
		foreach( m; __traits(allMembers, T) ){
			static if( __traits(compiles, __traits(getMember, value, m) = __traits(getMember, value, m)) ){
				auto mn = __traits(identifier, m);
				auto mv = __traits(getMember, value, m);
				ret[mn] = serializeToJson(mv);
			}
		}
		return Json(ret);
	} else {
		static assert(false, "Unsupported type '"~T.stringof~"' for JSON serialization.");
	}
}

void deserializeJson(T)(ref T dst, Json src)
{
	static if( is(T == Json) ) dst = src;
	else static if( is(T == typeof(null)) ){ }
	else static if( is(T == bool) ) dst = src.get!bool;
	else static if( is(T == float) ) dst = src.get!float;
	else static if( is(T == double) ) dst = src.get!double;
	else static if( is(T : long) ) dst = cast(T)src.get!long;
	else static if( is(T == string) ) dst = src.get!string;
	else static if( isArray!T ){
		dst.length = src.length;
		foreach( size_t i, v; src )
			deserializeJson(dst[i], v);
	} else static if( isAssociativeArray!T ){
		typeof(dst.keys[0]) val;
		foreach( string key, value; src ){
			deserializeJson(val, value);
			dst[key] = val;
		}
	} else static if( is(T == struct) ){
		foreach( m; __traits(allMembers, T) ){
			auto mn = __traits(identifier, m);
			static if( __traits(compiles, __traits(getMember, value, m) = __traits(getMember, value, m)) )
				deserializeJson(__traits(getMember, value, m), value[mn]);
		}
	} else static if( is(T == class) ){
		dst = new T;
		foreach( m; __traits(allMembers, T) ){
			auto mn = __traits(identifier, m);
			static if( __traits(compiles, __traits(getMember, value, m) = __traits(getMember, value, m)) )
				deserializeJson(__traits(getMember, value, m), value[mn]);
		}
	} else {
		static assert(false, "Unsupported type '"~T.stringof~"' for JSON serialization.");
	}
}

/**
	Writes the given JSON object as a JSON string into the destination range.

	The basic version will not output any whitespace and thus minizime the size of the string.

	toPrettyJSON() in the other hand will add newlines and indents to make the output human
	readable.
*/
void toJson(R)(ref R dst, in Json json)
//	if( isOutputRange!R && is(ElementEncodingType!R == char) )
{
	final switch( json.type ){
		case Json.Type.Undefined: dst.put("undefined"); break;
		case Json.Type.Null: dst.put("null"); break;
		case Json.Type.Bool: dst.put(cast(bool)json ? "true" : "false"); break;
		case Json.Type.Int: dst.put(to!string(cast(long)json)); break;
		case Json.Type.Float: dst.put(to!string(cast(double)json)); break;
		case Json.Type.String:
			dst.put("\"");
			jsonEscape(dst, cast(string)json);
			dst.put("\"");
			break;
		case Json.Type.Array:
			dst.put("[");
			foreach( size_t i, ref const Json e; json ){
				if( i > 0 ) dst.put(",");
				toJson(dst, e);
			}
			dst.put("]");
			break;
		case Json.Type.Object:
			dst.put("{");
			bool first = true;
			foreach( string k, ref const Json e; json ){
				if( !first ) dst.put(",");
				first = false;
				dst.put("\"");
				jsonEscape(dst, k);
				dst.put("\":");
				toJson(dst, e);
			}
			dst.put("}");
			break;
	}
}

/// ditto
void toPrettyJson(R)(ref R dst, ref const(Json) json, int level = 0)
//	if( isOutputRange!R && is(ElementEncodingType!R == char) )
{
	final switch( json.type ){
		case Json.Type.Undefined: dst.put("undefined"); break;
		case Json.Type.Null: dst.put("null"); break;
		case Json.Type.Bool: dst.put(cast(bool)json ? "true" : "false"); break;
		case Json.Type.Int: dst.put(to!string(cast(long)json)); break;
		case Json.Type.Float: dst.put(to!string(cast(double)json)); break;
		case Json.Type.String:
			dst.put("\"");
			jsonEscape(dst, cast(string)json);
			dst.put("\"");
			break;
		case Json.Type.Array:
			dst.put("[");
			foreach( size_t i, e; json ){
				if( i > 0 ) dst.put(",");
				dst.put("\n");
				foreach( tab; 0 .. level ) dst.put('\t');
				toPrettyJson(dst, e, level+1);
			}
			if( json.length > 0 ) {
				dst.put('\n');
				foreach( tab; 0 .. (level-1) ) dst.put('\t');
			}
			dst.put("]");
			break;
		case Json.Type.Object:
			dst.put("{");
			bool first = true;
			foreach( string k, e; json ){
				if( !first ) dst.put(",");
				dst.put("\n");
				first = false;
				foreach( tab; 0 .. level ) dst.put('\t');
				dst.put("\"");
				jsonEscape(dst, k);
				dst.put("\": ");
				toPrettyJson(dst, e, level+1);
			}
			if( json.length > 0 ) {
				dst.put('\n');
				foreach( tab; 0 .. (level-1) ) dst.put('\t');
			}
			dst.put("}");
			break;
	}
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
				enforce(!range.empty, "Unterminated string escape sequence.");
				switch(range.front){
					default: enforce("Invalid string escape sequence."); break;
					case '"': ret.put('\"'); break;
					case '\\': ret.put('\\'); break;
					case '/': ret.put('/'); break;
					case 'b': ret.put('\b'); break;
					case 'f': ret.put('\f'); break;
					case 'n': ret.put('\n'); break;
					case 'r': ret.put('\r'); break;
					case 't': ret.put('\t'); break;
					case 'u':
						range.popFront();
						dchar uch = 0;
						foreach( i; 0 .. 4 ){
							uch *= 16;
							enforce(!range.empty, "Unicode sequence must be '\\uXXXX'.");
							auto dc = range.front;
							if( dc >= '0' && dc <= '9' ) uch += dc - '0';
							else if( dc >= 'a' && dc <= 'f' ) uch += dc - 'a' + 10;
							else if( dc >= 'A' && dc <= 'F' ) uch += dc - 'A' + 10;
							else enforce(false, "Unicode sequence must be '\\uXXXX'.");
						}
						ret.put(uch);
						break;
				}
				break;
			default: ret.put(ch); break;
		}
		range.popFront();
	}
	return ret.data;
}

private string skipNumber(ref string s, out bool is_float)
{
	size_t idx = 0;
	is_float = false;
	if( s[idx] == '-' ) idx++;
	if( s[idx] == '0' ) idx++;
	else {
		enforce(isDigit(s[idx++]), "Digit expected at beginning of number.");
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
		enforce( idx < s.length && isDigit(s[idx]), "Expected exponent." ~ s[0 .. idx]);
		idx++;
		while( idx < s.length && isDigit(idx) ) idx++;
	}

	string ret = s[0 .. idx];
	s = s[idx .. $];
	return ret;
}

private string skipJsonString(ref string s, int* line = null)
{
	enforce(s.length > 2 && s[0] == '\"', "too small: '" ~ s ~ "'");
	s = s[1 .. $];
	string ret = jsonUnescape(s);
	enforce(s.length > 0 && s[0] == '\"', "Unterminated string literal.");
	s = s[1 .. $];
	return ret;
}

private void skipWhitespace(ref string s, int* line = null)
{
	while( s.length > 0 ){
		switch( s[0] ){
			default: return;
			case ' ', '\t': s = s[1 .. $]; break;
			case '\n':
				s = s[1 .. $];
				if( s.length > 0 && s[0] == '\r' ) s = s[1 .. $];
				if( line ) (*line)++;
				break;
			case '\r':
				s = s[1 .. $];
				if( s.length > 0 && s[0] == '\n' ) s = s[1 .. $];
				if( line ) (*line)++;
				break;
		}
	}
}

/// private
private bool isDigit(T)(T ch){ return ch >= '0' && ch <= '9'; }
