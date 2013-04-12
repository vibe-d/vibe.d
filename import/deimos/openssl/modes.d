/* ====================================================================
 * Copyright (c) 2008 The OpenSSL Project. All rights reserved.
 *
 * Rights for redistribution and usage in source and binary
 * forms are granted according to the OpenSSL license.
 */
module deimos.openssl.modes;

import deimos.openssl._d_util;

import core.stdc.config;

alias ExternC!(void function(const ubyte in_[16],
			ubyte out_[16],
			const(void)* key)) block128_f;

alias ExternC!(void function(const(ubyte)* in_, ubyte* out_,
			size_t len, const(void)* key,
			ubyte ivec[16], int enc)) cbc128_f;

void CRYPTO_cbc128_encrypt(const(ubyte)* in_, ubyte* out_,
			size_t len, const(void)* key,
			ubyte ivec[16], block128_f block);
void CRYPTO_cbc128_decrypt(const(ubyte)* in_, ubyte* out_,
			size_t len, const(void)* key,
			ubyte ivec[16], block128_f block);

void CRYPTO_ctr128_encrypt(const(ubyte)* in_, ubyte* out_,
			size_t len, const(void)* key,
			ubyte ivec[16], ubyte ecount_buf[16],
			uint* num, block128_f block);

void CRYPTO_ofb128_encrypt(const(ubyte)* in_, ubyte* out_,
			size_t len, const(void)* key,
			ubyte ivec[16], int* num,
			block128_f block);

void CRYPTO_cfb128_encrypt(const(ubyte)* in_, ubyte* out_,
			size_t len, const(void)* key,
			ubyte ivec[16], int* num,
			int enc, block128_f block);
void CRYPTO_cfb128_8_encrypt(const(ubyte)* in_, ubyte* out_,
			size_t length, const(void)* key,
			ubyte ivec[16], int* num,
			int enc, block128_f block);
void CRYPTO_cfb128_1_encrypt(const(ubyte)* in_, ubyte* out_,
			size_t bits, const(void)* key,
			ubyte ivec[16], int* num,
			int enc, block128_f block);

size_t CRYPTO_cts128_encrypt_block(const(ubyte)* in_, ubyte* out_,
			size_t len, const(void)* key,
			ubyte ivec[16], block128_f block);
size_t CRYPTO_cts128_encrypt(const(ubyte)* in_, ubyte* out_,
			size_t len, const(void)* key,
			ubyte ivec[16], cbc128_f cbc);
size_t CRYPTO_cts128_decrypt_block(const(ubyte)* in_, ubyte* out_,
			size_t len, const(void)* key,
			ubyte ivec[16], block128_f block);
size_t CRYPTO_cts128_decrypt(const(ubyte)* in_, ubyte* out_,
			size_t len, const(void)* key,
			ubyte ivec[16], cbc128_f cbc);
