/**
	Database independent object relational mapping framework.

	This framework adds a typesafe layer on top of a database driver for
	creating, modifying and querying the data. It aims to use no dynamic memory
	allocations wherever possible.

	Copyright: © 2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.orm;

import std.algorithm : map;
import std.string : format;
import std.traits;
import std.typetuple;
import std.typecons : Nullable, tuple;

import vibe.data.serialization;
import vibe.internal.meta.uda;


/// Simple example of defining tables and inserting/querying/updating rows.
unittest {
	import vibe.core.log;
	import vibe.data.bson;

	@tableDefinition
	struct User {
		static:
		@primaryKey int id;
		string name;
		int age;
	}

	struct Tables {
		User users;
	}

	//auto dbdriver = new MongoDBDriver("127.0.0.1", "test");
	auto dbdriver = new InMemoryORMDriver;

	auto db = createORM!Tables(dbdriver);
	db.removeAll!User();
	db.insertRow!User(0, "Tom", 45);
	db.insertRow!User(1, "Peter", 13);
	db.insertRow!User(2, "Peter", 42);
	db.insertRow!User(3, "Foxy", 8);
	db.insertRow!User(4, "Peter", 69);

	assert(std.algorithm.equal(
		db.find(and(cmp!User.name("Peter"), cmp!User.age.greater(29))).map!(r => r.toTuple),
		[tuple(2, "Peter", 42), tuple(4, "Peter", 69)]));

	assert(std.algorithm.equal(
		db.find(cmp!User.name("Peter") & cmp!User.age.greater(29)).map!(r => r.toTuple),
		[tuple(2, "Peter", 42), tuple(4, "Peter", 69)]));

	assert(std.algorithm.equal(
		db.find(or(cmp!User.name("Peter"), cmp!User.age.greater(29))).map!(r => r.toTuple),
		[tuple(0, "Tom", 45), tuple(1, "Peter", 13), tuple(2, "Peter", 42), tuple(4, "Peter", 69)]));

	db.update(cmp!User.name("Tom"), set!(User.age)(20));

	assert(std.algorithm.equal(
		db.find(cmp!User.name("Tom")).map!(r => r.toTuple),
		[tuple(0, "Tom", 20)]));
}


/// Connecting tables using collections
unittest {
	import vibe.core.log;
	import vibe.data.bson;

	@tableDefinition
	struct User {
		static:
		@primaryKey
		string name;
	}

	@tableDefinition
	struct Box {
		static:
		@primaryKey
		string name;
		User[] users;
	}

	struct Tables {
		User users;
		Box boxes;
	}

	//auto dbdriver = new MongoDBDriver("127.0.0.1", "test");
	auto dbdriver = new InMemoryORMDriver;
	auto db = createORM!Tables(dbdriver);

	db.removeAll!User();
	db.insertRow!User("Tom");
	db.insertRow!User("Peter");
	db.insertRow!User("Foxy");
	db.insertRow!User("Lynn");
	db.insertRow!User("Hartmut");

	db.removeAll!Box();
	db.insertRow!Box("box 1", ["Tom", "Foxy"]);
	db.insertRow!Box("box 2", ["Tom", "Hartmut", "Lynn"]);
	db.insertRow!Box("box 3", ["Lynn", "Hartmut", "Peter"]);

	assert(std.algorithm.equal(
		db.find(cmp!Box.users.containsAll("Hartmut", "Lynn")).map!(r => r.toTuple),
		[tuple("box 2", ["Tom", "Hartmut", "Lynn"]), tuple("box 3", ["Lynn", "Hartmut", "Peter"])]));
}


// just playing with ideas for query syntaxes
auto dummy = q{
	// the current solution. works, but kind of ugly
	auto res = m_db.find(and(.equal!(User.name)("Peter"), greater!(User.age)(min_age)));
	// short, but what to do with explicit joins?
	auto res = m_db.find!User(equal!"name"("Peter") & greater!"age"(min_age));
	// short, but what to do with explicit joins? and requires a parser
	auto res = m_db.find!(User, q{name == "Peter" && age > args[0]})(min_age);
	// clean syntax, but needs a parser and mixins in user code are kind of ugly
	auto res = mixin(find("m_db", q{User.name == "Peter" && User.age > min_age}));
	// using expression templates where possible, simple extension to the current solution, puts the comparison operator in the middle
	auto res = m_db.find(Cmp!(User.name, "==")("Peter") & Cmp!(User.age, ">")(min_age));
	auto res = m_db.find(Cmp!(User.name)("Peter") & Cmp!(User.age, ">")(min_age));
	auto res = m_db.find(Cmp!User.name.equal("Peter") & Cmp!User.age.greater(min_age));
	auto res = m_db.find(Cmp!User.name("Peter") & Cmp!User.age!">"(min_age));
	auto res = m_db.find(Cmp!User.name("Peter") & Cmp!User.age(greater(min_age)));
	// requires different way to define the tables
	auto res = m_db.find(User.name.equal("Peter") & User.age.greater(min_age));
	auto res = m_db.find(User.name.cmp!"=="("Peter") & User.age.cmp!">"(min_age));
	auto res = m_db.find(User.name("Peter") & User.age!">"(min_age));
	auto res = m_db.find(User.name("Peter") & User.age(greater(min_age)));
	// short for complex expressions, but long for simple ones
	auto res = m_db.find!((Var!User u) => u.name.equal("Peter") & u.age.greater(min_age));
};


@property TableDefinitionAttribute tableDefinition() { return TableDefinitionAttribute.init; }
@property PrimaryKeyAttribute primaryKey() { return PrimaryKeyAttribute.init; }

struct TableDefinitionAttribute {}
struct PrimaryKeyAttribute {}


ORM!(Tables, Driver) createORM(Tables, Driver)(Driver driver) { return new ORM!(Tables, Driver)(driver); }

class ORM(TABLES, DRIVER) {
	alias Tables = TABLES;
	alias Driver = DRIVER;

	private {
		Driver m_driver;
		struct TableInfo {
			Driver.TableHandle handle;
			//Driver.ColumnHandle[] columnHandles;
		}
		TableInfo[] m_tables;
	}

	this(Driver driver)
	{
		m_driver = driver;

		foreach (tname; __traits(allMembers, Tables)) {
			//pragma(msg, "TAB "~tname);
			alias Table = typeof(__traits(getMember, Tables, tname));
			static assert(isTableDefinition!Table, "Table defintion lacks @TableDefinition UDA: "~Table.stringof);
			TableInfo ti;
			ti.handle = driver.getTableHandle!Table(tname);
			foreach (cname; __traits(allMembers, Table)) {
				//pragma(msg, "COL "~cname);
				//ti.columnHandles ~= driver.getColumnHandle(ti.handle, cname);
			}
			m_tables ~= ti;
		}

		upgradeColumns();
	}

	/// The underlying database driver
	@property inout(Driver) driver() inout { return m_driver; }

	/** Queries a table for a set of rows.

		The return value is an input range of type Row!(T, ORM), where T is the type
		of the underlying table.
	*/
	auto find(QUERY)(QUERY query)
	{
		alias T = QueryTable!QUERY;
		enum tidx = tableIndex!(T, Tables);
		return m_driver.find!(RawRow!(ORM, T))(m_tables[tidx].handle, query).map!(r => Row!(ORM, T)(this, r));
	}

	/** Queries a table for the first match.

		A Nullable!T is returned and set to null when no match was found.
	*/
	Nullable!(Row!(ORM, QueryTable!QUERY)) findOne(QUERY)(QUERY query)
	{
		auto res = find(query); // TODO: give a hint to the DB driver that only one document is desired
		Nullable!(Row!(ORM, QueryTable!QUERY)) ret;
		if (!res.empty) ret = res.front;
		return ret;
	}

	/** Driver specific version of find.

		This method takes a set of driver defined arguments (e.g. a
		string plus parameters for an SQL database or a BSON document
		for the MongoDB driver).
	*/
	auto findRaw(TABLE, T...)(T params)
	{
		enum tidx = tableIndex!(T, Tables);
		return m_driver.findRaw!(RawRow!TABLE)(m_tables[tidx].handle, params);
	}

	void update(QUERY, UPDATE)(QUERY query, UPDATE update)
	{
		alias T = QueryTable!QUERY;
		auto tidx = tableIndex!(T, Tables);
		m_driver.update!(RawRow!(ORM, T))(m_tables[tidx].handle, query, update);
	}

	void insertRow(T, FIELDS...)(FIELDS fields)
		if (isTableDefinition!T)
	{
		enum tidx = tableIndex!(T, Tables);
		RawRow!(ORM, T) value;
		// TODO: translate references to other tables automatically
		value.tupleof = fields;
		m_driver.insert(m_tables[tidx].handle, value);
	}

	void removeAll(T)()
		if (isTableDefinition!T)
	{
		enum tidx = tableIndex!(T, Tables);
		m_driver.removeAll(m_tables[tidx].handle);
	}

	/*void insert(T)(Item!T item)
	{
		m_driver.insert(item);
	}

	void remove!(QUERY...)()
		if (QUERY.length == 1)
	{
		return m_driver.remove(QUERY);
	}*/

	private void upgradeColumns()
	{

	}
}


