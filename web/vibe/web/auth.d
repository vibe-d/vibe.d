/**
	Authentication and authorization framework based on fine-grained roles.

	Copyright: © 2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.web.auth;

import vibe.http.common : HTTPStatusException;
import vibe.http.status : HTTPStatus;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.internal.meta.uda : findFirstUDA;

import std.meta : AliasSeq, staticIndexOf;

///
@safe unittest {
	import vibe.http.router : URLRouter;
	import vibe.web.web : noRoute, registerWebInterface;

	static struct AuthInfo {
	@safe:
		string userName;

		bool isAdmin() { return this.userName == "tom"; }
		bool isRoomMember(int chat_room) {
			if (chat_room == 0)
				return this.userName == "macy" || this.userName == "peter";
			else if (chat_room == 1)
				return this.userName == "macy";
			else
				return false;
		}
		bool isPremiumUser() { return this.userName == "peter"; }
	}

	@requiresAuth
	static class ChatWebService {
	@safe:
		@noRoute AuthInfo authenticate(scope HTTPServerRequest req, scope HTTPServerResponse res)
		{
			if (req.headers["AuthToken"] == "foobar")
				return AuthInfo(req.headers["AuthUser"]);
			throw new HTTPStatusException(HTTPStatus.unauthorized);
		}

		@noAuth
		void getLoginPage()
		{
			// code that can be executed for any client
		}

		@anyAuth
		void getOverview()
		{
			// code that can be executed by any registered user
		}

		@auth(Role.admin)
		void getAdminSection()
		{
			// code that may only be executed by adminitrators
		}

		@auth(Role.admin | Role.roomMember)
		void getChatroomHistory(int chat_room)
		{
			// code that may execute for administrators or for chat room members
		}

		@auth(Role.roomMember & Role.premiumUser)
		void getPremiumInformation(int chat_room)
		{
			// code that may only execute for users that are members of a room and have a premium subscription
		}
	}

	void registerService(URLRouter router)
	@safe {
		router.registerWebInterface(new ChatWebService);
	}
}


/**
	Enables authentication and authorization checks for an interface class.

	Web/REST interface classes that have authentication enabled are required
	to specify either the `@auth` or the `@noAuth` attribute for every public
	method.

	The type of the authentication information, as returned by the
	`authenticate()` method, can optionally be specified as a template argument.
	This is useful if an `interface` is annotated and the `authenticate()`
	method is only declared in the actual class implementation.
*/
@property RequiresAuthAttribute!void requiresAuth()
{
	return RequiresAuthAttribute!void.init;
}
/// ditto
@property RequiresAuthAttribute!AUTH_INFO requiresAuth(AUTH_INFO)()
{
	return RequiresAuthAttribute!AUTH_INFO.init;
}

/** Enforces authentication and authorization.

	Params:
		roles = Role expression to control authorization. If no role
			set is given, any authenticated user is granted access.
*/
AuthAttribute!R auth(R)(R roles) { return AuthAttribute!R.init; }

/** Enforces only authentication.
*/
@property AuthAttribute!void anyAuth() { return AuthAttribute!void.init; }

/** Disables authentication checks.
*/
@property NoAuthAttribute noAuth() { return NoAuthAttribute.init; }

/// private
struct RequiresAuthAttribute(AUTH_INFO) { alias AuthInfo = AUTH_INFO; }

/// private
struct AuthAttribute(R) { alias Roles = R; }

// private
struct NoAuthAttribute {}

/** Represents a required authorization role.

	Roles can be combined using logical or (`|` operator) or logical and (`&`
	operator). The role name is directly mapped to a method name of the
	authorization interface specified on the web interface class using the
	`@requiresAuth` attribute.

	See_Also: `auth`
*/
struct Role {
	@disable this();

	static @property R!(Op.ident, name, void, void) opDispatch(string name)() { return R!(Op.ident, name, void, void).init; }
}

