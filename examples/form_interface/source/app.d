import vibe.d;
import std.stdio;
import std.algorithm;
import std.string;
import vibe.http.form;

struct Address {
	string street;
	int door;
	int zip_code;
}
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

/**
  * This class serves its users array as html table. Also have a look at views/createTable.dt.
  */
class DataProvider {
		enum Fields {
				nameid, surnameid, addressid
		}
		void index(HttpServerRequest req, HttpServerResponse res) {
			getData(req, res);
		}
		void getData(HttpServerRequest req, HttpServerResponse res) {
			auto table=users;
			res.render!("createTable.dt", table)();
		}
		/**
		  Overload that takes an enumeration for indexing the users array in a secure way and a value to filter on.
		  Method code does not have to care about validating user data, no need to check that a field is actually present, no manual conversion, ...
		  Say that this is not ingenious, I love D.
		 */
		void getData(HttpServerRequest req, HttpServerResponse res, Fields field, string value) {
			auto table=users.filter!((a) => value.length==0 || a[field]==value)();
			res.render!("createTable.dt", table)();
		}
		/// Add a new user to the array, using this method from JavaScript is left as an exercise.
		void addUser(string name, string surname, string address) {
				users~=[name, surname, address];
		}
		/// Add user with structured address
		/// Don't use ref Address at the moment (dmd 2.060) you'll get an ICE.
		void addUser(string name, string surname, Address address) {
			users~=[name, surname, address.street~" "~to!string(address.door)~"\n"~to!string(address.zip_code)];
		}
private:
		string[][] users=[["Tina", "Muster", "Wassergasse 12"],
				["Martina", "Maier", "Broadway 6"],
				["John", "Foo", "Church Street 7"]];
}

class App {
	this(UrlRouter router, string prefix="/") {
		provider_=new DataProvider;
		prefix_= prefix.length==0 || prefix[$-1]!='/' ?  prefix~"/" : prefix;
		registerFormInterface(router, this, prefix);
		registerFormInterface(router, provider_, prefix~"dataProvider/");
	}
	void index(HttpServerRequest req, HttpServerResponse res) {
		getTable(req, res);
	}
	void getTable(HttpServerRequest req, HttpServerResponse res) {
			res.headers["Content-Type"] = "text/html";
			res.render!("tableview.dt", req, res, dataProvider)();
	}
	void getTable(HttpServerRequest req, HttpServerResponse res, DataProvider.Fields field, string value) {
			res.headers["Content-Type"] = "text/html";
			res.render!("tableview.dt", req, res, dataProvider, field, value)();
	}
	void addUser(HttpServerRequest req, HttpServerResponse res, string name, string surname, string address) {
		dataProvider.addUser(name, surname, address);
		res.redirect(prefix);	
	}
	void addUser(HttpServerRequest req, HttpServerResponse res, string name, string surname, Address address) {
		dataProvider.addUser(name, surname, address);
		res.redirect(prefix);	
	}
	@property string prefix() {
		return prefix_;
	}
	@property DataProvider dataProvider() {
			return provider_;
	}
	static void getSomethingStatic() { // static methods are ignored.
		return;
	}
private:
	string prefix_;
	DataProvider provider_;
}

shared static this()
{
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	auto router = new UrlRouter;
	auto app=new App(router);
	listenHttp(settings, router);
}
