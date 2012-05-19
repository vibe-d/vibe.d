/**
	BSON serialization and value handling.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.data.bson;

public import vibe.data.json;
import vibe.core.log;

import std.algorithm;
import std.array;
import std.bitmanip;
import std.conv;
import std.datetime;
import std.exception;
import std.range;
import std.traits;


alias immutable(ubyte)[] bdata_t;

/**
	Represents a BSON value.


*/
struct Bson {
	enum Type : ubyte {
		End        = 0x00,
		Double     = 0x01,
		String     = 0x02,
		Object     = 0x03,
		Array      = 0x04,
		BinData    = 0x05,
		Undefined  = 0x06, // Deprecated
		ObjectID   = 0x07,
		Bool       = 0x08,
		Date       = 0x09,
		Null       = 0x0A,
		Regex      = 0x0B,
		DBRef      = 0x0C, // Deprecated.
		Code       = 0x0D, // JavaScript code
		Symbol     = 0x0E,
		CodeWScope = 0x0F, // JavaScript code with scope
		Int        = 0x10,
		Timestamp  = 0x11,
		Long       = 0x12,
		MinKey     = 0xff,
		MaxKey     = 0x7f
	}

	static @property Bson EmptyObject(){ return Bson(cast(Bson[string])null); }

	private {
		Type m_type = Type.Undefined;
		bdata_t m_data;
	}

	/**
		Creates a new BSON value using raw data.

		A slice of the first bytes of 'data' is stored, containg the data related to the value. An
		exception is thrown if 'data' is too short.
	*/
	this(Type type, bdata_t data)
	{
		m_type = type;
		m_data = data;
		final switch(type){
			case Type.End: m_data = null; break;
			case Type.Double: m_data = m_data[0 .. 8]; break;
			case Type.String: m_data = m_data[0 .. 4 + fromBsonData!int(m_data)]; break;
			case Type.Object: m_data = m_data[0 .. fromBsonData!int(m_data)]; break;
			case Type.Array: m_data = m_data[0 .. fromBsonData!int(m_data)]; break;
			case Type.BinData: m_data = m_data[0 .. 5 + fromBsonData!int(m_data)]; break;
			case Type.Undefined: m_data = null; break;
			case Type.ObjectID: m_data = m_data[0 .. 12]; break;
			case Type.Bool: m_data = m_data[0 .. 1]; break;
			case Type.Date: m_data = m_data[0 .. 8]; break;
			case Type.Null: m_data = null; break;
			case Type.Regex: m_data = m_data[0 .. 0]; assert(false); break;
			case Type.DBRef: m_data = m_data[0 .. 0]; assert(false); break;
			case Type.Code: m_data = m_data[0 .. 4 + fromBsonData!int(m_data)]; break;
			case Type.Symbol: m_data = m_data[0 .. 4 + fromBsonData!int(m_data)]; break;
			case Type.CodeWScope: m_data = m_data[0 .. 0]; assert(false); break;
			case Type.Int: m_data = m_data[0 .. 4]; break;
			case Type.Timestamp: m_data = m_data[0 .. 8]; break;
			case Type.Long: m_data = m_data[0 .. 8]; break;
			case Type.MinKey: m_data = null; break;
			case Type.MaxKey: m_data = null; break;
		}
	}

	/**
		Initializes a new BSON value from the given D type.
	*/
	this(double value) { opAssign(value); }
	/// ditto
	this(string value, Type type = Type.String)
	{
		assert(type == Type.String || type == Type.Code || type == Type.Symbol);
		opAssign(value);
		m_type = type;
	}
	/// ditto
	this(Bson[string] value) { opAssign(value); }
	/// ditto
	this(Bson[] value) { opAssign(value); }
	/// ditto
	this(BsonBinData value) { opAssign(value); }
	/// ditto
	this(BsonObjectID value) { opAssign(value); }
	/// ditto
	this(bool value) { opAssign(value); }
	/// ditto
	this(BsonDate value) { opAssign(value); }
	/// ditto
	this(typeof(null)) { opAssign(null); }
	/// ditto
	this(BsonRegex value) { opAssign(value); }
	/// ditto
	this(int value) { opAssign(value); }
	/// ditto
	this(BsonTimestamp value) { opAssign(value); }
	/// ditto
	this(long value) { opAssign(value); }
	/// ditto
	this(Json value) { opAssign(value); }

