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
	a = createProxyStream(p1, p2);
	b = createProxyStream(p2, p1);
}

enum Expected {
	success,
	fail,
	dontCare
}

void testConn(
	Expected cli_expect, string cli_cert, string cli_key, string cli_trust, string cli_peer, TLSPeerValidationMode cli_mode,
	Expected srv_expect, string srv_cert, string srv_key, string srv_trust, string srv_peer, TLSPeerValidationMode srv_mode)
{
	Stream ctunnel, stunnel;
	logInfo("Test client %s (%s, %s, %s, %s), server %s (%s, %s, %s, %s)",
		cli_expect, cli_cert, cli_key, cli_trust, cli_peer,
		srv_expect, srv_cert, srv_key, srv_trust, srv_peer);

	createPipePair(ctunnel, stunnel);
	auto t1 = runTask({
		try {
			auto sctx = createContext(TLSContextKind.server, srv_cert, srv_key, srv_trust, srv_mode);
			TLSStream sconn;
			try {
				sconn = createTLSStream(stunnel, sctx, TLSStreamState.accepting, srv_peer);
				logDiagnostic("Successfully initiated server tunnel.");
				assert(srv_expect != Expected.fail, "Server expected to fail TLS connection.");
			} catch (Exception e) {
				if (srv_expect == Expected.dontCare) logDiagnostic("Server tunnel failed (dont-care): %s", e.msg);
				else if (srv_expect == Expected.fail) logDiagnostic("Server tunnel failed as expected: %s", e.msg);
				else {
					logError("Server tunnel failed: %s", e.toString().sanitize);
					assert(false, "Server not expected to fail TLS connection.");
				}
				return;
			}
			if (cli_expect == Expected.fail) return;
			assert(sconn.readLine() == "foo");
			sconn.write("bar\r\n");
			sconn.finalize();
		} catch (Exception e) assert(false, e.msg);
	});
	auto t2 = runTask({
		try {
			auto cctx = createContext(TLSContextKind.client, cli_cert, cli_key, cli_trust, cli_mode);
			TLSStream cconn;
			try {
				cconn = createTLSStream(ctunnel, cctx, TLSStreamState.connecting, cli_peer);
				logDiagnostic("Successfully initiated client tunnel.");
				assert(cli_expect != Expected.fail, "Client expected to fail TLS connection.");
			} catch (Exception e) {
				if (cli_expect == Expected.dontCare) logDiagnostic("Client tunnel failed (dont-care): %s", e.msg);
				else if (cli_expect == Expected.fail) logDiagnostic("Client tunnel failed as expected: %s", e.msg);
				else {
					logError("Client tunnel failed: %s", e.toString().sanitize);
					assert(false, "Client not expected to fail TLS connection.");
				}
				return;
			}
			if (srv_expect == Expected.fail) return;
			cconn.write("foo\r\n");
			assert(cconn.readLine() == "bar");
			cconn.finalize();
		} catch (Exception e) assert(false, e.msg);
	});

	t1.join();
	t2.join();
}

