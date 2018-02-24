module app;

import vibe.core.core;
import vibe.core.log;
import vibe.http.auth.basic_auth;
import vibe.http.client;
import vibe.http.router;
import vibe.http.server;
import vibe.web.auth;
import vibe.web.web;

import std.algorithm : among;
import std.datetime;
import std.format : format;


shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	auto router = new URLRouter;
	router.registerWebInterface(new Service);
	immutable serverAddr = listenHTTP(settings, router).bindAddresses[0];

    runTask({
        scope (exit) exitEventLoop();

        void test(string url, string user, HTTPStatus expected)
        nothrow {
            try {
                requestHTTP("http://" ~ serverAddr.toString ~ url, (scope req) {
                    if (user !is null) req.addBasicAuth(user, "secret");
                }, (scope res) {
                    res.dropBody();
                    assert(res.statusCode == expected, format("Unexpected status code for GET %s (%s): %s", url, user, res.statusCode));
                });
            } catch (Exception e) {
                assert(false, e.msg);
            }
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
        logInfo("All auth tests successful.");
    });
}

struct Auth {
    string username;

    bool isAdmin() { return username == "admin"; }
    bool isMember() { return username == "peter"; }
}

@requiresAuth
class Service {
    @noAuth void getPublic(HTTPServerResponse res) { res.writeBody("success"); }
    @anyAuth void getAny(HTTPServerResponse res) { res.writeBody("success"); }
    @anyAuth void getAnyA(HTTPServerResponse res, Auth auth) { assert(auth.username.among("admin", "peter", "stacy")); res.writeBody("success"); }
    @auth(Role.admin) void getAdmin(HTTPServerResponse res) { res.writeBody("success"); }
    @auth(Role.admin) void getAdminA(HTTPServerResponse res, Auth auth) { assert(auth.username == "admin"); res.writeBody("success"); }
    @auth(Role.member) void getMember(HTTPServerResponse res) { res.writeBody("success"); }
    @auth(Role.admin | Role.member) void getAdminMember(HTTPServerResponse res) { res.writeBody("success"); }

    @noRoute Auth authenticate(HTTPServerRequest req, HTTPServerResponse res)
    {
        Auth ret;
        ret.username = performBasicAuth(req, res, "test", (user, pw) { return pw == "secret"; });
        return ret;
    }
}
