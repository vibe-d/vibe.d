import vibe.core.core;
import vibe.core.file;
import vibe.core.log;
import vibe.core.net;
import vibe.http.client;
import vibe.http.server;
import vibe.inet.webform;
import vibe.stream.memory;
import vibe.stream.operations;

void main(string[] args)
{
	bool handled = false;

	listenHTTP("127.0.0.1:11005", (scope req, scope res) {
		assert(req.form.length == 1);
		assert(req.files.length == 1);
		assert(req.form["name"] == "bob");
		assert(req.files["picture"].filename == "picture.png");
		auto f = openFile(req.files["picture"].tempPath, FileMode.read);
		auto data = f.readAllUTF8;
		f.close();
		assert(data == "Totally\0a\0PNG\0file.");
		removeFile(req.files["picture"].tempPath);
		res.writeBody("ok");
		handled = true;
	});

	requestHTTP("http://127.0.0.1:11005",
		(scope req) {
			MultiPartBody part;
			part.parts ~= MultiPart.formData("name", "bob");
			auto memStream = createMemoryStream(cast(ubyte[]) "Totally\0a\0PNG\0file.", false);
			part.parts ~= MultiPart.singleFile("picture", "picture.png", "image/png", memStream, true);
			req.writeMultiPartBody(part);
		},
		(scope res) {
			assert(res.bodyReader.readAllUTF8() == "ok");
		}
	);

	assert(handled);
}
