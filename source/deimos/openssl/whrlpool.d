module deimos.openssl.whrlpool;

import deimos.openssl._d_util;

public import deimos.openssl.e_os2;
import core.stdc.config;

extern (C):
nothrow:

enum WHIRLPOOL_DIGEST_LENGTH = (512/8);
enum WHIRLPOOL_BBLOCK = 512;
enum WHIRLPOOL_COUNTER = (256/8);

struct WHIRLPOOL_CTX {
	union H_ {
		ubyte	c[WHIRLPOOL_DIGEST_LENGTH];
		/* double q is here to ensure 64-bit alignment */
		double		q[WHIRLPOOL_DIGEST_LENGTH/double.sizeof];
		}
	H_ H;
	ubyte	data[WHIRLPOOL_BBLOCK/8];
	uint	bitoff;
	size_t		bitlen[WHIRLPOOL_COUNTER/size_t.sizeof];
	};

version(OPENSSL_NO_WHIRLPOOL) {} else {
int WHIRLPOOL_Init	(WHIRLPOOL_CTX* c);
int WHIRLPOOL_Update	(WHIRLPOOL_CTX* c,const(void)* inp,size_t bytes);
void WHIRLPOOL_BitUpdate(WHIRLPOOL_CTX* c,const(void)* inp,size_t bits);
int WHIRLPOOL_Final	(ubyte* md,WHIRLPOOL_CTX* c);
ubyte* WHIRLPOOL(const(void)* inp,size_t bytes,ubyte* md);
}
