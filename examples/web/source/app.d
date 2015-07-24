// This module implements a simple web service with a login form and two
// settings that can be changed by the logged in user.
module app;

import std.exception : enforce;
import vibe.core.log;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import vibe.utils.validation;
import vibe.web.web;

// Aggregates all information about the currently logged in user (if any).
struct UserSettings {
	bool loggedIn = false;
	string userName;
	bool someSetting;
}

// The methods of this class will be mapped to HTTP routes and serve as
// request handlers.
class SampleService {
	private {
		// Type-safe and convenient access of user settings. This
		// SessionVar will store the contents of the variable in the
		// HTTP session with the key "settings". A session will be
		// started automatically as soon as m_userSettings gets modified
		// modified.
		SessionVar!(UserSettings, "settings") m_userSettings;
	}

	// overrides the path that gets inferred from the method name to
	// "GET /"
	@path("/") void getHome()
	{
		auto settings = m_userSettings;
		render!("home.dt", settings);
	}

	// Method name gets mapped to "GET /login" and a single optional
	// _error parameter is accepted (see postLogin)
	void getLogin(string _error = null)
	{
		string error = _error;
		render!("login.dt", error);
	}

	// Method name gets mapped to "POST /login" and two HTTP form parameters
	// (taken from HTTPServerRequest.form or .query) are accepted.
	//
	// The @errorDisplay attribute causes any exceptions to be passed to the
	// _error parameter of getLogin to render the error. The same happens for
	// validation errors (ValidUsername).
	@errorDisplay!getLogin
	void postLogin(ValidUsername user, string password)
	{
		enforce(password == "secret", "Invalid password.");

		UserSettings s;
		s.loggedIn = true;
		s.userName = user;
		s.someSetting = false;
		m_userSettings = s;
		redirect("./");
	}

	// GET /logout
	// This method accepts the raw HTTPServerResponse to access advanced fields
	void postLogout(scope HTTPServerResponse res)
	{
		m_userSettings = UserSettings.init;
		// NOTE: there is also a terminateSession() function in vibe.web.web
		// that avoids the need to work with a raw HTTPServerResponse.
		res.terminateSession();
		redirect("./");
	}

	// GET /settings
	// This method uses a custom @auth attribute (defined below) that injects
	// code to ensure correct authentication and that fills the _authUser parameter
	// with the authenticated user name
	@auth
	void getSettings(string _authUser, string _error = null)
	{
		UserSettings settings = m_userSettings;
		auto error = _error;
		render!("settings.dt", error, settings);
	}

	// POST /settings
	// Again uses the @auth custom attribute and @errorDisplay to render errors
	// using the getSettings method.
	@auth @errorDisplay!getSettings
	void postSettings(bool some_setting, ValidUsername user_name, string _authUser)
	{
		assert(m_userSettings.loggedIn);
		UserSettings s = m_userSettings;
		s.userName = user_name;
		s.someSetting = some_setting;
		m_userSettings = s;
		redirect("./");
	}

	// Defines the @auth attribute in terms of an @before annotation. @before causes
	// the given method (ensureAuth) to be called before the request handler is run.
	// It's return value will be passed to the "_authUser" parameter of the handler.
	private enum auth = before!ensureAuth("_authUser");

	// Implementation of the @auth attribute - ensures that the user is logged in and
	// redirects to the log in page otherwise (causing the actual request handler method
	// to be skipped).
	private string ensureAuth(scope HTTPServerRequest req, scope HTTPServerResponse res)
	{
		if (!SampleService.m_userSettings.loggedIn) redirect("/login");
		return SampleService.m_userSettings.userName;
	}

	// Adds support for using private member functions with "before". The ensureAuth method
	// is only used internally in this class and should be private, but by default external
	// template code has no access to private symbols, even if those are explicitly passed
	// to the template. This mixin template defined in vibe.web.web creates a special class
	// member that enables this usage pattern.
	mixin PrivateAccessProxy;
}


shared static this()
{
	// Create the router that will dispatch each request to the proper handler method
	auto router = new URLRouter;
	// Register our sample service class as a web interface. Each public method
	// will be mapped to a route in the URLRouter
	router.registerWebInterface(new SampleService);
	// All requests that haven't been handled by the web interface registered above
	// will be handled by looking for a matching file in the public/ folder.
	router.get("*", serveStaticFiles("public/"));

	// Start up the HTTP server
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	settings.sessionStore = new MemorySessionStore;
	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8080/ in your browser.");
}
