module app;

import std.exception : enforce;
import vibe.core.log;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import vibe.utils.validation;
import vibe.web.web;
import vibe.web.i18n;

class UserSettings {
	string userName;
	bool someSetting;
}

struct TranslationContext {
	import std.typetuple;
	enum enforceExistingKeys = true;
	alias languages = TypeTuple!("en_US", "de_DE");
	mixin translationModule!"example";
}

static assert(tr!(TranslationContext, "de_DE")("Welcome to the i18n example app!") == "Willkommen zum i28n-Beispiel!");

@translationContext!TranslationContext
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

		auto s = new UserSettings;
		s.userName = user;
		s.someSetting = false;
		m_userSettings = s;
		redirect("./");
	}

	void postLogout()
	{
		m_userSettings = null;
		terminateSession();
		redirect("./");
	}

	void getSettings(string error = null)
	{
		auto settings = m_userSettings;
		render!("settings.dt", error, settings);
	}

	void postSettings(bool some_setting, string user_name)
	{
		try {
			enforce(m_userSettings !is null, "Must be logged in to change settings.");
			validateUserName(user_name);
			m_userSettings.userName = user_name;
			m_userSettings.someSetting = some_setting;
		} catch (Exception e) {
			getSettings(e.msg);
			return;
		}

		redirect("./");
	}
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
