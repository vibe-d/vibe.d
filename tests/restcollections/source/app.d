module app;

import vibe.vibe;

interface API {
@safe:
	Collection!ItemAPI items();
}

interface ItemAPI {
	struct CollectionIndices {
		string _item;
	}

@safe:
	Collection!SubItemAPI subItems(string _item);

	ItemManagerAPI manager();
}

interface SubItemAPI {
	struct CollectionIndices {
		string _item;
		int _index;
	}

@safe:
	@property int length(string _item);

	@method(HTTPMethod.GET)
	string name(string _item, int _index);
}

interface ItemManagerAPI {
@safe:
	@property string databaseURL();
}


class LocalAPI : API {
	LocalItemAPI m_items;
@safe:
	this() { m_items = new LocalItemAPI; }
	Collection!ItemAPI items() { return Collection!ItemAPI(m_items); }
}

class LocalItemAPI : ItemAPI {
	private {
		LocalItemManagerAPI m_manager;
		LocalSubItemAPI m_subItems;
	}

@safe:
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

@safe:
	this(LocalItemManagerAPI manager)
	{
		m_manager = manager;
	}

	@property int length(string _item) { return cast(int)m_manager.items[_item].length; }

	string name(string _item, int _index) { return m_manager.items[_item][_index]; }
}

class LocalItemManagerAPI : ItemManagerAPI {
	string[][string] items;

@safe:
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
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	settings.disableDistHost = true;
	immutable serverAddr = listenHTTP(settings, router).bindAddresses[0];

	auto api = new RestInterfaceClient!API("http://" ~ serverAddr.toString);
	assert(api.items["foo"].subItems.length == 2);
	assert(api.items["foo"].subItems[0].name == "hello");
	assert(api.items["foo"].subItems[1].name == "world");
	assert(api.items.manager.databaseURL == "in-memory://");
	exitEventLoop(true);
}

int main()
{
	setLogLevel(LogLevel.debug_);
	runTask(toDelegate(&runTest));
	return runEventLoop();
}
