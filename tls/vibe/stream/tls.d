/**
	TLS stream implementation

	TLSStream can be used to implement TLS communication on top of a TCP connection. The
	TLSContextKind of an TLSStream determines if the TLS tunnel is established actively (client) or
	passively (server).

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.tls;

import vibe.core.log;
import vibe.core.net;
import vibe.core.path : NativePath;
import vibe.core.stream;
import vibe.core.sync;

import vibe.utils.dictionarylist;
import vibe.internal.interfaceproxy;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.string;

import core.stdc.string : strlen;
import core.sync.mutex;
import core.thread;

version (VibeNoSSL) {}
else version(Have_openssl) version = OpenSSL;
else version(Have_botan) version = Botan;


/// A simple TLS client
unittest {
	import vibe.core.net;
	import vibe.stream.tls;

	void sendTLSMessage()
	{
		auto conn = connectTCP("127.0.0.1", 1234);
		auto sslctx = createTLSContext(TLSContextKind.client);
		auto stream = createTLSStream(conn, sslctx);
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
	import vibe.stream.tls;

	void listenForTLS()
	{
		auto sslctx = createTLSContext(TLSContextKind.server);
		sslctx.useCertificateChainFile("server.crt");
		sslctx.usePrivateKeyFile("server.key");
		listenTCP(1234, delegate void(TCPConnection conn) nothrow {
			try {
				auto stream = createTLSStream(conn, sslctx);
				logInfo("Got message: %s", stream.readAllUTF8());
				stream.finalize();
			} catch (Exception e) {
				logInfo("Failed to receive encrypted message");
			}
		});
	}
}


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/
@safe:

/** Creates a new context of the given kind.

	Params:
		kind = Specifies if the context is going to be used on the client
			or on the server end of the TLS tunnel
		ver = The TLS protocol used for negotiating the tunnel
*/
TLSContext createTLSContext(TLSContextKind kind, TLSVersion ver = TLSVersion.any)
@trusted {
	version (OpenSSL) {
		static TLSContext createOpenSSLContext(TLSContextKind kind, TLSVersion ver) @safe {
			import vibe.stream.openssl;
			return new OpenSSLContext(kind, ver);
		}
		if (!gs_sslContextFactory)
			setTLSContextFactory(&createOpenSSLContext);
	} else version(Botan) {
		static TLSContext createBotanContext(TLSContextKind kind, TLSVersion ver) @safe {
			import vibe.stream.botan;
			return new BotanTLSContext(kind);
		}
		if (!gs_sslContextFactory)
			setTLSContextFactory(&createBotanContext);
	}
	assert(gs_sslContextFactory !is null, "No TLS context factory registered. Compile in botan or openssl dependencies, or call setTLSContextFactory first.");
	return gs_sslContextFactory(kind, ver);
}

