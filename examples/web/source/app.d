module app;

import std.exception : enforce;
import vibe.core.log;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import vibe.utils.validation;
import vibe.web.web;

struct UserSettings {
	bool loggedIn = false;
	string userName;
	bool someSetting;
}

class SampleService {
	private {
		SessionVar!(UserSettings, "settings") m_userSettings;
	}

	@path("/") void getHome()
	{
		auto settings = m_userSettings;
		render!("home.dt", settings);
	}

	void getLogin(string error = null) { render!("login.dt", error); }
	void postLogin(string user, string password)
	{
		try {
			validateUserName(user);
			enforce(password == "secret", "Invalid password.");
		} catch (Exception e) {
			getLogin(e.msg);
			return;
		}

		UserSettings s;
		s.loggedIn = true;
		s.userName = user;
		s.someSetting = false;
		m_userSettings = s;
		redirect("./");
	}

	void postLogout(HTTPServerResponse res)
	{
		m_userSettings = UserSettings.init;
		res.terminateSession();
		redirect("./");
	}

	@auth
	void getSettings(string _authUser, string _error = null)
	{
		UserSettings settings = m_userSettings;
		auto error = _error;
		render!("settings.dt", error, settings);
	}

	@auth @errorDisplay!getSettings
	void postSettings(bool some_setting, string user_name, string _authUser)
	{
		assert(m_userSettings.loggedIn);
		validateUserName(user_name);
		UserSettings s = m_userSettings;
		s.userName = user_name;
		s.someSetting = some_setting;
		m_userSettings = s;
		redirect("./");
	}

	private enum auth = before!ensureAuth("_authUser");
	private string ensureAuth(HTTPServerRequest req, HTTPServerResponse res)
	{
		if (!SampleService.m_userSettings.loggedIn) redirect("/login");
		return SampleService.m_userSettings.userName;
	}

	mixin PrivateAccessProxy; // adds support for using private member functions with "before"
}


shared static this()
{
	auto router = new URLRouter;
	router.registerWebInterface(new SampleService);
	router.get("*", serveStaticFiles("public/"));

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	settings.sessionStore = new MemorySessionStore;
	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8080/ in your browser.");
}
