import vibe.d;

shared static this()
{
	listenTcp(7, conn => conn.write(conn));
}
