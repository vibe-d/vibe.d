/**
	SSL/TLS stream implementation

	SSLStream can be used to implement SSL/TLS communication on top of a TCP connection. The
	initial SSLStreamState determines if the SSL tunnel is on the client or server side.

	Examples:
		A simple SSL client:
		---
		void sendSSLMessage()
		{
			auto conn = connectTCP("127.0.0.1", 1234);
			auto sslctx = mew SSLContext;
			auto stream = new SSLStream(conn, sslctx, SSLStreamState.connecting);
			stream.write("Hello, World!");
			stream.finalize();
			conn.close();
		}
		---

		Corresponding server:
		---
		void listenForSSL()
		{
			auto sslctx = new SSLContext("server.crt", "server.key");
			listenTCP(1234, (conn){
				auto stream = new SSLStream(conn, sslctx, SSLStreamState.accepting);
				logInfo("Got message: %s", strea.readAllUtf8());
				stream.finalize();
			});
		}
		---

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.ssl;

import vibe.core.log;
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

	/** Constructs a new SSL tunnel.
	*/
	this(Stream underlying, SSLContext ctx, SSLStreamState state)
	{
		m_stream = underlying;
		m_state = state;
		m_sslCtx = ctx;
		m_ssl = ctx.createClientCtx();
		scope(failure) SSL_free(m_ssl);

		m_bio = BIO_new(&s_bio_methods);
		enforce(m_bio !is null, "SSL failed: failed to create BIO structure.");
		m_bio.init_ = 1;
		m_bio.ptr = cast(void*)this;
		m_bio.shutdown = 0;

		SSL_set_bio(m_ssl, m_bio, m_bio);

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
		checkExceptions();
	}

	~this()
	{
		if( m_ssl ) SSL_free(m_ssl);
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
		if( ret <= 0 ){
			auto errmsg = to!string(SSL_get_error(m_ssl, ret));
			throw new Exception(message~": "~errmsg);
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


class SSLContext {
	private {
		ssl_ctx_st* m_ctx;
	}

	this(string cert_file, string key_file, SSLVersion ver = SSLVersion.ssl23)
	{
		version(SSL){
			const(SSL_METHOD)* method;
			final switch(ver){
				case SSLVersion.ssl23: method = SSLv23_server_method(); break;
				case SSLVersion.ssl3: method = SSLv3_server_method(); break;
				case SSLVersion.tls1: method = TLSv1_server_method(); break;
				case SSLVersion.dtls1: method = DTLSv1_server_method(); break;
			}
			m_ctx = SSL_CTX_new(method);
			scope(failure) SSL_CTX_free(m_ctx);
			auto succ = SSL_CTX_use_certificate_chain_file(m_ctx, toStringz(cert_file)) &&
					SSL_CTX_use_PrivateKey_file(m_ctx, toStringz(key_file), SSL_FILETYPE_PEM);
			enforce(succ, "Failed to load server cert/key.");
			SSL_CTX_set_options!()(m_ctx, SSL_OP_NO_SSLv2);
		} else enforce(false, "No SSL support compiled in!");
	}

	this(SSLVersion ver = SSLVersion.ssl23)
	{
		version(SSL){
			const(SSL_METHOD)* method;
			final switch(ver){
				case SSLVersion.ssl23: method = SSLv23_client_method(); break;
				case SSLVersion.ssl3: method = SSLv3_client_method(); break;
				case SSLVersion.tls1: method = TLSv1_client_method(); break;
				case SSLVersion.dtls1: method = DTLSv1_client_method(); break;
			}
			m_ctx = SSL_CTX_new(method);
			SSL_CTX_set_options!()(m_ctx, SSL_OP_NO_SSLv2);
		} else enforce(false, "No SSL support compiled in!");
	}

	~this()
	{
		SSL_CTX_free(m_ctx);
		m_ctx = null;
	}

	ssl_st* createClientCtx()
	{
		version(SSL) return SSL_new(m_ctx);
		else assert(false);
	}
}

/// Deprecated compatibility alias
deprecated("Please use SSLContext instead.") alias SslContext = SSLContext;


enum SSLVersion {
	ssl23,
	ssl3,
	tls1,
	dtls1
}


/**************************************************************************************************/
/* Private functions                                                                              */
/**************************************************************************************************/

__gshared Mutex[] g_cryptoMutexes;

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
}

private nothrow extern(C)
{
	import core.stdc.config;

	size_t onCryptoGetThreadID()
	{
		try return cast(size_t)cast(void*)Thread.getThis();
		catch (Exception e) {
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
