import vibe.appmain;
import vibe.core.net;

shared static this()
{
	listenTCP(7, conn => conn.write(conn));
}
