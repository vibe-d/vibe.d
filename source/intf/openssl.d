module intf.openssl;

extern(C):

//
//
// 
enum X509_FILETYPE_PEM = 1;


//
// ssl.h
//
enum SSL_FILETYPE_PEM = X509_FILETYPE_PEM;

enum {
	SSL_OP_NO_SSLv2 = 0x01000000L,
	SSL_OP_NO_SSLv3 = 0x02000000L,
	SSL_OP_NO_TLSv1 = 0x04000000L,
}

enum SSL_CTRL_OPTIONS = 32;


struct ssl_st;
//{}
struct ssl_ctx_st;
//{}
struct ssl_method_st;
//{}

alias ssl_st SSL;
alias ssl_ctx_st SSL_CTX;
alias ssl_method_st SSL_METHOD;

auto SSL_CTX_set_options()(SSL_CTX* ctx, int op){ return SSL_CTX_ctrl(ctx,SSL_CTRL_OPTIONS,op,null); }
auto SSL_CTX_get_options()(SSL_CTX* ctx, int op){ return SSL_CTX_ctrl(ctx,SSL_CTRL_OPTIONS,op,null); }
auto SSL_set_options()(SSL* ctx){ return SSL_ctrl(ctx,SSL_CTRL_OPTIONS,0,null); }
auto SSL_get_options()(SSL* ctx){ return SSL_ctrl(ctx,SSL_CTRL_OPTIONS,0,null); }


int SSL_library_init();
void	SSL_load_error_strings();


SSL_CTX *SSL_CTX_new(SSL_METHOD *meth);
sizediff_t SSL_ctrl(SSL *ssl, int cmd, sizediff_t larg, void *parg);
sizediff_t SSL_CTX_ctrl(SSL_CTX *ctx, int cmd, sizediff_t larg, void *parg);
int SSL_CTX_use_PrivateKey_file(SSL_CTX *ctx, const char *file, int type);
int SSL_CTX_use_certificate_chain_file(SSL_CTX *ctx, const char *file);
SSL *	SSL_new(SSL_CTX *ctx);

SSL_METHOD *SSLv3_method();
SSL_METHOD *SSLv3_server_method();
SSL_METHOD *SSLv3_client_method();
SSL_METHOD *SSLv23_method();
SSL_METHOD *SSLv23_server_method();
SSL_METHOD *SSLv23_client_method();
SSL_METHOD *TLSv1_method();
SSL_METHOD *TLSv1_server_method();
SSL_METHOD *TLSv1_client_method();
SSL_METHOD *DTLSv1_method();
SSL_METHOD *DTLSv1_server_method();
SSL_METHOD *DTLSv1_client_method();

//
// rand.h
//
int RAND_poll();

//
// SHA1
//

struct SHA_CTX {
	size_t[5] h;
	size_t[2] count;
	int index;
	ubyte[64] X;
}

enum SHA1_DIGEST_LENGTH = 20;
ubyte *SHA1(const ubyte *d, size_t n, ubyte *md);
int SHA1_Init(SHA_CTX *c);
int SHA1_Update(SHA_CTX *c, const void *data, size_t len);
int SHA1_Final(ubyte *md, SHA_CTX *c);
