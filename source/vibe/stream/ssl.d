/**
	SSL/TLS stream implementation

	SSLStream can be used to implement SSL/TLS communication on top of a TCP connection. The
	SSLContextKind of an SSLStream determines if the SSL tunnel is established actively (client) or
	passively (server).

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.ssl;

import vibe.core.log;
import vibe.core.net;
import vibe.core.stream;
import vibe.core.sync;

import deimos.openssl.bio;
import deimos.openssl.err;
import deimos.openssl.rand;
import deimos.openssl.ssl;

import std.algorithm;
import std.conv;
import std.exception;
import std.string;

import core.stdc.string : strlen;
import core.sync.mutex;
import core.thread;

version(VibePragmaLib) pragma(lib, "ssl");
version(VibePragmaLib) version (Windows) pragma(lib, "eay");

version = SSL;

/// A simple SSL client
unittest {
	import vibe.core.net;
	import vibe.stream.ssl;

	void sendSSLMessage()
	{
		auto conn = connectTCP("127.0.0.1", 1234);
		auto sslctx = new SSLContext(SSLContextKind.client);
		auto stream = new SSLStream(conn, sslctx);
		stream.write("Hello, World!");
		stream.finalize();
		conn.close();
	}
}

/// Corresponding server
unittest {
	import vibe.core.log;
	import vibe.core.net;
	import vibe.stream.operations;
	import vibe.stream.ssl;

	void listenForSSL()
	{
		auto sslctx = new SSLContext(SSLContextKind.server);
		sslctx.useCertificateChainFile("server.crt");
		sslctx.usePrivateKeyFile("server.key");
		listenTCP(1234, (conn){
			auto stream = new SSLStream(conn, sslctx);
			logInfo("Got message: %s", stream.readAllUTF8());
			stream.finalize();
		});
	}
}


/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

/**
	Creates an SSL/TLS tunnel within an existing stream.

	Note: Be sure to call finalize before finalizing/closing the outer stream so that the SSL
		tunnel is properly closed first.
*/
class SSLStream : Stream {
	private {
		Stream m_stream;
		SSLContext m_sslCtx;
		SSLStreamState m_state;
		BIO* m_bio;
		ssl_st* m_ssl;
		ubyte m_peekBuffer[64];
		Exception[] m_exceptions;
	}

