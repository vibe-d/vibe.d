import vibe.d;

shared static this()
{
	listenTCP(7, conn => conn.write(conn));
}