/*struct Column(T) {
	alias Type = T;

	auto equal()
}*/

/******************************************************************************/
/* QUERY EXPRESSIONS                                                          */
/******************************************************************************/

struct cmp(TABLE)
{
	static struct cmpfield(string column)
	{
		alias FIELD = ComparatorType!(typeof(__traits(getMember, TABLE, column)));
		static opCall(FIELD value) { return equal(value); }
		static auto equal(FIELD value) { return compare!(Comparator.equal)(value); }
		static auto notEqual(FIELD value) { return compare!(Comparator.notEqual)(value); }
		static auto greater(FIELD value) { return compare!(Comparator.greater)(value); }
		static auto greaterEqual(FIELD value) { return compare!(Comparator.greaterEqual)(value); }
		static auto less(FIELD value) { return compare!(Comparator.less)(value); }
		static auto lessEqual(FIELD value) { return compare!(Comparator.lessEqual)(value); }
		static if (isArray!FIELD) {
			// FIXME: avoid dynamic array here:
			static auto containsAll(FIELD values...) { return compare!(Comparator.containsAll)(values); }
		}
		static auto compare(Comparator comp)(FIELD value) { return ComparatorExpr!(__traits(getMember, TABLE, column), comp)(value); }
	}

	mixin template CmpFields(MEMBERS...) {
		static if (MEMBERS.length > 1) {
			mixin CmpFields!(MEMBERS[0 .. $/2]);
			mixin CmpFields!(MEMBERS[$/2 .. $]);
		} else static if (MEMBERS.length == 1) {
			alias T = typeof(__traits(getMember, TABLE, MEMBERS[0]));
			//pragma(msg, "MEMBER: "~MEMBERS[0]);
			mixin(format(`alias %s = cmpfield!"%s";`, MEMBERS[0], MEMBERS[0]));
		}
	}

