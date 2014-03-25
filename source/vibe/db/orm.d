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

unittest {
	import vibe.core.log;
	import vibe.data.bson;

	@tableDefinition
	static struct User {
		static:
		string name;
		int age;
	}

	struct Tables {
		User users;
	}

	auto dbdriver = new MongoDBDriver("127.0.0.1", "test");
	auto db = createORM!Tables(dbdriver);
	db.removeAll!User();
	db.insertRow!User("Tom", 45);
	db.insertRow!User("Peter", 13);
	db.insertRow!User("Peter", 42);
	db.insertRow!User("Foxy", 8);
	db.insertRow!User("Peter", 69);
	foreach (usr; db.find!(and!(.equal!(User.name)("Peter"), greater!(User.age)(29))))
		logInfo("%s", usr);
	foreach (usr; db.find!(or!(.equal!(User.name)("Peter"), greater!(User.age)(29))))
		logInfo("%s", usr);
	db.update!(and!(.equal!(User.name)("Tom")), set!(User.age)(20));
	foreach (usr; db.find!(.equal!(User.name)("Tom")))
		logInfo("Changed age: %s", usr);
	logInfo("Done.");
}

unittest {
	import vibe.core.log;
	import vibe.data.bson;

	@tableDefinition
	static struct User {
		static:
		@primaryID
		string name;
	}

	@tableDefinition
	static struct Box {
		static:
		string name;
		//User[] users;
		string[] users;
	}

	struct Tables {
		User users;
		Box boxes;
	}

	auto dbdriver = new MongoDBDriver("127.0.0.1", "test");
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
	db.insertRow!Box("box 3", ["Peter", "Hartmut", "Lynn"]);

	foreach(box; db.find!(containsAll!(Box.users)("Hartmut", "Lynn")))
		logInfo("%s", box.name);

	logInfo("Done.");
}

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
			Driver.ColumnHandle[] columnHandles;
		}
		TableInfo[] m_tables;
	}

	this(Driver driver)
	{
		m_driver = driver;

		foreach (tname; __traits(allMembers, Tables)) {
			pragma(msg, "TAB "~tname);
			alias Table = typeof(__traits(getMember, Tables, tname));
			static assert(isTableDefinition!Table, "Table defintion lacks @TableDefinition UDA: "~Table.stringof);
			TableInfo ti;
			ti.handle = driver.getTableHandle(tname);
			foreach (cname; __traits(allMembers, Table)) {
				pragma(msg, "COL "~cname);
				ti.columnHandles ~= driver.getColumnHandle(ti.handle, cname);
			}
			m_tables ~= ti;
		}

		upgradeColumns();
	}

	auto find(QUERY...)()
		if (QUERY.length == 1)
	{
		alias T = QueryTable!QUERY;
		enum tidx = tableIndex!(T, Tables);
		return m_driver.find!(Row!T, QUERY)(m_tables[tidx].handle);
	}

	auto findOne(QUERY...)()
		if (QUERY.length == 1)
	{
		auto res = find!QUERY();
		enforce(!res.empty, "Not found!");
		return res.front;
	}

	void update(QUERY_AND_UPDATE...)()
		if (QUERY_AND_UPDATE.length == 2)
	{
		alias T = QueryTable!(QUERY_AND_UPDATE[0]);
		auto tidx = tableIndex!(T, Tables);
		m_driver.update!(Row!T, QUERY_AND_UPDATE)(m_tables[tidx].handle);
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

@property auto and(EXPRS...)() { return ConjunctionExpr!EXPRS(); }
@property auto or(EXPRS...)() { return DisjunctionExpr!EXPRS(); }
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
struct ConjunctionExpr(EXPRS...) { alias exprs = TypeTuple!EXPRS; }
struct DisjunctionExpr(EXPRS...) { alias exprs = TypeTuple!EXPRS; }


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
		pragma(msg, "MEMBER: "~MEMBERS[0]);
		mixin(format(`T %s;`, MEMBERS[0]));
	}
}

template isTableDefinition(T) {
	enum isTableDefinition = findFirstUDA!(TableDefinitionAttribute, T).found;
}

