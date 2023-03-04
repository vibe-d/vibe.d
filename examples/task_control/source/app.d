module app;

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

int main(string[] args)
{
	g_task = runTask({
		logInfo("Starting task, waiting for max. 10 seconds.");
		try sleep(dur!"seconds"(10));
		catch (Exception e) logInfo("Task interrupted");
		logInfo("Exiting task after 10 seconds.");
	});

	runTask({
		logInfo("Monitor task started. Waiting for first task to end.");
		g_task.joinUninterruptible();
		logInfo("Task has finished.");
	});

	auto routes = new URLRouter;
	routes.get("/", &status);
	routes.post("/interrupt", &interrupt);

	auto settings = new HTTPServerSettings;
	settings.port = 8080;

	auto listener = listenHTTP(settings, routes);

	logInfo("Please open http://localhost:8080/ in a browser to monitor or interrupt the task.");
	return runApplication(&args);
}
