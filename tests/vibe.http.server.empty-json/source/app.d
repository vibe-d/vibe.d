import vibe.core.core : runTask, runEventLoop, exitEventLoop;
import vibe.data.json : serializeToJsonString;
import vibe.http.client : requestHTTP;
import vibe.http.server;
import vibe.stream.operations : readAllUTF8;

import std.conv : to;

void main()
{
	auto s1 = new HTTPServerSettings;
	s1.options &= ~HTTPServerOption.errorStackTraces;
	s1.bindAddresses = ["127.0.0.1"];
	s1.port = 11721;
	listenHTTP(s1, &handler);

	runTask({
		scope (exit) exitEventLoop();
		try {
			auto req = requestHTTP("http://127.0.0.1:" ~ s1.port.to!string);
			assert(req.bodyReader.readAllUTF8 == "JSON: null - World!\r\n");
		} catch (Exception e) {
			assert(false, e.msg);
		}
	});
	runEventLoop();
}

void handler(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	req.contentType = "application/json; charset=UTF-8";
	res.bodyWriter.write("JSON: " ~ req.json.serializeToJsonString);
	res.bodyWriter.write(" - World!\r\n");
}
