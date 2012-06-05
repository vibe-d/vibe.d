import vibe.d;

interface IMyApi {
	string getStatus();

	@property string greeting();
	@property void greeting(string text);

	void addNewUser(string name);
	@property string[] users();
	string[] index();
	string getName(int id);
}

class MyApiImpl : IMyApi {
	private {
		string m_greeting;
		string[] m_users;
	}

	string getStatus() { return "OK"; }

	@property string greeting() { return m_greeting; }
	@property void greeting(string text) { m_greeting = text; }

	void addNewUser(string name) { m_users ~= name; }
	@property string[] users() { return m_users; }
	string[] index() { return m_users; }
	string getName(int id) { return m_users[id]; }
}

static this()
{
	// start the rest server
	auto routes = new UrlRouter;
	registerRestInterface!IMyApi(routes, new MyApiImpl, "/api/");
	listenHttp(new HttpServerSettings, routes);

	// use a timer to let the listen socket be setup before we try to connect
	setTimer(dur!"seconds"(1), {
			auto api = new RestInterfaceClient!IMyApi("http://127.0.0.1/api/");

			logInfo("Status: %s", api.getStatus());
			api.greeting = "Hello, World!";
			logInfo("Greeting message: %s", api.greeting);
			api.addNewUser("Peter");
			api.addNewUser("Igor");
			logInfo("Users: %s", api.users);
			logInfo("User index: %s", api.index());
		});
}