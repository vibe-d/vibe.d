import vibe.d;

static this()
{
	listenTcp(7, conn => conn.write(conn));
}