private template QueryTable(QUERIES...) if (QUERIES.length > 0) {
	static if (QUERIES.length == 1) {
		alias Q = typeof(QUERIES[0]);
		static if (isInstanceOf!(ConjunctionExpr, Q) || isInstanceOf!(DisjunctionExpr, Q)) {
			alias QueryTable = QueryTable!(Q.exprs);
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
/* MONGODB DRIVER                                                             */
/******************************************************************************/

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

	MongoCollection getTableHandle(string name) { return m_db[name]; }
	string getColumnHandle(MongoCollection coll, string name) { return name; }
	
	auto find(T, QUERY...)(MongoCollection table) if (QUERY.length == 1)
	{
		struct Query { mixin MongoQuery!(0, QUERY); }
		Query query;
		mixin(initializeMongoQuery!(0, QUERY)("query", "QUERY[0]"));
		
		import vibe.core.log; import vibe.data.bson;
		logInfo("QUERY (%s): %s", table.name, serializeToBson(query).toString());
		
		return table.find(query).map!(b => deserializeBson!T(b));
	}

	auto update(T, QUERY_AND_UPDATE...)(MongoCollection table) if (QUERY_AND_UPDATE.length == 2)
	{
		struct Query { mixin MongoQuery!(0, QUERY_AND_UPDATE[0]); }
		Query query;
		mixin(initializeMongoQuery!(0, QUERY_AND_UPDATE[0])("query", "QUERY_AND_UPDATE[0]"));

		struct Update { mixin MongoUpdate!(0, QUERY_AND_UPDATE[1]); }
		Update update;
		mixin(initializeMongoUpdate!(0, QUERY_AND_UPDATE[1])("update", "QUERY_AND_UPDATE[1]"));

		import vibe.core.log; import vibe.data.bson;
		logInfo("QUERY (%s): %s", table.name, serializeToBson(query).toString());
		logInfo("UPDATE: %s", serializeToBson(update).toString());

		table.update(query, update);
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

mixin template MongoQuery(size_t idx, QUERIES...) {
	static if (QUERIES.length > 1) {
		mixin MongoQuery!(idx, QUERIES[0 .. $/2]);
		mixin MongoQuery!(idx + QUERIES.length/2, QUERIES[$/2 .. $]);
	} else static if (QUERIES.length == 1) {
		alias Q = typeof(QUERIES[0]);

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
			mixin MongoQuery!(0, Q.exprs);
		} else static if (isInstanceOf!(DisjunctionExpr, Q)) {
			mixin(format(
				`static struct Q%s { mixin MongoQueries!(0, Q.exprs); } @(vibe.data.serialization.name("$or"), asArray) Q%s q%s;`, idx, idx, idx));
		} else static assert(false, "Unsupported query expression type: "~Q.stringof);
	}
}

mixin template MongoQueries(size_t idx, QUERIES...) {
	static if (QUERIES.length > 1) {
		mixin MongoQueries!(idx, QUERIES[0 .. $/2]);
		mixin MongoQueries!(idx + QUERIES.length/2, QUERIES[$/2 .. $]);
	} else static if (QUERIES.length == 1) {
		mixin(format(`struct Q%s { mixin MongoQuery!(0, QUERIES[0]); } Q%s q%s;`, idx, idx, idx));
	}
}

private static string initializeMongoQuery(size_t idx, QUERY...)(string name, string srcfield)
	if (QUERY.length == 1)
{
	string ret;
	alias Q = typeof(QUERY[0]);

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
		foreach (i, E; Q.exprs)
			//ret ~= initializeMongoQuery!(i, E)(format("%s.q%s", name, idx), format("%s.exprs[%s]", srcfield, i));
			ret ~= initializeMongoQuery!(i, E)(name, format("%s.exprs[%s]", srcfield, i));
	} else static if (isInstanceOf!(DisjunctionExpr, Q)) {
		foreach (i, E; Q.exprs)
			ret ~= initializeMongoQuery!(i, E)(format("%s.q%s.q%s", name, idx, i), format("%s.exprs[%s]", srcfield, i));
	} else static assert(false, "Unsupported query expression type: "~Q.stringof);

	return ret;
}

mixin template MongoUpdate(size_t idx, QUERIES...) {
	static if (QUERIES.length > 1) {
		mixin MongoUpdate!(idx, QUERIES[0 .. $/2]);
		mixin MongoUpdate!(idx + QUERIES.length/2, QUERIES[$/2 .. $]);
	} else static if (QUERIES.length == 1) {
		alias Q = typeof(QUERIES[0]);

		static if (isInstanceOf!(SetExpr, Q)) {
			mixin(format(q{static struct Q%s { Q.T %s; } @(vibe.data.serialization.name("$set")) Q%s q%s;}, idx, Q.name, idx, idx));
		} else static assert(false, "Unsupported update expression type: "~Q.stringof);
	}
}

mixin template MongoUpdates(size_t idx, QUERIES...) {
	static if (QUERIES.length > 1) {
		mixin MongoUpdates!(idx, QUERIES[0 .. $/2]);
		mixin MongoUpdates!(idx + QUERIES.length/2, QUERIES[$/2 .. $]);
	} else static if (QUERIES.length == 1) {
		mixin(format(`struct Q%s { mixin MongoUpdate!(0, QUERIES[0]); } Q%s q%s;`, idx, idx, idx));
	}
}

private static string initializeMongoUpdate(size_t idx, QUERY...)(string name, string srcfield)
	if (QUERY.length == 1)
{
	string ret;
	alias Q = typeof(QUERY[0]);

	static if (isInstanceOf!(SetExpr, Q)) {
		ret ~= format("%s.q%s.%s = %s.value;", name, idx, Q.name, srcfield);
	} else static assert(false, "Unsupported update expression type: "~Q.stringof);

	return ret;
}

bool anyOf(T)(T value, T[] values...)
{
	foreach (v; values)
		if (v == value)
			return true;
	return false;
}

