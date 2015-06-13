/**
	This example demonstrates some possibilities of registerWebInterface in conjunction with AJAX requests.

	The tableview.dt uses JavaScript for just replacing the table if filter-data changes if no JavaScript is available
	the whole site gets reloaded.
*/
module app;

import vibe.appmain;
import vibe.http.router;
import vibe.http.server;
import vibe.web.web;

import std.array;
import std.algorithm;
import std.conv;
import std.stdio;
import std.string;


struct Address {
	string street;
	int door;
	int zip_code;
}

/**
	This class serves its users array as html table. Also have a look at views/createTable.dt.

	It's intended to be used by AJAX queries to provide HTML snippets to use as replacements for
	DOM parts.
*/
class DataProvider {
	enum Fields {
		nameid,
		surnameid,
		addressid
	}

	private {
		string[][] users = [
				["Tina", "Muster", "Wassergasse 12"],
				["Martina", "Maier", "Broadway 6"],
				["John", "Foo", "Church Street 7"]
			];
	}

	// GET /data_provider/data
	void getData()
	{
		auto table = users;
		render!("createTable.dt", table)();
	}

	// GET /data_provider/data_filtered
	/**
		Overload that takes an enumeration for indexing the users array in a secure way and a value to filter on.
		Method code does not have to care about validating user data, no need to check that a field is actually present, no manual conversion, ...
		Say that this is not ingenious, I love D.
	*/
	void getDataFiltered(Fields field, string value)
	{
		auto table = users.filter!((a) => value.length==0 || a[field]==value)().array();
		render!("createTable.dt", table)();
	}

	// POST /data_provider/add_user
	/// Add a new user to the array, using this method from JavaScript is left as an exercise.
	void postAddUser(string name, string surname, string address)
	{
		users ~= [name, surname, address];
	}

	// POST /data_provider/add_user_structured
	/// Add user with structured address
	void postAddUserStructured(string name, string surname, Address address)
	{
		users ~= [name, surname, address.street~" "~to!string(address.door)~"\n"~to!string(address.zip_code)];
	}
}

class App {
	private {
		DataProvider m_provider;
	}

	this()
	{
		m_provider = new DataProvider;
	}

	// the methods of DataProvider will be available at /data_provider/*
	@property DataProvider dataProvider() { return m_provider; }

	// GET /
	void get()
	{
		redirect("/table");
	}

	// GET /table
	void getTable()
	{
		auto table = m_provider.users;
		render!("tableview.dt", table)();
	}

	// GET /table?field=...&value=...
	void getTable(DataProvider.Fields field, string value)
	{
		auto table = m_provider.users.filter!((a) => value.length==0 || a[field]==value)().array();
		render!("tableview.dt", table, field, value);
	}

	// POST /add_user
	void postAddUser(string name, string surname, string address)
	{
		dataProvider.postAddUser(name, surname, address);
		redirect("/");
	}

	// POST /add_user_structured
	void postAddUserStructured(string name, string surname, Address address)
	{
		dataProvider.postAddUserStructured(name, surname, address);
		redirect("/");
	}

	// static methods are ignored.
	static void getSomethingStatic()
	{
		return;
	}
}

shared static this()
{
	auto router = new URLRouter;
	router.registerWebInterface(new App);

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	listenHTTP(settings, router);
}
