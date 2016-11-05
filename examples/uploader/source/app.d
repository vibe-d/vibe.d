import vibe.appmain;
import vibe.core.file;
import vibe.core.log;
import vibe.core.path;
import vibe.http.router;
import vibe.http.server;

import std.exception;


void uploadFile(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	auto pf = "file" in req.files;
	enforce(pf !is null, "No file uploaded!");
	try moveFile(pf.tempPath, Path(".") ~ pf.filename);
	catch (Exception e) {
		logWarn("Failed to move file to destination folder: %s", e.msg);
		logInfo("Performing copy+delete instead.");
		copyFile(pf.tempPath, Path(".") ~ pf.filename);
	}

	res.writeBody("File uploaded!", "text/plain");
}

shared static this()
{
	auto router = new URLRouter;
	router.get("/", staticTemplate!"upload_form.dt");
	router.post("/upload", &uploadFile);

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	listenHTTP(settings, router);
}
