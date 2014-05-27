/**
	SSL/TLS stream implementation

	SSLStream can be used to implement SSL/TLS communication on top of a TCP connection. The
	SSLContextKind of an SSLStream determines if the SSL tunnel is established actively (client) or
	passively (server).

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.ssl;

import vibe.core.log;
import vibe.core.net;
import vibe.core.stream;
import vibe.core.sync;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.string;

import core.stdc.string : strlen;
import core.sync.mutex;
import core.thread;

version (VibeNoSSL) {}
else version = OpenSSL;


/// A simple SSL client
unittest {
	import vibe.core.net;
	import vibe.stream.ssl;

	void sendSSLMessage()
	{
		auto conn = connectTCP("127.0.0.1", 1234);
		auto sslctx = createSSLContext(SSLContextKind.client);
		auto stream = createSSLStream(conn, sslctx);
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
		auto sslctx = createSSLContext(SSLContextKind.server);
		sslctx.useCertificateChainFile("server.crt");
		sslctx.usePrivateKeyFile("server.key");
		listenTCP(1234, (conn){
			auto stream = createSSLStream(conn, sslctx);
			logInfo("Got message: %s", stream.readAllUTF8());
			stream.finalize();
		});
	}
}


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/

/** Creates a new context of the given kind.

	Params:
		kind = Specifies if the context is going to be used on the client
			or on the server end of the SSL tunnel
		ver = The SSL/TLS protocol used for negotiating the tunnel
*/
SSLContext createSSLContext(SSLContextKind kind, SSLVersion ver = SSLVersion.any)
{
	version (VibeNoSSL) assert(false, "No SSL support compiled in (VibeNoSSL)");
	else return new SSLContext(DEPRECATION_HACK.init, kind, ver);
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
SSLStream createSSLStream(Stream underlying, SSLContext ctx, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
{
	auto stream_state = ctx.kind == SSLContextKind.client ? SSLStreamState.connecting : SSLStreamState.accepting;
	return createSSLStream(underlying, ctx, stream_state, peer_name, peer_address);
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
SSLStream createSSLStream(Stream underlying, SSLContext ctx, SSLStreamState state, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
{
	version (VibeNoSSL) assert(false, "No SSL support compiled in (VibeNoSSL)");
	else return new SSLStream(DEPRECATION_HACK.init, underlying, ctx, state, peer_name, peer_address);
}

/**
	Constructs a new SSL stream using manual memory allocator.
*/
FreeListRef!SSLStream createSSLStreamFL(Stream underlying, SSLContext ctx, SSLStreamState state, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
{
	version (VibeNoSSL) assert(false, "No SSL support compiled in (VibeNoSSL)");
	else {
		import vibe.utils.memory;
		static assert(AllocSize!SSLStream > 0);
		return FreeListRef!SSLStream(DEPRECATION_HACK.init, underlying, ctx, state, peer_name, peer_address);
	}
}


/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

version (OpenSSL) {
	import deimos.openssl.bio;
	import deimos.openssl.err;
	import deimos.openssl.rand;
	import deimos.openssl.ssl;
	import deimos.openssl.x509v3;

	version (VibePragmaLib) {
		pragma(lib, "ssl");
		version (Windows) pragma(lib, "eay");
	}
}

/**
	Creates an SSL/TLS tunnel within an existing stream.

	Note: Be sure to call finalize before finalizing/closing the outer stream so that the SSL
		tunnel is properly closed first.
*/
final class SSLStream : Stream {
	private {
		Stream m_stream;
		SSLContext m_sslCtx;
		SSLStreamState m_state;
		SSLState m_ssl;
		version (OpenSSL) {
			BIO* m_bio;
		}
		ubyte m_peekBuffer[64];
		Exception[] m_exceptions;
	}

	/** Deprecated. Use createSSLStream instead.
	*/
	deprecated("Use createSSLStream instead of directly instantiating SSLStream.")
	this(Stream underlying, SSLContext ctx, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
	{
		auto stream_state = ctx.kind == SSLContextKind.client ? SSLStreamState.connecting : SSLStreamState.accepting;
		this(DEPRECATION_HACK.init, underlying, ctx, stream_state, peer_name, peer_address);
	}

	/** Deprecated. Use createSSLStream instead.
	*/
	deprecated("Use createSSLStream instead of directly instantiating SSLStream.")
	this(Stream underlying, SSLContext ctx, SSLStreamState state, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
	{
		this(DEPRECATION_HACK.init, underlying, ctx, state, peer_name, peer_address);
	}

	/// private
	/*private*/ this(DEPRECATION_HACK, Stream underlying, SSLContext ctx, SSLStreamState state, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
	{
		m_stream = underlying;
		m_state = state;
		m_sslCtx = ctx;
		m_ssl = ctx.createClientCtx();
		scope (failure) {
			version (OpenSSL) SSL_free(m_ssl);
			m_ssl = null;
		}

		version (OpenSSL) {
			m_bio = BIO_new(&s_bio_methods);
			enforce(m_bio !is null, "SSL failed: failed to create BIO structure.");
			m_bio.init_ = 1;
			m_bio.ptr = cast(void*)this;
			m_bio.shutdown = 0;

			SSL_set_bio(m_ssl, m_bio, m_bio);

			if (state != SSLStreamState.connected) {
				SSLContext.VerifyData vdata;
				vdata.verifyDepth = ctx.maxCertChainLength;
				vdata.validationMode = ctx.peerValidationMode;
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

				// ensure that the SSL tunnel gets terminated when an error happens during verification
				scope (failure) SSL_shutdown(m_ssl);

				if (auto peer = SSL_get_peer_certificate(m_ssl)) {
					scope(exit) X509_free(peer);
					auto result = SSL_get_verify_result(m_ssl);
					if (result == X509_V_OK && ctx.peerValidationMode >= SSLPeerValidationMode.validCert) {
						if (!verifyCertName(peer, GENERAL_NAME.GEN_DNS, vdata.peerName)) {
							version(Windows) import std.c.windows.winsock;
							else import core.sys.posix.netinet.in_;

							logWarn("peer name %s couldn't be verified, trying IP address.", vdata.peerName);
							char* addr;
							int addrlen;
							switch (vdata.peerAddress.family) {
								default: break;
								case AF_INET:
									addr = cast(char*)&vdata.peerAddress.sockAddrInet4.sin_addr;
									addrlen = vdata.peerAddress.sockAddrInet4.sin_addr.sizeof;
									break;
								case AF_INET6:
									addr = cast(char*)&vdata.peerAddress.sockAddrInet6.sin6_addr;
									addrlen = vdata.peerAddress.sockAddrInet6.sin6_addr.sizeof;
									break;
							}

							if (!verifyCertName(peer, GENERAL_NAME.GEN_IPADD, addr[0 .. addrlen])) {
								logWarn("Error validating peer address");
								result = X509_V_ERR_APPLICATION_VERIFICATION;
							}
						}
					}

					enforce(result == X509_V_OK, "Peer failed the certificate validation: "~to!string(result));
				} //else enforce(ctx.verifyMode < requireCert);
			}

			checkExceptions();
		} else assert(false, "No SSL support compiled in (VibeNoSSL).");
	}

	~this()
	{
		version (OpenSSL) if (m_ssl) SSL_free(m_ssl);
	}

	@property bool empty()
	{
		return leastSize() == 0 && m_stream.empty;
	}

	@property ulong leastSize()
	{
		version (OpenSSL) {
			auto ret = SSL_pending(m_ssl);
			return ret > 0 ? ret : m_stream.empty ? 0 : 1;
		} else assert(false);
	}

	@property bool dataAvailableForRead()
	{
		version (OpenSSL) return SSL_pending(m_ssl) > 0 || m_stream.dataAvailableForRead;
		else assert(false);
	}

	const(ubyte)[] peek()
	{
		version (OpenSSL) {
			auto ret = SSL_peek(m_ssl, m_peekBuffer.ptr, m_peekBuffer.length);
			checkExceptions();
			return ret > 0 ? m_peekBuffer[0 .. ret] : null;
		} else assert(false);
	}

	void read(ubyte[] dst)
	{
		version (OpenSSL) {
			while( dst.length > 0 ){
				int readlen = min(dst.length, int.max);
				auto ret = checkSSLRet("SSL_read", SSL_read(m_ssl, dst.ptr, readlen));
				//logTrace("SSL read %d/%d", ret, dst.length);
				dst = dst[ret .. $];
			}
		}
	}

	void write(in ubyte[] bytes_)
	{
		version (OpenSSL) {
			const(ubyte)[] bytes = bytes_;
			while( bytes.length > 0 ){
				int writelen = min(bytes.length, int.max);
				auto ret = checkSSLRet("SSL_write", SSL_write(m_ssl, bytes.ptr, writelen));
				//logTrace("SSL write %s", cast(string)bytes[0 .. ret]);
				bytes = bytes[ret .. $];
			}
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

		version (OpenSSL) {
			SSL_shutdown(m_ssl);
			SSL_free(m_ssl);
		}
		m_ssl = null;

		checkExceptions();
	}

	void write(InputStream stream, ulong nbytes = 0)
	{
		writeDefault(stream, nbytes);
	}

	version (OpenSSL) {
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

	private void checkExceptions()
	{
		if( m_exceptions.length > 0 ){
			foreach( e; m_exceptions )
				logDiagnostic("Exception occured on SSL source stream: %s", e.toString());
			throw m_exceptions[0];
		}
	}
}


enum SSLStreamState {
	connecting,
	accepting,
	connected
}


/**
	Encapsulates the configuration for an SSL tunnel.

	Note that when creating an SSLContext with SSLContextKind.client, the
	peerValidationMode will be set to SSLPeerValidationMode.trustedCert,
	but no trusted certificate authorities are added by default. Use
	useTrustedCertificateFile to add those.
*/
final class SSLContext {
	private {
		SSLContextKind m_kind;
		version (OpenSSL) ssl_ctx_st* m_ctx;
		SSLPeerValidationCallback m_peerValidationCallback;
		SSLPeerValidationMode m_validationMode;
		int m_verifyDepth;
	}

	/** Deprecated. Use createSSLContext instead.
	*/
	deprecated("Use createSSLContext instead of directly instantiating SSLContext.")
	this(SSLContextKind kind, SSLVersion ver = SSLVersion.any)
	{
		this(DEPRECATION_HACK.init, kind, ver);
	}

	private this(DEPRECATION_HACK, SSLContextKind kind, SSLVersion ver = SSLVersion.any)
	{
		m_kind = kind;

		version (OpenSSL) {
			const(SSL_METHOD)* method;
			c_long options = SSL_OP_NO_SSLv2|SSL_OP_NO_COMPRESSION|
				SSL_OP_SINGLE_DH_USE|SSL_OP_SINGLE_ECDH_USE;

			final switch (kind) {
				case SSLContextKind.client:
					final switch (ver) {
						case SSLVersion.any: method = SSLv23_client_method(); break;
						case SSLVersion.ssl3: method = SSLv3_client_method(); break;
						case SSLVersion.tls1: method = TLSv1_client_method(); break;
						case SSLVersion.dtls1: method = DTLSv1_client_method(); break;
					}
					break;
				case SSLContextKind.server:
					final switch (ver) {
						case SSLVersion.any: method = SSLv23_server_method(); break;
						case SSLVersion.ssl3: method = SSLv3_server_method(); break;
						case SSLVersion.tls1: method = TLSv1_server_method(); break;
						case SSLVersion.dtls1: method = DTLSv1_server_method(); break;
					}
					options |= SSL_OP_CIPHER_SERVER_PREFERENCE;
					break;
			}

			m_ctx = SSL_CTX_new(method);
			SSL_CTX_set_options!()(m_ctx, options);
			if (kind == SSLContextKind.server) {
				setDHParams();
				setECDHCurve();
			}

			setCipherList();
		} else enforce(false, "No SSL support compiled in!");

		maxCertChainLength = 9;
		if (kind == SSLContextKind.client) peerValidationMode = SSLPeerValidationMode.trustedCert;
		else peerValidationMode = SSLPeerValidationMode.none;

		// while it would be nice to use the system's certificate store, this
		// seems to be difficult to get right across all systems. The most
		// popular alternative is to use Mozilla's certificate store and
		// distribute it along with the library (e.g. in source code form.

		/*version (Posix) {
			enforce(SSL_CTX_load_verify_locations(m_ctx, null, "/etc/ssl/certs"),
				"Failed to load system certificate store.");
		}

		version (Windows) {
			auto store = CertOpenSystemStore(null, "ROOT");
			enforce(store !is null, "Failed to load system certificate store.");
			scope (exit) CertCloseStore(store, 0);

			PCCERT_CONTEXT ctx;
			while((ctx = CertEnumCertificatesInStore(store, ctx)) !is null) {
				X509* x509cert; 
				auto buffer = ctx.pbCertEncoded; 
				auto len = ctx.cbCertEncoded; 
				if (ctx.dwCertEncodingType & X509_ASN_ENCODING) { 
					x509cert = d2i_X509(null, &buffer, len);
					X509_STORE_add_cert(SSL_CTX_get_cert_store(m_ctx), x509cert); 
				} 
			}
		}*/
	}

	/** Deprecated. Use createSSLContext instead.
	*/
	deprecated("Use createSSLContext instead of directly instantiating SSLContext.")
	this(string cert_file, string key_file, SSLVersion ver = SSLVersion.any)
	{
		this(SSLContextKind.server, ver);
		version (OpenSSL) {
			scope(failure) SSL_CTX_free(m_ctx);
			auto succ = SSL_CTX_use_certificate_chain_file(m_ctx, toStringz(cert_file)) &&
					SSL_CTX_use_PrivateKey_file(m_ctx, toStringz(key_file), SSL_FILETYPE_PEM);
			enforce(succ, "Failed to load server cert/key.");
		}
	}

	/** Deprecated. Use createSSLContext instead.
	*/
	deprecated("Use createSSLContext instead of directly instantiating SSLContext.")
	this(SSLVersion ver = SSLVersion.any)
	{
		this(SSLContextKind.client, ver);
	}

	~this()
	{
		version (OpenSSL) {
			SSL_CTX_free(m_ctx);
			m_ctx = null;
		}
	}


	/// The kind of SSL context (client/server)
	@property SSLContextKind kind() const { return m_kind; }


	/** Specifies the validation level of remote peers.

		The default mode for SSLContextKind.client is
		SSLPeerValidationMode.trustedCert and the default for
		SSLContextKind.server is SSLPeerValidationMode.none.
	*/
	@property void peerValidationMode(SSLPeerValidationMode mode)
	{
		m_validationMode = mode;

		version (OpenSSL) {
			int sslmode;
			final switch (mode) with (SSLPeerValidationMode) {
				case none:
					sslmode = SSL_VERIFY_NONE;
					break;
				case requireCert:
				case validCert:
				case trustedCert:
					sslmode = SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT |
						SSL_VERIFY_CLIENT_ONCE;
					break;
			}
			SSL_CTX_set_verify(m_ctx, sslmode, &verify_callback);
		}
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
		version (OpenSSL) SSL_CTX_set_verify_depth(m_ctx, val + 1);
	}


	/** An optional user callback for peer validation.

		This callback will be called for each peer and each certificate of
		its certificate chain to allow overriding the validation decision
		based on the selected peerValidationMode (e.g. to allow invalid
		certificates or to reject valid ones). This is mainly useful for
		presenting the user with a dialog in case of untrusted or mismatching
		certificates.
	*/
	@property void peerValidationCallback(SSLPeerValidationCallback callback) { m_peerValidationCallback = callback; }
	/// ditto
	@property inout(SSLPeerValidationCallback) peerValidationCallback() inout { return m_peerValidationCallback; }

	/** Set the list of cipher specifications to use for SSL/TLS tunnels.

		The list must be a colon separated list of cipher
		specifications as accepted by OpenSSL. Calling this function
		without argument will restore the default.

		See_also: $(LINK https://www.openssl.org/docs/apps/ciphers.html#CIPHER_LIST_FORMAT)
	*/
	void setCipherList(string list = null)
	{
		version (OpenSSL) {
			if (list is null)
				SSL_CTX_set_cipher_list(m_ctx,
					"ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:"
					"RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS");
			else
				SSL_CTX_set_cipher_list(m_ctx, toStringz(list));
		}
	}

	/** Set params to use for DH cipher.
	 *
	 * By default the 2048-bit prime from RFC 3526 is used.
	 *
	 * Params:
	 * pem_file = Path to a PEM file containing the DH parameters. Calling
	 *    this function without argument will restore the default.
	 */
	void setDHParams(string pem_file=null)
	{
		version (OpenSSL) {
			DH* dh;
			scope(exit) DH_free(dh);

			if (pem_file is null) {
				dh = enforce(DH_new(), "Unable to create DH structure.");
				dh.p = get_rfc3526_prime_2048(null);
				ubyte dh_generator = 2;
				dh.g = BN_bin2bn(&dh_generator, dh_generator.sizeof, null);
			} else {
				import core.stdc.stdio : fclose, fopen;

				auto f = enforce(fopen(toStringz(pem_file), "r"), "Failed to load dhparams file "~pem_file);
				scope(exit) fclose(f);
				dh = enforce(PEM_read_DHparams(f, null, null, null), "Failed to read dhparams file "~pem_file);
			}

			SSL_CTX_set_tmp_dh(m_ctx, dh);
		}
	}

	/** Set the elliptic curve to use for ECDH cipher.
	 *
	 * By default a curve is either chosen automatically or  prime256v1 is used.
	 *
	 * Params:
	 * curve = The short name of the elliptic curve to use. Calling this
	 *    function without argument will restore the default.
	 *
	 */
	void setECDHCurve(string curve=null)
	{
		version (OpenSSL) {
			static if (OPENSSL_VERSION_NUMBER >= 0x10200000) {
				// use automatic ecdh curve selection by default
				if (curve is null) {
					SSL_CTX_set_ecdh_auto(m_ctx, true);
					return;
				}
				// but disable it when an explicit curve is given
				SSL_CTX_set_ecdh_auto(m_ctx, false);
			}

			int nid;
			if (curve is null)
				nid = NID_X9_62_prime256v1;
			else
				nid = enforce(OBJ_sn2nid(toStringz(curve)), "Unknown ECDH curve '"~curve~"'.");

			auto ecdh = enforce(EC_KEY_new_by_curve_name(nid), "Unable to create ECDH curve.");
			SSL_CTX_set_tmp_ecdh(m_ctx, ecdh);
			EC_KEY_free(ecdh);
		}
	}

	/// Sets a certificate file to use for authenticating to the remote peer
	void useCertificateChainFile(string path)
	{
		version (OpenSSL) enforce(SSL_CTX_use_certificate_chain_file(m_ctx, toStringz(path)), "Failed to load certificate file " ~ path);
	}

	/// Sets the private key to use for authenticating to the remote peer based
	/// on the configured certificate chain file.
	void usePrivateKeyFile(string path)
	{
		version (OpenSSL) enforce(SSL_CTX_use_PrivateKey_file(m_ctx, toStringz(path), SSL_FILETYPE_PEM), "Failed to load private key file " ~ path);
	}

	/** Sets the list of trusted certificates for verifying peer certificates.

		If this is a server context, this also entails that the given
		certificates are advertised to connecting clients during handshake.

		On Linux, the system's root certificate authority list is usually
		found at "/etc/ssl/certs/ca-certificates.crt",
		"/etc/pki/tls/certs/ca-bundle.crt", or "/etc/ssl/ca-bundle.pem".
	*/
	void useTrustedCertificateFile(string path)
	{
		version (OpenSSL) {
			immutable cPath = toStringz(path);
			enforce(SSL_CTX_load_verify_locations(m_ctx, cPath, null),
				"Failed to load trusted certificate file " ~ path);

			if (m_kind == SSLContextKind.server) {
				auto certNames = enforce(SSL_load_client_CA_file(cPath),
					"Failed to load client CA name list from file " ~ path);
				SSL_CTX_set_client_CA_list(m_ctx, certNames);
			}
		}
	}

	private SSLState createClientCtx()
	{
		version(OpenSSL) return SSL_new(m_ctx);
		else assert(false);
	}

	private static struct VerifyData {
		int verifyDepth;
		SSLPeerValidationMode validationMode;
		SSLPeerValidationCallback callback;
		string peerName;
		NetworkAddress peerAddress;
	}

	version (OpenSSL) {
		private static extern(C) nothrow
		int verify_callback(int valid, X509_STORE_CTX* ctx)
		{
			X509* err_cert = X509_STORE_CTX_get_current_cert(ctx);
			int err = X509_STORE_CTX_get_error(ctx);
			int depth = X509_STORE_CTX_get_error_depth(ctx);

			SSL* ssl = cast(SSL*)X509_STORE_CTX_get_ex_data(ctx, SSL_get_ex_data_X509_STORE_CTX_idx());
			VerifyData* vdata = cast(VerifyData*)SSL_get_ex_data(ssl, gs_verifyDataIndex);

			char[256] buf;
			X509_NAME_oneline(X509_get_subject_name(err_cert), buf.ptr, 256);

			try {
				logDebug("validate callback for %s", buf.ptr.to!string);

				if (depth > vdata.verifyDepth) {
					logDiagnostic("SSL cert chain too long: %s vs. %s", depth, vdata.verifyDepth);
				    valid = false;
				    err = X509_V_ERR_CERT_CHAIN_TOO_LONG;
				}

				if (err != X509_V_OK)
					logDebug("SSL cert error: %s", X509_verify_cert_error_string(err).to!string);

				if (!valid && (err == X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT)) {
					X509_NAME_oneline(X509_get_issuer_name(ctx.current_cert), buf.ptr, 256);
					logDebug("SSL unknown issuer cert: %s", buf.ptr.to!string);
					if (vdata.validationMode < SSLPeerValidationMode.trustedCert) {
						valid = true;
						err = X509_V_OK;
					}
				}

				if (vdata.validationMode < SSLPeerValidationMode.validCert) {
					valid = true;
					err = X509_V_OK;
				}

				if (vdata.callback) {
					SSLPeerValidationData pvdata;
					// ...
					if (!valid) {
						if (vdata.callback(pvdata)) {
							valid = true;
							err = X509_V_OK;
						}
					} else {
						if (!vdata.callback(pvdata)) {
							valid = false;
							err = X509_V_ERR_APPLICATION_VERIFICATION;
						}
					}
				}
			} catch (Exception e) {
				logWarn("SSL verification failed due to exception: %s", e.msg);
				err = X509_V_ERR_APPLICATION_VERIFICATION;
				valid = false;
			}

			X509_STORE_CTX_set_error(ctx, err);

			return valid;
		}
	}
}

version (OpenSSL) alias SSLState = ssl_st*;
else alias SSLState = void*;

enum SSLContextKind {
	client,
	server
}

enum SSLVersion {
	any, /// Accept SSLv3 or TLSv1.0 and greater
	ssl3, /// Accept only SSLv3
	tls1, /// Accept only TLSv1.0
	dtls1, /// Use DTLSv1.0

	ssl23 = any /// Deprecated compatibility alias
}


/** Specifies how rigorously SSL peer certificates are validated.

	Usually trustedCert
*/
enum SSLPeerValidationMode {
	/** Accept any peer regardless if and which certificate is presented.

		This mode is generally discouraged and should only be used with
		a custom validation callback set to do the verification.
	*/
	none,

	/** Require the peer to persent a certificate without further validation.

		Note that this mode does not verify the certificate at all. This mode
		can be useful if a custom validation callback is used to validate
		certificates.
	*/
	requireCert,

	/** Require a valid certificate matching the peer name.

		In this mode, the certificate is validated for general validity and
		possible expiration and the peer name is checked to see if the
		certificate actually applies.

		However, the certificate chain is not matched against the system's
		pool of trusted certificate authorities, so a custom validation
		callback is still needed to get a secure validation process.
	*/
	validCert,

	/** Require a valid and trusted certificate (strongly recommended).

		Checks the certificate and peer name for validity and requires that
		the certificate chain originates from a trusted CA (based on the
		systen's pool of certificate authorities).
	*/
    trustedCert,
}

struct SSLPeerValidationData {
	char[] certName;
	string errorString;
	// certificate chain
	// public key
	// public key fingerprint
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
	version (OpenSSL) {
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
}

version (OpenSSL) {
	private bool verifyCertName(X509* cert, int field, in char[] value, bool allow_wildcards = true)
	{
		bool delegate(in char[]) str_match;

		bool check_value(ASN1_STRING* str, int type) {
			if (!str.data || !str.length) return false;

			if (type > 0) {
				if (type != str.type) return 0;
				auto strstr = cast(string)str.data[0 .. str.length];
				return type == V_ASN1_IA5STRING ? str_match(strstr) : strstr == value;
			}

			char* utfstr;
			auto utflen = ASN1_STRING_to_UTF8(&utfstr, str);
			enforce (utflen >= 0, "Error converting ASN1 string to UTF-8.");
			scope (exit) OPENSSL_free(utfstr);
			return str_match(utfstr[0 .. utflen]); 
		}

		int cnid;
		int alt_type;
		final switch (field) {
			case GENERAL_NAME.GEN_DNS:
				cnid = NID_commonName;
				alt_type = V_ASN1_IA5STRING;
				str_match = allow_wildcards ? s => matchWildcard(value, s) : s => s.icmp(value) == 0;
				break;
			case GENERAL_NAME.GEN_IPADD:
				cnid = 0;
				alt_type = V_ASN1_OCTET_STRING;
				str_match = s => s == value;
				break;
		}

		if (auto gens = cast(STACK_OF!GENERAL_NAME*)X509_get_ext_d2i(cert, NID_subject_alt_name, null, null)) {
			scope(exit) GENERAL_NAMES_free(gens);

			foreach (i; 0 .. sk_GENERAL_NAME_num(gens)) {
				auto gen = sk_GENERAL_NAME_value(gens, i);
				if (gen.type != field) continue;
				ASN1_STRING *cstr = field == GENERAL_NAME.GEN_DNS ? gen.d.dNSName : gen.d.iPAddress;
				if (check_value(cstr, alt_type)) return true;
			}
			if (!cnid) return false;
		}

		X509_NAME* name = X509_get_subject_name(cert);
		int i;
		while ((i = X509_NAME_get_index_by_NID(name, cnid, i)) >= 0) {
			X509_NAME_ENTRY* ne = X509_NAME_get_entry(name, i);
			ASN1_STRING* str = X509_NAME_ENTRY_get_data(ne);
			if (check_value(str, -1)) return true;
		}

		return false;
	}
}

private bool matchWildcard(const(char)[] str, const(char)[] pattern)
{
	auto strparts = str.split(".");
	auto patternparts = pattern.split(".");
	if (strparts.length != patternparts.length) return false;

	bool isValidChar(dchar ch) {
		if (ch >= '0' && ch <= '9') return true;
		if (ch >= 'a' && ch <= 'z') return true;
		if (ch >= 'A' && ch <= 'Z') return true;
		if (ch == '-' || ch == '.') return true;
		return false;
	}

	if (!pattern.all!(c => isValidChar(c) || c == '*') || !str.all!(c => isValidChar(c)))
		return false;

	foreach (i; 0 .. strparts.length) {
		import std.regex;
		auto p = patternparts[i];
		auto s = strparts[i];
		if (!p.length || !s.length) return false;
		auto rex = "^" ~ std.array.replace(p, "*", "[^.]*") ~ "$";
		if (!match(s, rex)) return false;
	}
	return true;
}

unittest {
	assert(matchWildcard("www.example.org", "*.example.org"));
	assert(matchWildcard("www.example.org", "*w.example.org"));
	assert(matchWildcard("www.example.org", "w*w.example.org"));
	assert(matchWildcard("www.example.org", "*w*.example.org"));
	assert(matchWildcard("test.abc.example.org", "test.*.example.org"));
	assert(!matchWildcard("test.abc.example.org", "abc.example.org"));
	assert(!matchWildcard("test.abc.example.org", ".abc.example.org"));
	assert(!matchWildcard("abc.example.org", "a.example.org"));
	assert(!matchWildcard("abc.example.org", "bc.example.org"));
	assert(!matchWildcard("abcdexample.org", "abc.example.org"));
}


version (OpenSSL) private nothrow extern(C)
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

version (OpenSSL) {
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
}

private struct DEPRECATION_HACK {}
