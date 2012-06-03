/**
	Contains the SSLContext class used for SSL based network connections.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.crypto.ssl;

import vibe.core.log;

import deimos.openssl.rand;
import deimos.openssl.ssl;

import std.exception;
import std.string;

//version(Posix){
	version = SSL;
//}


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/

/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

class SslContext {
	private {
		ssl_ctx_st* m_ctx;
	}

	this(string cert_file, string key_file, SSLVersion ver = SSLVersion.SSLv23)
	{
		version(SSL){
			const(SSL_METHOD)* method;
			final switch(ver){
				case SSLVersion.SSLv23: method = SSLv23_server_method(); break;
				case SSLVersion.SSLv3: method = SSLv3_server_method(); break;
				case SSLVersion.TLSv1: method = TLSv1_server_method(); break;
				case SSLVersion.DTLSv1: method = DTLSv1_server_method(); break;
			}
			m_ctx = SSL_CTX_new(method);
			auto succ = SSL_CTX_use_certificate_chain_file(m_ctx, toStringz(cert_file)) &&
					SSL_CTX_use_PrivateKey_file(m_ctx, toStringz(key_file), SSL_FILETYPE_PEM);
			enforce(succ, "Failed to load server cert/key.");
			SSL_CTX_set_options!()(m_ctx, SSL_OP_NO_SSLv2);
		} else enforce(false, "No SSL support compiled in!");
	}

	this(SSLVersion ver = SSLVersion.SSLv23)
	{
		version(SSL){
			const(SSL_METHOD)* method;
			final switch(ver){
				case SSLVersion.SSLv23: method = SSLv23_client_method(); break;
				case SSLVersion.SSLv3: method = SSLv3_client_method(); break;
				case SSLVersion.TLSv1: method = TLSv1_client_method(); break;
				case SSLVersion.DTLSv1: method = DTLSv1_client_method(); break;
			}
			m_ctx = SSL_CTX_new(method);
			SSL_CTX_set_options!()(m_ctx, SSL_OP_NO_SSLv2);
		} else enforce(false, "No SSL support compiled in!");
	}

	ssl_st* createClientCtx()
	{
		version(SSL) return SSL_new(m_ctx);
		else assert(false);
	}
}

enum SSLVersion {
	SSLv23,
	SSLv3,
	TLSv1,
	DTLSv1
}

/**************************************************************************************************/
/* Private functions                                                                              */
/**************************************************************************************************/

version(SSL)
{
	shared static this()
	{
		logDebug("Initializing OpenSSL...");
		SSL_load_error_strings();
		SSL_library_init();
		// TODO: call thread safety functions!
		/* We MUST have entropy, or else there's no point to crypto. */
		auto ret = RAND_poll();
		assert(ret);
		logDebug("... done.");
	}
}
