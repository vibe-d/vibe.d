import vibe.core.log;
import vibe.core.core;
import vibe.http.cookiejar;
import std.stdio;
import vibe.http.client;
import vibe.stream.operations : readAllUTF8;
import std.datetime;
import core.thread;
import vibe.stream.botan;
void main()
{
	setLogLevel(LogLevel.debug_);
	FileCookieJar cookies = new FileCookieJar("hello.cookies");
	HTTPClientSettings settings = new HTTPClientSettings;
	settings.cookieJar = cookies;
	settings.http2.settings.enablePush = false;
	settings.maxRedirects = 2;
	settings.defaultKeepAliveTimeout = 3.seconds;
	string result;

	void secondTask() {
		runTask(
			{
				StopWatch sw;
				sw.start();
				requestHTTP("https://google.com",
					(scope req) {
						
						logDebug("Callback called with Request");
						req.headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8";
						req.headers["Accept-Language"] = "en-US,en;q=0.5";
						if (req.isHTTP2)
							logDebug("Ping request took: %s ms", req.ping().total!"msecs");
						version (Botan) {
							if (auto tls = cast(BotanTLSStream) req.tlsStream()) {
								logDebug("Session id: %s", tls.sessionId);
								logDebug("Cipher: %s", tls.cipher);
								logDebug("Protocol: %s", tls.protocol.toString());
								if (tls.x509Certificate) logDebug("%s", tls.x509Certificate.toString());
							}
						}
					},
					(scope res) {
						logInfo("Response: %d", res.statusCode);
						foreach (k, v; res.headers)
							logInfo("Header: %s: %s", k, v);
						result = res.bodyReader.readAllUTF8(true);
						sw.stop();
						auto sw_msecs = sw.peek().msecs;
						logDebug("Finished reading result in %s ms", sw_msecs);
						Thread.sleep(30.msecs);
					}, settings);
				
			}
			
			);
	}

	setTimer(15.seconds, &secondTask);

	runTask(
		{
			StopWatch sw;
			sw.start();
			requestHTTP("https://127.0.0.1:8080/static/10k",
				(scope req) {

					logDebug("Callback called with Request");
					req.headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8";
					req.headers["Accept-Language"] = "en-US,en;q=0.5";
					if (req.isHTTP2)
						logDebug("Ping request took: %s ms", req.ping().total!"msecs");
					version(Botan) {
						if (auto tls = cast(BotanTLSStream) req.tlsStream()) {
							logDebug("Session id: %s", tls.sessionId);
							logDebug("Cipher: %s", tls.cipher);
							logDebug("Protocol: %s", tls.protocol.toString());
							logDebug("%s", tls.x509Certificate.toString());
						}
					}
				},
				(scope res) {
					logInfo("Response: %d", res.statusCode);
					foreach (k, v; res.headers)
						logInfo("Header: %s: %s", k, v);
					result = res.bodyReader.readAllUTF8();
					sw.stop();
					auto sw_msecs = sw.peek().msecs;
					logDebug("Finished reading result in %s ms", sw_msecs);
					Thread.sleep(30.msecs);
				}, settings);
	
		}

	);

	runEventLoop();
	auto f = File("results.txt", "w+");
	f.rawWrite(result);
	getEventDriver().runEventLoopOnce();
}
