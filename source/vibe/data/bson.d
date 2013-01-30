/**
	BSON serialization and value handling.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.data.bson;

public import vibe.data.json;
import vibe.core.log;
import vibe.data.utils;

import std.algorithm;
import std.array;
import std.base64;
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
	/// Represents the type of a BSON value
	enum Type : ubyte {
		/// End marker - should never occur explicitly
		End        = 0x00,
		/// A 64-bit floating point value
		Double     = 0x01,
		/// A UTF-8 string
		String     = 0x02,
		/// An object aka. dictionary of string to Bson
		Object     = 0x03,
		/// An array of BSON values
		Array      = 0x04,
		/// Raw binary data (ubyte[])
		BinData    = 0x05,
		/// Deprecated
		Undefined  = 0x06,
		/// BSON Object ID (96-bit)
		ObjectID   = 0x07,
		/// Boolean value
		Bool       = 0x08,
		/// Date value (UTC)
		Date       = 0x09,
		/// Null value
		Null       = 0x0A,
		/// Regular expression
		Regex      = 0x0B,
		/// Deprecated
		DBRef      = 0x0C,
		/// JaveScript code
		Code       = 0x0D,
		/// Symbol/variable name
		Symbol     = 0x0E,
		/// JavaScript code with scope
		CodeWScope = 0x0F,
		/// 32-bit integer
		Int        = 0x10,
		/// Timestamp value
		Timestamp  = 0x11,
		/// 64-bit integer
		Long       = 0x12,
		/// Internal value
		MinKey     = 0xff,
		/// Internal value
		MaxKey     = 0x7f
	}

	/// Returns a new, empty Bson value of type Object.
	static @property Bson EmptyObject() { return Bson(cast(Bson[string])null); }

	/// Returns a new, empty Bson value of type Object.
	static @property Bson EmptyArray() { return Bson(cast(Bson[])null); }

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
			case Type.Regex: m_data = m_data[0 .. 0]; assert(false);
			case Type.DBRef: m_data = m_data[0 .. 0]; assert(false);
			case Type.Code: m_data = m_data[0 .. 4 + fromBsonData!int(m_data)]; break;
			case Type.Symbol: m_data = m_data[0 .. 4 + fromBsonData!int(m_data)]; break;
			case Type.CodeWScope: m_data = m_data[0 .. 0]; assert(false);
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
	this(in Bson[string] value) { opAssign(value); }
	/// ditto
	this(in Bson[] value) { opAssign(value); }
	/// ditto
	this(in BsonBinData value) { opAssign(value); }
	/// ditto
	this(in BsonObjectID value) { opAssign(value); }
	/// ditto
	this(bool value) { opAssign(value); }
	/// ditto
	this(in BsonDate value) { opAssign(value); }
	/// ditto
	this(typeof(null)) { opAssign(null); }
	/// ditto
	this(in BsonRegex value) { opAssign(value); }
	/// ditto
	this(int value) { opAssign(value); }
	/// ditto
	this(in BsonTimestamp value) { opAssign(value); }
	/// ditto
	this(long value) { opAssign(value); }
	/// ditto
	this(in Json value) { opAssign(value); }

	/**
		Assigns a D type to a BSON value.
	*/
	void opAssign(in Bson other)
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
	void opAssign(in BsonBinData value)
	{
		auto app = appender!bdata_t();
		app.put(toBsonData(cast(int)value.rawData.length));
		app.put(value.type);
		app.put(value.rawData);

		m_data = app.data;
		m_type = Type.BinData;
	}
	/// ditto
	void opAssign(in BsonObjectID value)
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
	void opAssign(in BsonDate value)
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
	void opAssign(in BsonRegex value)
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
	void opAssign(in BsonTimestamp value)
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
	void opAssign(in Json value)
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
		static if( is(T == double) ){ checkType(Type.Double); return fromBsonData!double(m_data); }
		else static if( is(T == string) ){
			checkType(Type.String, Type.Code, Type.Symbol);
			return cast(string)m_data[4 .. 4+fromBsonData!int(m_data)-1];
		}
		else static if( is(Unqual!T == Bson[string]) || is(Unqual!T == const(Bson)[string]) ){
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
		else static if( is(T == Json) ){
			pragma(msg, "Bson.get!Json() and Bson.opCast!Json() will soon be removed. Please use Bson.toJson() instead.");
			return this.toJson();
		}
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

	/** Returns the length of a BSON value of type String, Array, Object or BinData.
	*/
	@property size_t length() const {
		switch( m_type ){
			default: enforce(false, "Bson objects of type "~to!string(m_type)~" do not have a length field."); break;
			case Type.String, Type.Code, Type.Symbol: return (cast(string)this).length;
			case Type.Array: return (cast(const(Bson)[])this).length; // TODO: optimize!
			case Type.Object: return (cast(const(Bson)[string])this).length; // TODO: optimize!
			case Type.BinData: assert(false); //return (cast(BsonBinData)this).length; break;
		}
		assert(false);
	}

	/** Converts a given JSON value to the corresponding BSON value.
	*/
	static Bson fromJson(in Json value)
	{
		auto app = appender!bdata_t();
		auto tp = writeBson(app, value);
		return Bson(tp, app.data);
	}

	/** Converts a BSON value to a JSON value.
		
		All BSON types that cannot be exactly represented as JSON, will
		be converted to a string.
	*/
	Json toJson()
	const {
		switch( this.type ){
			default: assert(false);
			case Bson.Type.Double: return Json(get!double());
			case Bson.Type.String: return Json(get!string());
			case Bson.Type.Object:
				Json[string] ret;
				foreach( k, v; get!(Bson[string])() )
					ret[k] = v.toJson();
				return Json(ret);
			case Bson.Type.Array:
				auto ret = new Json[this.length];
				foreach( i, v; get!(Bson[])() )
					ret[i] = v.toJson();
				return Json(ret);
			case Bson.Type.BinData: return Json(cast(string)Base64.encode(get!BsonBinData.rawData));
			case Bson.Type.ObjectID: return Json(get!BsonObjectID().toString());
			case Bson.Type.Bool: return Json(get!bool());
			case Bson.Type.Date: return Json(get!BsonDate.toString());
			case Bson.Type.Null: return Json(null);
			case Bson.Type.Regex: assert(false, "TODO");
			case Bson.Type.DBRef: assert(false, "TODO");
			case Bson.Type.Code: return Json(get!string());
			case Bson.Type.Symbol: return Json(get!string());
			case Bson.Type.CodeWScope: assert(false, "TODO");
			case Bson.Type.Int: return Json(get!int());
			case Bson.Type.Timestamp: return Json(get!BsonTimestamp().m_time);
			case Bson.Type.Long: return Json(get!long());
		}
	}


	/** Allows accessing fields of a BSON object using [].

		Returns a null value if the specified field does not exist.
	*/
	inout(Bson) opIndex(string idx) inout {
		foreach( string key, v; this )
			if( key == idx )
				return v;
		return Bson(null);
	}
	/// ditto
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

	/** Allows index based access of a BSON array value.

		Returns a null value if the index is out of bounds.
	*/
	inout(Bson) opIndex(size_t idx) inout {
		foreach( size_t i, v; this )
			if( i == idx )
				return v;
		return Bson(null);
	}

	/**
		Allows foreach iterating over BSON objects and arrays.

		Note that although D requires to provide a 'ref' argument for
		opApply, in-place editing of the array/object fields is not possible.
		Any modification attempty will work on a temporary, even if the
		loop variable is declared 'ref'.
	*/
	int opApply(int delegate(ref Bson obj) del)
	const {
		checkType(Type.Array, Type.Object);
		if( m_type == Type.Array ){
			foreach( size_t idx, v; this )
				if( auto ret = del(v) )
					return ret;
			return 0;
		} else {
			foreach( string idx, v; this )
				if( auto ret = del(v) )
					return ret;
			return 0;
		}
	}
	/// ditto
	int opApply(int delegate(ref size_t idx, ref Bson obj) del)
	const {
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

			auto icopy = i;
			if( auto ret = del(icopy, value) )
				return ret;

			i++;
		}
		return 0;
	}
	/// ditto
	int opApply(int delegate(ref string idx, ref Bson obj) del)
	const {
		checkType(Type.Object);
		auto d = m_data[4 .. $];
		while( d.length > 0 ){
			auto tp = cast(Type)d[0];
			if( tp == Type.End ) break;
			d = d[1 .. $];
			auto key = skipCString(d);
			auto value = Bson(tp, d);
			d = d[value.data.length .. $];

			if( auto ret = del(key, value) )
				return ret;
		}
		return 0;
	}

	/** Allows to access existing fields of a JSON object using dot syntax.

		Returns a null value for non-existent fields.
	*/
	@property inout(Bson) opDispatch(string prop)() inout { return opIndex(prop); }
	/// ditto
	@property void opDispatch(string prop, T)(T val) { opIndexAssign(val, prop); }

	///
	bool opEquals(ref const Bson other) const {
		if( m_type != other.m_type ) return false;
		return m_data == other.m_data;
	}
	/// ditto
	bool opEquals(const Bson other) const {
		if( m_type != other.m_type ) return false;
		return m_data == other.m_data;
	}

	private void checkType(in Type[] valid_types...)
	const {
		foreach( t; valid_types )
			if( m_type == t )
				return;
		throw new Exception("BSON value is type '"~to!string(m_type)~"', expected to be one of "~to!string(valid_types));
	}
}


