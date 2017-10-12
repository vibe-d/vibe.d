module app;

import api;

import vibe.core.core;
import vibe.core.log;
import vibe.http.router;
import vibe.http.server;
import vibe.web.rest;


class ForumData {
	// maps thread ID to a list of messages
	string[][string] threads;
}

class LocalForumAPI : ForumAPI {
	ForumData m_data;
	LocalThreadAPI m_threads;

	this()
	{
		m_data = new ForumData;
		m_threads = new LocalThreadAPI(m_data);
	}

	Collection!ThreadAPI threads() { return Collection!ThreadAPI(m_threads); }
}

class LocalThreadAPI : ThreadAPI {
	private {
		ForumData m_data;
		LocalPostAPI m_posts;
	}

	this(ForumData data)
	{
		m_data = data;
		m_posts = new LocalPostAPI(data);
	}

	Collection!PostAPI posts(string _thread_name) { return Collection!PostAPI(m_posts, _thread_name); }

	void post(string name, string message)
	{
		m_data.threads[name] = [message];
	}

	string[] get()
	{
		return m_data.threads.keys;
	}
}

class LocalPostAPI : PostAPI {
	private {
		ForumData m_data;
	}

	this(ForumData data)
	{
		m_data = data;
	}

	void post(string _thread_name, string message)
	{
		m_data.threads[_thread_name] ~= message;
	}

	int getLength(string _thread_name)
	{
		return cast(int)m_data.threads[_thread_name].length;
	}

	string getMessage(string _thread_name, int _post_index)
	{
		return m_data.threads[_thread_name][_post_index];
	}

	string[] get(string _thread_name)
	{
		return m_data.threads[_thread_name];
	}
}

shared static this()
{
	auto router = new URLRouter;
	router.registerRestInterface(new LocalForumAPI);

	auto settings = new HTTPServerSettings;
	settings.bindAddresses = ["127.0.0.1"];
	settings.port = 8080;
	listenHTTP(settings, router);

	runTask({
		auto api = new RestInterfaceClient!ForumAPI("http://127.0.0.1:8080/");
		logInfo("Current number of threads: %s", api.threads.get().length);
		logInfo("Posting a topic...");
		api.threads.post("RESTful services", "Hi, just wanted to post something!");
		logInfo("Posting a reply...");
		api.threads["RESTful services"].posts.post("Okay, but what do you actually want to say?");
		logInfo("New list of threads:");
		foreach (th; api.threads.get) {
			import std.array : replicate;
			logInfo("\n%s\n%s", th, "=".replicate(th.length));
			foreach (m; api.threads[th].posts.get)
				logInfo("%s\n---", m);
		}
		logInfo("Leaving REST server running. Hit Ctrl+C to exit.");
	});
}