	mixin CmpFields!(__traits(allMembers, TABLE));
}

@property auto and(EXPRS...)(EXPRS exprs) { return ConjunctionExpr!EXPRS(exprs); }
@property auto or(EXPRS...)(EXPRS exprs) { return DisjunctionExpr!EXPRS(exprs); }
//JoinExpr!()

struct ComparatorExpr(alias FIELD, Comparator COMP)
{
	alias T = typeof(FIELD);
	alias V = ComparatorType!T;
	alias TABLE = TypeTuple!(__traits(parent, FIELD))[0];
	enum name = __traits(identifier, FIELD);
	enum comp = COMP;
	V value;

	auto opBinary(string op, T)(T other) if(op == "|") { return DisjunctionExpr!(typeof(this), T)(this, other); }
	auto opBinary(string op, T)(T other) if(op == "&") { return ConjunctionExpr!(typeof(this), T)(this, other); }
}
enum Comparator {
	equal,
	notEqual,
	greater,
	greaterEqual,
	less,
	lessEqual,
	containsAll
}
template ComparatorType(T)
{
	static if (isTableDefinition!T) alias ComparatorType = PrimaryKeyType!T;
	else static if (isArray!T && isTableDefinition!(typeof(T.init[0]))) alias ComparatorType = PrimaryKeyType!(typeof(T.init[0]))[];
	else alias ComparatorType = T;
}
struct ConjunctionExpr(EXPRS...) { EXPRS exprs; }
struct DisjunctionExpr(EXPRS...) { EXPRS exprs; }