package auto handleAuthentication(alias fun, C)(C c, HTTPServerRequest req, HTTPServerResponse res)
{
	import std.traits : MemberFunctionsTuple;

	alias AI = AuthInfo!C;
	enum funname = __traits(identifier, fun);

	static if (!is(AI == void)) {
		alias AR = GetAuthAttribute!fun;
		static if (findFirstUDA!(NoAuthAttribute, fun).found) {
			static assert (is(AR == void), "Method "~funname~" specifies both, @noAuth and @auth(...)/@anyAuth attributes.");
			static assert(!hasParameterType!(fun, AI), "Method "~funname~" is attributed @noAuth, but also has an "~AI.stringof~" paramter.");
			// nothing to do
		} else {
			static assert(!is(AR == void), "Missing @auth(...)/@anyAuth attribute for method "~funname~".");

			static if (!__traits(compiles, () @safe { c.authenticate(req, res); } ()))
				pragma(msg, "Non-@safe .authenticate() methods are deprecated - annotate "~C.stringof~".authenticate() with @safe or @trusted.");
			return () @trusted { return c.authenticate(req, res); } ();
		}
	} else {
		// make sure that there are no @auth/@noAuth annotations for non-authorizing classes
		foreach (mem; __traits(allMembers, C))
			foreach (fun; MemberFunctionsTuple!(C, mem)) {
				static if (__traits(getProtection, fun) == "public") {
					static assert (!findFirstUDA!(NoAuthAttribute, C).found,
						"@noAuth attribute on method "~funname~" is not allowed without annotating "~C.stringof~" with @requiresAuth.");
					static assert (is(GetAuthAttribute!fun == void),
						"@auth(...)/@anyAuth attribute on method "~funname~" is not allowed without annotating "~C.stringof~" with @requiresAuth.");
				}
			}
	}
}

package void handleAuthorization(C, alias fun, PARAMS...)(AuthInfo!C auth_info)
{
	import std.traits : MemberFunctionsTuple, ParameterIdentifierTuple;
	import vibe.internal.meta.typetuple : Group;

	alias AI = AuthInfo!C;
	alias ParamNames = Group!(ParameterIdentifierTuple!fun);

	static if (!is(AI == void)) {
		static if (!findFirstUDA!(NoAuthAttribute, fun).found) {
			alias AR = GetAuthAttribute!fun;
			static if (!is(AR.Roles == void)) {
				static if (!__traits(compiles, () @safe { evaluate!(__traits(identifier, fun), AR.Roles, AI, ParamNames, PARAMS)(auth_info); } ()))
					pragma(msg, "Non-@safe role evaluator methods are deprecated - annotate "~C.stringof~"."~__traits(identifier, fun)~"() with @safe or @trusted.");
				if (!() @trusted { return evaluate!(__traits(identifier, fun), AR.Roles, AI, ParamNames, PARAMS)(auth_info); } ())
					throw new HTTPStatusException(HTTPStatus.forbidden, "Not allowed to access this resource.");
			}
			// successfully authorized, fall-through
		}
	}
}

package template isAuthenticated(C, alias fun) {
	static if (is(AuthInfo!C == void)) {
		static assert(!findFirstUDA!(NoAuthAttribute, fun).found && !findFirstUDA!(AuthAttribute, fun).found,
			C.stringof~"."~__traits(identifier, fun)~": @auth/@anyAuth/@noAuth attributes require @requiresAuth attribute on the containing class.");
		enum isAuthenticated = false;
	} else {
		static assert(findFirstUDA!(NoAuthAttribute, fun).found || findFirstUDA!(AuthAttribute, fun).found,
			C.stringof~"."~__traits(identifier, fun)~": Endpoint method must be annotated with either of @auth/@anyAuth/@noAuth.");
		enum isAuthenticated = !findFirstUDA!(NoAuthAttribute, fun).found;
	}
}

