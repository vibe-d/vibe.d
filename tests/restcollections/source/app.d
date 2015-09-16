module app;

import vibe.vibe;

interface API {
	Collection!ItemAPI items();
}

interface ItemAPI {
	alias ItemID = string;

	Collection!SubItemAPI subItems(string id);
	ItemManagerAPI manager();


}

interface SubItemAPI {
	import std.typetuple;
	alias ItemID = TypeTuple!(string, int);

	@property int length(string item);

	@method(HTTPMethod.GET)
	string name(string item, int index);
}

interface ItemManagerAPI {
	@property string databaseURL();
}


class LocalAPI : API {
	LocalItemAPI m_items;
	this() { m_items = new LocalItemAPI; }
	Collection!ItemAPI items() { return Collection!ItemAPI(m_items); }
}

class LocalItemAPI : ItemAPI {
	private {
		LocalItemManagerAPI m_manager;
		LocalSubItemAPI m_subItems;
	}

	this()
	{
		m_manager = new LocalItemManagerAPI;
		m_subItems = new LocalSubItemAPI(m_manager);
	}

	Collection!SubItemAPI subItems(string id) { return Collection!SubItemAPI(m_subItems, id); }

	ItemManagerAPI manager() { return m_manager; }
}

class LocalSubItemAPI : SubItemAPI {
	private LocalItemManagerAPI m_manager;

	this(LocalItemManagerAPI manager)
	{
		m_manager = manager;
	}
	
	@property int length(string item) { return cast(int)m_manager.items[item].length; }

	string name(string item, int index) { return m_manager.items[item][index]; }
}

class LocalItemManagerAPI : ItemManagerAPI {
	string[][string] items;

	this()
	{
		items = [
			"foo": ["hello", "world"],
			"bar": ["this", "is", "a", "test"]
		];
	}

	@property string databaseURL() { return "in-memory://"; }
}


void runTest()
{
	auto router = new URLRouter;
	router.registerRestInterface(new LocalAPI);

	auto settings = new HTTPServerSettings;
	settings.disableDistHost = true;
	settings.port = 8000;
	listenHTTP(settings, router);

	auto api = new RestInterfaceClient!API("http://127.0.0.1:8000/");
	//assert(api.items["foo"].subItems.length == 2);
	assert(api.items["foo"].subItems[0].name == "hello");
	assert(api.items["foo"].subItems[1].name == "world");
	exitEventLoop(true);
}

int main()
{
	setLogLevel(LogLevel.debug_);
	runTask(toDelegate(&runTest));
	return runEventLoop();
}