	/** Constructs a new SSL tunnel and infers the stream state from the SSLContextKind.

		Depending on the SSLContextKind of ctx, the tunnel will try to establish an SSL
		tunnel by either passively accepting or by actively connecting.

		Params:
			underlying = The base stream which is used for the SSL tunnel
			ctx = SSL context used for initiating the tunnel
			peer_name = DNS name of the remote peer, used for certificate validation
			peer_address = IP address of the remote peer, used for certificate validation
	*/
	this(Stream underlying, SSLContext ctx, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
	{
		auto stream_state = ctx.kind == SSLContextKind.client ? SSLStreamState.connecting : SSLStreamState.accepting;
		this(underlying, ctx, stream_state, peer_name, peer_address);
	}

	/** Constructs a new SSL tunnel, allowing to override the stream state.

		This constructor allows to specify a custom tunnel state, which can
		be useful when a tunnel has already been established by other means.

		Params:
			underlying = The base stream which is used for the SSL tunnel
			ctx = SSL context used for initiating the tunnel
			state = The manually specified tunnel state
			peer_name = DNS name of the remote peer, used for certificate validation
			peer_address = IP address of the remote peer, used for certificate validation
	*/
	this(Stream underlying, SSLContext ctx, SSLStreamState state, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
	{
		m_stream = underlying;
		m_state = state;
		m_sslCtx = ctx;
		m_ssl = ctx.createClientCtx();
		scope (failure) {
			SSL_free(m_ssl);
			m_ssl = null;
		}

		m_bio = BIO_new(&s_bio_methods);
		enforce(m_bio !is null, "SSL failed: failed to create BIO structure.");
		m_bio.init_ = 1;
		m_bio.ptr = cast(void*)this;
		m_bio.shutdown = 0;

		SSL_set_bio(m_ssl, m_bio, m_bio);

		if (state != SSLStreamState.connected) {
			SSLContext.VerifyData vdata;
			vdata.verifyDepth = ctx.maxCertChainLength;
			vdata.callback = ctx.peerValidationCallback;
			vdata.peerName = peer_name;
			vdata.peerAddress = peer_address;
			SSL_set_ex_data(m_ssl, gs_verifyDataIndex, &vdata);
			scope (exit) SSL_set_ex_data(m_ssl, gs_verifyDataIndex, null);

			final switch (state) {
				case SSLStreamState.accepting:
					//SSL_set_accept_state(m_ssl);
					enforceSSL(SSL_accept(m_ssl), "Failed to accept SSL tunnel");
					break;
				case SSLStreamState.connecting:
					//SSL_set_connect_state(m_ssl);
					enforceSSL(SSL_connect(m_ssl), "Failed to connect SSL tunnel.");
					break;
				case SSLStreamState.connected:
					break;
			}

			if (auto peer = SSL_get_peer_certificate(m_ssl)) {
				scope(exit) X509_free(peer);
				auto result = SSL_get_verify_result(m_ssl);
				if (result != X509_V_OK) {
					SSL_shutdown(m_ssl);
					throw new Exception("Peer failed the certificate validation: "~to!string(result));
				}
			}
		}

		checkExceptions();
	}

	~this()
	{
		if (m_ssl) SSL_free(m_ssl);
	}

	@property bool empty()
	{
		return leastSize() == 0 && m_stream.empty;
	}

	@property ulong leastSize()
	{
		auto ret = SSL_pending(m_ssl);
		return ret > 0 ? ret : m_stream.empty ? 0 : 1;
	}

	@property bool dataAvailableForRead()
	{
		return SSL_pending(m_ssl) > 0 || m_stream.dataAvailableForRead;
	}

	const(ubyte)[] peek()
	{
		auto ret = SSL_peek(m_ssl, m_peekBuffer.ptr, m_peekBuffer.length);
		checkExceptions();
		return ret > 0 ? m_peekBuffer[0 .. ret] : null;
	}

	void read(ubyte[] dst)
	{
		while( dst.length > 0 ){
			int readlen = min(dst.length, int.max);
			auto ret = checkSSLRet("SSL_read", SSL_read(m_ssl, dst.ptr, readlen));
			//logTrace("SSL read %d/%d", ret, dst.length);
			dst = dst[ret .. $];
		}
	}

	void write(in ubyte[] bytes_)
	{
		const(ubyte)[] bytes = bytes_;
		while( bytes.length > 0 ){
			int writelen = min(bytes.length, int.max);
			auto ret = checkSSLRet("SSL_write", SSL_write(m_ssl, bytes.ptr, writelen));
			//logTrace("SSL write %s", cast(string)bytes[0 .. ret]);
			bytes = bytes[ret .. $];
		}
	}

	alias Stream.write write;

	void flush()
	{

	}

	void finalize()
	{
		if( !m_ssl ) return;
		logTrace("SSLStream finalize");

		SSL_shutdown(m_ssl);
		SSL_free(m_ssl);
		m_ssl = null;

		checkExceptions();
	}

	void write(InputStream stream, ulong nbytes = 0)
	{
		writeDefault(stream, nbytes);
	}

	private int checkSSLRet(string what, int ret)
	{
		checkExceptions();
		if (ret <= 0) {
			const(char)* file = null, data = null;
			int line;
			int flags;
			c_ulong eret;
			char[120] ebuf;
			while( (eret = ERR_get_error_line_data(&file, &line, &data, &flags)) != 0 ){
				ERR_error_string(eret, ebuf.ptr);
				logDiagnostic("%s error at at %s:%d: %s (%s)", what, to!string(file), line, to!string(ebuf.ptr), flags & ERR_TXT_STRING ? to!string(data) : "-");
			}
		}
		enforce(ret != 0, format("%s was unsuccessful with ret 0", what));
		enforce(ret >= 0, format("%s returned an error: %s", what, SSL_get_error(m_ssl, ret)));
		return ret;
	}

	private void checkExceptions()
	{
		if( m_exceptions.length > 0 ){
			foreach( e; m_exceptions )
				logDiagnostic("Exception occured on SSL source stream: %s", e.toString());
			throw m_exceptions[0];
		}
	}

	private int enforceSSL(int ret, string message)
	{
		if (ret <= 0) {
			auto err = SSL_get_error(m_ssl, ret);
			char[120] ebuf;
			ERR_error_string(err, ebuf.ptr);
			throw new Exception(format("%s: %s (%s)", message, ebuf.ptr.to!string(), err));
		}
		return ret;
	}
}

/// Deprecated compatibility alias
deprecated("Please use SSLStream instead.") alias SslStream = SSLStream;


enum SSLStreamState {
	connecting,
	accepting,
	connected
}

/// Deprecated compatibility alias
deprecated("Please use SSLStreamState instead.") alias SslStreamState = SSLStreamState;


/**
	Encapsulates the configuration for an SSL tunnel.
*/
class SSLContext {
	private {
		SSLContextKind m_kind;
		ssl_ctx_st* m_ctx;
		SSLPeerValidationCallback m_peerValidationCallback;
		SSLPeerValidationMode m_validationMode;
		int m_verifyDepth;
	}

	/** Creates a new context of the given kind.

		Params:
			kind = Specifies if the context is going to be used on the client
				or on the server end of the SSL tunnel
			ver = The SSL/TLS protocol used for negotiating the tunnel
	*/
	this(SSLContextKind kind, SSLVersion ver = SSLVersion.tls1)
	{
		m_kind = kind;

		version (SSL) {
			const(SSL_METHOD)* method;
			final switch (kind) {
				case SSLContextKind.client:
					final switch (ver) {
						case SSLVersion.ssl23: method = SSLv23_client_method(); break;
						case SSLVersion.ssl3: method = SSLv3_client_method(); break;
						case SSLVersion.tls1: method = TLSv1_client_method(); break;
						case SSLVersion.dtls1: method = DTLSv1_client_method(); break;
					}
					break;
				case SSLContextKind.server:
					final switch (ver) {
						case SSLVersion.ssl23: method = SSLv23_server_method(); break;
						case SSLVersion.ssl3: method = SSLv3_server_method(); break;
						case SSLVersion.tls1: method = TLSv1_server_method(); break;
						case SSLVersion.dtls1: method = DTLSv1_server_method(); break;
					}
					break;
			}

			m_ctx = SSL_CTX_new(method);

			SSL_CTX_set_options!()(m_ctx, SSL_OP_NO_SSLv2);
		} else enforce(false, "No SSL support compiled in!");

		maxCertChainLength = 9;
		peerValidationMode = SSLPeerValidationMode.trustedCert;


		SSL_CTX_load_verify_locations(m_ctx, null, "/etc/ssl/certs");
	}

	/// Convenience constructor to create a server context - will be deprecated soon
	this(string cert_file, string key_file, SSLVersion ver = SSLVersion.ssl23)
	{
		this(SSLContextKind.server, ver);
		version (SSL) {
			scope(failure) SSL_CTX_free(m_ctx);
			auto succ = SSL_CTX_use_certificate_chain_file(m_ctx, toStringz(cert_file)) &&
					SSL_CTX_use_PrivateKey_file(m_ctx, toStringz(key_file), SSL_FILETYPE_PEM);
			enforce(succ, "Failed to load server cert/key.");
		}
	}

	/// Convenience constructor to create a client context - will be deprecated soon
	this(SSLVersion ver = SSLVersion.ssl23)
	{
		this(SSLContextKind.client, ver);
	}

	~this()
	{
		SSL_CTX_free(m_ctx);
		m_ctx = null;
	}


	/// The kind of SSL context (client/server)
	@property SSLContextKind kind() const { return m_kind; }


	/** Specifies the validation level of remote peers.

		The default mode is SSLPeerValidationMode..
	*/
	@property void peerValidationMode(SSLPeerValidationMode mode)
	{
		m_validationMode = mode;

		int sslmode;
		if (mode >= SSLPeerValidationMode.peerName) {
			sslmode = SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT |
				SSL_VERIFY_CLIENT_ONCE;
		} else {
			sslmode = SSL_VERIFY_NONE;
		}
		SSL_CTX_set_verify(m_ctx, sslmode, &verify_callback);
	}
	/// ditto
	@property SSLPeerValidationMode peerValidationMode() const { return m_validationMode; }


	/** The maximum length of an accepted certificate chain.

		Any certificate chain longer than this will result in the SSL/TLS
		negitiation failing.

		The default value is 9.
	*/
	@property int maxCertChainLength() { return m_verifyDepth; }
	/// ditto
	@property void maxCertChainLength(int val)
	{
		m_verifyDepth = val;
		// + 1 to let the validation callback handle the error
		SSL_CTX_set_verify_depth(m_ctx, val + 1);
	}


	/** An optional user callback for peer validation.

		This callback will be called for each peer to allow overriding the
		validation decision (allow untrusted certificates or reject trusted
		ones). This is mainly useful for presenting the user with a dialog
		in case of untrusted or mismatching certificates.
	*/
	@property void peerValidationCallback(SSLPeerValidationCallback callback) { m_peerValidationCallback = callback; }
	/// ditto
	@property inout(SSLPeerValidationCallback) peerValidationCallback() inout { return m_peerValidationCallback; }

	/// Sets a certificate file to use for authenticating to the remote peer
	void useCertificateChainFile(string path)
	{
		enforce(SSL_CTX_use_certificate_chain_file(m_ctx, toStringz(path)), "Failed to load certificate file " ~ path);
	}

	/// Sets the private key to use for authenticating to the remote peer based
	/// on the configured certificate chain file.
	void usePrivateKeyFile(string path)
	{
		enforce(SSL_CTX_use_PrivateKey_file(m_ctx, toStringz(path), SSL_FILETYPE_PEM), "Failed to load private key file " ~ path);
	}

	/// Sets the list of certificates to considers trusted when verifying the
	/// certificate presented by the peer.
	///
	/// If this is a server context, this also entails that the given
	/// certificates are advertised to connecting clients during handshake.
	void useTrustedCertificateFile(string path)
	{
		immutable cPath = toStringz(path);
		enforce(SSL_CTX_load_verify_locations(m_ctx, cPath, null),
			"Failed to load trusted certificate file " ~ path);

		if (m_kind == SSLContextKind.server) {
			auto certNames = enforce(SSL_load_client_CA_file(cPath),
				"Failed to load client CA name list from file " ~ path);
			SSL_CTX_set_client_CA_list(m_ctx, certNames);
		}
	}

	/// Creates an SSL client context usable for a concrete SSLStream.
	ssl_st* createClientCtx()
	{
		version(SSL) return SSL_new(m_ctx);
		else assert(false);
	}

	private static struct VerifyData {
		int verifyDepth;
		SSLPeerValidationCallback callback;
		string peerName;
		NetworkAddress peerAddress;
	}

	private static extern(C) nothrow
	int verify_callback(int preverify_ok, X509_STORE_CTX* ctx)
	{
		version(Windows) import std.c.windows.winsock;
		else import core.sys.posix.netinet.in_;


		X509* err_cert = X509_STORE_CTX_get_current_cert(ctx);
		int err = X509_STORE_CTX_get_error(ctx);
		int depth = X509_STORE_CTX_get_error_depth(ctx);

		SSL* ssl = cast(SSL*)X509_STORE_CTX_get_ex_data(ctx, SSL_get_ex_data_X509_STORE_CTX_idx());
		VerifyData* vdata = cast(VerifyData*)SSL_get_ex_data(ssl, gs_verifyDataIndex);

		char[256] buf;
		X509_NAME_oneline(X509_get_subject_name(err_cert), buf.ptr, 256);

		try {
			logInfo("validate callback for %s", buf.ptr.to!string);

			if (depth > vdata.verifyDepth) {
				logWarn("SSL cert chain too long: %s vs. %s", depth, vdata.verifyDepth);
			    preverify_ok = 0;
			    err = X509_V_ERR_CERT_CHAIN_TOO_LONG;
			    X509_STORE_CTX_set_error(ctx, err);
			}

			if (err != X509_V_OK)
				logWarn("SSL cert error: %s", X509_verify_cert_error_string(err).to!string);

			if (!preverify_ok && (err == X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT)) {
				X509_NAME_oneline(X509_get_issuer_name(ctx.current_cert), buf.ptr, 256);
				logWarn("SSL unknown issuer cert: %s", buf.ptr.to!string);
			}

			if (vdata.callback) {
				SSLPeerValidationData pvdata;
				// ...
				preverify_ok = vdata.callback(pvdata);
			}
		} catch (Exception e) {
			logWarn("SSL verification failed due to exception: %s", e.msg);
			preverify_ok = false;
		}

		return preverify_ok;
	}
}

/// Deprecated compatibility alias
deprecated("Please use SSLContext instead.") alias SslContext = SSLContext;

enum SSLContextKind {
	client,
	server
}

enum SSLVersion {
	ssl23,
	ssl3,
	tls1,
	dtls1
}

enum SSLPeerValidationMode {
	none,        /// Accept any peer and any certificate
	peerName,    /// Validate that the presented certificate matches the peer name
    trustedCert, /// Validate the peer name and require that the certificate is trusted
}

struct SSLPeerValidationData {
	char[] certName;
	string errorString;
}

alias SSLPeerValidationCallback = bool delegate(scope SSLPeerValidationData data);

/**************************************************************************************************/
/* Private functions                                                                              */
/**************************************************************************************************/

private {
	__gshared Mutex[] g_cryptoMutexes;
	__gshared int gs_verifyDataIndex;
}

shared static this()
{
	logDebug("Initializing OpenSSL...");
	SSL_load_error_strings();
	SSL_library_init();

	g_cryptoMutexes.length = CRYPTO_num_locks();
	// TODO: investigate if a normal Mutex is enough - not sure if BIO is called in a locked state
	foreach (i; 0 .. g_cryptoMutexes.length)
		g_cryptoMutexes[i] = new TaskMutex;
	foreach (ref m; g_cryptoMutexes) {
		assert(m !is null);
	}

	CRYPTO_set_id_callback(&onCryptoGetThreadID);
	CRYPTO_set_locking_callback(&onCryptoLock);

	enforce(RAND_poll(), "Fatal: failed to initialize random number generator entropy (RAND_poll).");
	logDebug("... done.");

	gs_verifyDataIndex = SSL_get_ex_new_index(0, cast(void*)"VerifyData".ptr, null, null, null);
}

private nothrow extern(C)
{
	import core.stdc.config;

	c_ulong onCryptoGetThreadID()
	{
		try {
			return cast(c_ulong)(cast(size_t)cast(void*)Thread.getThis() * 0x35d2c57);
		} catch (Exception e) {
			logWarn("OpenSSL: failed to get current thread ID: %s", e.msg);
			return 0;
		}
	}

	void onCryptoLock(int mode, int n, const(char)* file, int line)
	{
		try {
			enforce(n >= 0 && n < g_cryptoMutexes.length, "Mutex index out of range.");
			auto mutex = g_cryptoMutexes[n];
			assert(mutex !is null);
			if (mode & CRYPTO_LOCK) mutex.lock();
			else mutex.unlock();
		} catch (Exception e) {
			logWarn("OpenSSL: failed to lock/unlock mutex: %s", e.msg);
		}
	}

	int onBioNew(BIO *b) nothrow
	{
		b.init_ = 0;
		b.num = -1;
		b.ptr = null;
		b.flags = 0;
		return 1;
	}

	int onBioFree(BIO *b)
	{
		if( !b ) return 0;
		if( b.shutdown ){
			//if( b.init && b.ptr ) b.ptr.stream.free();
			b.init_ = 0;
			b.flags = 0;
			b.ptr = null;
		}
		return 1;
	}

	int onBioRead(BIO *b, char *outb, int outlen)
	{
		auto stream = cast(SSLStream)b.ptr;
		
		try {
			outlen = min(outlen, stream.m_stream.leastSize);
			stream.m_stream.read(cast(ubyte[])outb[0 .. outlen]);
		} catch(Exception e){
			stream.m_exceptions ~= e;
			return -1;
		}
		return outlen;
	}

	int onBioWrite(BIO *b, const(char) *inb, int inlen)
	{
		auto stream = cast(SSLStream)b.ptr;
		try {
			stream.m_stream.write(inb[0 .. inlen]);
		} catch(Exception e){
			stream.m_exceptions ~= e;
			return -1;
		}
		return inlen;
	}

	c_long onBioCtrl(BIO *b, int cmd, c_long num, void *ptr)
	{
		auto stream = cast(SSLStream)b.ptr;
		c_long ret = 1;

		switch(cmd){
			case BIO_CTRL_GET_CLOSE: ret = b.shutdown; break;
			case BIO_CTRL_SET_CLOSE:
				logTrace("SSL set close %d", num);
				b.shutdown = cast(int)num;
				break;
			case BIO_CTRL_PENDING:
				try {
					auto sz = stream.m_stream.leastSize;
					return sz <= c_long.max ? cast(c_long)sz : c_long.max;
				} catch( Exception e ){
					stream.m_exceptions ~= e;
					return -1;
				}
			case BIO_CTRL_WPENDING: return 0;
			case BIO_CTRL_DUP:
			case BIO_CTRL_FLUSH:
				ret = 1;
				break;
			default:
				ret = 0;
				break;
		}
		return ret;
	}

	int onBioPuts(BIO *b, const(char) *s)
	{
		return onBioWrite(b, s, cast(int)strlen(s));
	}
}

private BIO_METHOD s_bio_methods = {
	57, "SslStream",
	&onBioWrite,
	&onBioRead,
	&onBioPuts,
	null, // &onBioGets
	&onBioCtrl,
	&onBioNew,
	&onBioFree,
	null, // &onBioCallbackCtrl
};
