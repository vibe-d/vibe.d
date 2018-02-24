import std.datetime;
import vibe.d;

interface IOrientDBRoot
{
	@property IOrientDBQuery query();
}

interface IOrientDBQuery
{
	@method(HTTPMethod.GET)
	@path(":db_name/sql/:query/:result_set_size")
	Json sql(string _db_name, string _query, int _result_set_size);

	@method(HTTPMethod.GET)
	@path(":db_name/sql2/:query/:result_set_size")
	Json sql2(string _db_name, string _query, int _result_set_size);
}

class OrientDBRoot : IOrientDBRoot {
	private OrientDBQuery m_query;
	override @property IOrientDBQuery query() { return m_query; }
	public this() { this.m_query = new OrientDBQuery(); }
}

class OrientDBQuery : IOrientDBQuery {
	override Json sql(string _db_name, string _query, int _result_set_size) {
		assert(_db_name == Param1, _db_name);
		assert(_query == Param2, _query);
		assert(_result_set_size == Param3, to!string(_result_set_size));
		return Json.emptyObject;
	}

	override Json sql2(string _db_name, string _query, int _result_set_size) {
		assert(_db_name == Param1, _db_name);
		assert(_query == Param2ALT, _query);
		assert(_result_set_size == Param3, to!string(_result_set_size));
		return Json.emptyObject;
	}
}

enum Param1 = "twitter_data";
enum Param2 = "select DownloadedDateTime from Message";
enum Param2ALT = "tricky/param/eter";
enum Param3 = 1;

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	auto router = new URLRouter;
	router.registerRestInterface(new OrientDBRoot);
	immutable serverAddr = listenHTTP(settings, router).bindAddresses[0];

	setTimer(1.seconds, {
			scope (exit) exitEventLoop(true);
			auto api = new RestInterfaceClient!IOrientDBRoot(
				"http://"~serverAddr.toString);
			api.query.sql(Param1, Param2, Param3);
			api.query.sql2(Param1, Param2ALT, Param3);
		});
}
