/**
	OpenSSL based SSL/TLS stream implementation

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.openssl;
version(Have_openssl):
import vibe.core.log;
import vibe.core.net;
import vibe.core.stream;
import vibe.core.sync;
import vibe.stream.tls;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.socket;
import std.string;

import core.stdc.string : strlen;
import core.sync.mutex;
import core.thread;

/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

import deimos.openssl.bio;
import deimos.openssl.err;
import deimos.openssl.rand;
import deimos.openssl.ssl;
import deimos.openssl.x509v3;

version (VibePragmaLib) {
	pragma(lib, "ssl");
	version (Windows) pragma(lib, "eay");
}

version (VibeUseOldOpenSSL) private enum haveECDH = false;
else private enum haveECDH = OPENSSL_VERSION_NUMBER >= 0x10001000;
version(VibeForceALPN) enum alpn_forced = true;
else enum alpn_forced = false;
enum haveALPN = OPENSSL_VERSION_NUMBER >= 0x10200000 || alpn_forced;


/**
	Creates an SSL/TLS tunnel within an existing stream.

	Note: Be sure to call finalize before finalizing/closing the outer stream so that the SSL
		tunnel is properly closed first.
*/
final class OpenSSLStream : TLSStream {
	private {
		Stream m_stream;
		TLSContext m_tlsCtx;
		TLSStreamState m_state;
		SSLState m_tls;
		BIO* m_bio;
		ubyte[64] m_peekBuffer;
		Exception[] m_exceptions;
		TLSCertificateInformation m_peerCertificate;
	}

