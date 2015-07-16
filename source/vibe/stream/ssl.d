/**
	Compatibility module for `vibe.stream.tls`.

	Copyright: © 2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.ssl;

public import vibe.stream.tls;

/// Compatibility alias for `createTLSContext` - scheduled for deprecation.
alias createSSLContext = createTLSContext;

/// Compatibility alias for `createTLSStream` - scheduled for deprecation.
alias createSSLStream = createTLSStream;

/// Compatibility alias for `createTLSStreamFL` - scheduled for deprecation.
alias createSSLStreamFL = createTLSStreamFL;

/// Compatibility alias for `setTLSContextFactory` - scheduled for deprecation.
alias setSSLContextFactory = setTLSContextFactory;

/// Compatibility alias for `TLSStream` - scheduled for deprecation.
alias SSLStream = TLSStream;

/// Compatibility alias for `TLSStreamState` - scheduled for deprecation.
alias SSLStreamState = TLSStreamState;

/// Compatibility alias for `TLSContext` - scheduled for deprecation.
alias SSLContext = TLSContext;

/// Compatibility alias for `TLSContextKind` - scheduled for deprecation.
alias SSLContextKind = TLSContextKind;

/// Compatibility alias for `TLSVersion` - scheduled for deprecation.
alias SSLVersion = TLSVersion;

/// Compatibility alias for `TLSPeerValidationMode` - scheduled for deprecation.
alias SSLPeerValidationMode = TLSPeerValidationMode;

/// Compatibility alias for `TLSCertificateInformation` - scheduled for deprecation.
alias SSLCertificateInformation = TLSCertificateInformation;

/// Compatibility alias for `TLSPeerValidationData` - scheduled for deprecation.
alias SSLPeerValidationData = TLSPeerValidationData;

/// Compatibility alias for `TLSPeerValidationCallback` - scheduled for deprecation.
alias SSLPeerValidationCallback = TLSPeerValidationCallback;


/// Compatibility alias for `TLSServerNameCallback` - scheduled for deprecation.
alias SSLServerNameCallback = TLSServerNameCallback;
