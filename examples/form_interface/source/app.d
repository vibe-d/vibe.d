import vibe.d;
import std.stdio;
import std.algorithm;
import std.string;
import vibe.http.form;

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
		void getData(HttpServerRequest req, HttpServerResponse res, Fields field, string value) {
			auto table=users.filter!((a) => value.length==0 || a[field]==value)();
			res.render!("createTable.dt", table)();
		}
		void postUser(HttpServerRequest req, HttpServerResponse res, string name, string surname, string address) {
				users~=[name, surname, address];
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
		//router.get("/getTable", &app.getTable);
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
	@property string prefix() {
		return prefix_;
	}
	@property DataProvider dataProvider() {
			return provider_;
	}
private:
	string prefix_;
	DataProvider provider_;
}

static this()
{
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	auto router = new UrlRouter;
	auto app=new App(router);
	listenHttp(settings, router);
}
