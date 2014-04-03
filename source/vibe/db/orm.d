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

import vibe.data.serialization;
import vibe.internal.meta.uda;


/// Simple example of defining tables and inserting/querying/updating rows.
unittest {
	import vibe.core.log;
	import vibe.data.bson;

	@tableDefinition
	struct User {
		static:
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
	db.insertRow!User("Tom", 45);
	db.insertRow!User("Peter", 13);
	db.insertRow!User("Peter", 42);
	db.insertRow!User("Foxy", 8);
	db.insertRow!User("Peter", 69);
	
	assert(std.algorithm.equal(
		db.find(and(.equal!(User.name)("Peter"), greater!(User.age)(29))),
		[Row!User("Peter", 42), Row!User("Peter", 69)]));

	assert(std.algorithm.equal(
		db.find(or(.equal!(User.name)("Peter"), greater!(User.age)(29))),
		[Row!User("Tom", 45), Row!User("Peter", 13), Row!User("Peter", 42), Row!User("Peter", 69)]));

	db.update(.equal!(User.name)("Tom"), set!(User.age)(20));

	assert(std.algorithm.equal(
		db.find(.equal!(User.name)("Tom")),
		[Row!User("Tom", 20)]));
}


/// Connecting tables using collections
unittest {
	import vibe.core.log;
	import vibe.data.bson;

	@tableDefinition
	struct User {
		static:
		@primaryID
		string name;
	}

	@tableDefinition
	struct Box {
		static:
		string name;
		//User[] users;
		string[] users;
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
		db.find(containsAll!(Box.users)("Hartmut", "Lynn")),
		[Row!Box("box 2", ["Tom", "Hartmut", "Lynn"]), Row!Box("box 3", ["Lynn", "Hartmut", "Peter"])]));
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
@property PrimaryIDAttribute primaryID() { return PrimaryIDAttribute.init; }

struct TableDefinitionAttribute {}
struct PrimaryIDAttribute {}


ORM!(Tables, Driver) createORM(Tables, Driver)(Driver driver) { return new ORM!(Tables, Driver)(driver); }

class ORM(Tables, Driver) {
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

	auto find(QUERY)(QUERY query)
	{
		alias T = QueryTable!QUERY;
		enum tidx = tableIndex!(T, Tables);
		return m_driver.find!(Row!T)(m_tables[tidx].handle, query);
	}

	auto findOne(QUERY)(QUERY query)
	{
		auto res = find(query);
		enforce(!res.empty, "Not found!");
		return res.front;
	}

	void update(QUERY, UPDATE)(QUERY query, UPDATE update)
	{
		alias T = QueryTable!QUERY;
		auto tidx = tableIndex!(T, Tables);
		m_driver.update!(Row!T)(m_tables[tidx].handle, query, update);
	}

	void insertRow(T, FIELDS...)(FIELDS fields)
		if (isTableDefinition!T)
	{
		enum tidx = tableIndex!(T, Tables);
		Row!T value;
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

auto equal(alias field)(typeof(field) value) { return ComparatorExpr!(field, Comparator.equal)(value); }
auto notEqual(alias field)(typeof(field) value) { return ComparatorExpr!(field, Comparator.notEqual)(value); }
auto greater(alias field)(typeof(field) value) { return ComparatorExpr!(field, Comparator.greater)(value); }
auto greaterEqual(alias field)(typeof(field) value) { return ComparatorExpr!(field, Comparator.greaterEqual)(value); }
auto less(alias field)(typeof(field) value) { return ComparatorExpr!(field, Comparator.less)(value); }
auto lessEqual(alias field)(typeof(field) value) { return ComparatorExpr!(field, Comparator.lessEqual)(value); }
auto containsAll(alias field)(typeof(field) values...) { return ComparatorExpr!(field, Comparator.containsAll)(values.dup); }

@property auto and(EXPRS...)(EXPRS exprs) { return ConjunctionExpr!EXPRS(exprs); }
@property auto or(EXPRS...)(EXPRS exprs) { return DisjunctionExpr!EXPRS(exprs); }
//JoinExpr!()

struct ComparatorExpr(alias FIELD, Comparator COMP)
{
	alias T = typeof(FIELD);
	alias TABLE = TypeTuple!(__traits(parent, FIELD))[0];
	enum name = __traits(identifier, FIELD);
	enum comp = COMP;
	T value;
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

struct Row(TABLE)
	if (findFirstUDA!(TableDefinitionAttribute, TABLE).found)
{
	mixin RowFields!(TABLE, __traits(allMembers, TABLE));
}
mixin template RowFields(TABLE, MEMBERS...) {
	static if (MEMBERS.length > 1) {
		mixin RowFields!(TABLE, MEMBERS[0 .. $/2]);
		mixin RowFields!(TABLE, MEMBERS[$/2 .. $]);
	} else static if (MEMBERS.length == 1) {
		alias T = typeof(__traits(getMember, TABLE, MEMBERS[0]));
		//pragma(msg, "MEMBER: "~MEMBERS[0]);
		mixin(format(`T %s;`, MEMBERS[0]));
	}
}

template isTableDefinition(T) {
	enum isTableDefinition = findFirstUDA!(TableDefinitionAttribute, T).found;
}

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

	this(string url_or_host, string name)
	{
		auto cli = connectMongoDB(url_or_host);
		m_db = cli.getDatabase(name);
	}

	MongoCollection getTableHandle(T)(string name) { return m_db[name]; }
	//string getColumnHandle(MongoCollection coll, string name) { return name; }
	
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
			static if (Q.comp == Comparator.equal) mixin("Q.T "~Q.name~";");
			else static if (Q.comp == Comparator.notEqual) mixin(format(`static struct Q%s { @(vibe.data.serialization.name("$ne")) Q.T value; } Q%s %s;`, idx, idx, Q.name));
			else static if (Q.comp == Comparator.greater) mixin(format(`static struct Q%s { @(vibe.data.serialization.name("$gt")) Q.T value; } Q%s %s;`, idx, idx, Q.name));
			else static if (Q.comp == Comparator.greaterEqual) mixin(format(`static struct Q%s { @(vibe.data.serialization.name("$gte")) Q.T value; } Q%s %s;`, idx, idx, Q.name));
			else static if (Q.comp == Comparator.less) mixin(format(`static struct Q%s { @(vibe.data.serialization.name("$lt")) Q.T value; } Q%s %s;`, idx, idx, Q.name));
			else static if (Q.comp == Comparator.lessEqual) mixin(format(`static struct Q%s { @(vibe.data.serialization.name("$lte")) Q.T value; } Q%s %s;`, idx, idx, Q.name));
			else static if (Q.comp == Comparator.containsAll) mixin(format(`static struct Q%s { @(vibe.data.serialization.name("$all")) Q.T value; } Q%s %s;`, idx, idx, Q.name));
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