	/**
		Assigns a D type to a BSON value.
	*/
	void opAssign(Bson other)
	{
		m_data = other.m_data;
 		m_type = other.m_type;
 	}
	/// ditto
	void opAssign(double value)
	{
		m_data = toBsonData(value).idup;
		m_type = Type.Double;
	}
	/// ditto
	void opAssign(string value)
	{
		auto app = appender!bdata_t();
		app.put(toBsonData(cast(int)value.length+1));
		app.put(cast(bdata_t)value);
		app.put(cast(ubyte)0);
		m_data = app.data;
		m_type = Type.String;
	}
	/// ditto
	void opAssign(in Bson[string] value)
	{
		auto app = appender!bdata_t();
		foreach( k, ref v; value ){
			app.put(cast(ubyte)v.type);
			putCString(app, k);
			app.put(v.data);
		}

		auto dapp = appender!bdata_t();
		dapp.put(toBsonData(cast(int)app.data.length+5));
		dapp.put(app.data);
		dapp.put(cast(ubyte)0);
		m_data = dapp.data;
		m_type = Type.Object;
	}
	/// ditto
	void opAssign(in Bson[] value)
	{
		auto app = appender!bdata_t();
		foreach( i, ref v; value ){
			app.put(v.type);
			putCString(app, to!string(i));
			app.put(v.data);
		}

		auto dapp = appender!bdata_t();
		dapp.put(toBsonData(cast(int)app.data.length+5));
		dapp.put(app.data);
		dapp.put(cast(ubyte)0);
		m_data = dapp.data;
		m_type = Type.Array;
	}
	/// ditto
	void opAssign(BsonBinData value)
	{
		auto app = appender!bdata_t();
		app.put(toBsonData(cast(int)value.rawData.length));
		app.put(value.type);
		app.put(value.rawData);

		m_data = app.data;
		m_type = Type.BinData;
	}
	/// ditto
	void opAssign(BsonObjectID value)
	{
		m_data = value.m_bytes.idup;
		m_type = Type.ObjectID;
	}
	/// ditto
	void opAssign(bool value)
	{
		m_data = [value ? 0x01 : 0x00];
		m_type = Type.Bool;
	}
	/// ditto
	void opAssign(BsonDate value)
	{
		m_data = toBsonData(value.m_time).idup;
		m_type = Type.Date;
	}
	/// ditto
	void opAssign(typeof(null))
	{
		m_data = null;
		m_type = Type.Null;
	}
	/// ditto
	void opAssign(BsonRegex value)
	{
		auto app = appender!bdata_t();
		putCString(app, value.expression);
		putCString(app, value.options);
		m_data = app.data;
		m_type = type.Regex;
	}
	/// ditto
	void opAssign(int value)
	{
		m_data = toBsonData(value).idup;
		m_type = Type.Int;
	}
	/// ditto
	void opAssign(BsonTimestamp value)
	{
		m_data = toBsonData(value.m_time).idup;
		m_type = Type.Timestamp;
	}
	/// ditto
	void opAssign(long value)
	{
		m_data = toBsonData(value).idup;
		m_type = Type.Long;
	}
	/// ditto
	void opAssign(Json value)
	{
		auto app = appender!bdata_t();
		m_type = writeBson(app, value);
		m_data = app.data;
	}

	/**
		Returns the BSON type of this value.
	*/
	@property Type type() const { return m_type; }

	bool isNull() const { return m_type == Type.Null; }

	/**
		Returns the raw data representing this BSON value (not including the field name and type).
	*/
	@property bdata_t data() const { return m_data; }

