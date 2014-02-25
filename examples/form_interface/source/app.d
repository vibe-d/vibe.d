/**
	This example pretty well shows how registerFormInterface is meant to be used and what possibilities it offers.
	The API that is exposed by DataProvider is conveniently usable by the methods in App and from JavaScript, with just
	one line of code: 

	---
	registerFormInterface(router, provider_, prefix~"dataProvider/");
	---

	The tableview.dt uses JavaScript for just replacing the table if filter-data changes if no JavaScript is available
	the whole site gets reloaded.
*/
module app;

import vibe.appmain;
import vibe.http.form;
import vibe.http.router;
import vibe.http.server;

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
  * This class serves its users array as html table. Also have a look at views/createTable.dt.
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

	void index(HTTPServerRequest req, HTTPServerResponse res)
	{
		getData(req, res);
	}

	void getData(HTTPServerRequest req, HTTPServerResponse res)
	{
		auto table = users;
		res.render!("createTable.dt", table)();
		//res.renderCompat!("createTable.dt",
		//	string[][], "table")(table);
	}

	/**
		Overload that takes an enumeration for indexing the users array in a secure way and a value to filter on.
		Method code does not have to care about validating user data, no need to check that a field is actually present, no manual conversion, ...
		Say that this is not ingenious, I love D.
	*/
	void getData(HTTPServerRequest req, HTTPServerResponse res, Fields field, string value)
	{
		auto table = users.filter!((a) => value.length==0 || a[field]==value)().array();
		res.render!("createTable.dt", table)();
		//res.renderCompat!("createTable.dt",
		//	string[][], "table")(table);
	}

	/// Add a new user to the array, using this method from JavaScript is left as an exercise.
	void addUser(string name, string surname, string address)
	{
		users ~= [name, surname, address];
	}

	/// Add user with structured address
	/// Don't use ref Address at the moment (dmd 2.060) you'll get an ICE.
	void addUser(string name, string surname, Address address)
	{
		users ~= [name, surname, address.street~" "~to!string(address.door)~"\n"~to!string(address.zip_code)];
	}
}

class App {
	private {
		string m_prefix;
		DataProvider m_provider;
	}

	this(URLRouter router, string prefix="/")
	{
		m_provider = new DataProvider;
		m_prefix = prefix.length==0 || prefix[$-1]!='/' ?  prefix~"/" : prefix;
		registerFormInterface(router, this, prefix);
		registerFormInterface(router, m_provider, prefix~"dataProvider/");
	}

	@property string prefix() const { return m_prefix; }

	@property inout(DataProvider) dataProvider() inout { return m_provider; }
	
	void index(HTTPServerRequest req, HTTPServerResponse res)
	{
		getTable(req, res);
	}

	void getTable(HTTPServerRequest req, HTTPServerResponse res)
	{
		res.headers["Content-Type"] = "text/html";
		res.render!("tableview.dt", req, res, dataProvider)();
		//res.renderCompat!("tableview.dt",
		//	HTTPServerRequest, "req",
		//	HTTPServerResponse, "res",
		//	DataProvider, "dataProvider")(req, res, dataProvider);
	}

	void getTable(HTTPServerRequest req, HTTPServerResponse res, DataProvider.Fields field, string value)
	{
		res.headers["Content-Type"] = "text/html";
		res.render!("tableview.dt", req, res, dataProvider, field, value)();
		//res.renderCompat!("tableview.dt",
		//	HTTPServerRequest, "req",
		//	HTTPServerResponse, "res",
		//	DataProvider, "dataProvider",
		//	DataProvider.Fields, "field",
		//	string, "value")(req, res, dataProvider, field, value);
	}

	void addUser(HTTPServerRequest req, HTTPServerResponse res, string name, string surname, string address)
	{
		dataProvider.addUser(name, surname, address);
		res.redirect(prefix);	
	}

	void addUser(HTTPServerRequest req, HTTPServerResponse res, string name, string surname, Address address)
	{
		dataProvider.addUser(name, surname, address);
		res.redirect(prefix);	
	}

	// static methods are ignored.
	static void getSomethingStatic()
	{
		return;
	}
}

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	auto router = new URLRouter;
	auto app = new App(router);
	listenHTTP(settings, router);
}