/******************************************************************************/
/* UPDATE EXPRESSIONS                                                         */
/******************************************************************************/

auto set(alias field)(typeof(field) value) { return SetExpr!(field)(value); }

struct SetExpr(alias FIELD)
{
	alias T = typeof(FIELD);
	alias TABLE = TypeTuple!(__traits(parent, FIELD))[0];
	enum name = __traits(identifier, FIELD);
	T value;
}


/******************************************************************************/
/* UTILITY TEMPLATES                                                          */
/******************************************************************************/

struct Row(ORM, TABLE)
	if (isTableDefinition!TABLE)
{
	private {
		ORM m_orm;
		RawRow!(ORM, TABLE) m_rawData;
	}

	this(ORM orm, RawRow!(ORM, TABLE) data)
	{
		m_orm = orm;
		m_rawData = data;
	}

	@property ref const(RawRow!(ORM, TABLE)) rawRowData() const { return m_rawData; }

	auto toTuple() { return tuple(m_rawData.tupleof); }

	mixin RowFields!(ORM, TABLE, __traits(allMembers, TABLE));
}

mixin template RowFields(ORM, TABLE, MEMBERS...) {
	static if (MEMBERS.length > 1) {
		mixin RowFields!(ORM, TABLE, MEMBERS[0 .. $/2]);
		mixin RowFields!(ORM, TABLE, MEMBERS[$/2 .. $]);
	} else static if (MEMBERS.length == 1) {
		alias T = typeof(__traits(getMember, TABLE, MEMBERS[0]));
		static if (isTableDefinition!T) {
			mixin(format(`@property auto %s() { return m_orm.findOne(cmp!T.%s(m_rawData.%s)); }`, MEMBERS[0], primaryKeyOf!T, MEMBERS[0]));
		} else static if (isDynamicArray!T && !isSomeString!T) {
			alias E = typeof(T.init[0]);
			static assert(isTableDefinition!E);
			static if (!isTableDefinition!E) static assert(false);
			static if (ORM.Driver.supportsArrays) {
				mixin(format(`@property auto %s() { return RowArray!(ORM, E)(m_orm, m_rawData.%s); }`, MEMBERS[0], MEMBERS[0]));
			} else {
				static assert(false);
			}
		} else {
			static assert(!isAssociativeArray!T);
			mixin(format(`@property auto %s() const { return m_rawData.%s; }`, MEMBERS[0], MEMBERS[0]));
		}
	}
}

struct RowArray(ORM, T) {
	private {
		alias E = PrimaryKeyType!T;
		alias R = Row!(ORM, T);
		enum primaryKeyName = primaryKeyOf!T;
		ORM m_orm;
		E[] m_items;
	}

	this(ORM orm, E[] items)
	{
		m_orm = orm;
		m_items = items;
	}

	R opIndex(size_t idx) { return resolve(m_items[idx]); }

	auto opSlice()
	{
		static int dummy; dummy++; // force method to be impure to work around DMD 2.065 issue
		return m_items.map!(itm => resolve(itm));
	}

	private R resolve(E key)
	{
		return m_orm.findOne(__traits(getMember, cmp!T, primaryKeyName)(key));
	}
}


struct RawRow(ORM, TABLE)
	if (isTableDefinition!TABLE)
{
	mixin RawRowFields!(ORM, TABLE, __traits(allMembers, TABLE));
}