/** Constructs a new TLS tunnel and infers the stream state from the TLSContextKind.

	Depending on the TLSContextKind of ctx, the tunnel will try to establish an TLS
	tunnel by either passively accepting or by actively connecting.

	Params:
		underlying = The base stream which is used for the TLS tunnel
		ctx = TLS context used for initiating the tunnel
		peer_name = DNS name of the remote peer, used for certificate validation
		peer_address = IP address of the remote peer, used for certificate validation
*/
TLSStream createTLSStream(Stream)(Stream underlying, TLSContext ctx, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
	if (isStream!Stream)
{
	auto stream_state = ctx.kind == TLSContextKind.client ? TLSStreamState.connecting : TLSStreamState.accepting;
	return createTLSStream(underlying, ctx, stream_state, peer_name, peer_address);
}

/** Constructs a new TLS tunnel, allowing to override the stream state.

	This constructor allows to specify a custom tunnel state, which can
	be useful when a tunnel has already been established by other means.

	Params:
		underlying = The base stream which is used for the TLS tunnel
		ctx = TLS context used for initiating the tunnel
		state = The manually specified tunnel state
		peer_name = DNS name of the remote peer, used for certificate validation
		peer_address = IP address of the remote peer, used for certificate validation
*/
TLSStream createTLSStream(Stream)(Stream underlying, TLSContext ctx, TLSStreamState state, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
	if (isStream!Stream)
{
	return ctx.createStream(interfaceProxy!(.Stream)(underlying), state, peer_name, peer_address);
}

/**
	Constructs a new TLS stream using manual memory allocator.
*/
auto createTLSStreamFL(Stream)(Stream underlying, TLSContext ctx, TLSStreamState state, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init)
	if (isStream!Stream)
{
	// This function has an auto return type to avoid the import of the TLS
	// implementation headers.  When client code uses this function the compiler
	// will have to semantically analyse it and subsequently will import the TLS
	// implementation headers.
	version (OpenSSL) {
		import vibe.internal.freelistref;
		import vibe.stream.openssl;
		static assert(AllocSize!TLSStream > 0);
		return FreeListRef!OpenSSLStream(interfaceProxy!(.Stream)(underlying), cast(OpenSSLContext)ctx,
										 state, peer_name, peer_address);
	} else version (Botan) {
		import vibe.internal.freelistref;
		import vibe.stream.botan;
		return FreeListRef!BotanTLSStream(interfaceProxy!(.Stream)(underlying), cast(BotanTLSContext) ctx, state, peer_name, peer_address);
	} else assert(false, "No TLS support compiled in (VibeNoTLS)");
}

void setTLSContextFactory(TLSContext function(TLSContextKind, TLSVersion) @safe factory)
{
	() @trusted { gs_sslContextFactory = factory; } ();
}


/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

/**
	Creates an TLS tunnel within an existing stream.

	Note: Be sure to call finalize before finalizing/closing the outer stream so that the TLS
		tunnel is properly closed first.
*/
interface TLSStream : Stream {
	@safe:

	@property TLSCertificateInformation peerCertificate();

	//-/ The host name reported through SNI
	//@property string hostName() const;

	/** The ALPN that has been negotiated for this connection.

		See_also: $(WEB https://en.wikipedia.org/wiki/Application-Layer_Protocol_Negotiation)
	*/
	@property string alpn() const;
}

enum TLSStreamState {
	connecting,
	accepting,
	connected
}


/**
	Encapsulates the configuration for an TLS tunnel.

	Note that when creating an TLSContext with TLSContextKind.client, the
	peerValidationMode will be set to TLSPeerValidationMode.trustedCert,
	but no trusted certificate authorities are added by default. Use
	useTrustedCertificateFile to add those.
*/
interface TLSContext {
	@safe:

	/// The kind of TLS context (client/server)
	@property TLSContextKind kind() const;

	/** Specifies the validation level of remote peers.

		The default mode for TLSContextKind.client is
		TLSPeerValidationMode.trustedCert and the default for
		TLSContextKind.server is TLSPeerValidationMode.none.
	*/
	@property void peerValidationMode(TLSPeerValidationMode mode);
	/// ditto
	@property TLSPeerValidationMode peerValidationMode() const;

	/** The maximum length of an accepted certificate chain.

		Any certificate chain longer than this will result in the TLS
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
	@property void peerValidationCallback(TLSPeerValidationCallback callback);
	/// ditto
	@property inout(TLSPeerValidationCallback) peerValidationCallback() inout;

	/** The callback used to associcate host names with TLS certificates/contexts.

		This property is only used for kind $(D TLSContextKind.serverSNI).
	*/
	@property void sniCallback(TLSServerNameCallback callback);
	/// ditto
	@property inout(TLSServerNameCallback) sniCallback() inout;

	/// Callback function invoked to choose alpn (client side)
	@property void alpnCallback(TLSALPNCallback alpn_chooser);
	/// ditto
	@property TLSALPNCallback alpnCallback() const;

	/// Setter method invoked to offer ALPN (server side)
	void setClientALPN(string[] alpn);

	/** Creates a new stream associated to this context.
	*/
	TLSStream createStream(InterfaceProxy!Stream underlying, TLSStreamState state, string peer_name = null, NetworkAddress peer_address = NetworkAddress.init);

	/** Set the list of cipher specifications to use for TLS tunnels.

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
	/// ditto
	final void useCertificateChainFile(NativePath path) { useCertificateChainFile(path.toString()); }

	/// Sets the private key to use for authenticating to the remote peer based
	/// on the configured certificate chain file.
	void usePrivateKeyFile(string path);
	/// ditto
	final void usePrivateKeyFile(NativePath path) { usePrivateKeyFile(path.toString()); }

	/** Sets the list of trusted certificates for verifying peer certificates.

		If this is a server context, this also entails that the given
		certificates are advertised to connecting clients during handshake.

		On Linux, the system's root certificate authority list is usually
		found at "/etc/ssl/certs/ca-certificates.crt",
		"/etc/pki/tls/certs/ca-bundle.crt", or "/etc/ssl/ca-bundle.pem".
	*/
	void useTrustedCertificateFile(string path);
}

enum TLSContextKind {
	client,     /// Client context (active connector)
	server,     /// Server context (passive connector)
	serverSNI,  /// Server context with multiple certificate support (SNI)
}

enum TLSVersion {
	any, /// Accept SSLv3 or TLSv1.0 and greater
	ssl3, /// Accept only SSLv3
	tls1, /// Accept only TLSv1.0
	tls1_1, /// Accept only TLSv1.1
	tls1_2, /// Accept only TLSv1.2
	dtls1, /// Use DTLSv1.0

	ssl23 = any /// Deprecated compatibility alias
}


/** Specifies how rigorously TLS peer certificates are validated.

	The individual options can be combined using a bitwise "or". Usually it is
	recommended to use $(D trustedCert) for full validation.
*/
enum TLSPeerValidationMode {
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
		$(D createTLSStream) to the list of patterns present in the
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

/** Certificate information  */
struct TLSCertificateInformation {

	/** Information about the certificate's subject name.

		Maps fields to their values. For example, typical fields on a
		certificate will be 'commonName', 'countryName', 'emailAddress', etc.
	*/
	DictionaryList!(string, false, 8) subjectName;

	/** Vendor specific representation of the peer certificate.

		This field is only set if the functionality is supported and if the
		peer certificate is a X509 certificate.

		For the OpenSSL driver, this will point to an `X509` struct. Note
		that the life time of the object is limited to the life time of the
		TLS stream.
	*/
	void* _x509;
}

struct TLSPeerValidationData {
	char[] certName;
	string errorString;
	// certificate chain
	// public key
	// public key fingerprint
}

alias TLSPeerValidationCallback = bool delegate(scope TLSPeerValidationData data);

alias TLSServerNameCallback = TLSContext delegate(string hostname);
alias TLSALPNCallback = string delegate(string[] alpn_choices);

private {
	__gshared TLSContext function(TLSContextKind, TLSVersion) gs_sslContextFactory;
}
