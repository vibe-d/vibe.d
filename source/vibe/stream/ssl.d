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
	version (OpenSSL) {
		static SSLContext createOpenSSLContext(SSLContextKind kind, SSLVersion ver) {
			import vibe.stream.openssl;
			return new OpenSSLContext(kind, ver);
		}
		if (!gs_sslContextFactory)
			setSSLContextFactory(&createOpenSSLContext);
	}
	assert(gs_sslContextFactory !is null, "No SSL context factory registered.");
	return gs_sslContextFactory(kind, ver);
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
	return ctx.createStream(underlying, state, peer_name, peer_address);
}

/**
	Constructs a new SSL stream using manual memory allocator.
*/
auto createSSLStreamFL(Stream underlying, SSLContext ctx, SSLStreamState state, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
{
	// This function has an auto return type to avoid the import of the SSL
	// implementation headers.  When client code uses this function the compiler
	// will have to semantically analyse it and subsequently will import the SSL
	// implementation headers.
	version (VibeNoSSL) assert(false, "No SSL support compiled in (VibeNoSSL)");
	else {
		import vibe.utils.memory;
		import vibe.stream.openssl;
		static assert(AllocSize!SSLStream > 0);
		return FreeListRef!OpenSSLStream(underlying, cast(OpenSSLContext)ctx,
										 state, peer_name, peer_address);
	}
}

void setSSLContextFactory(SSLContext function(SSLContextKind, SSLVersion) factory)
{
	gs_sslContextFactory = factory;
}


/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

/**
	Creates an SSL/TLS tunnel within an existing stream.

	Note: Be sure to call finalize before finalizing/closing the outer stream so that the SSL
		tunnel is properly closed first.
*/
interface SSLStream : Stream {
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
interface SSLContext {
	/// The kind of SSL context (client/server)
	@property SSLContextKind kind() const;

	/** Specifies the validation level of remote peers.

		The default mode for SSLContextKind.client is
		SSLPeerValidationMode.trustedCert and the default for
		SSLContextKind.server is SSLPeerValidationMode.none.
	*/
	@property void peerValidationMode(SSLPeerValidationMode mode);
	/// ditto
	@property SSLPeerValidationMode peerValidationMode() const;

	/** The maximum length of an accepted certificate chain.

		Any certificate chain longer than this will result in the SSL/TLS
		negitiation failing.

		The default value is 9.
	*/
	@property void maxCertChainLength(int val);
	/// ditto
	@property int maxCertChainLength() const;

	/** An optional user callback for peer validation.

		This callback will be called for each peer and each certificate of
		its certificate chain to allow overriding the validation decision
		based on the selected peerValidationMode (e.g. to allow invalid
		certificates or to reject valid ones). This is mainly useful for
		presenting the user with a dialog in case of untrusted or mismatching
		certificates.
	*/
	@property void peerValidationCallback(SSLPeerValidationCallback callback);
	/// ditto
	@property inout(SSLPeerValidationCallback) peerValidationCallback() inout;

	/** The callback used to associcate host names with SSL certificates/contexts.

		This property is only used for kind $(D SSLContextKind.serverSNI).
	*/
	@property void sniCallback(SSLServerNameCallback callback);
	/// ditto
	@property inout(SSLServerNameCallback) sniCallback() inout;

	/** Creates a new stream associated to this context.
	*/
	SSLStream createStream(Stream underlying, SSLStreamState state, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init);

	/** Set the list of cipher specifications to use for SSL/TLS tunnels.

		The list must be a colon separated list of cipher
		specifications as accepted by OpenSSL. Calling this function
		without argument will restore the default.

		See_also: $(LINK https://www.openssl.org/docs/apps/ciphers.html#CIPHER_LIST_FORMAT)
	*/
	void setCipherList(string list = null);

	/** Set params to use for DH cipher.
	 *
	 * By default the 2048-bit prime from RFC 3526 is used.
	 *
	 * Params:
	 * pem_file = Path to a PEM file containing the DH parameters. Calling
	 *    this function without argument will restore the default.
	 */
	void setDHParams(string pem_file=null);

	/** Set the elliptic curve to use for ECDH cipher.
	 *
	 * By default a curve is either chosen automatically or  prime256v1 is used.
	 *
	 * Params:
	 * curve = The short name of the elliptic curve to use. Calling this
	 *    function without argument will restore the default.
	 *
	 */
	void setECDHCurve(string curve=null);

	/// Sets a certificate file to use for authenticating to the remote peer
	void useCertificateChainFile(string path);

	/// Sets the private key to use for authenticating to the remote peer based
	/// on the configured certificate chain file.
	void usePrivateKeyFile(string path);

	/** Sets the list of trusted certificates for verifying peer certificates.

		If this is a server context, this also entails that the given
		certificates are advertised to connecting clients during handshake.

		On Linux, the system's root certificate authority list is usually
		found at "/etc/ssl/certs/ca-certificates.crt",
		"/etc/pki/tls/certs/ca-bundle.crt", or "/etc/ssl/ca-bundle.pem".
	*/
	void useTrustedCertificateFile(string path);
}

enum SSLContextKind {
	client,     /// Client context (active connector)
	server,     /// Server context (passive connector)
	serverSNI,  /// Server context with multiple certificate support (SNI)
}

enum SSLVersion {
	any, /// Accept SSLv3 or TLSv1.0 and greater
	ssl3, /// Accept only SSLv3
	tls1, /// Accept only TLSv1.0
	dtls1, /// Use DTLSv1.0

	ssl23 = any /// Deprecated compatibility alias
}


/** Specifies how rigorously SSL peer certificates are validated.

	The individual options can be combined using a bitwise "or". Usually it is
	recommended to use $(D trustedCert) for full validation.
*/
enum SSLPeerValidationMode {
	/** Accept any peer regardless if and which certificate is presented.

		This mode is generally discouraged and should only be used with
		a custom validation callback set to do the verification.
	*/
	none = 0,

	/** Require the peer to always present a certificate.

		Note that this option alone does not verify the certificate at all. It
		can be used together with the "check" options, or by using a custom
		validation callback to actually validate certificates.
	*/
	requireCert = 1<<0,

	/** Check the certificate for basic validity.

		This verifies the validity of the certificate chain and some other
		general properties, such as expiration time. It doesn't verify
		either the peer name or the trust state of the certificate.
	*/
	checkCert = 1<<1,

	/** Validate the actual peer name/address against the certificate.

		Compares the name/address of the connected peer, as passed to
		$(D createSSLStream) to the list of patterns present in the
		certificate, if any. If no match is found, the connection is
		rejected.
	*/
	checkPeer = 1<<2,

	/** Requires that the certificate or any parent certificate is trusted.

		Searches list of trusted certificates for a match of the certificate
		chain. If no match is found, the connection is rejected.

		See_also: $(D useTrustedCertificateFile)
	*/
	checkTrust = 1<<3,

	/** Require a valid certificate matching the peer name.

		In this mode, the certificate is validated for general consistency and
		possible expiration, and the peer name is checked to see if the
		certificate actually applies.

		However, the certificate chain is not matched against the system's
		pool of trusted certificate authorities, so a custom validation
		callback is still needed to get a secure validation process.

		This option is a combination $(D requireCert), $(D checkCert) and
		$(D checkPeer).
	*/
	validCert = requireCert | checkCert | checkPeer,

	/** Require a valid and trusted certificate (strongly recommended).

		Checks the certificate and peer name for validity and requires that
		the certificate chain originates from a trusted CA (based on the
		registered pool of certificate authorities).

		This option is a combination $(D validCert) and $(D checkTrust).

		See_also: $(D useTrustedCertificateFile)
	*/
    trustedCert = validCert | checkTrust,
}

struct SSLPeerValidationData {
	char[] certName;
	string errorString;
	// certificate chain
	// public key
	// public key fingerprint
}

alias SSLPeerValidationCallback = bool delegate(scope SSLPeerValidationData data);

alias SSLServerNameCallback = SSLContext delegate(string hostname);

private {
	__gshared SSLContext function(SSLContextKind, SSLVersion) gs_sslContextFactory;
}