mixin template RawRowFields(ORM, TABLE, MEMBERS...) {
	static if (MEMBERS.length > 1) {
		mixin RawRowFields!(ORM, TABLE, MEMBERS[0 .. $/2]);
		mixin RawRowFields!(ORM, TABLE, MEMBERS[$/2 .. $]);
	} else static if (MEMBERS.length == 1) {
		alias T = typeof(__traits(getMember, TABLE, MEMBERS[0]));
		mixin(format(`RawColumnType!(ORM, T) %s;`, MEMBERS[0]));
	}
}

template RawColumnType(ORM, T)
{
	static if (isTableDefinition!T) { // TODO: support in-document storage of table types for 1 to n relations
		alias RawColumnType = PrimaryKeyType!T;
	} else static if (isDynamicArray!T && !isSomeString!T) {
		alias E = typeof(T.init[0]);
		static assert(isTableDefinition!E, format("Array %s.%s may only contain table references, not %s.", TABLE.stringof, MEMBERS[0], E.stringof));
		static if (!isTableDefinition!E) static assert(false);
		else static if (ORM.Driver.supportsArrays) {
			alias RawColumnType = PrimaryKeyType!E[]; // TODO: avoid dyamic allocations!
		} else {
			static assert(false, "Arrays for column based databases are not yet supported.");
		}
	} else {
		static assert(!isAssociativeArray!T, "Associative arrays are not supported as column types. Please use a separate table instead.");
		alias RawColumnType = T;
	}
}

template isTableDefinition(T) {
	static if (is(T == struct)) enum isTableDefinition = findFirstUDA!(TableDefinitionAttribute, T).found;
	else enum isTableDefinition = false;
}
template isPrimaryKey(T, string key) { enum isPrimaryKey = findFirstUDA!(PrimaryKeyAttribute, __traits(getMember, T, key)).found; }

@property string primaryKeyOf(T)()
	if (isTableDefinition!T)
{
	// TODO: produce better error messages for duplicate or missing primary keys!
	foreach (m; __traits(allMembers, T))
		static if (isPrimaryKey!(T, m))
			return m;
	assert(false, "No primary key for "~T.stringof);
}

template PrimaryKeyType(T) if (isTableDefinition!T) { enum string key = primaryKeyOf!T; alias PrimaryKeyType = typeof(__traits(getMember, T, key)); }


private template QueryTable(QUERIES...) if (QUERIES.length > 0) {
	static if (QUERIES.length == 1) {
		alias Q = QUERIES[0];
		static if (isInstanceOf!(ConjunctionExpr, Q) || isInstanceOf!(DisjunctionExpr, Q)) {
			alias QueryTable = QueryTable!(typeof(Q.exprs));
		} else static if (isInstanceOf!(ComparatorExpr, Q) || isInstanceOf!(ContainsExpr, Q)) {
			alias QueryTable = Q.TABLE;
		} else static assert(false, "Invalid query type: "~Q.stringof);
	} else {
		alias T1 = QueryTable!(QUERIES[0 .. $/2]);
		alias T2 = QueryTable!(QUERIES[$/2 .. $]);
		static assert(is(T1 == T2), "Query references different tables: "~T1.stringof~" and "~T2.stringof);
		alias QueryTable = T1;
	}
}

private template tableIndex(TABLE, TABLES)
{
	template impl(size_t idx, MEMBERS...) {
		static if (MEMBERS.length > 1) {
			enum a = impl!(0, MEMBERS[0 .. $/2]);
			enum b = impl!(MEMBERS.length/2, MEMBERS[$/2 .. $]);
			enum impl = a != size_t.max ? a : b;
		} else static if (MEMBERS.length == 1) {
			enum mname = MEMBERS[0];
			static if (is(typeof(__traits(getMember, TABLES, mname)) == TABLE))
				enum impl = idx;
			else enum impl = size_t.max;
		} else enum impl = size_t.max;
	}
	enum tableIndex = impl!(0, __traits(allMembers, TABLES));
	static assert(tableIndex != size_t.max, "Invalid table: "~TABLE.stringof);
}


/******************************************************************************/
/* IN-MEMORY DRIVER                                                           */
/******************************************************************************/

