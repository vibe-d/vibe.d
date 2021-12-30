module app;

import vibe.core.core;
import vibe.core.net;
import vibe.core.stream;

int main(string[] args)
{
	auto listener = listenTCP(2000, (conn) {
		try conn.pipe(conn);
		catch (Exception e) conn.close();
	});
	return runApplication(&args);
}