/**
	Represents a BSON binary data value (Bson.Type.BinData).
*/
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


/**
	Represents a BSON object id (Bson.Type.BinData).
*/
struct BsonObjectID {
	private {
		ubyte[12] m_bytes;
		static int ms_pid = -1;
		static uint ms_inc = 0;
		static uint MACHINE_ID = 0;
	}

	/** Constructs a new object ID from the given raw byte array.
	*/
	this( in ubyte[] bytes ){
		assert(bytes.length == 12);
		m_bytes[] = bytes;
	}

	/** Creates an on object ID from a string in standard hexa-decimal form.
	*/
	static BsonObjectID fromString(string str)
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
	/// ditto
	alias fromString fromHexString;

	/** Generates a unique object ID.
	*/
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

	/** Creates a pseudo object ID that matches the given date.

		This kind of ID can be useful to query a database for items in a certain
		date interval using their ID. This works using the property of standard BSON
		object IDs that they store their creation date as part of the ID. Note that
		this date part is only 32-bit wide and is limited to the same timespan as a
		32-bit Unix timestamp.
	*/
	static BsonObjectID createDateID(in SysTime date)
	{
		BsonObjectID ret;
		ret.m_bytes[0 .. 4] = toBigEndianData(cast(uint)date.toUnixTime());
		return ret;
	}

