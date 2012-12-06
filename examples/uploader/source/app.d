import vibe.d;

void uploadFile(HttpServerRequest req, HttpServerResponse res)
{
	auto pf = "file" in req.files;
	enforce(pf !is null, "No file uploaded!");
	try moveFile(pf.tempPath, Path(".")~pf.filename);
	catch( Exception e ){
		logWarn("Failed to move file to destination folder: %s", e.msg);
		logInfo("Performing copy+delete instead.");
		copyFile(pf.tempPath, Path(".")~pf.filename);
	}

	res.writeBody("File uploaded!", "text/plain");
}

shared static this()
{
	auto router = new UrlRouter;
	router.get("/", staticTemplate!"upload_form.dt");
	router.post("/upload", &uploadFile);

	auto settings = new HttpServerSettings;
	settings.port = 8080;
	listenHttp(settings, router);
}