unittest {
	class C {
		@noAuth void a() {}
		@auth(Role.test) void b() {}
		@anyAuth void c() {}
		void d() {}
	}

	static assert(!is(typeof(isAuthenticated!(C, C.a))));
	static assert(!is(typeof(isAuthenticated!(C, C.b))));
	static assert(!is(typeof(isAuthenticated!(C, C.c))));
	static assert(!isAuthenticated!(C, C.d));

	@requiresAuth
	class D {
		@noAuth void a() {}
		@auth(Role.test) void b() {}
		@anyAuth void c() {}
		void d() {}
	}

	static assert(!isAuthenticated!(D, D.a));
	static assert(isAuthenticated!(D, D.b));
	static assert(isAuthenticated!(D, D.c));
	static assert(!is(typeof(isAuthenticated!(D, D.d))));
}


package template AuthInfo(C, CA = C)
{
	import std.traits : BaseTypeTuple, isInstanceOf;
	alias ATTS = AliasSeq!(__traits(getAttributes, CA));
	alias BASES = BaseTypeTuple!CA;

	template impl(size_t idx) {
		static if (idx < ATTS.length) {
			static if (is(typeof(ATTS[idx])) && isInstanceOf!(RequiresAuthAttribute, typeof(ATTS[idx]))) {
				static if (is(typeof(C.init.authenticate(HTTPServerRequest.init, HTTPServerResponse.init)))) {
					alias impl = typeof(C.init.authenticate(HTTPServerRequest.init, HTTPServerResponse.init));
					static assert(is(ATTS[idx].AuthInfo == void) || is(ATTS[idx].AuthInfo == impl),
						"Type mismatch between the @requiresAuth annotation and the authenticate() method.");
				} else static if (is(C == interface)) {
					alias impl = ATTS[idx].AuthInfo;
					static assert(!is(impl == void), "Interface "~C.stringof~" either needs to supply an authenticate method or must supply the authentication information via @requiresAuth!T.");
				} else
					static assert (false,
						C.stringof~" must have an authenticate(...) method that takes HTTPServerRequest/HTTPServerResponse parameters and returns an authentication information object.");
			} else alias impl = impl!(idx+1);
		} else alias impl = void;
	}

	template cimpl(size_t idx) {
		static if (idx < BASES.length) {
			alias AI = AuthInfo!(C, BASES[idx]);
			static if (is(AI == void)) alias cimpl = cimpl!(idx+1);
			else alias cimpl = AI;
		} else alias cimpl = void;
	}

	static if (!is(impl!0 == void)) alias AuthInfo = impl!0;
	else alias AuthInfo = cimpl!0;
}

unittest {
	@requiresAuth
	static class I {
		static struct A {}
	}
	static assert (!is(AuthInfo!I)); // missing authenticate method

	@requiresAuth
	static class J {
		static struct A {
		}
		A authenticate(HTTPServerRequest, HTTPServerResponse) { return A.init; }
	}
	static assert (is(AuthInfo!J == J.A));

	static class K {}
	static assert (is(AuthInfo!K == void));

	static class L : J {}
	static assert (is(AuthInfo!L == J.A));

	@requiresAuth
	interface M {
		static struct A {
		}
	}
	static class N : M {
		A authenticate(HTTPServerRequest, HTTPServerResponse) { return A.init; }
	}
	static assert (is(AuthInfo!N == M.A));
}

private template GetAuthAttribute(alias fun)
{
	import std.traits : isInstanceOf;
	alias ATTS = AliasSeq!(__traits(getAttributes, fun));

	template impl(size_t idx) {
		static if (idx < ATTS.length) {
			static if (is(typeof(ATTS[idx])) && isInstanceOf!(AuthAttribute, typeof(ATTS[idx]))) {
				alias impl = typeof(ATTS[idx]);
				static assert(is(impl!(idx+1) == void), "Method "~__traits(identifier, fun)~" may only specify one @auth attribute.");
			} else alias impl = impl!(idx+1);
		} else alias impl = void;
	}
	alias GetAuthAttribute = impl!0;
}