	/**
		Converts the BSON value to a D value.

		If the BSON type of the value does not match the D type, an exception is thrown.
	*/
	T opCast(T)() const { return get!T(); }
	/// ditto
	@property T get(T)()
	const {
		static if( is(this == const) && !is(T == const) || is(T == immutable) ){
			static assert(false, "Invalid const combination.");
		}
		static if( is(T == double) ){ checkType(Type.Double); return fromBsonData!double(m_data); }
		else static if( is(T == string) ){
			checkType(Type.String, Type.Code, Type.Symbol);
			return cast(string)m_data[4 .. 4+fromBsonData!int(m_data)-1];
		}
		else static if( is(Unqual!T == Bson[string]) || is(Unqual!T == const(Bson)[string])  ){
			checkType(Type.Object);
			Bson[string] ret;
			auto d = m_data[4 .. $];
			while( d.length > 0 ){
				auto tp = cast(Type)d[0];
				if( tp == Type.End ) break;
				d = d[1 .. $];
				auto key = skipCString(d);	
				auto value = Bson(tp, d);
				d = d[value.data.length .. $];

				ret[key] = value;
			}
			return cast(T)ret;
		}
		else static if( is(Unqual!T == Bson[]) || is(Unqual!T == const(Bson)[]) ){
			checkType(Type.Array);
			Bson[] ret;
			auto d = m_data[4 .. $];
			while( d.length > 0 ){
				auto tp = cast(Type)d[0];
				if( tp == Type.End ) break;
				auto key = skipCString(d); // should be '0', '1', ...
				auto value = Bson(tp, d);
				d = d[value.data.length .. $];

				ret ~= value;
			}
			return cast(T)ret;
		}
		else static if( is(T == BsonBinData) ){
			checkType(Type.BinData);
			auto size = fromBsonData!int(m_data);
			auto type = cast(BsonBinData.Type)m_data[4];
			return BsonBinData(type, m_data[5 .. 5+size]);
		}
		else static if( is(T == BsonObjectID) ){ checkType(Type.ObjectID); return BsonObjectID(m_data[0 .. 12]); }
		else static if( is(T == bool) ){ checkType(Type.Bool); return m_data[0] != 0; }
		else static if( is(T == BsonDate) ){ checkType(Type.Date); return BsonDate(fromBsonData!long(m_data)); }
		else static if( is(T == BsonRegex) ){
			checkType(Type.Regex);
			auto d = m_data;
			auto expr = skipCString(d);
			auto options = skipCString(d);
			return BsonRegex(expr, options);
		}
		else static if( is(T == int) ){ checkType(Type.Int); return fromBsonData!int(m_data); }
		else static if( is(T == BsonTimestamp) ){ checkType(Type.Timestamp); return BsonTimestamp(fromBsonData!long(m_data)); }
		else static if( is(T == long) ){ checkType(Type.Long); return fromBsonData!long(m_data); }
		else static if( is(T == Json) ){ return bsonToJson(this); }
		else static assert(false, "Cannot cast "~typeof(this).stringof~" to '"~T.stringof~"'.");
	}

	/** Returns the native type for this BSON if it matches the current runtime type.

		If the runtime type does not match the given native type, the 'def' parameter is returned
		instead.
	*/
	inout(T) opt(T)(T def = T.init) inout {
		if( isNull() ) return def;
		try def = cast(T)this;
		catch( Exception e ) {}
		return def;
	}

	@property size_t length() const {
		switch( m_type ){
			default: enforce(false, "Bson objects of type "~to!string(m_type)~" do not have a length field."); break;
			case Type.String, Type.Code, Type.Symbol: return (cast(string)this).length;
			case Type.Array: return (cast(const(Bson)[])this).length;
			case Type.BinData: assert(false); //return (cast(BsonBinData)this).length; break;
		}
		assert(false);
	}

	inout(Bson) opIndex(string idx) inout {
		checkType(Type.Object);
		auto d = m_data[4 .. $];
		while( d.length > 0 ){
			auto tp = cast(Type)d[0];
			if( tp == Type.End ) break;
			d = d[1 .. $];
			auto key = skipCString(d);
			auto value = Bson(tp, d);
			d = d[value.data.length .. $];

			if( key == idx )
				return value;
		}
		return Bson(null);
	}

