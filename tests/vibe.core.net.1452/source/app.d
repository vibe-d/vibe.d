import vibe.core.core;
import vibe.core.net;
import core.time : msecs;

class C {
	TCPConnection m_conn;

	this()
	{
		m_conn = connectTCP("google.com", 443);
	}

	~this()
	{
		m_conn.close();
	}
}

void main()
{
	auto c = new C;
	// let druntime collect c during shutdown
}
