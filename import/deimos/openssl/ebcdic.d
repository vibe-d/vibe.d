/* crypto/ebcdic.h */

module deimos.openssl.ebcdic;

import deimos.openssl._d_util;

/* Avoid name clashes with other applications */
alias _openssl_os_toascii os_toascii;
alias _openssl_os_toebcdic os_toebcdic;
alias _openssl_ebcdic2ascii ebcdic2ascii;
alias _openssl_ascii2ebcdic ascii2ebcdic;

extern const ubyte _openssl_os_toascii[256];
extern const ubyte _openssl_os_toebcdic[256];
void* _openssl_ebcdic2ascii(void* dest, const(void)* srce, size_t count);
void* _openssl_ascii2ebcdic(void* dest, const(void)* srce, size_t count);
