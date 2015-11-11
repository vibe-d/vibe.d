module app;

import vibe.core.core;
import vibe.core.log;
import vibe.core.stream;
import vibe.stream.operations;
import vibe.stream.wrapper;
import vibe.stream.tls;
import vibe.stream.taskpipe;
import std.encoding : sanitize;

TLSContext createContext(TLSContextKind kind, string cert, string key, string trust, TLSPeerValidationMode mode)
{
	auto ctx = createTLSContext(kind);
	ctx.peerValidationMode = mode;
	if (cert.length) ctx.useCertificateChainFile(cert);
	if (key.length) ctx.usePrivateKeyFile(key);
	if (trust.length) ctx.useTrustedCertificateFile(trust);
	return ctx;
}

void createPipePair(out Stream a, out Stream b)
{
	auto p1 = new TaskPipe;
	auto p2 = new TaskPipe;
	a = new ProxyStream(p1, p2);
	b = new ProxyStream(p2, p1);
}

void testConn(
	bool cli_fail, string cli_cert, string cli_key, string cli_trust, string cli_peer, TLSPeerValidationMode cli_mode,
	bool srv_fail, string srv_cert, string srv_key, string srv_trust, string srv_peer, TLSPeerValidationMode srv_mode)
{
	Stream ctunnel, stunnel;
	logInfo("Test client %s (%s, %s, %s, %s), server %s (%s, %s, %s, %s)",
		cli_fail ? "fail" : "success", cli_cert, cli_key, cli_trust, cli_peer,
		srv_fail ? "fail" : "success", srv_cert, srv_key, srv_trust, srv_peer);

	createPipePair(ctunnel, stunnel);
	auto t1 = runTask({
		auto sctx = createContext(TLSContextKind.server, srv_cert, srv_key, srv_trust, srv_mode);
		TLSStream sconn;
		try {
			sconn = createTLSStream(stunnel, sctx, TLSStreamState.accepting, srv_peer);
			logDiagnostic("Successfully initiated server tunnel.");
			assert(!srv_fail, "Server expected to fail TLS connection.");
		} catch (Exception e) {
			if (srv_fail) logDiagnostic("Server tunnel failed as expected: %s", e.msg);
			else logError("Server tunnel failed: %s", e.toString().sanitize);
			assert(srv_fail, "Server not expected to fail TLS connection.");
			return;
		}
		if (cli_fail) return;
		assert(sconn.readLine() == "foo");
		sconn.write("bar\r\n");
		sconn.finalize();
	});
	auto t2 = runTask({
		auto cctx = createContext(TLSContextKind.client, cli_cert, cli_key, cli_trust, cli_mode);
		TLSStream cconn;
		try {
			cconn = createTLSStream(ctunnel, cctx, TLSStreamState.connecting, cli_peer);
			logDiagnostic("Successfully initiated client tunnel.");
			assert(!cli_fail, "Client expected to fail TLS connection.");
		} catch (Exception e) {
			if (cli_fail) logDiagnostic("Client tunnel failed as expected: %s", e.msg);
			else logError("Client tunnel failed: %s", e.toString().sanitize);
			assert(cli_fail, "Client not expected to fail TLS connection.");
			return;
		}
		if (srv_fail) return;
		cconn.write("foo\r\n");
		assert(cconn.readLine() == "bar");
		cconn.finalize();
	});

	t1.join();
	t2.join();
}

void test()
{
	//
	// Server certificates
	//

	// fail for untrusted server cert
	testConn(
		true, null, null, null, "localhost", TLSPeerValidationMode.trustedCert,
		true, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// succeed for untrusted server cert with disabled validation
	testConn(
		false, null, null, null, null, TLSPeerValidationMode.none,
		false, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// succeed for untrusted server cert if ignored
	testConn(
		false, null, null, null, "localhost", TLSPeerValidationMode.requireCert|TLSPeerValidationMode.checkPeer,
		false, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// fail for trusted server cert with no/wrong host name
	testConn(
		true, null, null, "ca.crt", "wronghost", TLSPeerValidationMode.trustedCert,
		false, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// succeed for trusted server cert with no/wrong host name if ignored
	testConn(
		false, null, null, "ca.crt", "wronghost", TLSPeerValidationMode.trustedCert & ~TLSPeerValidationMode.checkPeer,
		false, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// succeed for trusted server cert
	testConn(
		false, null, null, "ca.crt", "localhost", TLSPeerValidationMode.trustedCert,
		false, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// succeed with no certificates
	/*testConn(
		false, null, null, null, null,
		false, null, null, null, null
	);*/

	//
	// Client certificates
	//

	// fail for untrusted server cert
	testConn(
		true, "client.crt", "client.key", null, null, TLSPeerValidationMode.none,
		true, "server.crt", "server.key", null, null, TLSPeerValidationMode.trustedCert
	);

	// succeed for untrusted server cert with disabled validation
	testConn(
		false, "client.crt", "client.key", null, null, TLSPeerValidationMode.none,
		false, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// succeed for untrusted server cert if ignored
	testConn(
		false, "client.crt", "client.key", null, null, TLSPeerValidationMode.none,
		false, "server.crt", "server.key", null, null, TLSPeerValidationMode.requireCert
	);

	// succeed for trusted server cert
	testConn(
		false, "client.crt", "client.key", null, null, TLSPeerValidationMode.none,
		false, "server.crt", "server.key", "ca.crt", null, TLSPeerValidationMode.trustedCert & ~TLSPeerValidationMode.checkPeer
	);

	exitEventLoop();
}

void main()
{
	import std.functional : toDelegate;
	runTask(toDelegate(&test));
	runEventLoop();
}
