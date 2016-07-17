/**
	A simple way to test routes added to a URLRouter

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module crate.request;

import vibe.inet.url;
import vibe.http.router;
import vibe.data.json;

import vibe.stream.memory;

import std.conv, std.string, std.array;
import std.stdio;

/**
	A nicer sintax to create a TestRouter.
	This function returns a TestRouter from URLRouter.
*/
TestRouter request(URLRouter router)
{
	return new TestRouter(router);
}

/**
	A simple class that offers an interface to inject and get data from URLRouter.
*/
final class TestRouter
{
	private
	{
		URLRouter router;
		HTTPServerRequest preparedRequest;

		string[string] expectHeaders;
		string[string] expectHeadersContains;
		int expectedStatusCode;

		string responseBody;
	}

	this(URLRouter router)
	{
		this.router = router;
	}

	/**
		Set the request body.
	*/
	TestRouter send(T)(T data)
	{
		static if (is(T == string))
		{
			preparedRequest.bodyReader = new MemoryStream(cast(ubyte[]) data);
			return this;
		}
		else static if (is(T == Json))
		{
			preparedRequest.json = data;
			return send(data.to!string);
		}
		else
		{
			return send(data.serializeToJson());
		}
	}

	/*
		Mock a POST request
	*/
	TestRouter post(string path)
	{
		return request!(HTTPMethod.POST)(URL("http://localhost" ~ path));
	}

  /*
    Mock a PUT request
  */
  TestRouter put(string path)
  {
    return request!(HTTPMethod.PUT)(URL("http://localhost" ~ path));
  }

	/*
		Mock a PATCH request
	*/
	TestRouter patch(string path)
	{
		return request!(HTTPMethod.PATCH)(URL("http://localhost" ~ path));
	}

	/*
		Mock a DELETE request
	*/
	TestRouter delete_(string path)
	{
		return request!(HTTPMethod.DELETE)(URL("http://localhost" ~ path));
	}

	/*
		Mock a GET request
	*/
	TestRouter get(string path)
	{
		return request!(HTTPMethod.GET)(URL("http://localhost" ~ path));
	}

	/*
		Mock a custom method request
	*/
	TestRouter request(HTTPMethod method)(URL url)
	{
		preparedRequest = createTestHTTPServerRequest(url, method);
		preparedRequest.host = "localhost";

		return this;
	}

	/*
		Set an expected response header. This method will match the full text inside
		the header value
	*/
	TestRouter expectHeader(string name, string value)
	{
		expectHeaders[name] = value;
		return this;
	}

	/*
		Set an expected response header. This method will match a part inside the
		header value
	*/
	TestRouter expectHeaderContains(string name, string value)
	{
		expectHeadersContains[name] = value;
		return this;
	}

	/*
		Set an expected response code.
	*/
	TestRouter expectStatusCode(int code)
	{
		expectedStatusCode = code;
		return this;
	}

	/*
		It checks for expected headers and status code.
	*/
	private void performExpected(TestResponse res)
	{

		if (expectedStatusCode != 0)
		{
			assert(expectedStatusCode == res.statusCode,
					"Expected status code `" ~ expectedStatusCode.to!string
					~ "` not found. Got `" ~ res.statusCode.to!string ~ "` instead");
		}

		foreach (string key, value; expectHeaders)
		{
			assert(key in res.headers, "Response header `" ~ key ~ "` is missing.");
			assert(res.headers[key] == value,
					"Response header `" ~ key ~ "` has an unexpected value. Expected `"
					~ value ~ "` != `" ~ res.headers[key].to!string ~ "`");
		}

		foreach (string key, value; expectHeadersContains)
		{
			assert(key in res.headers, "Response header `" ~ key ~ "` is missing.");
			assert(res.headers[key].indexOf(value) != -1,
					"Response header `" ~ key ~ "` has an unexpected value. Expected `"
					~ value ~ "` not found in `" ~ res.headers[key].to!string ~ "`");
		}

	}

	/*
		It performs the request and calls a callback for more validation, when it's needed.
	*/
	void end(T)(T callback)
	{
		import vibe.stream.operations : readAllUTF8;

		auto data = new ubyte[5000];

		MemoryStream stream = new MemoryStream(data);
		HTTPServerResponse res = createTestHTTPServerResponse(stream);
		res.statusCode = 404;

		router.handleRequest(preparedRequest, res);

		auto response = new TestResponse(cast(string) data);

		performExpected(response);

		callback(response)();
	}
}

class TestResponse
{
	string bodyString;

	private
	{
		Json _bodyJson;
	}

	string[string] headers;
	int statusCode;

	this(string data)
	{
		data = data.toStringz.to!string;
		auto bodyIndex = data.indexOf("\r\n\r\n");

		assert(bodyIndex != -1, "Invalid response data");

		auto headers = data[0 .. bodyIndex].split("\r\n").array;

		statusCode = headers[0].split(" ")[1].to!int;

		foreach (i; 1 .. headers.length)
		{
			auto header = headers[i].split(": ");
			this.headers[header[0]] = header[1];
		}

		bodyString = data[bodyIndex + 4 .. $];
	}

	@property Json bodyJson()
	{
		if (_bodyJson.type == Json.Type.undefined)
		{
			_bodyJson = bodyString.parseJson;
		}

		return _bodyJson;
	}
}

version(unittest) {
  void successResponse(HTTPServerRequest req, HTTPServerResponse res)
	{
    res.statusCode = 200;
		res.writeBody("success");
	}

  void echoResponse(HTTPServerRequest req, HTTPServerResponse res)
	{
    res.statusCode = 200;
		res.writeJsonBody(req.json);
	}
}

unittest {
  auto router = new URLRouter();
  router.get("/", &successResponse);

  request(router)
    .get("/")
    .expectStatusCode(200)
    .end((TestResponse response) => {
      assert(response.bodyString == "success");
    });
}

unittest {
  auto router = new URLRouter();
  router.get("/", &successResponse);

  request(router)
    .get("/")
    .expectStatusCode(200)
    .end((TestResponse response) => {
      assert(response.bodyString == "success");
    });
}

unittest {
  auto router = new URLRouter();
  router.post("/", &successResponse);

  request(router)
    .post("/")
    .expectStatusCode(200)
    .end((TestResponse response) => {
      assert(response.bodyString == "success");
    });
}

unittest {
  auto router = new URLRouter();
  router.delete_("/", &successResponse);

  request(router)
    .delete_("/")
    .expectStatusCode(200)
    .end((TestResponse response) => {
      assert(response.bodyString == "success");
    });
}

unittest {
  auto router = new URLRouter();
  router.patch("/", &successResponse);

  request(router)
    .patch("/")
    .expectStatusCode(200)
    .end((TestResponse response) => {
      assert(response.bodyString == "success");
    });
}

unittest {
  auto router = new URLRouter();
  router.put("/", &successResponse);

  request(router)
    .put("/")
    .expectStatusCode(200)
    .end((TestResponse response) => {
      assert(response.bodyString == "success");
    });
}

unittest {
  auto router = new URLRouter();
  router.put("/", &echoResponse);

  Json data = Json.emptyObject;
  data["message"] = "success";

  request(router)
    .put("/")
    .send(data)
    .expectStatusCode(200)
    .end((TestResponse response) => {
      writeln("===>", response.bodyString);
      assert(response.bodyJson["message"] == "success");
    });
}
