import vibe.d;

Task g_task;

void status(HttpServerRequest req, HttpServerResponse res)
{
	res.renderCompat!("index.dt", Task, "task")(g_task);
}

void interrupt(HttpServerRequest req, HttpServerResponse res)
{
	g_task.interrupt();
	res.redirect("/");
}

shared static this()
{
	g_task = runTask({
		logInfo("Starting task, waiting for max. 10 seconds.");
		sleep(dur!"seconds"(10));
		logInfo("Exiting task after 10 seconds.");
	});

	runTask({
		logInfo("Monitor task started. Waiting for first task to end.");
		g_task.join();
		logInfo("Task has finished.");
	});

	auto routes = new UrlRouter;
	routes.get("/", &status);
	routes.post("/interrupt", &interrupt);

	auto settings = new HttpServerSettings;
	settings.port = 8080;
	listenHttp(settings, routes);

	logInfo("Please open http://localhost:8080/ in a browser to monitor or interrupt the task.");
}
