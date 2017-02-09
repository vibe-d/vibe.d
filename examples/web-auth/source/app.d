// This module implements a simple web service with a login form and two
// settings that can be changed by the logged in user.
// It uses an authorization framework for fine-grained roles.
module app;

import std.exception : enforce;
import vibe.core.log;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import vibe.utils.validation;
import vibe.web.auth;
import vibe.web.web;

// Aggregates information and roles about the currently logged in user
struct AuthInfo {
	string userName;
    bool premium;
    bool admin;

	@safe:
	bool isAdmin() { return this.admin; }
	bool isPremiumUser() { return this.premium; }
}

/**
The methods of this class will be mapped to HTTP routes and serve as request handlers.
The @requiresAuth annotation demands that every public method is annotated with either:
- @noAuth
- @anyAuth
- @auth(...)
*/
@requiresAuth
class SampleService {

	// The authentication handler which will be called whenever auth info is needed.
	// Its return type can be injected into the routes of the associated service.
	// (for obvious reasons this shouldn't be a route itself)
	@noRoute
	AuthInfo authenticate(scope HTTPServerRequest req, scope HTTPServerResponse res) @safe
	{
		if (!req.session || !req.session.isKeySet("auth"))
			throw new HTTPStatusException(HTTPStatus.forbidden, "Not authorized to perform this action!");

		return req.session.get!AuthInfo("auth");
	}

	// All public routes wrapped into one block
	@noAuth {

		// "GET /"
		// overrides the path that gets inferred from the method name to
		// HTTPServer{Request, Response} parameters get automatically injected
		@path("/") void getHome(scope HTTPServerRequest req)
		{
			import std.typecons : Nullable;

			Nullable!AuthInfo auth;
			if (req.session && req.session.isKeySet("auth"))
				auth = req.session.get!AuthInfo("auth");

			render!("home.dt", auth);
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
		void postLogin(ValidUsername user, string password, scope HTTPServerRequest req, scope HTTPServerResponse res)
		{
			enforce(password == "secret", "Invalid password.");

			AuthInfo s = {userName: user};
			req.session = res.startSession;
			req.session.set("auth", s);
			redirect("./");
		}
	}

	// Routes that require any kind of authentication
	@anyAuth {

		// GET /logout
		void postLogout()
		{
			terminateSession();
			redirect("./");
		}

		// GET /settings
		// authUser is automatically injected based on the authenticate() result
		void getSettings(AuthInfo auth, string _error = null)
		{
			auto error = _error;
			render!("settings.dt", error, auth);
		}

		// POST /settings
		// @errorDisplay will render errors using the getSettings method.
		// authUser gets injected with the associated authenticate()
		@errorDisplay!getSettings
		void postSettings(bool premium, bool admin, ValidUsername user_name, AuthInfo authUser, scope HTTPServerRequest req)
		{
			AuthInfo s = authUser;
			s.userName = user_name;
			s.premium = premium;
			s.admin = admin;
			req.session.set("auth", s);
			redirect("./");
		}
	}

	/**
		With @auth specific roles can be required. Moreover, they can be combined:

		    @auth(Role.admin) - requires an admin role
		    @auth(Role.admin | Role.premium) - requires an admin or a premium role
		    @auth(Role.admin & Role.premium) - requires an admin and a premium role

		The role is mapped to is<NameOfTheRole> of the type returned by the regarding
		authenticate method. For example, `Role.admin` will call `AuthInfo.isAdmin`
	*/

	// GET /premium
	@auth(Role.admin | Role.premiumUser)
	void getPremium()
	{
		render!("premium.dt");
	}

	// GET /admin
	@auth(Role.admin)
	void getAdmin()
	{
		render!("admin.dt");
	}
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