/** Simple in-memory ORM back end.

	This database back end is mostly useful as a lightweight replacement for
	a full database engine. It offers no data persistence across program runs.

	The primary uses for this class are to serve as a reference implementation
	and to enable unit testing without involving an external database process
	or disk access. However, it can also be useful in cases where persistence
	isn't needed, but where the ORM interface is already used.
*/
class InMemoryORMDriver {
	alias DefaultID = size_t; // running index
	alias TableHandle = size_t; // table index
	alias ColumnHandle = size_t; // byte offset
	enum bool supportsArrays = true;

	private {
		static struct Table {
			string name;
			size_t[size_t] rowIndices;
			size_t rowCounter;
			ubyte[] storage;
			size_t idCounter;
		}
		Table[] m_tables;
	}

	size_t getTableHandle(T)(string name)
	{
		foreach (i, ref t; m_tables)
			if (t.name == name)
				return i;
		m_tables ~= Table(name);
		return m_tables.length - 1;
	}

	auto find(T, QUERY)(size_t table, QUERY query)
	{
		import std.algorithm : filter;
		auto ptable = &m_tables[table];
		auto items = cast(T[])ptable.storage;
		items = items[0 .. ptable.rowCounter];
		return filter!((itm => matchQuery(itm, query)))(items);
	}

	void update(T, QUERY, UPDATE)(size_t table, QUERY query, UPDATE update)
	{
		auto ptable = &m_tables[table];
		auto items = cast(T[])ptable.storage;
		items = items[0 .. ptable.rowCounter];
		foreach (ref itm; items)
			if (matchQuery(itm, query))
				applyUpdate(itm, update);
	}

	void insert(T)(size_t table, T value)
	{
		import std.algorithm : max;
		auto ptable = &m_tables[table];
		if (ptable.storage.length <= ptable.rowCounter)
			ptable.storage.length = max(16 * T.sizeof, ptable.storage.length * 2);
		auto items = cast(T[])ptable.storage;
		items[ptable.rowCounter++] = value;
	}

	void removeAll(size_t table)
	{
		m_tables[table].rowCounter = 0;
	}

	private static bool matchQuery(T, Q)(ref T item, ref Q query)
	{
		static if (isInstanceOf!(ComparatorExpr, Q)) {
			static if (Q.comp == Comparator.equal) return __traits(getMember, item, Q.name) == query.value;
			else static if (Q.comp == Comparator.notEqual) return __traits(getMember, item, Q.name) != query.value;
			else static if (Q.comp == Comparator.greater) return __traits(getMember, item, Q.name) > query.value;
			else static if (Q.comp == Comparator.greaterEqual) return __traits(getMember, item, Q.name) >= query.value;
			else static if (Q.comp == Comparator.less) return __traits(getMember, item, Q.name) < query.value;
			else static if (Q.comp == Comparator.lessEqual) return __traits(getMember, item, Q.name) <= query.value;
			else static if (Q.comp == Comparator.containsAll) {
				import std.algorithm : canFind;
				foreach (v; query.value)
					if (!canFind(__traits(getMember, item, Q.name), v))
						return false;
				return true;
			} else static assert(false, format("Unsupported comparator: %s", Q.comp));
		} else static if (isInstanceOf!(ConjunctionExpr, Q)) {
			foreach (i, E; typeof(Q.exprs))
				if (!matchQuery(item, query.exprs[i]))
					return false;
			return true;
		} else static if (isInstanceOf!(DisjunctionExpr, Q)) {
			foreach (i, E; typeof(Q.exprs))
				if (matchQuery(item, query.exprs[i]))
					return true;
			return false;
		} else static assert(false, "Unsupported query expression type: "~Q.stringof);
	}

	private static void applyUpdate(T, U)(ref T item, ref U query)
	{
		static if (isInstanceOf!(SetExpr, U)) {
			__traits(getMember, item, U.name) = query.value;
		} else static assert(false, "Unsupported update expression type: "~U.stringof);
	}
}


/******************************************************************************/
/* MONGODB DRIVER                                                             */
/******************************************************************************/


/** ORM driver using MongoDB for data storage and query execution.

	The driver generates static types used to efficiently and directly
	serialize query expressions to BSON without unnecessary memory allocations.
*/
class MongoDBDriver {
	import vibe.db.mongo.mongo;