void testValidation()
{
	//
	// Server certificates
	//

	// fail for untrusted server cert
	testConn(
		Expected.fail, null, null, null, "localhost", TLSPeerValidationMode.trustedCert,
		Expected.fail, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// succeed for untrusted server cert with disabled validation
	testConn(
		Expected.success, null, null, null, null, TLSPeerValidationMode.none,
		Expected.success, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// succeed for untrusted server cert if ignored
	testConn(
		Expected.success, null, null, null, "localhost", TLSPeerValidationMode.requireCert|TLSPeerValidationMode.checkPeer,
		Expected.success, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// fail for trusted server cert with no/wrong host name
	testConn(
		Expected.fail, null, null, "ca.crt", "wronghost", TLSPeerValidationMode.trustedCert,
		Expected.success, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// succeed for trusted server cert with no/wrong host name if ignored
	testConn(
		Expected.success, null, null, "ca.crt", "wronghost", TLSPeerValidationMode.trustedCert & ~TLSPeerValidationMode.checkPeer,
		Expected.success, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// succeed for trusted server cert
	testConn(
		Expected.success, null, null, "ca.crt", "localhost", TLSPeerValidationMode.trustedCert,
		Expected.success, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
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
		Expected.dontCare, "client.crt", "client.key", null, null, TLSPeerValidationMode.none,
		Expected.fail, "server.crt", "server.key", null, null, TLSPeerValidationMode.trustedCert
	);

	// succeed for untrusted server cert with disabled validation
	testConn(
		Expected.success, "client.crt", "client.key", null, null, TLSPeerValidationMode.none,
		Expected.success, "server.crt", "server.key", null, null, TLSPeerValidationMode.none
	);

	// succeed for untrusted server cert if ignored
	testConn(
		Expected.success, "client.crt", "client.key", null, null, TLSPeerValidationMode.none,
		Expected.success, "server.crt", "server.key", null, null, TLSPeerValidationMode.requireCert
	);

	// succeed for trusted server cert
	testConn(
		Expected.success, "client.crt", "client.key", null, null, TLSPeerValidationMode.none,
		Expected.success, "server.crt", "server.key", "ca.crt", null, TLSPeerValidationMode.trustedCert & ~TLSPeerValidationMode.checkPeer
	);
}


void testConn(TLSVersion cli_version, TLSVersion srv_version, bool expect_success)
{
	Stream ctunnel, stunnel;
	logInfo("Test for %s client %s, server %s", expect_success ? "success" : "failure",
		cli_version, srv_version);

	createPipePair(ctunnel, stunnel);
	auto t1 = runTask({
		try {
			TLSContext sctx;
			try sctx = createTLSContext(TLSContextKind.server, srv_version);
			catch (Exception e) {
				assert(!expect_success, "Failed to create TLS context: " ~ e.msg);
				ctunnel.finalize();
				stunnel.finalize();
				return;
			}
			sctx.useCertificateChainFile("server.crt");
			sctx.usePrivateKeyFile("server.key");
			sctx.peerValidationMode = TLSPeerValidationMode.none;
			TLSStream sconn;
			try {
				sconn = createTLSStream(stunnel, sctx, TLSStreamState.accepting, null);
				logDiagnostic("Successfully initiated server tunnel.");
				assert(expect_success, "Server expected to fail TLS connection.");
			} catch (Exception e) {
				if (expect_success) {
					logError("Server tunnel failed: %s", e.toString().sanitize);
					assert(false, "Server not expected to fail TLS connection.");
				}
				logDiagnostic("Server tunnel failed as expected: %s", e.msg);
				return;
			}
			if (!expect_success) return;
			assert(sconn.readLine() == "foo");
			sconn.write("bar\r\n");
			sconn.finalize();
		} catch (Exception e) assert(false, e.msg);
	});
	auto t2 = runTask({
		try {
			TLSContext cctx;
			try cctx = createTLSContext(TLSContextKind.client, cli_version);
			catch (Exception e) {
				assert(!expect_success, "Failed to create TLS context: " ~ e.msg);
				ctunnel.finalize();
				stunnel.finalize();
				return;
			}
			cctx.peerValidationMode = TLSPeerValidationMode.none;
			TLSStream cconn;
			try {
				cconn = createTLSStream(ctunnel, cctx, TLSStreamState.connecting, null);
				logDiagnostic("Successfully initiated client tunnel.");
				assert(expect_success, "Client expected to fail TLS connection.");
			} catch (Exception e) {
				if (expect_success) {
					logError("Client tunnel failed: %s", e.toString().sanitize);
					assert(false, "Client not expected to fail TLS connection.");
				}
				logDiagnostic("Client tunnel failed as expected: %s", e.msg);
				ctunnel.finalize();
				stunnel.finalize();
				return;
			}
			if (!expect_success) return;
			cconn.write("foo\r\n");
			assert(cconn.readLine() == "bar");
			cconn.finalize();
		} catch (Exception e) assert(false, e.msg);
	});

	t1.join();
	t2.join();
}

void testVersion()
{
	// NOTE: SSLv3 is not supported anymore by current OpenSSL versions
	// NOTE: Ubuntu 20.04 has removed support for TLSv1/TLSv1.1 from OpenSSL
	version (linux) enum support_old_tls = false;
	else enum support_old_tls = true;

	testConn(TLSVersion.ssl3, TLSVersion.any, false);
	testConn(TLSVersion.ssl3, TLSVersion.ssl3, false);
	testConn(TLSVersion.ssl3, TLSVersion.tls1, false);
	testConn(TLSVersion.ssl3, TLSVersion.tls1_1, false);
	testConn(TLSVersion.ssl3, TLSVersion.tls1_2, false);

	if (support_old_tls) testConn(TLSVersion.tls1, TLSVersion.any, true);
	testConn(TLSVersion.tls1, TLSVersion.ssl3, false);
	if (support_old_tls) testConn(TLSVersion.tls1, TLSVersion.tls1, true);
	testConn(TLSVersion.tls1, TLSVersion.tls1_1, false);
	testConn(TLSVersion.tls1, TLSVersion.tls1_2, false);

	if (support_old_tls) testConn(TLSVersion.tls1_1, TLSVersion.any, true);
	testConn(TLSVersion.tls1_1, TLSVersion.ssl3, false);
	testConn(TLSVersion.tls1_1, TLSVersion.tls1, false);
	if (support_old_tls) testConn(TLSVersion.tls1_1, TLSVersion.tls1_1, true);
	testConn(TLSVersion.tls1_1, TLSVersion.tls1_2, false);

	testConn(TLSVersion.tls1_2, TLSVersion.any, true);
	testConn(TLSVersion.tls1_2, TLSVersion.ssl3, false);
	testConn(TLSVersion.tls1_2, TLSVersion.tls1, false);
	testConn(TLSVersion.tls1_2, TLSVersion.tls1_1, false);
	testConn(TLSVersion.tls1_2, TLSVersion.tls1_2, true);

	testConn(TLSVersion.any, TLSVersion.any, true);
	testConn(TLSVersion.any, TLSVersion.ssl3, false);
	if (support_old_tls) testConn(TLSVersion.any, TLSVersion.tls1, true);
	if (support_old_tls) testConn(TLSVersion.any, TLSVersion.tls1_1, true);
	testConn(TLSVersion.any, TLSVersion.tls1_2, true);
}

void main()
{
	testValidation();
	testVersion();
}