	/** Returns true for any non-zero ID.
	*/
	@property bool valid() const {
		foreach( b; m_bytes )
			if( b != 0 )
				return true;
		return false;
	}

	/** Extracts the time/date portion of the object ID.

		For IDs created using the standard generation algorithm or using createDateID
		this will return the associated time stamp.
	*/
	@property SysTime timeStamp()
	{
		ubyte[4] tm = m_bytes[0 .. 4];
		return SysTime(unixTimeToStdTime(bigEndianToNative!uint(tm)));
	}

	/** Allows for relational comparison of different IDs.
	*/
	int opCmp(ref const BsonObjectID other)
	const {
		import core.stdc.string;
		return memcmp(m_bytes.ptr, other.m_bytes.ptr, m_bytes.length);
	}

	/** Converts the ID to its standard hexa-decimal string representation.
	*/
	string toString() const {
		enum hexdigits = "0123456789abcdef";
		auto ret = new char[24];
		foreach( i, b; m_bytes ){
			ret[i*2+0] = hexdigits[(b >> 4) & 0x0F];
			ret[i*2+1] = hexdigits[b & 0x0F];
		}
		return cast(immutable)ret;
	}

	ubyte[] opCast() {
		return m_bytes;
	}
}


/**
	Represents a BSON date value (Bson.Type.Date).
*/
struct BsonDate {
	private long m_time; // milliseconds since UTC unix epoch