	void opIndexAssign(T)(T value, string idx){
		auto newcont = appender!bdata_t();
		checkType(Type.Object);
		auto d = m_data[4 .. $];
		while( d.length > 0 ){
			auto tp = cast(Type)d[0];
			if( tp == Type.End ) break;
			d = d[1 .. $];
			auto key = skipCString(d);
			auto val = Bson(tp, d);
			d = d[val.data.length .. $];

			if( key != idx ){
				// copy to new array
				newcont.put(cast(ubyte)tp);
				putCString(newcont, key);
				newcont.put(val.data);
			}
		}

		static if( is(T == Bson) )
			alias value bval;
		else
			auto bval = Bson(value);

		newcont.put(cast(ubyte)bval.type);
		putCString(newcont, idx);
		newcont.put(bval.data);

		auto newdata = appender!bdata_t();
		newdata.put(toBsonData(cast(uint)(newcont.data.length + 5)));
		newdata.put(newcont.data);
		newdata.put(cast(ubyte)0);
		m_data = newdata.data;
	}

	inout(Bson) opIndex(size_t idx) inout {
		checkType(Type.Array);
		auto d = m_data[4 .. $];
		size_t i = 0;
		while( d.length > 0 ){
			auto tp = cast(Type)d[0];
			if( tp == Type.End ) break;
			d = d[1 .. $];
			skipCString(d);
			auto value = Bson(tp, d);
			d = d[value.data.length .. $];

			if( i == idx ) return value;
			i++;
		}
		return Bson(null);
	}

	/**
		Allows to access existing fields of a JSON object using dot syntax.
	*/
	@property inout(Bson) opDispatch(string prop)() inout { return opIndex(prop); }
	/// ditto
	@property void opDispatch(string prop, T)(T val) { opIndexAssign(Bson(val), prop); }

	bool opEquals(ref const Bson other) const {
		if( m_type != other.m_type ) return false;
		return m_data == other.m_data;
	}

	private void checkType(Type[] valid_types...)
	const {
		foreach( t; valid_types )
			if( m_type == t )
				return;
		throw new Exception("BSON value is type '"~to!string(m_type)~"', expected to be one of "~to!string(valid_types));
	}
}

struct BsonBinData {
	enum Type : ubyte {
		Generic = 0x00,
		Function = 0x01,
		BinaryOld = 0x02,
		UUID = 0x03,
		MD5 = 0x05,
		UserDefined = 0x80
	}

	private {
		Type m_type;
		bdata_t m_data;
	}

	this(Type type, immutable(ubyte)[] data)
	{
		m_type = type;
		m_data = data;
	}

	@property Type type() const { return m_type; }
	@property bdata_t rawData() const { return m_data; }
}

struct BsonObjectID {
	private {
		ubyte[12] m_bytes;
		static int ms_pid = -1;
		static uint ms_inc = 0;
		static uint MACHINE_ID = 0;
	}

	this( in ubyte[] bytes ){
		assert(bytes.length == 12);
		m_bytes[] = bytes;
	}

	static BsonObjectID fromHexString(string str)
	{
		assert(str.length == 24, "BSON Object ID string s must be 24 characters.");
		BsonObjectID ret = void;
		uint b = 0;
		foreach( i, ch; str ){
			ubyte n;
			if( ch >= '0' && ch <= '9' ) n = cast(ubyte)(ch - '0');
			else if( ch >= 'a' && ch <= 'f' ) n = cast(ubyte)(ch - 'a' + 10);
			else if( ch >= 'A' && ch <= 'F' ) n = cast(ubyte)(ch - 'F' + 10);
			else assert(false, "Not a valid hex string.");
			b <<= 4;
			b += n;
			if( i % 8 == 7 ){
				auto j = i / 8;
				ret.m_bytes[j*4 .. (j+1)*4] = toBigEndianData(b);
				b = 0;
			}
		}
		return ret;
	}

	static BsonObjectID generate()
	{
		import std.datetime;
		import std.process;
		import std.random;

		if( ms_pid == -1 ) ms_pid = getpid();
		if( MACHINE_ID == 0 ) MACHINE_ID = uniform(0, 0xffffff);
	  	auto unixTime = Clock.currTime(UTC()).toUnixTime();

	  	BsonObjectID ret = void;
	  	ret.m_bytes[0 .. 4] = toBigEndianData(cast(uint)unixTime);
	  	ret.m_bytes[4 .. 7] = toBsonData(MACHINE_ID)[0 .. 3];
	  	ret.m_bytes[7 .. 9] = toBsonData(cast(ushort)ms_pid);
	  	ret.m_bytes[9 .. 12] = toBigEndianData(ms_inc++)[1 .. 4];
	  	return ret;
	}

