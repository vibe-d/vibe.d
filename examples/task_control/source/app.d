import vibe.appmain;
import vibe.core.core;
import vibe.core.log;
import vibe.http.router;
import vibe.http.server;

import core.time;


Task g_task;

void status(HTTPServerRequest req, HTTPServerResponse res)
{
	auto task = g_task;
	res.render!("index.dt", task);
}

void interrupt(HTTPServerRequest req, HTTPServerResponse res)
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

	auto routes = new URLRouter;
	routes.get("/", &status);
	routes.post("/interrupt", &interrupt);

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	listenHTTP(settings, routes);

	logInfo("Please open http://localhost:8080/ in a browser to monitor or interrupt the task.");
}
