import vibe.core.core;
import vibe.core.log;
import vibe.core.net;
import vibe.http.client;
import vibe.http.server;
import vibe.stream.operations;
import vibe.stream.memory;

shared static this()
{
	listenHTTP("127.0.0.1:11005", (scope req, scope res) {
		foreach (k, v; req.form)
			logInfo("%s: %s", k, v);
		foreach (k, v; req.files)
			logInfo("%s: %s", k, v.filename);
		res.writeBody("Hello world.");
	});

	runTask({
		requestHTTP("http://127.0.0.1:11005",
			(scope req) {
				MultiPart part = new MultiPart;
				part.parts ~= MultiPartBodyPart.formData("name", "bob");
				auto memStream = createMemoryStream(cast(ubyte[]) "Totally\0a\0PNG\0file.", false);
				part.parts ~= MultiPartBodyPart.singleFile("picture", "picture.png", "image/png", memStream, true);
				req.writePart(part);
			},
			(scope res) {}
		);
		exitEventLoop();
	});
}