	static BsonObjectID createDateID(SysTime date)
	{
	  	BsonObjectID ret;
	  	ret.m_bytes[0 .. 4] = toBigEndianData(cast(uint)date.toUnixTime());
	  	return ret;
	}

	@property bool valid() const {
		foreach( b; m_bytes )
			if( b != 0 )
				return true;
		return false;
	}

	int opCmp(ref const BsonObjectID other) const {
		if( m_bytes == other.m_bytes) return 0;
		return m_bytes < other.m_bytes ? -1 : 1;
	}

	string toString() const {
		enum hexdigits = "0123456789abcdef";
		auto ret = new char[24];
		foreach( i, b; m_bytes ){
			ret[i*2+0] = hexdigits[(b >> 4) & 0x0F];
			ret[i*2+1] = hexdigits[b & 0x0F];
		}
		return cast(immutable)ret;
	}
}

struct BsonDate {
	private long m_time; // milliseconds since UTC unix epoch

    this(Date date) {
        this(SysTime(date));
    }

    this(DateTime date) {
        this(SysTime(date));
    }

	this(long time){
		m_time = time;
	}

	this(SysTime time){
		auto zero = unixTimeToStdTime(0);
		m_time = (time.stdTime() - zero) / 10_000L;
	}


	SysTime toSysTime() const {
		auto zero = unixTimeToStdTime(0);
		return SysTime(zero + m_time * 10_000L, UTC());
	}

	string toString() const {
		return toSysTime().toString();
	}

	bool opEquals(ref const BsonDate other) const { return m_time == other.m_time; }
	int opCmp(ref const BsonDate other) const {
		if( m_time == other.m_time ) return 0;
		if( m_time < other.m_time ) return -1;
		else return 1;
	}

	@property long value() const { return m_time; }
	@property void value(long v) { m_time = v; }
}

struct BsonTimestamp {
	private long m_time;

	this( long time ){
		m_time = time;
	}
}

struct BsonRegex {
	private {
		string m_expr;
		string m_options;
	}

	this(string expr, string options)
	{
		m_expr = expr;
		m_options = options;
	}

	@property string expression() const { return m_expr; }
	@property string options() const { return m_options; }
}



Bson serializeToBson(T)(T value)
{
	static if( is(T == Bson) ) return value;
	else static if( is(T == Json) ) return jsonToBson(value);
	else static if( is(T == BsonBinData) ) return Bson(value);
	else static if( is(T == BsonObjectID) ) return Bson(value);
	else static if( is(T == BsonDate) ) return Bson(value);
	else static if( is(T == BsonTimestamp) ) return Bson(value);
	else static if( is(T == BsonRegex) ) return Bson(value);
	else static if( is(T == typeof(null)) ) return Bson(null);
	else static if( is(T == bool) ) return Bson(value);
	else static if( is(T == float) ) return Bson(cast(double)value);
	else static if( is(T == double) ) return Bson(value);
	else static if( is(T : long) ) return Bson(cast(long)value);
	else static if( is(T == string) ) return Bson(value);
	else static if( is(T : const(ubyte)[]) ) return Bson(BsonBinData(BsonBinData.Type.Generic, value.idup));
	else static if( isArray!T ){
		auto ret = new Bson[value.length];
		foreach( i; 0 .. value.length )
			ret[i] = serializeToBson(value[i]);
		return Bson(ret);
	} else static if( isAssociativeArray!T ){
		Bson[string] ret;
		foreach( string key, value; value )
			ret[key] = serializeToBson(value);
		return Bson(ret);
	} else static if( is(T == struct) ){
		Bson[string] ret;
		foreach( m; __traits(allMembers, T) ){
			static if( __traits(compiles, __traits(getMember, value, m) = __traits(getMember, value, m)) ){
				auto mn = m;
				auto mv = __traits(getMember, value, m);
				ret[mn] = serializeToBson(mv);
			}
		}
		return Bson(ret);
	} else static if( is(T == class) ){
		if( value is null ) return Bson(null);
		Bson[string] ret;
		foreach( m; __traits(allMembers, T) ){
			static if( __traits(compiles, __traits(getMember, value, m) = __traits(getMember, value, m)) ){
				auto mn = m;
				auto mv = __traits(getMember, value, m);
				ret[mn] = serializeToBson(mv);
			}
		}
		return Bson(ret);
	} else {
		static assert(false, "Unsupported type '"~T.stringof~"' for JSON serialization.");
	}
}

