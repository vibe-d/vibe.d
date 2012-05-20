module vibe.crypto.sha1;

import deimos.openssl.sha;

ubyte[20] sha1(in char[] str) 
{
	ubyte[20] digest;
	SHA_CTX ctx;
	SHA1_Init(&ctx);
	SHA1_Update(&ctx, str.ptr, str.length);
	SHA1_Final(digest.ptr, &ctx);
	return digest;
}