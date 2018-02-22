import vibe.d;
import std.datetime;
import vibe.web.auth;

void main()
{
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	auto router = new URLRouter;
	router.registerRestInterface(new AuthAPI);
	immutable serverAddr = listenHTTP(settings, router).bindAddresses[0];

	runTask({
		scope(exit) exitEventLoop();

		void test(string url, string user, HTTPStatus expected = HTTPStatus.ok){
			requestHTTP("http://" ~ serverAddr.toString ~ url, (scope req){
				if(user !is null)
					req.headers["AuthUser"] = user;
			}, (scope res) {
				assert(res.statusCode == expected, format("Unexpected status code for GET %s (%s): %s\n%s", url, user, res.statusCode,res.readJson));
			});
		}

		test("/non_auth_number?num=5", null);
		test("/non_auth_number?num=5", "admin");
		test("/auth_number?num=5", "admin");
		test("/auth_number?num=5", null, HTTPStatus.forbidden);
		test("/items/name?item=something", "admin");
		test("/items/name?item=something", null, HTTPStatus.forbidden);
		test("/items/num?num=37", "admin");
		test("/items/num?num=37", null, HTTPStatus.forbidden);
	});

	runApplication();
}

struct AuthInfo {
	string name;
}

@requiresAuth
interface IItemAPI {
	struct CollectionIndices {
		string item;
	}

	@anyAuth string getName(string item, AuthInfo info);
	@anyAuth int getNum(int num);

	@noRoute final mixin CreateAuthFunc;
}

class ItemAPI : IItemAPI {
	string getName(string item, AuthInfo info){
		return info.name ~ item;
	}

	int getNum(int num){
		return num;
	}
}

@requiresAuth
interface IAuthAPI {
	@noAuth int getNonAuthNumber(int num);
	@anyAuth int getAuthNumber(AuthInfo info, int num);
	@anyAuth Collection!IItemAPI items();

	@noRoute final mixin CreateAuthFunc;
}

class AuthAPI : IAuthAPI {
	private IItemAPI m_items;
	this(){
		m_items = new ItemAPI;
	}

	Collection!IItemAPI items(){
		return Collection!IItemAPI(m_items);
	}

	int getNonAuthNumber(int num){
		return num;
	}
	int getAuthNumber(AuthInfo info, int num){
		logInfo("Returning auth number for authorized user: %s", info.name);
		return info.name.length.to!int * num;
	}
}

auto getReq(HTTPServerRequest req, HTTPServerResponse _){
	return req;
}

auto getRes(HTTPServerRequest _, HTTPServerResponse res){
	return res;
}

mixin template CreateAuthFunc(){
	AuthInfo authenticate(HTTPServerRequest req, HTTPServerResponse res){
		AuthInfo ret;
		if("AuthUser" in req.headers && req.headers["AuthUser"]=="admin"){
			ret.name = "admin";
		} else throw new HTTPStatusException(HTTPStatus.forbidden, "Forbidden");
		return ret;
	}
}