void deserializeBson(T)(ref T dst, Bson src)
{
	static if( is(T == Bson) ) dst = src;
	else static if( is(T == Json) ) dst = bsonToJson(value);
	else static if( is(T == BsonBinData) ) dst = cast(T)src;
	else static if( is(T == BsonObjectID) ) dst = cast(T)src;
	else static if( is(T == BsonDate) ) dst = cast(T)src;
	else static if( is(T == BsonTimestamp) ) dst = cast(T)src;
	else static if( is(T == BsonRegex) ) dst = cast(T)src;
	else static if( is(T == typeof(null)) ){ }
	else static if( is(T == bool) ) dst = cast(bool)src;
	else static if( is(T == float) ) dst = cast(double)src;
	else static if( is(T == double) ) dst = cast(double)src;
	else static if( is(T : long) ) dst = cast(T)cast(long)src;
	else static if( is(T == string) ) dst = cast(string)src;
	else static if( is(T : const(ubyte)[]) ) dst = cast(T)src.get!BsonBinData.rawData.dup;
	else static if( isArray!T ){
		dst.length = src.length;
		foreach( size_t i, v; cast(Bson[])src )
			deserializeBson(dst[i], v);
	} else static if( isAssociativeArray!T ){
		typeof(dst.values[0]) val;
		foreach( string key, value; cast(Bson[string])src ){
			deserializeBson(val, value);
			dst[key] = val;
		}
	} else static if( is(T == struct) ){
		foreach( m; __traits(allMembers, T) ){
			static if( __traits(compiles, __traits(getMember, dst, m) = __traits(getMember, dst, m)) )
				deserializeBson(__traits(getMember, dst, m), src[m]);
		}
	} else static if( is(T == class) ){
		dst = new T;
		foreach( m; __traits(allMembers, T) ){
			static if( __traits(compiles, __traits(getMember, dst, m) = __traits(getMember, dst, m)) )
				deserializeBson(__traits(getMember, dst, m), src[m]);
		}
	} else {
		static assert(false, "Unsupported type '"~T.stringof~"' for JSON serialization.");
	}
}


private Bson.Type writeBson(R)(ref R dst, in Json value)
	if( isOutputRange!(R, ubyte) )
{
	final switch(value.type){
		case Json.Type.Undefined:
			return Bson.Type.Undefined;
		case Json.Type.Null:
			return Bson.Type.Null;
		case Json.Type.Bool:
			dst.put(cast(ubyte)(cast(bool)value ? 0x00 : 0x01));
			return Bson.Type.Bool;
		case Json.Type.Int:
			auto v = cast(long)value;
			if( v >= int.min && v <= int.max ){
				dst.put(toBsonData(cast(int)v));
				return Bson.Type.Int;
			}
			dst.put(toBsonData(v));
			return Bson.Type.Long;
		case Json.Type.Float:
			dst.put(toBsonData(cast(double)value));
			return Bson.Type.Double;
		case Json.Type.String:
			dst.put(toBsonData(cast(uint)value.length));
			dst.put(cast(bdata_t)cast(string)value);
			return Bson.Type.String;
		case Json.Type.Array:
			auto app = appender!bdata_t();
			foreach( size_t i, ref const Json v; value ){
				app.put(cast(ubyte)v.type);
				putCString(app, to!string(i));
				writeBson(dst, v);
			}

			dst.put(toBsonData(cast(int)app.data.length));
			dst.put(app.data);
			dst.put(cast(ubyte)0);
			return Bson.Type.Array;
		case Json.Type.Object:
			auto app = appender!bdata_t();
			foreach( string k, ref const Json v; value ){
				app.put(cast(ubyte)v.type);
				putCString(app, k);
				writeBson(dst, v);
			}

			dst.put(toBsonData(cast(int)app.data.length));
			dst.put(app.data);
			dst.put(cast(ubyte)0);
			return Bson.Type.Object;
	}
}