	private {
		MongoDatabase m_db;
	}

	alias DefaultID = BsonObjectID;
	alias TableHandle = MongoCollection;
	alias ColumnHandle = string;
	enum bool supportsArrays = true;

	this(string url_or_host, string name)
	{
		auto cli = connectMongoDB(url_or_host);
		m_db = cli.getDatabase(name);
	}

	MongoCollection getTableHandle(T)(string name)
	{
		// TODO: setup keys, especially the primary key!
		return m_db[name];
	}
	
	auto find(T, QUERY)(MongoCollection table, QUERY query)
	{
		struct Query { mixin MongoQuery!(0, QUERY); }
		Query mquery;
		mixin(initializeMongoQuery!(0, QUERY)("mquery", "query"));
		
		import vibe.core.log; import vibe.data.bson;
		//logInfo("QUERY (%s): %s", table.name, serializeToBson(mquery).toString());
		
		return table.find(mquery).map!(b => deserializeBson!T(b));
	}

	void update(T, QUERY, UPDATE)(MongoCollection table, QUERY query, UPDATE update)
	{
		struct Query { mixin MongoQuery!(0, QUERY); }
		Query mquery;
		mixin(initializeMongoQuery!(0, QUERY)("mquery", "query"));

		struct Update { mixin MongoUpdate!(0, UPDATE); }
		Update mupdate;
		mixin(initializeMongoUpdate!(0, UPDATE)("mupdate", "update"));

		import vibe.core.log; import vibe.data.bson;
		//logInfo("QUERY (%s): %s", table.name, serializeToBson(mquery).toString());
		//logInfo("UPDATE: %s", serializeToBson(mupdate).toString());

		table.update(mquery, mupdate);
	}

	void insert(T)(MongoCollection table, T value)
	{
		table.insert(value);
	}

	void removeAll(MongoCollection table)
	{
		table.remove(Bson.emptyObject);
	}
}

private mixin template MongoQuery(size_t idx, QUERIES...) {
	static if (QUERIES.length > 1) {
		mixin MongoQuery!(idx, QUERIES[0 .. $/2]);
		mixin MongoQuery!(idx + QUERIES.length/2, QUERIES[$/2 .. $]);
	} else static if (QUERIES.length == 1) {
		static assert(!is(typeof(QUERIES[0])) || is(typeof(QUERIES[0])), "Arguments to MongoQuery must be types.");
		alias Q = QUERIES[0];

		static if (isInstanceOf!(ComparatorExpr, Q)) {
			static if (Q.comp == Comparator.equal) mixin("Q.V "~Q.name~";");
			else static if (Q.comp == Comparator.notEqual) mixin(format(`static struct Q%s { @(vibe.data.serialization.name("$ne")) Q.V value; } Q%s %s;`, idx, idx, Q.name));
			else static if (Q.comp == Comparator.greater) mixin(format(`static struct Q%s { @(vibe.data.serialization.name("$gt")) Q.V value; } Q%s %s;`, idx, idx, Q.name));
			else static if (Q.comp == Comparator.greaterEqual) mixin(format(`static struct Q%s { @(vibe.data.serialization.name("$gte")) Q.V value; } Q%s %s;`, idx, idx, Q.name));
			else static if (Q.comp == Comparator.less) mixin(format(`static struct Q%s { @(vibe.data.serialization.name("$lt")) Q.V value; } Q%s %s;`, idx, idx, Q.name));
			else static if (Q.comp == Comparator.lessEqual) mixin(format(`static struct Q%s { @(vibe.data.serialization.name("$lte")) Q.V value; } Q%s %s;`, idx, idx, Q.name));
			else static if (Q.comp == Comparator.containsAll) mixin(format(`static struct Q%s { @(vibe.data.serialization.name("$all")) Q.V value; } Q%s %s;`, idx, idx, Q.name));
			else static assert(false, format("Unsupported comparator: %s", Q.comp));
		} else static if (isInstanceOf!(ConjunctionExpr, Q)) {
			//mixin(format(`static struct Q%s { mixin MongoQuery!(0, Q.exprs); } @(vibe.data.serialization.name("$and")) Q%s q%s;`, idx, idx, idx));
			mixin MongoQuery!(0, typeof(Q.exprs));
		} else static if (isInstanceOf!(DisjunctionExpr, Q)) {
			mixin(format(
				q{static struct Q%s { mixin MongoQueries!(0, typeof(Q.exprs)); } @(vibe.data.serialization.name("$or"), asArray) Q%s q%s;}, idx, idx, idx));
		} else static assert(false, "Unsupported query expression type: "~Q.stringof);
	}
}

