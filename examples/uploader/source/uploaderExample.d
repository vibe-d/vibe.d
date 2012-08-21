import vibe.d;

void uploadFile(HttpServerRequest req, HttpServerResponse res)
{
	auto pf = "file" in req.files;
	enforce(pf !is null, "No file uploaded!");
	moveFile(pf.tempPath, Path(".")~pf.filename);

	res.writeBody("File uploaded!", "text/plain");
}

static this()
{
	auto router = new UrlRouter;
	router.get("/", staticTemplate!"upload_form.dt");
	router.post("/upload", &uploadFile);

	auto settings = new HttpServerSettings;
	settings.port = 8080;
	listenHttp(settings, router);
}