private Json bsonToJson(Bson value)
{
	switch( value.type ){
		default: assert(false);
	    case Bson.Type.Double: return Json(cast(double)value);
	    case Bson.Type.String: return Json(cast(string)value);
	    case Bson.Type.Object:
	    	Json[string] ret;
	    	foreach( k, v; cast(Bson[string])value )
	    		ret[k] = bsonToJson(v);
	    	return Json(ret);
	    case Bson.Type.Array:
	    	auto ret = new Json[value.length];
	    	foreach( i, v; cast(Bson[])value )
	    		ret[i] = bsonToJson(v);
	    	return Json(ret);
	    case Bson.Type.BinData: assert(false, "TODO");
	    case Bson.Type.ObjectID: return Json((cast(BsonObjectID)value).toString());
	    case Bson.Type.Bool: return Json(cast(bool)value);
	    case Bson.Type.Date: return Json((cast(BsonDate)value).m_time);
	    case Bson.Type.Null: return Json(null);
	    case Bson.Type.Regex: assert(false, "TODO");
	    case Bson.Type.DBRef: assert(false, "TODO");
	    case Bson.Type.Code: return Json(cast(string)value);
	    case Bson.Type.Symbol: return Json(cast(string)value);
	    case Bson.Type.CodeWScope: assert(false, "TODO");
	    case Bson.Type.Int: return Json(cast(int)value);
	    case Bson.Type.Timestamp: return Json((cast(BsonTimestamp)value).m_time);
	    case Bson.Type.Long: return Json(cast(long)value);
	}
}

private Bson jsonToBson(Json value)
{
	final switch( value.type ){
		case Json.Type.Undefined: return Bson();
		case Json.Type.Null: return Bson(null);
		case Json.Type.Bool: return Bson(cast(bool)value);
		case Json.Type.Int: return Bson(cast(long)value);
		case Json.Type.Float: return Bson(cast(double)value);
		case Json.Type.String: return Bson(cast(string)value);
		case Json.Type.Array:
			Bson[] ret = new Bson[value.length];
			foreach( size_t i, v; value )
				ret[i] = jsonToBson(v);
			return Bson(ret);
		case Json.Type.Object:
			Bson[string] ret;
			foreach( string k, v; value )
				ret[k] = jsonToBson(v);
			return Bson(ret);
	}
}

private string skipCString(ref bdata_t data)
{
	auto idx = data.indexOf(0);
	enforce(idx >= 0, "Unterminated BSON C-string.");
	auto ret = data[0 .. idx];
	data = data[idx+1 .. $];
	return cast(string)ret;
}

private void putCString(R)(R dst, string str)
{
	dst.put(cast(bdata_t)str);
	dst.put(cast(ubyte)0);
}

ubyte[] toBsonData(T)(T v)
{
	/*static T tmp;
	tmp = nativeToLittleEndian(v);
	return cast(ubyte[])((&tmp)[0 .. 1]);*/
	static ubyte[T.sizeof] ret;
	ret = nativeToLittleEndian(v);
	return ret;
}

T fromBsonData(T)(in ubyte[] v)
{
	assert(v.length >= T.sizeof);
	//return (cast(T[])v[0 .. T.sizeof])[0];
	ubyte[T.sizeof] vu = v[0 .. T.sizeof];
	return littleEndianToNative!T(vu);
}

ubyte[] toBigEndianData(T)(T v)
{
	/*static T tmp;
	tmp = nativeToBigEndian(v);
	return cast(ubyte[])((&tmp)[0 .. 1]);*/
	static ubyte[T.sizeof] ret;
	ret = nativeToBigEndian(v);
	return ret;
}