private mixin template MongoQueries(size_t idx, QUERIES...) {
	static if (QUERIES.length > 1) {
		mixin MongoQueries!(idx, QUERIES[0 .. $/2]);
		mixin MongoQueries!(idx + QUERIES.length/2, QUERIES[$/2 .. $]);
	} else static if (QUERIES.length == 1) {
		mixin(format(`struct Q%s { mixin MongoQuery!(0, QUERIES[0]); } Q%s q%s;`, idx, idx, idx));
	}
}

private static string initializeMongoQuery(size_t idx, QUERY)(string name, string srcfield)
{
	string ret;
	alias Q = QUERY;

	static if (isInstanceOf!(ComparatorExpr, Q)) {
		final switch (Q.comp) with (Comparator) {
			case equal:
				ret ~= format("%s.%s = %s.value;", name, Q.name, srcfield);
				break;
			case notEqual, greater, greaterEqual, less, lessEqual:
			case containsAll:
				ret ~= format("%s.%s.value = %s.value;", name, Q.name, srcfield);
				break;
		}
	} else static if (isInstanceOf!(ConjunctionExpr, Q)) {
		foreach (i, E; typeof(Q.exprs))
			//ret ~= initializeMongoQuery!(i, E)(format("%s.q%s", name, idx), format("%s.exprs[%s]", srcfield, i));
			ret ~= initializeMongoQuery!(i, E)(name, format("%s.exprs[%s]", srcfield, i));
	} else static if (isInstanceOf!(DisjunctionExpr, Q)) {
		foreach (i, E; typeof(Q.exprs))
			ret ~= initializeMongoQuery!(i, E)(format("%s.q%s.q%s", name, idx, i), format("%s.exprs[%s]", srcfield, i));
	} else static assert(false, "Unsupported query expression type: "~Q.stringof);

	return ret;
}

private mixin template MongoUpdate(size_t idx, UPDATES...) {
	static if (UPDATES.length > 1) {
		mixin MongoUpdate!(idx, UPDATES[0 .. $/2]);
		mixin MongoUpdate!(idx + UPDATES.length/2, UPDATES[$/2 .. $]);
	} else static if (UPDATES.length == 1) {
		alias Q = UPDATES[0];

		static if (isInstanceOf!(SetExpr, Q)) {
			mixin(format(q{static struct Q%s { Q.T %s; } @(vibe.data.serialization.name("$set")) Q%s q%s;}, idx, Q.name, idx, idx));
		} else static assert(false, "Unsupported update expression type: "~Q.stringof);
	}
}

private mixin template MongoUpdates(size_t idx, UPDATES...) {
	static if (UPDATES.length > 1) {
		mixin MongoUpdates!(idx, UPDATES[0 .. $/2]);
		mixin MongoUpdates!(idx + UPDATES.length/2, UPDATES[$/2 .. $]);
	} else static if (UPDATES.length == 1) {
		mixin(format(q{struct Q%s { mixin MongoUpdate!(0, UPDATES[0]); } Q%s q%s;}, idx, idx, idx));
	}
}

private static string initializeMongoUpdate(size_t idx, UPDATE)(string name, string srcfield)
{
	string ret;
	alias Q = UPDATE;

	static if (isInstanceOf!(SetExpr, Q)) {
		ret ~= format("%s.q%s.%s = %s.value;", name, idx, Q.name, srcfield);
	} else static assert(false, "Unsupported update expression type: "~Q.stringof);

	return ret;
}
