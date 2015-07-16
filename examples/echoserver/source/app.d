import vibe.appmain;
import vibe.core.net;

shared static this()
{
	listenTCP(2000, conn => conn.write(conn));
}