	this(Stream underlying, OpenSSLContext ctx, TLSStreamState state, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init, string[] alpn = null)
	{
		m_stream = underlying;
		m_state = state;
		m_tlsCtx = ctx;
		m_tls = ctx.createClientCtx();
		scope (failure) {
			SSL_free(m_tls);
			m_tls = null;
		}

		m_bio = BIO_new(&s_bio_methods);
		enforce(m_bio !is null, "SSL failed: failed to create BIO structure.");
		m_bio.init_ = 1;
		m_bio.ptr = cast(void*)this;
		m_bio.shutdown = 0;

		SSL_set_bio(m_tls, m_bio, m_bio);

		if (state != TLSStreamState.connected) {
			OpenSSLContext.VerifyData vdata;
			vdata.verifyDepth = ctx.maxCertChainLength;
			vdata.validationMode = ctx.peerValidationMode;
			vdata.callback = ctx.peerValidationCallback;
			vdata.peerName = peer_name;
			vdata.peerAddress = peer_address;
			SSL_set_ex_data(m_tls, gs_verifyDataIndex, &vdata);
			scope (exit) SSL_set_ex_data(m_tls, gs_verifyDataIndex, null);

			final switch (state) {
				case TLSStreamState.accepting:
					//SSL_set_accept_state(m_tls);
					checkSSLRet(SSL_accept(m_tls), "Accepting SSL tunnel");
					break;
				case TLSStreamState.connecting:
					// a client stream can override the default ALPN setting for this context
					if (alpn.length) setClientALPN(alpn);
					if (peer_name.length)
						SSL_ctrl(m_tls, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, cast(void*)peer_name.toStringz);
					//SSL_set_connect_state(m_tls);
					checkSSLRet(SSL_connect(m_tls), "Connecting TLS tunnel");
					break;
				case TLSStreamState.connected:
					break;
			}

			// ensure that the SSL tunnel gets terminated when an error happens during verification
			scope (failure) SSL_shutdown(m_tls);

			if (auto peer = SSL_get_peer_certificate(m_tls)) {
				scope(exit) X509_free(peer);

				readPeerCertInfo(peer);
				auto result = SSL_get_verify_result(m_tls);
				if (result == X509_V_OK && (ctx.peerValidationMode & TLSPeerValidationMode.checkPeer)) {
					if (!verifyCertName(peer, GENERAL_NAME.GEN_DNS, vdata.peerName)) {
						version(Windows) import std.c.windows.winsock;
						else import core.sys.posix.netinet.in_;

						logWarn("peer name '%s' couldn't be verified, trying IP address.", vdata.peerName);
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
	}

	/** Read certificate info into the clientInformation field */
	private void readPeerCertInfo(X509 *cert)
	{
		X509_NAME* name = X509_get_subject_name(cert);

		int c = X509_NAME_entry_count(name);
		foreach (i; 0 .. c) {
			X509_NAME_ENTRY *e = X509_NAME_get_entry(name, i);

			ASN1_OBJECT *obj = X509_NAME_ENTRY_get_object(e);
			ASN1_STRING *val = X509_NAME_ENTRY_get_data(e);

			auto longName = OBJ_nid2ln(OBJ_obj2nid(obj)).to!string;
			auto valStr = cast(string)val.data[0 .. val.length];

			m_peerCertificate.subjectName.addField(longName, valStr);
		}
	}

	~this()
	{
		if (m_tls) SSL_free(m_tls);
	}

	@property bool empty()
	{
		return leastSize() == 0 && m_stream.empty;
	}

	@property ulong leastSize()
	{
		auto ret = SSL_pending(m_tls);
		return ret > 0 ? ret : m_stream.empty ? 0 : 1;
	}

	@property bool dataAvailableForRead()
	{
		return SSL_pending(m_tls) > 0 || m_stream.dataAvailableForRead;
	}

	const(ubyte)[] peek()
	{
		auto ret = SSL_peek(m_tls, m_peekBuffer.ptr, m_peekBuffer.length);
		checkExceptions();
		return ret > 0 ? m_peekBuffer[0 .. ret] : null;
	}

	void read(ubyte[] dst)
	{
		while( dst.length > 0 ){
			int readlen = min(dst.length, int.max);
			auto ret = checkSSLRet(SSL_read(m_tls, dst.ptr, readlen), "Reading from TLS stream");
			//logTrace("SSL read %d/%d", ret, dst.length);
			dst = dst[ret .. $];
		}
	}

	void write(in ubyte[] bytes_)
	{
		const(ubyte)[] bytes = bytes_;
		while( bytes.length > 0 ){
			int writelen = min(bytes.length, int.max);
			auto ret = checkSSLRet(SSL_write(m_tls, bytes.ptr, writelen), "Writing to TLS stream");
			//logTrace("SSL write %s", cast(string)bytes[0 .. ret]);
			bytes = bytes[ret .. $];
		}
	}

	alias write = Stream.write;

	void flush()
	{
		m_stream.flush();
	}

	void finalize()
	{
		if( !m_tls ) return;
		logTrace("OpenSSLStream finalize");

		SSL_shutdown(m_tls);
		SSL_free(m_tls);

		m_tls = null;

		checkExceptions();
	}

	void write(InputStream stream, ulong nbytes = 0)
	{
		writeDefault(stream, nbytes);
	}

	private int checkSSLRet(int ret, string what)
	{
		checkExceptions();
		if (ret > 0) return ret;

		string desc;
		auto err = SSL_get_error(m_tls, ret);
		switch (err) {
			default: desc = format("Unknown error (%s)", err); break;
			case SSL_ERROR_NONE: desc = "No error"; break;
			case SSL_ERROR_ZERO_RETURN: desc = "SSL/TLS tunnel closed"; break;
			case SSL_ERROR_WANT_READ: desc = "Need to block for read"; break;
			case SSL_ERROR_WANT_WRITE: desc = "Need to block for write"; break;
			case SSL_ERROR_WANT_CONNECT: desc = "Need to block for connect"; break;
			case SSL_ERROR_WANT_ACCEPT: desc = "Need to block for accept"; break;
			case SSL_ERROR_WANT_X509_LOOKUP: desc = "Need to block for certificate lookup"; break;
			case SSL_ERROR_SYSCALL:
			case SSL_ERROR_SSL:
				return enforceSSL(ret, what);
		}

		const(char)* file = null, data = null;
		int line;
		int flags;
		c_ulong eret;
		char[120] ebuf;
		while( (eret = ERR_get_error_line_data(&file, &line, &data, &flags)) != 0 ){
			ERR_error_string(eret, ebuf.ptr);
			logDiagnostic("%s error at %s:%d: %s (%s)", what, to!string(file), line, to!string(ebuf.ptr), flags & ERR_TXT_STRING ? to!string(data) : "-");
		}

		enforce(ret != 0, format("%s was unsuccessful with ret 0", what));
		enforce(ret >= 0, format("%s returned an error: %s", what, desc));
		return ret;
	}

	private int enforceSSL(int ret, string message)
	{
		if (ret > 0) return ret;

		c_ulong eret;
		const(char)* file = null, data = null;
		int line;
		int flags;
		string estr;
		char[120] ebuf = 0;

		while ((eret = ERR_get_error_line_data(&file, &line, &data, &flags)) != 0) {
			ERR_error_string_n(eret, ebuf.ptr, ebuf.length);
			estr = ebuf.ptr.to!string;
			// throw the last error code as an exception
			if (!ERR_peek_error()) break;
			logDiagnostic("OpenSSL error at %s:%d: %s (%s)", file.to!string, line, estr, flags & ERR_TXT_STRING ? to!string(data) : "-");
		}

		throw new Exception(format("%s: %s (%s)", message, estr, eret));
	}

	private void checkExceptions()
	{
		if( m_exceptions.length > 0 ){
			foreach( e; m_exceptions )
				logDiagnostic("Exception occured on SSL source stream: %s", e.toString());
			throw m_exceptions[0];
		}
	}

	@property TLSCertificateInformation peerCertificate()
	{
		return m_peerCertificate;
	}

	@property string alpn()
	const {
		static if (!haveALPN) assert(false, "OpenSSL support not compiled with ALPN enabled. Use VibeForceALPN.");
		else {
			char[32] data;
			uint datalen;

			SSL_get0_alpn_selected(m_ssl, cast(const char*) data.ptr, &datalen);
			logDebug("alpn selected: ", data.to!string);
			if (datalen > 0)
				return data[0..datalen].idup;
			else return null;
		}
	}

	/// Invoked by client to offer alpn
	private void setClientALPN(string[] alpn_list)
	{
		logDebug("SetClientALPN: ", alpn_list);
		import vibe.utils.memory : allocArray, freeArray, manualAllocator;
		ubyte[] alpn;
		size_t len;
		foreach (string alpn_val; alpn_list)
			len += alpn_val.length + 1;
		alpn = allocArray!ubyte(manualAllocator(), len);

		size_t i;
		foreach (string alpn_val; alpn_list)
		{
			alpn[i++] = cast(ubyte)alpn_val.length;
			alpn[i .. i+alpn_val.length] = cast(ubyte[])alpn_val;
			i += alpn_val.length;
		}
		assert(i == len);

		static if (haveALPN)
			SSL_set_alpn_protos(m_ssl, cast(const char*) alpn.ptr, cast(uint) len);

		freeArray(manualAllocator(), alpn);
	}
}


/**
	Encapsulates the configuration for an SSL tunnel.

	Note that when creating an SSLContext with SSLContextKind.client, the
	peerValidationMode will be set to SSLPeerValidationMode.trustedCert,
	but no trusted certificate authorities are added by default. Use
	useTrustedCertificateFile to add those.
*/
final class OpenSSLContext : TLSContext {
	private {
		TLSContextKind m_kind;
		ssl_ctx_st* m_ctx;
		TLSPeerValidationCallback m_peerValidationCallback;
		TLSPeerValidationMode m_validationMode;
		int m_verifyDepth;
		TLSServerNameCallback m_sniCallback;
		TLSALPNCallback m_alpnCallback;
	}

	this(TLSContextKind kind, TLSVersion ver = TLSVersion.any)
	{
		m_kind = kind;

		const(SSL_METHOD)* method;
		c_long options = SSL_OP_NO_SSLv2|SSL_OP_NO_COMPRESSION|
			SSL_OP_SINGLE_DH_USE|SSL_OP_SINGLE_ECDH_USE;

		final switch (kind) {
			case TLSContextKind.client:
				final switch (ver) {
					case TLSVersion.any: method = SSLv23_client_method(); options |= SSL_OP_NO_SSLv3; break;
					case TLSVersion.ssl3: method = SSLv23_client_method(); options |= SSL_OP_NO_SSLv2|SSL_OP_NO_TLSv1_1|SSL_OP_NO_TLSv1|SSL_OP_NO_TLSv1_2; break;
					case TLSVersion.tls1: method = TLSv1_client_method(); break;
					//case TLSVersion.tls1_1: method = TLSv1_1_client_method(); break;
					//case TLSVersion.tls1_2: method = TLSv1_2_client_method(); break;
					case TLSVersion.tls1_1: method = SSLv23_client_method(); options |= SSL_OP_NO_SSLv3|SSL_OP_NO_TLSv1|SSL_OP_NO_TLSv1_2; break;
					case TLSVersion.tls1_2: method = SSLv23_client_method(); options |= SSL_OP_NO_SSLv3|SSL_OP_NO_TLSv1|SSL_OP_NO_TLSv1_1; break;
					case TLSVersion.dtls1: method = DTLSv1_client_method(); break;
				}
				break;
			case TLSContextKind.server:
			case TLSContextKind.serverSNI:
				final switch (ver) {
					case TLSVersion.any: method = SSLv23_server_method(); options |= SSL_OP_NO_SSLv3; break;
					case TLSVersion.ssl3: method = SSLv23_server_method(); options |= SSL_OP_NO_SSLv2|SSL_OP_NO_TLSv1_1|SSL_OP_NO_TLSv1|SSL_OP_NO_TLSv1_2; break;
					case TLSVersion.tls1: method = TLSv1_server_method(); break;
					case TLSVersion.tls1_1: method = SSLv23_server_method(); options |= SSL_OP_NO_SSLv3|SSL_OP_NO_TLSv1|SSL_OP_NO_TLSv1_2; break;
					case TLSVersion.tls1_2: method = SSLv23_server_method(); options |= SSL_OP_NO_SSLv3|SSL_OP_NO_TLSv1|SSL_OP_NO_TLSv1_1; break;
					//case TLSVersion.tls1_1: method = TLSv1_1_server_method(); break;
					//case TLSVersion.tls1_2: method = TLSv1_2_server_method(); break;
					case TLSVersion.dtls1: method = DTLSv1_server_method(); break;
				}
				options |= SSL_OP_CIPHER_SERVER_PREFERENCE;
				break;
		}

		m_ctx = SSL_CTX_new(method);
		SSL_CTX_set_options!()(m_ctx, options);
		if (kind == TLSContextKind.server) {
			setDHParams();
			static if (haveECDH) setECDHCurve();
			guessSessionIDContext();
		}

		setCipherList();

		maxCertChainLength = 9;
		if (kind == TLSContextKind.client) peerValidationMode = TLSPeerValidationMode.trustedCert;
		else peerValidationMode = TLSPeerValidationMode.none;

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

	~this()
	{
		SSL_CTX_free(m_ctx);
		m_ctx = null;
	}


	/// The kind of SSL context (client/server)
	@property TLSContextKind kind() const { return m_kind; }

	/// Callback function invoked by server to choose alpn
	@property void alpnCallback(string delegate(string[]) alpn_chooser)
	{
		logDebug("Choosing ALPN callback");
		m_alpnCallback = alpn_chooser;
		static if (haveALPN) {
			logDebug("Call select cb");
			SSL_CTX_set_alpn_select_cb(m_ctx, &chooser, cast(void*)this);
		}
	}

	/// Get the current ALPN callback function
	@property string delegate(string[]) alpnCallback() const { return m_alpnCallback; }

	/// Invoked by client to offer alpn
	void setClientALPN(string[] alpn_list)
	{
		static if (!haveALPN) assert(false, "OpenSSL support not compiled with ALPN enabled. Use VibeForceALPN.");
		else {
			import vibe.utils.memory : allocArray, freeArray, manualAllocator;
			ubyte[] alpn;
			size_t len;
			foreach (string alpn_value; alpn_list)
				len += alpn_value.length + 1;
			alpn = allocArray!ubyte(manualAllocator(), len);

			size_t i;
			foreach (string alpn_value; alpn_list)
			{
				alpn[i++] = cast(ubyte)alpn_value.length;
				alpn[i .. i+alpn_value.length] = cast(ubyte[])alpn_value;
				i += alpn_value.length;
			}
			assert(i == len);

			SSL_CTX_set_alpn_protos(m_ctx, cast(const char*) alpn.ptr, cast(uint) len);

			freeArray(manualAllocator(), alpn);
		}
	}

	/** Specifies the validation level of remote peers.

		The default mode for TLSContextKind.client is
		TLSPeerValidationMode.trustedCert and the default for
		TLSContextKind.server is TLSPeerValidationMode.none.
	*/
	@property void peerValidationMode(TLSPeerValidationMode mode)
	{
		m_validationMode = mode;

		int sslmode;

		with (TLSPeerValidationMode) {
			if (mode == none) sslmode = SSL_VERIFY_NONE;
			else {
				sslmode |= SSL_VERIFY_PEER | SSL_VERIFY_CLIENT_ONCE;
				if (mode & requireCert) sslmode |= SSL_VERIFY_FAIL_IF_NO_PEER_CERT;
			}
		}

		SSL_CTX_set_verify(m_ctx, sslmode, &verify_callback);
	}
	/// ditto
	@property TLSPeerValidationMode peerValidationMode() const { return m_validationMode; }


	/** The maximum length of an accepted certificate chain.

		Any certificate chain longer than this will result in the SSL/TLS
		negitiation failing.

		The default value is 9.
	*/
	@property void maxCertChainLength(int val)
	{
		m_verifyDepth = val;
		// + 1 to let the validation callback handle the error
		SSL_CTX_set_verify_depth(m_ctx, val + 1);
	}

	/// ditto
	@property int maxCertChainLength() const { return m_verifyDepth; }

	/** An optional user callback for peer validation.

		This callback will be called for each peer and each certificate of
		its certificate chain to allow overriding the validation decision
		based on the selected peerValidationMode (e.g. to allow invalid
		certificates or to reject valid ones). This is mainly useful for
		presenting the user with a dialog in case of untrusted or mismatching
		certificates.
	*/
	@property void peerValidationCallback(TLSPeerValidationCallback callback) { m_peerValidationCallback = callback; }
	/// ditto
	@property inout(TLSPeerValidationCallback) peerValidationCallback() inout { return m_peerValidationCallback; }

	@property void sniCallback(TLSServerNameCallback callback)
	{
		m_sniCallback = callback;
		if (m_kind == TLSContextKind.serverSNI) {
			SSL_CTX_callback_ctrl(m_ctx, SSL_CTRL_SET_TLSEXT_SERVERNAME_CB, cast(OSSLCallback)&onContextForServerName);
			SSL_CTX_ctrl(m_ctx, SSL_CTRL_SET_TLSEXT_SERVERNAME_ARG, 0, cast(void*)this);
		}
	}
	@property inout(TLSServerNameCallback) sniCallback() inout { return m_sniCallback; }

	private extern(C) alias OSSLCallback = void function();
	private static extern(C) int onContextForServerName(SSL *s, int *ad, void *arg)
	{
		auto ctx = cast(OpenSSLContext)arg;
		auto servername = SSL_get_servername(s, TLSEXT_NAMETYPE_host_name);
		if (!servername) return SSL_TLSEXT_ERR_NOACK;
		auto newctx = cast(OpenSSLContext)ctx.m_sniCallback(servername.to!string);
		if (!newctx) return SSL_TLSEXT_ERR_NOACK;
		SSL_set_SSL_CTX(s, newctx.m_ctx);
		return SSL_TLSEXT_ERR_OK;
	}

	OpenSSLStream createStream(Stream underlying, TLSStreamState state, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
	{
		return new OpenSSLStream(underlying, this, state, peer_name, peer_address);
	}

	/** Set the list of cipher specifications to use for SSL/TLS tunnels.

		The list must be a colon separated list of cipher
		specifications as accepted by OpenSSL. Calling this function
		without argument will restore the default.

		See_also: $(LINK https://www.openssl.org/docs/apps/ciphers.html#CIPHER_LIST_FORMAT)
	*/
	void setCipherList(string list = null)
	{
		if (list is null)
			SSL_CTX_set_cipher_list(m_ctx,
				"ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:"
				~ "RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS");
		else
			SSL_CTX_set_cipher_list(m_ctx, toStringz(list));
	}

	/** Make up a context ID to assign to the SSL context.

		This is required when doing client cert authentication, otherwise many
		connections will go aborted as the client tries to revive a session
		that it used to have on another machine.

		The session ID context should be unique within a pool of servers.
		Currently, this is achieved by taking the hostname.
	*/
	private void guessSessionIDContext()
	{
		string contextID = Socket.hostName;
		SSL_CTX_set_session_id_context(m_ctx, cast(ubyte*)contextID.toStringz(), cast(uint)contextID.length);
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

	/** Set the elliptic curve to use for ECDH cipher.
	 *
	 * By default a curve is either chosen automatically or  prime256v1 is used.
	 *
	 * Params:
	 * curve = The short name of the elliptic curve to use. Calling this
	 *    function without argument will restore the default.
	 *
	 */
	void setECDHCurve(string curve = null)
	{
		static if (haveECDH) {
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
		} else assert(false, "ECDH curve selection not available for old versions of OpenSSL");
	}

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

	/** Sets the list of trusted certificates for verifying peer certificates.

		If this is a server context, this also entails that the given
		certificates are advertised to connecting clients during handshake.

		On Linux, the system's root certificate authority list is usually
		found at "/etc/ssl/certs/ca-certificates.crt",
		"/etc/pki/tls/certs/ca-bundle.crt", or "/etc/ssl/ca-bundle.pem".
	*/
	void useTrustedCertificateFile(string path)
	{
		immutable cPath = toStringz(path);
		enforce(SSL_CTX_load_verify_locations(m_ctx, cPath, null),
			"Failed to load trusted certificate file " ~ path);

		if (m_kind == TLSContextKind.server) {
			auto certNames = enforce(SSL_load_client_CA_file(cPath),
				"Failed to load client CA name list from file " ~ path);
			SSL_CTX_set_client_CA_list(m_ctx, certNames);
		}
	}

	private SSLState createClientCtx()
	{
		return SSL_new(m_ctx);
	}

	private static struct VerifyData {
		int verifyDepth;
		TLSPeerValidationMode validationMode;
		TLSPeerValidationCallback callback;
		string peerName;
		NetworkAddress peerAddress;
	}

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
				logDebug("SSL cert initial error: %s", X509_verify_cert_error_string(err).to!string);

			if (err == X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY) {
				logDebug("SSL certificate not accepted by remote.");
				return false;
			}

			if (!valid) {
				switch (err) {
					default: break;
					case X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT:
					case X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY:
					case X509_V_ERR_CERT_UNTRUSTED:
						X509_NAME_oneline(X509_get_issuer_name(ctx.current_cert), buf.ptr, 256);
						logDebug("SSL cert not trusted or unknown issuer: %s", buf.ptr.to!string);
						if (!(vdata.validationMode & TLSPeerValidationMode.checkTrust)) {
							valid = true;
							err = X509_V_OK;
						}
						break;
				}
			}

			if (!(vdata.validationMode & TLSPeerValidationMode.checkCert)) {
				valid = true;
				err = X509_V_OK;
			}

			if (vdata.callback) {
				TLSPeerValidationData pvdata;
				// ...
				if (!valid) {
					if (vdata.callback(pvdata)) {
						valid = true;
						err = X509_V_OK;
					}
				} else {
					if (!vdata.callback(pvdata)) {
						logDebug("SSL application verification failed");
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

		logDebug("SSL validation result: %s (%s)", valid, err);

		return valid;
	}
}

alias SSLState = ssl_st*;

/**************************************************************************************************/
/* Private functions                                                                              */
/**************************************************************************************************/

private {
	__gshared InterruptibleTaskMutex[] g_cryptoMutexes;
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
		g_cryptoMutexes[i] = new InterruptibleTaskMutex;
	foreach (ref m; g_cryptoMutexes) {
		assert(m !is null);
	}

	CRYPTO_set_id_callback(&onCryptoGetThreadID);
	CRYPTO_set_locking_callback(&onCryptoLock);

	enforce(RAND_poll(), "Fatal: failed to initialize random number generator entropy (RAND_poll).");
	logDebug("... done.");

	gs_verifyDataIndex = SSL_get_ex_new_index(0, cast(void*)"VerifyData".ptr, null, null, null);
}

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


private nothrow extern(C)
{
	import core.stdc.config;


	int chooser(SSL* ssl, const(char)** output, ubyte* outlen, const(char) *input, uint inlen, void* arg) {
		logDebug("Got chooser input: %s", input[0 .. inlen]);
		OpenSSLContext ctx = cast(OpenSSLContext) arg;
		import vibe.utils.array : AllocAppender, AppenderResetMode;
		size_t i;
		size_t len;
		Appender!(string[]) alpn_list;
		while (i < inlen)
		{
			len = cast(size_t) input[i];
			++i;
			ubyte[] proto = cast(ubyte[]) input[i .. i+len];
			i += len;
			alpn_list ~= cast(string)proto;
		}

		string alpn;

		try { alpn = ctx.m_alpnCallback(alpn_list.data); } catch { }
		if (alpn) {
			i = 0;
			while (i < inlen)
			{
				len = input[i];
				++i;
				ubyte[] proto = cast(ubyte[]) input[i .. i+len];
				i += len;
				if (cast(string) proto == alpn) {
					*output = cast(const(char)*)proto.ptr;
					*outlen = cast(ubyte) proto.length;
				}
			}
		}

		if (!output) {
			logError("None of the proposed ALPN were selected: %s / falling back on HTTP/1.1", input[0 .. inlen]);
			*output = cast(const(char)*)("http/1.1".ptr);
			*outlen = cast(ubyte)("http/1.1".length);
		}

		return 0;
	}

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
		auto stream = cast(OpenSSLStream)b.ptr;

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
		auto stream = cast(OpenSSLStream)b.ptr;
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
		auto stream = cast(OpenSSLStream)b.ptr;
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

private nothrow extern(C):
static if (haveALPN) {
	alias ALPNCallback = int function(SSL *ssl, const(char) **output, ubyte* outlen, const(char) *input, uint inlen, void *arg);
	void SSL_CTX_set_alpn_select_cb(SSL_CTX *ctx, ALPNCallback cb, void *arg);
	int SSL_set_alpn_protos(SSL *ssl, const char *data, uint len);
	int SSL_CTX_set_alpn_protos(SSL_CTX *ctx, const char* protos, uint protos_len);
	void SSL_get0_alpn_selected(const SSL *ssl, const char* data, uint *len);
}
const(ssl_method_st)* TLSv1_2_server_method();
