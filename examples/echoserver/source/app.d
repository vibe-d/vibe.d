import vibe.appmain;
import vibe.core.net;
import vibe.core.stream;

shared static this()
{
	listenTCP(2000, (conn) {
		try conn.pipe(conn);
		catch (Exception e) conn.close();
	});
}
