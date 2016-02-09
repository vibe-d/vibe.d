/**
	Compatibility module for `vibe.stream.tls`.

	Copyright: © 2015-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
deprecated("Import vibe.stream.tls instead.")
module vibe.stream.ssl;

public import vibe.stream.tls;

/// Compatibility alias for `createTLSContext`
deprecated("Use createTLSContext instead.")
alias createSSLContext = createTLSContext;

/// Compatibility alias for `createTLSStream`
deprecated("Use createTLSStream instead.")
alias createSSLStream = createTLSStream;

/// Compatibility alias for `createTLSStreamFL`
deprecated("Use createTLSStreamFL instead.")
alias createSSLStreamFL = createTLSStreamFL;

/// Compatibility alias for `setTLSContextFactory`
deprecated("Use setTLSContextFactory instead.")
alias setSSLContextFactory = setTLSContextFactory;

/// Compatibility alias for `TLSStream`
deprecated("Use TLSStream instead.")
alias SSLStream = TLSStream;

/// Compatibility alias for `TLSStreamState`
deprecated("Use TLSStreamState instead.")
alias SSLStreamState = TLSStreamState;

/// Compatibility alias for `TLSContext`
deprecated("Use TLSContext instead.")
alias SSLContext = TLSContext;

/// Compatibility alias for `TLSContextKind`
deprecated("Use TLSContextKind instead.")
alias SSLContextKind = TLSContextKind;

/// Compatibility alias for `TLSVersion`
deprecated("Use TLSVersion instead.")
alias SSLVersion = TLSVersion;

/// Compatibility alias for `TLSPeerValidationMode`
deprecated("Use TLSPeerValidationMode instead.")
alias SSLPeerValidationMode = TLSPeerValidationMode;

/// Compatibility alias for `TLSCertificateInformation`
deprecated("Use TLSCertificateInformation instead.")
alias SSLCertificateInformation = TLSCertificateInformation;

/// Compatibility alias for `TLSPeerValidationData`
deprecated("Use TLSPeerValidationData instead.")
alias SSLPeerValidationData = TLSPeerValidationData;

/// Compatibility alias for `TLSPeerValidationCallback`
deprecated("Use TLSPeerValidationCallback instead.")
alias SSLPeerValidationCallback = TLSPeerValidationCallback;


/// Compatibility alias for `TLSServerNameCallback`
deprecated("Use TLSServerNameCallback instead.")
alias SSLServerNameCallback = TLSServerNameCallback;
