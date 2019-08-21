module app;

import vibe.core.core;
import vibe.core.log;
import vibe.http.auth.basic_auth;
import vibe.http.client;
import vibe.http.router;
import vibe.http.server;
import vibe.web.auth;
import vibe.web.rest;

import std.algorithm : among;
import std.datetime;
import std.format : format;


shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	auto router = new URLRouter;
	router.registerRestInterface(new Service);
	immutable serverAddr = listenHTTP(settings, router).bindAddresses[0];

    runTask({
        scope (exit) exitEventLoop();

        void test(string url, string user, HTTPStatus expected)
        {
            requestHTTP("http://" ~ serverAddr.toString ~ url, (scope req) {
                if (user !is null) req.addBasicAuth(user, "secret");
            }, (scope res) {
                res.dropBody();
                assert(res.statusCode == expected, format("Unexpected status code for GET %s (%s): %s", url, user, res.statusCode));
            });
        }

        test("/public", null, HTTPStatus.ok);
        test("/any", null, HTTPStatus.unauthorized);
        test("/any", "stacy", HTTPStatus.ok);
        test("/any_a", null, HTTPStatus.unauthorized);
        test("/any_a", "stacy", HTTPStatus.ok);
        test("/admin", null, HTTPStatus.unauthorized);
        test("/admin", "admin", HTTPStatus.ok);
        test("/admin", "peter", HTTPStatus.forbidden);
        test("/admin", "stacy", HTTPStatus.forbidden);
        test("/admin_a", null, HTTPStatus.unauthorized);
        test("/admin_a", "admin", HTTPStatus.ok);
        test("/admin_a", "peter", HTTPStatus.forbidden);
        test("/admin_a", "stacy", HTTPStatus.forbidden);
        test("/member", "admin", HTTPStatus.forbidden);
        test("/member", "peter", HTTPStatus.ok);
        test("/member", "stacy", HTTPStatus.forbidden);
        test("/admin_member", "peter", HTTPStatus.ok);
        test("/admin_member", "admin", HTTPStatus.ok);
        test("/admin_member", "stacy", HTTPStatus.forbidden);
        test("/nobody", "peter", HTTPStatus.forbidden);
        test("/nobody", "admin", HTTPStatus.forbidden);
        test("/nobody", "stacy", HTTPStatus.forbidden);
        logInfo("All auth tests successful.");
    });
}

struct Auth {
    string username;

    bool isAdmin() { return username == "admin"; }
    bool isMember() { return username == "peter"; }
}

@requiresAuth
interface IService {
    @noAuth int getPublic();
    @anyAuth int getAny();
    @anyAuth int getAnyA(Auth auth);
    @auth(Role.admin) int getAdmin();
    @auth(Role.admin) int getAdminA(Auth auth);
    @auth(Role.member) int getMember();
    @auth(Role.admin | Role.member) int getAdminMember();
    @auth(Role.admin & Role.member) int getNobody();
}

class Service : IService {
    int getPublic() { return 42; }
    int getAny() { return 42; }
    int getAnyA(Auth auth) { assert(auth.username.among("admin", "peter", "stacy")); return 42; }
    int getAdmin() { return 42; }
    int getAdminA(Auth auth) { assert(auth.username == "admin"); return 42; }
    int getMember() { return 42; }
    int getAdminMember() { return 42; }
    int getNobody() { return 42; }

    Auth authenticate(HTTPServerRequest req, HTTPServerResponse res)
    {
        Auth ret;
        ret.username = performBasicAuth(req, res, "test", (user, pw) { return pw == "secret"; });
        return ret;
    }
}