	this(in Date date) {
		this(SysTime(date));
	}

	this(in DateTime date) {
		this(SysTime(date));
	}

	this(long time){
		m_time = time;
	}

	this(in SysTime time){
		auto zero = unixTimeToStdTime(0);
		m_time = (time.stdTime() - zero) / 10_000L;
	}

	static BsonDate fromString(string iso_ext_string) { return BsonDate(SysTime.fromISOExtString(iso_ext_string)); }

	string toString() const { return toSysTime().toISOExtString(); }

	SysTime toSysTime() const {
		auto zero = unixTimeToStdTime(0);
		return SysTime(zero + m_time * 10_000L, UTC());
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


/**
	Represents a BSON timestamp value (Bson.Type.Timestamp)
*/
struct BsonTimestamp {
	private long m_time;

	this( long time ){
		m_time = time;
	}
}


/**
	Represents a BSON regular expression value (Bson.Type.Regex).
*/
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


/**
	Serializes the given value to BSON.

	The following types of values are supported:

	$(DL
		$(DT Bson)            $(DD Used as-is)
		$(DT Json)            $(DD Converted to BSON)
		$(DT BsonBinData)     $(DD Converted to Bson.Type.BinData)
		$(DT BsonObjectID)    $(DD Converted to Bson.Type.ObjectID)
		$(DT BsonDate)        $(DD Converted to Bson.Type.Date)
		$(DT BsonTimestamp)   $(DD Converted to Bson.Type.Timestamp)
		$(DT BsonRegex)       $(DD Converted to Bson.Type.Regex)
		$(DT null)            $(DD Converted to Bson.Type.Null)
		$(DT bool)            $(DD Converted to Bson.Type.Bool)
		$(DT float, double)   $(DD Converted to Bson.Type.Double)
		$(DT short, ushort, int, uint, long, ulong) $(DD Converted to Bson.Type.Long)
		$(DT string)          $(DD Converted to Bson.Type.String)
		$(DT ubyte[])         $(DD Converted to Bson.Type.BinData)
		$(DT T[])             $(DD Converted to Bson.Type.Array)
		$(DT T[string])       $(DD Converted to Bson.Type.Object)
		$(DT struct)          $(DD Converted to Bson.Type.Object)
		$(DT class)           $(DD Converted to Bson.Type.Object or Bson.Type.Null)
	)

	All entries of an array or an associative array, as well as all R/W properties and
	all fields of a struct/class are recursively serialized using the same rules.

	Fields ending with an underscore will have the last underscore stripped in the
	serialized output. This makes it possible to use fields with D keywords as their name
	by simply appending an underscore.

	The following methods can be used to customize the serialization of structs/classes:

	---
	Bson toBson() const;
	static T fromBson(Bson src);

	Json toJson() const;
	static T fromJson(Json src);

	string toString() const;
	static T fromString(string src);
	---

	The methods will have to be defined in pairs. The first pair that is implemented by
	the type will be used for serialization (i.e. toBson overrides toJson).
*/
Bson serializeToBson(T)(T value)
{
    alias Unqual!T Unqualified;
	static if( is(Unqualified == Bson) ) return value;
	else static if( is(Unqualified == Json) ) return Bson.fromJson(value);
	else static if( is(Unqualified == BsonBinData) ) return Bson(value);
	else static if( is(Unqualified == BsonObjectID) ) return Bson(value);
	else static if( is(Unqualified == BsonDate) ) return Bson(value);
	else static if( is(Unqualified == BsonTimestamp) ) return Bson(value);
	else static if( is(Unqualified == BsonRegex) ) return Bson(value);
	else static if( is(Unqualified == DateTime) ) return Bson(BsonDate(value));
	else static if( is(Unqualified == SysTime) ) return Bson(BsonDate(value));
	else static if( is(Unqualified == typeof(null)) ) return Bson(null);
	else static if( is(Unqualified == bool) ) return Bson(value);
	else static if( is(Unqualified == float) ) return Bson(cast(double)value);
	else static if( is(Unqualified == double) ) return Bson(value);
	else static if( is(Unqualified : int) ) return Bson(cast(int)value);
	else static if( is(Unqualified : long) ) return Bson(cast(long)value);
	else static if( is(Unqualified == string) ) return Bson(value);
	else static if( is(Unqualified : const(ubyte)[]) ) return Bson(BsonBinData(BsonBinData.Type.Generic, value.idup));
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
	} else static if( __traits(compiles, value = T.fromBson(value.toBson())) ){
		return value.toBson();
	} else static if( __traits(compiles, value = T.fromJson(value.toJson())) ){
		return Bson.fromJson(value.toJson());
	} else static if( __traits(compiles, value = T.fromString(value.toString())) ){
		return Bson(value.toString());
	} else static if( is(Unqualified == struct) ){
		Bson[string] ret;
		foreach( m; __traits(allMembers, T) ){
			static if( isRWField!(Unqualified, m) ){
				auto mv = __traits(getMember, value, m);
				ret[underscoreStrip(m)] = serializeToBson(mv);
			}
		}
		return Bson(ret);
	} else static if( is(Unqualified == class) ){
		if( value is null ) return Bson(null);
		Bson[string] ret;
		foreach( m; __traits(allMembers, T) ){
			static if( isRWField!(Unqualified, m) ){
				auto mv = __traits(getMember, value, m);
				ret[underscoreStrip(m)] = serializeToBson(mv);
			}
		}
		return Bson(ret);
	} else {
		static assert(false, "Unsupported type '"~T.stringof~"' for BSON serialization.");
	}
}


/**
	Deserializes a BSON value into the destination variable.

	The same types as for serializeToBson() are supported and handled inversely.
*/
void deserializeBson(T)(ref T dst, Bson src)
{
	dst = deserializeBson!T(src);
}
/// ditto
T deserializeBson(T)(Bson src)
{
	static if( is(T == Bson) ) return src;
	else static if( is(T == Json) ) return src.toJson();
	else static if( is(T == BsonBinData) ) return cast(T)src;
	else static if( is(T == BsonObjectID) ) return cast(T)src;
	else static if( is(T == BsonDate) ) return cast(T)src;
	else static if( is(T == BsonTimestamp) ) return cast(T)src;
	else static if( is(T == BsonRegex) ) return cast(T)src;
	else static if( is(T == SysTime) ) return src.get!BsonDate().toSysTime();
	else static if( is(T == DateTime) ) return cast(DateTime)src.get!BsonDate().toSysTime();
	else static if( is(T == typeof(null)) ){ return null; }
	else static if( is(T == bool) ) return cast(bool)src;
	else static if( is(T == float) ) return cast(double)src;
	else static if( is(T == double) ) return cast(double)src;
	else static if( is(T : int) ) return cast(T)cast(int)src;
	else static if( is(T : long) ) return cast(T)cast(long)src;
	else static if( is(T == string) ) return cast(string)src;
	else static if( is(T : const(ubyte)[]) ) return cast(T)src.get!BsonBinData.rawData.dup;
	else static if( isArray!T ){
		alias typeof(T.init[0]) TV;
		auto ret = new Unqual!TV[src.length];
		foreach( size_t i, v; cast(Bson[])src )
			ret[i] = deserializeBson!(Unqual!TV)(v);
		return ret;
	} else static if( isAssociativeArray!T ){
		alias typeof(T.init.values[0]) TV;
		Unqual!TV[string] dst;
		foreach( string key, value; cast(Bson[string])src )
			dst[key] = deserializeBson!(Unqual!TV)(value);
		return dst;
	} else static if( __traits(compiles, { T dst; dst = T.fromBson(dst.toBson()); }) ){
		return T.fromBson(src);
	} else static if( __traits(compiles, { T dst; dst = T.fromJson(dst.toJson()); }) ){
		return T.fromJson(src.toJson());
	} else static if( __traits(compiles, { T dst; dst = T.fromString(dst.toString()); }) ){
		return T.fromString(cast(string)src);
	} else static if( is(T == struct) ){
		T dst;
		foreach( m; __traits(allMembers, T) ){
			static if( isRWPlainField!(T, m) || isRWField!(T, m) ){
				alias typeof(__traits(getMember, dst, m)) TM;
				debug enforce(!src[underscoreStrip(m)].isNull() || is(TM == class) || isPointer!TM || is(TM == typeof(null)),
					"Missing field '"~underscoreStrip(m)~"'.");
				__traits(getMember, dst, m) = deserializeBson!TM(src[underscoreStrip(m)]);
			}
		}
		return dst;
	} else static if( is(T == class) ){
		if (src.isNull()) return null;
		auto dst = new T;
		foreach( m; __traits(allMembers, T) ){
			static if( isRWPlainField!(T, m) || isRWField!(T, m) ){
				alias typeof(__traits(getMember, dst, m)) TM;
				__traits(getMember, dst, m) = deserializeBson!TM(src[underscoreStrip(m)]);
			}
		}
		return dst;
	} else static if( isPointer!T ){
		if( src.type == Bson.Type.Null ) return null;
		alias typeof(*T.init) TD;
		dst = new TD;
		*dst = deserializeBson!TD(src);
		return dst;
	} else {
		static assert(false, "Unsupported type '"~T.stringof~"' for BSON serialization.");
	}
}

unittest {
	import std.stdio;
	static struct S { float a; double b; bool c; int d; string e; byte f; ubyte g; long h; ulong i; float[] j; }
	immutable S t = {1.5, -3.0, true, int.min, "Test", -128, 255, long.min, ulong.max, [1.1, 1.2, 1.3]};
	S u;
	deserializeBson(u, serializeToBson(t));
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
	deserializeBson(d, serializeToBson(c));
	assert(c.a == d.a);
	assert(c.b == d.b);
}


private Bson.Type writeBson(R)(ref R dst, in Json value)
	if( isOutputRange!(R, ubyte) )
{
    static immutable uint[] JsonIDToBsonID = [
        Bson.Type.Undefined,
        Bson.Type.Null,
        Bson.Type.Bool,
        Bson.Type.Int,
        Bson.Type.Double,
        Bson.Type.String,
        Bson.Type.Array,
        Bson.Type.Object
    ];
    
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
			dst.put(toBsonData(cast(uint)value.length+1));
			dst.put(cast(bdata_t)cast(string)value);
			dst.put(cast(ubyte)0);
			return Bson.Type.String;
		case Json.Type.Array:
			auto app = appender!bdata_t();
			foreach( size_t i, ref const Json v; value ){
				app.put(cast(ubyte)(JsonIDToBsonID[v.type]));
				putCString(app, to!string(i));
				writeBson(app, v);
			}

            dst.put(toBsonData(cast(int)(app.data.length + int.sizeof + 1)));
			dst.put(app.data);
			dst.put(cast(ubyte)0);
			return Bson.Type.Array;
		case Json.Type.Object:
			auto app = appender!bdata_t();
			foreach( string k, ref const Json v; value ){
				app.put(cast(ubyte)(JsonIDToBsonID[v.type]));
				putCString(app, k);
				writeBson(app, v);
			}

			dst.put(toBsonData(cast(int)(app.data.length + int.sizeof + 1)));
			dst.put(app.data);
			dst.put(cast(ubyte)0);
			return Bson.Type.Object;
	}
}

unittest
{
    Json jsvalue = parseJsonString("{\"key\" : \"Value\"}");
    assert(serializeToBson(jsvalue).toJson() == jsvalue);
    
    jsvalue = parseJsonString("{\"key\" : [{\"key\" : \"Value\"}, {\"key2\" : \"Value2\"}] }");
    assert(serializeToBson(jsvalue).toJson() == jsvalue);
    
    jsvalue = parseJsonString("[ 1 , 2 , 3]");
    assert(serializeToBson(jsvalue).toJson() == jsvalue);
}

private string skipCString(ref bdata_t data)
{
	auto idx = data.countUntil(0);
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

private string underscoreStrip(string field_name)
pure {
	if( field_name.length < 1 || field_name[$-1] != '_' ) return field_name;
	else return field_name[0 .. $-1];
}