unittest {
	@auth(Role.a) void c();
	static assert(is(GetAuthAttribute!c.Roles == typeof(Role.a)));

	void d();
	static assert(is(GetAuthAttribute!d == void));

	@anyAuth void a();
	static assert(is(GetAuthAttribute!a.Roles == void));

	@anyAuth @anyAuth void b();
	static assert(!is(GetAuthAttribute!b));

}

private enum Op { none, and, or, ident }

private struct R(Op op_, string ident_, Left_, Right_) {
	alias op = op_;
	enum ident = ident_;
	alias Left = Left_;
	alias Right = Right_;

	R!(Op.or, null, R, O) opBinary(string op : "|", O)(O other) { return R!(Op.or, null, R, O).init; }
	R!(Op.and, null, R, O) opBinary(string op : "&", O)(O other) { return R!(Op.and, null, R, O).init; }
}

private bool evaluate(string methodname, R, A, alias ParamNames, PARAMS...)(ref A a)
{
	import std.ascii : toUpper;
	import std.traits : ParameterTypeTuple, ParameterIdentifierTuple;

	static if (R.op == Op.ident) {
		enum fname = "is" ~ toUpper(R.ident[0]) ~ R.ident[1 .. $];
		alias func = AliasSeq!(__traits(getMember, a, fname))[0];
		alias fpNames = ParameterIdentifierTuple!func;
		alias FPTypes = ParameterTypeTuple!func;
		FPTypes params;
		foreach (i, P; FPTypes) {
			enum name = fpNames[i];
			enum j = staticIndexOf!(name, ParamNames.expand);
			static assert(j >= 0, "Missing parameter "~name~" to evaluate @auth attribute for method "~methodname~".");
			static assert (is(typeof(PARAMS[j]) == P),
				"Parameter "~name~" of "~methodname~" is expected to have type "~P.stringof~" to match @auth attribute.");
			params[i] = PARAMS[j];
		}
		return __traits(getMember, a, fname)(params);
	}
	else static if (R.op == Op.and) return evaluate!(methodname, R.Left, A, ParamNames, PARAMS)(a) && evaluate!(methodname, R.Right, A, ParamNames, PARAMS)(a);
	else static if (R.op == Op.or) return evaluate!(methodname, R.Left, A, ParamNames, PARAMS)(a) || evaluate!(methodname, R.Right, A, ParamNames, PARAMS)(a);
	else return true;
}

unittest {
	import vibe.internal.meta.typetuple : Group;

	static struct AuthInfo {
		this(string u) { this.username = u; }
		string username;

		bool isAdmin() { return this.username == "peter"; }
		bool isMember(int room) { return this.username == "tom"; }
	}

	auto peter = AuthInfo("peter");
	auto tom = AuthInfo("tom");

	{
		int room;

		alias defargs = AliasSeq!(AuthInfo, Group!("room"), room);

		auto ra = Role.admin;
		assert(evaluate!("x", typeof(ra), defargs)(peter) == true);
		assert(evaluate!("x", typeof(ra), defargs)(tom) == false);

		auto rb = Role.member;
		assert(evaluate!("x", typeof(rb), defargs)(peter) == false);
		assert(evaluate!("x", typeof(rb), defargs)(tom) == true);

		auto rc = Role.admin & Role.member;
		assert(evaluate!("x", typeof(rc), defargs)(peter) == false);
		assert(evaluate!("x", typeof(rc), defargs)(tom) == false);

		auto rd = Role.admin | Role.member;
		assert(evaluate!("x", typeof(rd), defargs)(peter) == true);
		assert(evaluate!("x", typeof(rd), defargs)(tom) == true);

		static assert(__traits(compiles, evaluate!("x", typeof(ra), AuthInfo, Group!())(peter)));
		static assert(!__traits(compiles, evaluate!("x", typeof(rb), AuthInfo, Group!())(peter)));
	}

	{
		float room;
		static assert(!__traits(compiles, evaluate!("x", typeof(rb), AuthInfo, Group!("room"), room)(peter)));
	}

	{
		int foo;
		static assert(!__traits(compiles, evaluate!("x", typeof(rb), AuthInfo, Group!("foo"), foo)(peter)));
	}
}
