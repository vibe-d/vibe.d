/**
	BSON serialization and value handling.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.data.bson;

public import vibe.data.json;
import vibe.core.log;

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
		end        = 0x00,  /// End marker - should never occur explicitly
		double_    = 0x01,  /// A 64-bit floating point value
		string     = 0x02,  /// A UTF-8 string
		object     = 0x03,  /// An object aka. dictionary of string to Bson
		array      = 0x04,  /// An array of BSON values
		binData    = 0x05,  /// Raw binary data (ubyte[])
		undefined  = 0x06,  /// Deprecated
		objectID   = 0x07,  /// BSON Object ID (96-bit)
		bool_      = 0x08,  /// Boolean value
		date       = 0x09,  /// Date value (UTC)
		null_      = 0x0A,  /// Null value
		regex      = 0x0B,  /// Regular expression
		dbRef      = 0x0C,  /// Deprecated
		code       = 0x0D,  /// JaveScript code
		symbol     = 0x0E,  /// Symbol/variable name
		codeWScope = 0x0F,  /// JavaScript code with scope
		int_       = 0x10,  /// 32-bit integer
		timestamp  = 0x11,  /// Timestamp value
		long_      = 0x12,  /// 64-bit integer
		minKey     = 0xff,  /// Internal value
		maxKey     = 0x7f,  /// Internal value

		End = end,                /// Compatibility alias - will be deprecated soon.
		Double = double_,         /// Compatibility alias - will be deprecated soon.
		String = string,          /// Compatibility alias - will be deprecated soon.
		Object = object,          /// Compatibility alias - will be deprecated soon.
		Array = array,            /// Compatibility alias - will be deprecated soon.
		BinData = binData,        /// Compatibility alias - will be deprecated soon.
		Undefined = undefined,    /// Compatibility alias - will be deprecated soon.
		ObjectID = objectID,      /// Compatibility alias - will be deprecated soon.
		Bool = bool_,             /// Compatibility alias - will be deprecated soon.
		Date = date,              /// Compatibility alias - will be deprecated soon.
		Null = null_,             /// Compatibility alias - will be deprecated soon.
		Regex = regex,            /// Compatibility alias - will be deprecated soon.
		DBRef = dbRef,            /// Compatibility alias - will be deprecated soon.
		Code = code,              /// Compatibility alias - will be deprecated soon.
		Symbol = symbol,          /// Compatibility alias - will be deprecated soon.
		CodeWScope = codeWScope,  /// Compatibility alias - will be deprecated soon.
		Int = int_,               /// Compatibility alias - will be deprecated soon.
		Timestamp = timestamp,    /// Compatibility alias - will be deprecated soon.
		Long = long_,             /// Compatibility alias - will be deprecated soon.
		MinKey = minKey,          /// Compatibility alias - will be deprecated soon.
		MaxKey = maxKey           /// Compatibility alias - will be deprecated soon.
	}

	/// Returns a new, empty Bson value of type Object.
	static @property Bson emptyObject() { return Bson(cast(Bson[string])null); }

	/// Returns a new, empty Bson value of type Object.
	static @property Bson emptyArray() { return Bson(cast(Bson[])null); }

	/// Deprecated compatibility alias.
	deprecated("Please use emptyObject instead.")
	alias EmptyObject = emptyObject;
	/// Deprecated compatibility alias.
	deprecated("Please use emptyArray instead.")
	alias EmptyArray = emptyArray;

	private {
		Type m_type = Type.undefined;
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
			case Type.end: m_data = null; break;
			case Type.double_: m_data = m_data[0 .. 8]; break;
			case Type.string: m_data = m_data[0 .. 4 + fromBsonData!int(m_data)]; break;
			case Type.object: m_data = m_data[0 .. fromBsonData!int(m_data)]; break;
			case Type.array: m_data = m_data[0 .. fromBsonData!int(m_data)]; break;
			case Type.binData: m_data = m_data[0 .. 5 + fromBsonData!int(m_data)]; break;
			case Type.undefined: m_data = null; break;
			case Type.objectID: m_data = m_data[0 .. 12]; break;
			case Type.bool_: m_data = m_data[0 .. 1]; break;
			case Type.date: m_data = m_data[0 .. 8]; break;
			case Type.null_: m_data = null; break;
			case Type.regex:
				auto tmp = m_data;
    			tmp.skipCString();
    			tmp.skipCString();
    			m_data = m_data[0 .. $ - tmp.length];
    			break;
			case Type.dbRef: m_data = m_data[0 .. 0]; assert(false, "Not implemented.");
			case Type.code: m_data = m_data[0 .. 4 + fromBsonData!int(m_data)]; break;
			case Type.symbol: m_data = m_data[0 .. 4 + fromBsonData!int(m_data)]; break;
			case Type.codeWScope: m_data = m_data[0 .. 0]; assert(false, "Not implemented.");
			case Type.int_: m_data = m_data[0 .. 4]; break;
			case Type.timestamp: m_data = m_data[0 .. 8]; break;
			case Type.long_: m_data = m_data[0 .. 8]; break;
			case Type.minKey: m_data = null; break;
			case Type.maxKey: m_data = null; break;
		}
	}

	/**
		Initializes a new BSON value from the given D type.
	*/
	this(double value) { opAssign(value); }
	/// ditto
	this(string value, Type type = Type.string)
	{
		assert(type == Type.string || type == Type.code || type == Type.symbol);
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
		m_type = Type.double_;
	}
	/// ditto
	void opAssign(string value)
	{
		import std.utf;
		debug std.utf.validate(value);
		auto app = appender!bdata_t();
		app.put(toBsonData(cast(int)value.length+1));
		app.put(cast(bdata_t)value);
		app.put(cast(ubyte)0);
		m_data = app.data;
		m_type = Type.string;
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
		m_type = Type.object;
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
		m_type = Type.array;
	}
	/// ditto
	void opAssign(in BsonBinData value)
	{
		auto app = appender!bdata_t();
		app.put(toBsonData(cast(int)value.rawData.length));
		app.put(value.type);
		app.put(value.rawData);

		m_data = app.data;
		m_type = Type.binData;
	}
	/// ditto
	void opAssign(in BsonObjectID value)
	{
		m_data = value.m_bytes.idup;
		m_type = Type.objectID;
	}
	/// ditto
	void opAssign(bool value)
	{
		m_data = [value ? 0x01 : 0x00];
		m_type = Type.bool_;
	}
	/// ditto
	void opAssign(in BsonDate value)
	{
		m_data = toBsonData(value.m_time).idup;
		m_type = Type.date;
	}
	/// ditto
	void opAssign(typeof(null))
	{
		m_data = null;
		m_type = Type.null_;
	}
	/// ditto
	void opAssign(in BsonRegex value)
	{
		auto app = appender!bdata_t();
		putCString(app, value.expression);
		putCString(app, value.options);
		m_data = app.data;
		m_type = type.regex;
	}
	/// ditto
	void opAssign(int value)
	{
		m_data = toBsonData(value).idup;
		m_type = Type.int_;
	}
	/// ditto
	void opAssign(in BsonTimestamp value)
	{
		m_data = toBsonData(value.m_time).idup;
		m_type = Type.timestamp;
	}
	/// ditto
	void opAssign(long value)
	{
		m_data = toBsonData(value).idup;
		m_type = Type.long_;
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

	bool isNull() const { return m_type == Type.null_; }

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
		static if( is(T == double) ){ checkType(Type.double_); return fromBsonData!double(m_data); }
		else static if( is(T == string) ){
			checkType(Type.string, Type.code, Type.symbol);
			return cast(string)m_data[4 .. 4+fromBsonData!int(m_data)-1];
		}
		else static if( is(Unqual!T == Bson[string]) || is(Unqual!T == const(Bson)[string]) ){
			checkType(Type.object);
			Bson[string] ret;
			auto d = m_data[4 .. $];
			while( d.length > 0 ){
				auto tp = cast(Type)d[0];
				if( tp == Type.end ) break;
				d = d[1 .. $];
				auto key = skipCString(d);
				auto value = Bson(tp, d);
				d = d[value.data.length .. $];

				ret[key] = value;
			}
			return cast(T)ret;
		}
		else static if( is(Unqual!T == Bson[]) || is(Unqual!T == const(Bson)[]) ){
			checkType(Type.array);
			Bson[] ret;
			auto d = m_data[4 .. $];
			while( d.length > 0 ){
				auto tp = cast(Type)d[0];
				if( tp == Type.end ) break;
				/*auto key = */skipCString(d); // should be '0', '1', ...
				auto value = Bson(tp, d);
				d = d[value.data.length .. $];

				ret ~= value;
			}
			return cast(T)ret;
		}
		else static if( is(T == BsonBinData) ){
			checkType(Type.binData);
			auto size = fromBsonData!int(m_data);
			auto type = cast(BsonBinData.Type)m_data[4];
			return BsonBinData(type, m_data[5 .. 5+size]);
		}
		else static if( is(T == BsonObjectID) ){ checkType(Type.objectID); return BsonObjectID(m_data[0 .. 12]); }
		else static if( is(T == bool) ){ checkType(Type.bool_); return m_data[0] != 0; }
		else static if( is(T == BsonDate) ){ checkType(Type.date); return BsonDate(fromBsonData!long(m_data)); }
		else static if( is(T == BsonRegex) ){
			checkType(Type.regex);
			auto d = m_data;
			auto expr = skipCString(d);
			auto options = skipCString(d);
			return BsonRegex(expr, options);
		}
		else static if( is(T == int) ){ checkType(Type.int_); return fromBsonData!int(m_data); }
		else static if( is(T == BsonTimestamp) ){ checkType(Type.timestamp); return BsonTimestamp(fromBsonData!long(m_data)); }
		else static if( is(T == long) ){ checkType(Type.long_); return fromBsonData!long(m_data); }
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
			case Type.string, Type.code, Type.symbol: return (cast(string)this).length;
			case Type.array: return (cast(const(Bson)[])this).length; // TODO: optimize!
			case Type.object: return (cast(const(Bson)[string])this).length; // TODO: optimize!
			case Type.binData: assert(false); //return (cast(BsonBinData)this).length; break;
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
			case Bson.Type.double_: return Json(get!double());
			case Bson.Type.string: return Json(get!string());
			case Bson.Type.object:
				Json[string] ret;
				foreach( k, v; get!(Bson[string])() )
					ret[k] = v.toJson();
				return Json(ret);
			case Bson.Type.array:
				auto ret = new Json[this.length];
				foreach( i, v; get!(Bson[])() )
					ret[i] = v.toJson();
				return Json(ret);
			case Bson.Type.binData: return Json(cast(string)Base64.encode(get!BsonBinData.rawData));
			case Bson.Type.objectID: return Json(get!BsonObjectID().toString());
			case Bson.Type.bool_: return Json(get!bool());
			case Bson.Type.date: return Json(get!BsonDate.toString());
			case Bson.Type.null_: return Json(null);
			case Bson.Type.regex: assert(false, "TODO");
			case Bson.Type.dbRef: assert(false, "TODO");
			case Bson.Type.code: return Json(get!string());
			case Bson.Type.symbol: return Json(get!string());
			case Bson.Type.codeWScope: assert(false, "TODO");
			case Bson.Type.int_: return Json(get!int());
			case Bson.Type.timestamp: return Json(get!BsonTimestamp().m_time);
			case Bson.Type.long_: return Json(get!long());
		}
	}

	/** Returns a string representation of this BSON value in JSON format.
	*/
	string toString()
	const {
		return toJson().toString();
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
		checkType(Type.object);
		auto d = m_data[4 .. $];
		while( d.length > 0 ){
			auto tp = cast(Type)d[0];
			if( tp == Type.end ) break;
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
		checkType(Type.array, Type.object);
		if( m_type == Type.array ){
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
		checkType(Type.array);
		auto d = m_data[4 .. $];
		size_t i = 0;
		while( d.length > 0 ){
			auto tp = cast(Type)d[0];
			if( tp == Type.end ) break;
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
		checkType(Type.object);
		auto d = m_data[4 .. $];
		while( d.length > 0 ){
			auto tp = cast(Type)d[0];
			if( tp == Type.end ) break;
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
	Represents a BSON binary data value (Bson.Type.binData).
*/
struct BsonBinData {
	enum Type : ubyte {
		generic = 0x00,
		function_ = 0x01,
		binaryOld = 0x02,
		uuid = 0x03,
		md5 = 0x05,
		userDefined = 0x80,

		Generic = generic,          /// Compatibility alias - will be deprecated soon
		Function = function_,       /// Compatibility alias - will be deprecated soon
		BinaryOld = binaryOld,      /// Compatibility alias - will be deprecated soon
		UUID = uuid,                /// Compatibility alias - will be deprecated soon
		MD5 = md5,                  /// Compatibility alias - will be deprecated soon
		UserDefined	= userDefined,  /// Compatibility alias - will be deprecated soon
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
	Represents a BSON object id (Bson.Type.binData).
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
		m_bytes[] = bytes[];
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
				ret.m_bytes[j*4 .. (j+1)*4] = toBigEndianData(b)[];
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
		ret.m_bytes[0 .. 4] = toBigEndianData(cast(uint)unixTime)[];
		ret.m_bytes[4 .. 7] = toBsonData(MACHINE_ID)[0 .. 3];
		ret.m_bytes[7 .. 9] = toBsonData(cast(ushort)ms_pid)[];
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
		ret.m_bytes[0 .. 4] = toBigEndianData(cast(uint)date.toUnixTime())[];
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
	Represents a BSON date value (Bson.Type.date).

	BSON date values are stored in UNIX time format, counting the number of
	milliseconds from 1970/01/01.
*/
struct BsonDate {
	private long m_time; // milliseconds since UTC unix epoch

	/** Constructs a BsonDate from the given date value.

		The time-zone independent Date and DateTime types are assumed to be in
		the local time zone and converted to UTC if tz is left to null.
	*/
	this(in Date date, immutable TimeZone tz = null) { this(SysTime(date, tz)); }
	/// ditto
	this(in DateTime date, immutable TimeZone tz = null) { this(SysTime(date, tz)); }
	/// ditto
	this(in SysTime date) { this(fromStdTime(date.stdTime()).m_time); }

	/** Constructs a BsonDate from the given UNIX time.

		unix_time needs to be given in milliseconds from 1970/01/01. This is
		the native storage format for BsonDate.
	*/
	this(long unix_time)
	{
		m_time = unix_time;
	}

	/** Constructs a BsonDate from the given date/time string in ISO extended format.
	*/
	static BsonDate fromString(string iso_ext_string) { return BsonDate(SysTime.fromISOExtString(iso_ext_string)); }

	/** Constructs a BsonDate from the given date/time in standard time as defined in std.datetime.
	*/
	static BsonDate fromStdTime(long std_time)
	{
		enum zero = unixTimeToStdTime(0);
		return BsonDate((std_time - zero) / 10_000L);
	}

	/** The raw unix time value.

		This is the native storage/transfer format of a BsonDate.
	*/
	@property long value() const { return m_time; }
	/// ditto
	@property void value(long v) { m_time = v; }

	/** Returns the date formatted as ISO extended format.
	*/
	string toString() const { return toSysTime().toISOExtString(); }

	/* Converts to a SysTime.
	*/
	SysTime toSysTime() const {
		auto zero = unixTimeToStdTime(0);
		return SysTime(zero + m_time * 10_000L, UTC());
	}

	/** Allows relational and equality comparisons.
	*/
	bool opEquals(ref const BsonDate other) const { return m_time == other.m_time; }
	/// ditto
	int opCmp(ref const BsonDate other) const {
		if( m_time == other.m_time ) return 0;
		if( m_time < other.m_time ) return -1;
		else return 1;
	}
}


/**
	Represents a BSON timestamp value (Bson.Type.timestamp)
*/
struct BsonTimestamp {
	private long m_time;

	this( long time ){
		m_time = time;
	}
}


/**
	Represents a BSON regular expression value (Bson.Type.regex).
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
		$(DT BsonBinData)     $(DD Converted to Bson.Type.binData)
		$(DT BsonObjectID)    $(DD Converted to Bson.Type.objectID)
		$(DT BsonDate)        $(DD Converted to Bson.Type.date)
		$(DT BsonTimestamp)   $(DD Converted to Bson.Type.timestamp)
		$(DT BsonRegex)       $(DD Converted to Bson.Type.regex)
		$(DT null)            $(DD Converted to Bson.Type.null_)
		$(DT bool)            $(DD Converted to Bson.Type.bool_)
		$(DT float, double)   $(DD Converted to Bson.Type.double_)
		$(DT short, ushort, int, uint, long, ulong) $(DD Converted to Bson.Type.long_)
		$(DT string)          $(DD Converted to Bson.Type.string)
		$(DT ubyte[])         $(DD Converted to Bson.Type.binData)
		$(DT T[])             $(DD Converted to Bson.Type.array)
		$(DT T[string])       $(DD Converted to Bson.Type.object)
		$(DT struct)          $(DD Converted to Bson.Type.object)
		$(DT class)           $(DD Converted to Bson.Type.object or Bson.Type.null_)
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
Bson serializeToBson(T)(T value, ubyte[] buffer = null)
{
	version (VibeOldSerialization) {
		return serializeToBsonOld(value);
	} else {
		return serialize!BsonSerializer(value, buffer);
	}
}

/// private
Bson serializeToBsonOld(T)(T value)
{
    alias Unqual!T Unqualified;
	static if (is(Unqualified == Bson)) return value;
	else static if (is(Unqualified == Json)) return Bson.fromJson(value);
	else static if (is(Unqualified == BsonBinData)) return Bson(value);
	else static if (is(Unqualified == BsonObjectID)) return Bson(value);
	else static if (is(Unqualified == BsonDate)) return Bson(value);
	else static if (is(Unqualified == BsonTimestamp)) return Bson(value);
	else static if (is(Unqualified == BsonRegex)) return Bson(value);
	else static if (is(Unqualified == DateTime)) return Bson(BsonDate(value, UTC()));
	else static if (is(Unqualified == SysTime)) return Bson(BsonDate(value));
	else static if (is(Unqualified == Date)) return Bson(BsonDate(value, UTC()));
	else static if (is(Unqualified == typeof(null))) return Bson(null);
	else static if (is(Unqualified == bool)) return Bson(value);
	else static if (is(Unqualified == float)) return Bson(cast(double)value);
	else static if (is(Unqualified == double)) return Bson(value);
	else static if (is(Unqualified : int)) return Bson(cast(int)value);
	else static if (is(Unqualified : long)) return Bson(cast(long)value);
	else static if (is(Unqualified : string)) return Bson(value);
	else static if (is(Unqualified : const(ubyte)[])) return Bson(BsonBinData(BsonBinData.Type.generic, value.idup));
	else static if (isArray!T) {
		auto ret = new Bson[value.length];
		foreach (i; 0 .. value.length)
			ret[i] = serializeToBson(value[i]);
		return Bson(ret);
	} else static if (isAssociativeArray!T) {
		Bson[string] ret;
		alias KeyType!T TK;
		foreach (key, value; value) {
			static if(is(TK == string)) {
				ret[key] = serializeToBson(value);
			} else static if (is(TK == enum)) {
				ret[to!string(key)] = serializeToBson(value);
			} else static if (isStringSerializable!(TK)) {
				ret[key.toString()] = serializeToBson(value);
			} else static assert("AA key type %s not supported for BSON serialization.");
		}
		return Bson(ret);
	} else static if (isBsonSerializable!Unqualified) {
		return value.toBson();
	} else static if (isJsonSerializable!Unqualified) {
		return Bson.fromJson(value.toJson());
	} else static if (isStringSerializable!Unqualified) {
		return Bson(value.toString());
	} else static if (is(Unqualified == struct)) {
		Bson[string] ret;
		foreach (m; __traits(allMembers, T)) {
			static if (isRWField!(Unqualified, m)) {
				auto mv = __traits(getMember, value, m);
				ret[underscoreStrip(m)] = serializeToBson(mv);
			}
		}
		return Bson(ret);
	} else static if (is(Unqualified == class)) {
		if (value is null) return Bson(null);
		Bson[string] ret;
		foreach (m; __traits(allMembers, T)) {
			static if (isRWField!(Unqualified, m)) {
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
	version (VibeOldSerialization) {
		return deserializeBsonOld!T(src);
	} else {
		return deserialize!(BsonSerializer, T)(src);
	}
}

/// private
T deserializeBsonOld(T)(Bson src)
{
	static if (is(T == Bson)) return src;
	else static if (is(T == Json)) return src.toJson();
	else static if (is(T == BsonBinData)) return cast(T)src;
	else static if (is(T == BsonObjectID)) return cast(T)src;
	else static if (is(T == BsonDate)) return cast(T)src;
	else static if (is(T == BsonTimestamp)) return cast(T)src;
	else static if (is(T == BsonRegex)) return cast(T)src;
	else static if (is(T == SysTime)) return src.get!BsonDate().toSysTime();
	else static if (is(T == DateTime)) return cast(DateTime)src.get!BsonDate().toSysTime();
	else static if (is(T == Date)) return cast(Date)src.get!BsonDate().toSysTime();
	else static if (is(T == typeof(null))) return null;
	else static if (is(T == bool)) return cast(bool)src;
	else static if (is(T == float)) return cast(double)src;
	else static if (is(T == double)) return cast(double)src;
	else static if (is(T : int)) return cast(T)cast(int)src;
	else static if (is(T : long)) return cast(T)cast(long)src;
	else static if (is(T : string)) return cast(T)(cast(string)src);
	else static if (is(T : const(ubyte)[])) return cast(T)src.get!BsonBinData.rawData.dup;
	else static if (isArray!T) {
		alias typeof(T.init[0]) TV;
		auto ret = new Unqual!TV[src.length];
		foreach (size_t i, v; cast(Bson[])src)
			ret[i] = deserializeBson!(Unqual!TV)(v);
		return ret;
	} else static if (isAssociativeArray!T) {
		alias typeof(T.init.values[0]) TV;
		alias KeyType!T TK;
		Unqual!TV[TK] dst;
		foreach (string key, value; src) {
			static if (is(TK == string)) {
				dst[key] = deserializeBson!(Unqual!TV)(value);
			} else static if (is(TK == enum)) {
				dst[to!(TK)(key)] = deserializeBson!(Unqual!TV)(value);
			} else static if (isStringSerializable!TK) {
				auto dsk = TK.fromString(key);
				dst[dsk] = deserializeBson!(Unqual!TV)(value);
			} else static assert("AA key type %s not supported for BSON serialization.");
		}
		return dst;
	} else static if (isBsonSerializable!T) {
		return T.fromBson(src);
	} else static if (isJsonSerializable!T) {
		return T.fromJson(src.toJson());
	} else static if (isStringSerializable!T) {
		return T.fromString(cast(string)src);
	} else static if (is(T == struct)) {
		T dst;
		foreach (m; __traits(allMembers, T)) {
			static if (isRWPlainField!(T, m) || isRWField!(T, m)) {
				alias typeof(__traits(getMember, dst, m)) TM;
				debug enforce(!src[underscoreStrip(m)].isNull() || is(TM == class) || isPointer!TM || is(TM == typeof(null)),
					"Missing field '"~underscoreStrip(m)~"'.");
				__traits(getMember, dst, m) = deserializeBson!TM(src[underscoreStrip(m)]);
			}
		}
		return dst;
	} else static if (is(T == class)) {
		if (src.isNull()) return null;
		auto dst = new T;
		foreach (m; __traits(allMembers, T)) {
			static if (isRWPlainField!(T, m) || isRWField!(T, m)) {
				alias typeof(__traits(getMember, dst, m)) TM;
				__traits(getMember, dst, m) = deserializeBson!TM(src[underscoreStrip(m)]);
			}
		}
		return dst;
	} else static if (isPointer!T) {
		if (src.type == Bson.Type.null_) return null;
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
	enum Foo : string { k = "test" }
	enum Boo : int { l = 5 }
	static struct S { float a; double b; bool c; int d; string e; byte f; ubyte g; long h; ulong i; float[] j; Foo k; Boo l;}
	immutable S t = {1.5, -3.0, true, int.min, "Test", -128, 255, long.min, ulong.max, [1.1, 1.2, 1.3], Foo.k, Boo.l,};
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
	assert(t.k == u.k);
	assert(t.l == u.l);
}

unittest
{
    assert(uint.max == serializeToBson(uint.max).deserializeBson!uint);
    assert(ulong.max == serializeToBson(ulong.max).deserializeBson!ulong);
}

unittest {
	assert(deserializeBson!SysTime(serializeToBson(SysTime(0))) == SysTime(0));
	assert(deserializeBson!SysTime(serializeToBson(SysTime(0, UTC()))) == SysTime(0, UTC()));
	assert(deserializeBson!Date(serializeToBson(Date.init)) == Date.init);
	assert(deserializeBson!Date(serializeToBson(Date(2001, 1, 1))) == Date(2001, 1, 1));
}

unittest {
	static struct A { int value; static A fromJson(Json val) { return A(val.get!int); } Json toJson() const { return Json(value); } Bson toBson() { return Bson(); } }
	static assert(!isStringSerializable!A && isJsonSerializable!A && !isBsonSerializable!A);
	static assert(!isStringSerializable!(const(A)) && !isJsonSerializable!(const(A)) && !isBsonSerializable!(const(A)));
	assert(serializeToBson(const A(123)) == Bson(123));
	assert(serializeToBson(A(123))       == Bson(123));

	static struct B { int value; static B fromBson(Bson val) { return B(val.get!int); } Bson toBson() const { return Bson(value); } Json toJson() { return Json(); } }
	static assert(!isStringSerializable!B && !isJsonSerializable!B && isBsonSerializable!B);
	static assert(!isStringSerializable!(const(B)) && !isJsonSerializable!(const(B)) && !isBsonSerializable!(const(B)));
	assert(serializeToBson(const B(123)) == Bson(123));
	assert(serializeToBson(B(123))       == Bson(123));

	static struct C { int value; static C fromString(string val) { return C(val.to!int); } string toString() const { return value.to!string; } Json toJson() { return Json(); } }
	static assert(isStringSerializable!C && !isJsonSerializable!C && !isBsonSerializable!C);
	static assert(!isStringSerializable!(const(C)) && !isJsonSerializable!(const(C)) && !isBsonSerializable!(const(C)));
	assert(serializeToBson(const C(123)) == Bson("123"));
	assert(serializeToBson(C(123))       == Bson("123"));

	static struct D { int value; string toString() const { return ""; } }
	static assert(!isStringSerializable!D && !isJsonSerializable!D && !isBsonSerializable!D);
	static assert(!isStringSerializable!(const(D)) && !isJsonSerializable!(const(D)) && !isBsonSerializable!(const(D)));
	assert(serializeToBson(const D(123)) == serializeToBson(["value": 123]));
	assert(serializeToBson(D(123))       == serializeToBson(["value": 123]));

	// test if const(class) is serializable
	static class E { int value; this(int v) { value = v; } static E fromBson(Bson val) { return new E(val.get!int); } Bson toBson() const { return Bson(value); } Json toJson() { return Json(); } }
	static assert(!isStringSerializable!E && !isJsonSerializable!E && isBsonSerializable!E);
	static assert(!isStringSerializable!(const(E)) && !isJsonSerializable!(const(E)) && !isBsonSerializable!(const(E)));
	assert(serializeToBson(new const E(123)) == Bson(123));
	assert(serializeToBson(new E(123))       == Bson(123));
}

unittest {
	static struct E { ubyte[4] bytes; ubyte[] more; }
	auto e = E([1, 2, 3, 4], [5, 6]);
	auto eb = serializeToBson(e);
	assert(eb.bytes.type == Bson.Type.binData);
	assert(eb.more.type == Bson.Type.binData);
	assert(e == deserializeBson!E(eb));
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

	const(C) e = c; // serialize const class instances (issue #653)
	deserializeBson(d, serializeToBson(e));
	assert(e.a == d.a);
	assert(e.b == d.b);
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
		deserializeBson(other, serializeToBson(original));
		assert(serializeToBson(other) == serializeToBson(original));
	}
	{
		static struct S {
			string[Color] enumIndexedMap;
			string[C] stringableIndexedMap;
		}

		S original;
		original.enumIndexedMap = [ Color.Red : "magenta", Color.Blue : "deep blue" ];
		original.enumIndexedMap[Color.Green] = "olive";
                original.stringableIndexedMap = [ C(42) : "forty-two" ];
		S other;
		deserializeBson(other, serializeToBson(original));
		assert(serializeToBson(other) == serializeToBson(original));
	}
}

unittest {
	ubyte[] data = [1, 2, 3];
	auto bson = serializeToBson(data);
	assert(bson.type == Bson.Type.binData);
	assert(deserializeBson!(ubyte[])(bson) == data);
}


/**
	Serializes to an in-memory BSON representation.

	See_Also: vibe.data.serialization.serialize, vibe.data.serialization.deserialize, serializeToBson, deserializeBson
*/
struct BsonSerializer {
	import vibe.utils.array : AllocAppender;

	private {
		AllocAppender!(ubyte[]) m_dst;
		size_t[] m_compositeStack;
		Bson.Type m_type = Bson.Type.null_;
		Bson m_inputData;
		string m_entryName;
		size_t m_entryIndex = size_t.max;
	}

	this(Bson input)
	{
		m_inputData = input;
	}

	this(ubyte[] buffer)
	{
		import vibe.utils.memory;
		m_dst = AllocAppender!(ubyte[])(defaultAllocator(), buffer);
	}

	@disable this(this);

	template isSupportedValueType(T) { enum isSupportedValueType = is(typeof(getBsonTypeID(T.init))); }

	//
	// serialization
	//
	Bson getSerializedResult()
	{
		auto ret = Bson(m_type, cast(immutable)m_dst.data);
		m_dst.reset();
		m_type = Bson.Type.null_;
		return ret;
	}

	void beginWriteDictionary(T)()
	{
		writeCompositeEntryHeader(Bson.Type.object);
		m_compositeStack ~= m_dst.data.length;
		m_dst.put(toBsonData(cast(int)0));
	}
	void endWriteDictionary(T)()
	{
		m_dst.put(Bson.Type.end);
		auto sh = m_compositeStack[$-1];
		m_compositeStack.length--;
		m_dst.data[sh .. sh + 4] = toBsonData(cast(uint)(m_dst.data.length - sh))[];
	}
	void beginWriteDictionaryEntry(T)(string name) { m_entryName = name; }
	void endWriteDictionaryEntry(T)(string name) {}

	void beginWriteArray(T)(size_t)
	{
		writeCompositeEntryHeader(Bson.Type.array);
		m_compositeStack ~= m_dst.data.length;
		m_dst.put(toBsonData(cast(int)0));
	}
	void endWriteArray(T)() { endWriteDictionary!T(); }
	void beginWriteArrayEntry(T)(size_t idx) { m_entryIndex = idx; }
	void endWriteArrayEntry(T)(size_t idx) {}

	// auto ref does't work for DMD 2.064
	void writeValue(T)(/*auto ref const*/ in T value) { writeValueH!(T, true)(value); }
	
	private void writeValueH(T, bool write_header)(/*auto ref const*/ in T value)
	{
		static if (write_header) writeCompositeEntryHeader(getBsonTypeID(value));

		static if (is(T == Bson)) { m_dst.put(value.data); }
		else static if (is(T == Json)) { m_dst.put(Bson(value).data); } // FIXME: use .writeBsonValue
		else static if (is(T == typeof(null))) {}
		else static if (is(T == string)) { m_dst.put(toBsonData(cast(uint)value.length+1)); m_dst.putCString(value); }
		else static if (is(T == BsonBinData)) { m_dst.put(toBsonData(cast(int)value.rawData.length)); m_dst.put(value.type); m_dst.put(value.rawData); }
		else static if (is(T == BsonObjectID)) { m_dst.put(value.m_bytes[]); }
		else static if (is(T == BsonDate)) { m_dst.put(toBsonData(value.m_time)); }
		else static if (is(T == SysTime)) { m_dst.put(toBsonData(BsonDate(value).m_time)); }
		else static if (is(T == BsonRegex)) { m_dst.putCString(value.expression); m_dst.putCString(value.options); }
		else static if (is(T == BsonTimestamp)) { m_dst.put(toBsonData(value.m_time)); }
		else static if (is(T == bool)) { m_dst.put(cast(ubyte)(value ? 0x01 : 0x00)); }
		else static if (is(T : int)) { m_dst.put(toBsonData(cast(int)value)); }
		else static if (is(T : long)) { m_dst.put(toBsonData(value)); }
		else static if (is(T : double)) { m_dst.put(toBsonData(cast(double)value)); }
		else static if (isBsonSerializable!T) m_dst.put(value.toBson().data);
		else static if (isJsonSerializable!T) m_dst.put(Bson(value.toJson()).data);
		else static if (is(T : const(ubyte)[])) { writeValueH!(BsonBinData, false)(BsonBinData(BsonBinData.Type.generic, value.idup)); }
		else static assert(false, "Unsupported type: " ~ T.stringof);
	}

	private void writeCompositeEntryHeader(Bson.Type tp)
	{
		if (!m_compositeStack.length) {
			assert(m_type == Bson.Type.null_, "Overwriting root item.");
			m_type = tp;
		}

		if (m_entryName) {
			m_dst.put(tp);
			m_dst.putCString(m_entryName);
			m_entryName = null;
		} else if (m_entryIndex != size_t.max) {
			import std.format;
			m_dst.put(tp);
			static struct Wrapper {
				AllocAppender!(ubyte[])* app;
				void put(char ch) { (*app).put(ch); }
				void put(in char[] str) { (*app).put(cast(ubyte[])str); }
			}
			auto wr = Wrapper(&m_dst);
			wr.formattedWrite("%d\0", m_entryIndex);
			m_entryIndex = size_t.max;
		}
	}

	//
	// deserialization
	//
	void readDictionary(T)(scope void delegate(string) entry_callback)
	{
		enforce(m_inputData.type == Bson.Type.object, "Expected object instead of "~m_inputData.type.to!string());
		auto old = m_inputData;
		foreach (string name, value; old) {
			m_inputData = value;
			entry_callback(name);
		}
		m_inputData = old;
	}

	void readArray(T)(scope void delegate(size_t) size_callback, scope void delegate() entry_callback)
	{
		enforce(m_inputData.type == Bson.Type.array, "Expected array instead of "~m_inputData.type.to!string());
		auto old = m_inputData;
		foreach (value; old) {
			m_inputData = value;
			entry_callback();
		}
		m_inputData = old;
	}

	T readValue(T)()
	{
		static if (is(T == Bson)) return m_inputData;
		else static if (is(T == Json)) return m_inputData.toJson();
		else static if (is(T == bool)) return m_inputData.get!bool();
		else static if (is(T == uint)) return cast(T)m_inputData.get!int();
		else static if (is(T : int)) return m_inputData.get!int().to!T;
		else static if (is(T : long)) return cast(T)m_inputData.get!long();
		else static if (is(T : double)) return cast(T)m_inputData.get!double();
		else static if (is(T == SysTime)) {
			// support legacy behavior to serialize as string
			if (m_inputData.type == Bson.Type.string) return SysTime.fromISOExtString(m_inputData.get!string);
			else return m_inputData.get!BsonDate().toSysTime();
		}
		else static if (isBsonSerializable!T) return T.fromBson(readValue!Bson);
		else static if (isJsonSerializable!T) return T.fromJson(readValue!Bson.toJson());
		else static if (is(T : const(ubyte)[])) {
			auto ret = m_inputData.get!BsonBinData.rawData;
			static if (isStaticArray!T) return cast(T)ret[0 .. T.length];
			else static if (is(T : immutable(char)[])) return ret;
			else return cast(T)ret.dup;
		} else return m_inputData.get!T();
	}

	bool tryReadNull()
	{
		if (m_inputData.type == Bson.Type.null_) return true;
		return false;
	}

	private static Bson.Type getBsonTypeID(T, bool accept_ao = false)(/*auto ref const*/ in T value)
	{
		Bson.Type tp;
		static if (is(T == Bson)) tp = value.type;
		else static if (is(T == Json)) tp = jsonTypeToBsonType(value.type);
		else static if (is(T == typeof(null))) tp = Bson.Type.null_;
		else static if (is(T == string)) tp = Bson.Type.string;
		else static if (is(T == BsonBinData)) tp = Bson.Type.binData;
		else static if (is(T == BsonObjectID)) tp = Bson.Type.objectID;
		else static if (is(T == BsonDate)) tp = Bson.Type.date;
		else static if (is(T == SysTime)) tp = Bson.Type.date;
		else static if (is(T == BsonRegex)) tp = Bson.Type.regex;
		else static if (is(T == BsonTimestamp)) tp = Bson.Type.timestamp;
		else static if (is(T == bool)) tp = Bson.Type.bool_;
		else static if (is(T : int)) tp = Bson.Type.int_;
		else static if (is(T : long)) tp = Bson.Type.long_;
		else static if (is(T : double)) tp = Bson.Type.double_;
		else static if (isBsonSerializable!T) tp = value.toBson().type; // FIXME: this is highly inefficient
		else static if (isJsonSerializable!T) tp = jsonTypeToBsonType(value.toJson().type); // FIXME: this is highly inefficient
		else static if (is(T : const(ubyte)[])) tp = Bson.Type.binData;
		else static if (accept_ao && isArray!T) tp = Bson.Type.array;
		else static if (accept_ao && isAssociativeArray!T) tp = Bson.Type.object;
		else static if (accept_ao && (is(T == class) || is(T == struct))) tp = Bson.Type.object;
		else static assert(false, "Unsupported type: " ~ T.stringof);
		return tp;
	}
}

private Bson.Type jsonTypeToBsonType(Json.Type tp)
{
	static immutable Bson.Type[Json.Type.max+1] JsonIDToBsonID = [
		Bson.Type.undefined,
		Bson.Type.null_,
		Bson.Type.bool_,
		Bson.Type.int_,
		Bson.Type.double_,
		Bson.Type.string,
		Bson.Type.array,
		Bson.Type.object
	];
	return JsonIDToBsonID[tp];
}

private Bson.Type writeBson(R)(ref R dst, in Json value)
	if( isOutputRange!(R, ubyte) )
{
	final switch(value.type){
		case Json.Type.undefined:
			return Bson.Type.undefined;
		case Json.Type.null_:
			return Bson.Type.null_;
		case Json.Type.bool_:
			dst.put(cast(ubyte)(cast(bool)value ? 0x01 : 0x00));
			return Bson.Type.bool_;
		case Json.Type.int_:
			auto v = cast(long)value;
			if( v >= int.min && v <= int.max ){
				dst.put(toBsonData(cast(int)v));
				return Bson.Type.int_;
			}
			dst.put(toBsonData(v));
			return Bson.Type.long_;
		case Json.Type.float_:
			dst.put(toBsonData(cast(double)value));
			return Bson.Type.double_;
		case Json.Type.string:
			dst.put(toBsonData(cast(uint)value.length+1));
			dst.put(cast(bdata_t)cast(string)value);
			dst.put(cast(ubyte)0);
			return Bson.Type.string;
		case Json.Type.array:
			auto app = appender!bdata_t();
			foreach( size_t i, ref const Json v; value ){
				app.put(cast(ubyte)(jsonTypeToBsonType(v.type)));
				putCString(app, to!string(i));
				writeBson(app, v);
			}

            dst.put(toBsonData(cast(int)(app.data.length + int.sizeof + 1)));
			dst.put(app.data);
			dst.put(cast(ubyte)0);
			return Bson.Type.array;
		case Json.Type.object:
			auto app = appender!bdata_t();
			foreach( string k, ref const Json v; value ){
				app.put(cast(ubyte)(jsonTypeToBsonType(v.type)));
				putCString(app, k);
				writeBson(app, v);
			}

			dst.put(toBsonData(cast(int)(app.data.length + int.sizeof + 1)));
			dst.put(app.data);
			dst.put(cast(ubyte)0);
			return Bson.Type.object;
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

private void putCString(R)(ref R dst, string str)
{
	dst.put(cast(bdata_t)str);
	dst.put(cast(ubyte)0);
}

ubyte[] toBsonData(T)(T v)
{
	/*static T tmp;
	tmp = nativeToLittleEndian(v);
	return cast(ubyte[])((&tmp)[0 .. 1]);*/
	if (__ctfe) return nativeToLittleEndian(v).dup;
	else {
		static ubyte[T.sizeof] ret;
		ret = nativeToLittleEndian(v);
		return ret;
	}
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
	if (__ctfe) return nativeToBigEndian(v).dup;
	else {
		static ubyte[T.sizeof] ret;
		ret = nativeToBigEndian(v);
		return ret;
	}
}

private string underscoreStrip(string field_name)
pure {
	if( field_name.length < 1 || field_name[$-1] != '_' ) return field_name;
	else return field_name[0 .. $-1];
}

/// private
package template isBsonSerializable(T) { enum isBsonSerializable = is(typeof(T.init.toBson()) == Bson) && is(typeof(T.fromBson(Bson())) == T); }
