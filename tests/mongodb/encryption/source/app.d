/**
	Explicit field-level encryption against a real MongoDB server.

	Two MongoCryptProvider implementations are defined here:
	  - ReferenceCryptProvider: no cipher, no key. Wraps the value in a BSON
	    envelope and tags it subtype 0x06. Reversible by anyone; only shows the
	    data flow through the seam.
	  - LocalCryptProvider: real AES-256-CBC + HMAC-SHA-512 (encrypt-then-MAC)
	    keyed by a 96-byte master key, via OpenSSL. A test-only AEAD construction
	    modeled on, but NOT wire-compatible with, CSFLE's "local" KMS provider: its
	    blob is IV || ciphertext || HMAC and omits the key id, BSON type byte, and
	    associated-data binding that libmongocrypt's subtype-6 format requires, so
	    other drivers cannot read the subtype-6 values it writes. runTest() uses this one.

	The driver itself does no crypto: ClientEncryption (impl/encryption.d) just
	delegates to whichever provider is injected, and throws if none is. A real
	deployment would inject a libmongocrypt-backed provider instead and nothing
	else here would change. It does not cover external KMS providers, automatic
	encryption, and libmongocrypt's on-the-wire blob format.

	Needs a running mongod (any version, this is just binary storage). The
	encryption symbols come in through the vibe.db.mongo.mongo umbrella.
*/
module app;

import vibe.core.log;
import vibe.data.bson;
import vibe.db.mongo.mongo;

import std.algorithm : canFind;
import std.conv : to;

import deimos.openssl.evp;
import deimos.openssl.rand;
import std.digest.hmac : hmac;
import std.digest.sha : SHA512;
import std.exception : enforce;

/// Keyless stand-in that wraps the value in a `{"v": value}` envelope and tags it
/// subtype 0x06. Not encryption (reversible by anyone), it only exercises the
/// seam's plumbing. A real provider keeps these signatures but does actual crypto.
final class ReferenceCryptProvider : MongoCryptProvider {
@safe:
	BsonBinData encrypt(Bson value, EncryptOptions options) {
		options.validate();
		// With no cipher, wrap the value and label the plaintext bytes subtype 0x06.
		auto envelope = Bson(["v": value]);
		immutable(ubyte)[] payload = () @trusted {
			return cast(immutable(ubyte)[]) envelope.data.idup;
		}();
		return BsonBinData(encryptedBinarySubtype, payload);
	}

	Bson decrypt(BsonBinData value) {
		import std.exception : enforce;
		enforce(value.type == encryptedBinarySubtype,
			"payload is not a CSFLE-encrypted binary (subtype 0x06)");
		auto envelope = () @trusted {
			return Bson(Bson.Type.object, cast(immutable(ubyte)[]) value.rawData);
		}();
		return envelope["v"];
	}

	BsonBinData createDataKey(string kmsProvider, DataKeyOptions options) {
		// a real provider generates a key and KMS-wraps it into the vault; here
		// it's just a UUID derived from the provider name.
		ubyte[16] uuid;
		foreach (i; 0 .. uuid.length)
			uuid[i] = kmsProvider.length ? cast(ubyte)(kmsProvider[i % kmsProvider.length] ^ i) : cast(ubyte) i;
		return BsonBinData(BsonBinData.Type.uuid, uuid.idup);
	}
}

/// Real AES-256-CBC + HMAC-SHA-512 (encrypt-then-MAC), keyed by a 96-byte master
/// key split into encrypt / mac / iv-derivation parts. decrypt() checks the HMAC
/// before decrypting, so the wrong key fails. Test-only AEAD layout (IV || ciphertext
/// || HMAC) modeled on CSFLE's "local" KMS scheme but not libmongocrypt-wire-compatible:
/// it binds no key id or BSON type byte, so other drivers cannot read its subtype-6 blobs.
final class LocalCryptProvider : MongoCryptProvider {
@safe:
	private immutable(ubyte)[] m_encKey;
	private immutable(ubyte)[] m_macKey;
	private immutable(ubyte)[] m_ivKey;

	this(immutable(ubyte)[] masterKey96) {
		enforce(masterKey96.length == 96, "local master key must be 96 bytes");
		m_encKey = masterKey96[0 .. 32];
		m_macKey = masterKey96[32 .. 64];
		m_ivKey = masterKey96[64 .. 96];
	}

	BsonBinData encrypt(Bson value, EncryptOptions options) {
		options.validate();
		immutable(ubyte)[] plaintext = () @trusted {
			return cast(immutable(ubyte)[]) Bson(["v": value]).data.idup;
		}();

		// deterministic derives the IV from the plaintext (equal values -> equal
		// ciphertext, for equality queries); random uses a fresh IV.
		ubyte[16] iv;
		if (options.algorithm == EncryptionAlgorithm.deterministic) {
			auto derived = hmacSha512(m_ivKey, plaintext);
			iv[] = derived[0 .. 16];
		} else {
			enforce(() @trusted { return RAND_bytes(iv.ptr, 16); }() == 1, "RAND_bytes failed");
		}

		// The scheme is encrypt-then-MAC, so the HMAC covers IV || ciphertext.
		auto cipherText = aesCbcEncrypt(m_encKey, iv[], plaintext);
		auto mac = hmacSha512(m_macKey, iv[] ~ cipherText);
		immutable(ubyte)[] blob = (iv[] ~ cipherText ~ mac).idup;
		return BsonBinData(encryptedBinarySubtype, blob);
	}

	Bson decrypt(BsonBinData value) {
		enforce(value.type == encryptedBinarySubtype, "not a subtype-0x06 payload");
		auto blob = value.rawData;
		enforce(blob.length >= 16 + 64, "ciphertext too short");
		auto iv = blob[0 .. 16];
		auto mac = blob[$ - 64 .. $];
		auto cipherText = blob[16 .. $ - 64];
		// check the MAC before touching the cipher. This is what rejects a wrong key.
		enforce(constantTimeEquals(mac, hmacSha512(m_macKey, iv ~ cipherText)),
			"HMAC verification failed (wrong key or tampered ciphertext)");
		auto plaintext = aesCbcDecrypt(m_encKey, iv, cipherText);
		auto envelope = () @trusted {
			return Bson(Bson.Type.object, plaintext);
		}();
		return envelope["v"];
	}

	BsonBinData createDataKey(string kmsProvider, DataKeyOptions options) {
		ubyte[16] uuid;
		enforce(() @trusted { return RAND_bytes(uuid.ptr, 16); }() == 1, "RAND_bytes failed");
		return BsonBinData(BsonBinData.Type.uuid, uuid.idup);
	}
}

private immutable(ubyte)[] hmacSha512(const(ubyte)[] key, const(ubyte)[] data) @safe {
	auto engine = hmac!SHA512(key);
	engine.put(data);
	return engine.finish().idup;
}

private immutable(ubyte)[] aesCbcEncrypt(const(ubyte)[] key32, const(ubyte)[] iv16, const(ubyte)[] data) @trusted {
	auto ctx = EVP_CIPHER_CTX_new();
	scope(exit) EVP_CIPHER_CTX_free(ctx);
	enforce(EVP_EncryptInit_ex(ctx, EVP_aes_256_cbc(), null, key32.ptr, iv16.ptr) == 1, "EncryptInit");
	auto outbuf = new ubyte[data.length + 16]; // +1 block for PKCS7 padding
	int n1;
	enforce(EVP_EncryptUpdate(ctx, outbuf.ptr, &n1, data.ptr, cast(int) data.length) == 1, "EncryptUpdate");
	int n2;
	enforce(EVP_EncryptFinal_ex(ctx, outbuf.ptr + n1, &n2) == 1, "EncryptFinal");
	return outbuf[0 .. n1 + n2].idup;
}

private immutable(ubyte)[] aesCbcDecrypt(const(ubyte)[] key32, const(ubyte)[] iv16, const(ubyte)[] data) @trusted {
	auto ctx = EVP_CIPHER_CTX_new();
	scope(exit) EVP_CIPHER_CTX_free(ctx);
	enforce(EVP_DecryptInit_ex(ctx, EVP_aes_256_cbc(), null, key32.ptr, iv16.ptr) == 1, "DecryptInit");
	auto outbuf = new ubyte[data.length + 16];
	int n1;
	enforce(EVP_DecryptUpdate(ctx, outbuf.ptr, &n1, data.ptr, cast(int) data.length) == 1, "DecryptUpdate");
	int n2;
	enforce(EVP_DecryptFinal_ex(ctx, outbuf.ptr + n1, &n2) == 1, "DecryptFinal/padding");
	return outbuf[0 .. n1 + n2].idup;
}

private bool constantTimeEquals(const(ubyte)[] a, const(ubyte)[] b) @safe {
	if (a.length != b.length) return false;
	ubyte diff = 0;
	foreach (i; 0 .. a.length) diff |= cast(ubyte)(a[i] ^ b[i]);
	return diff == 0;
}

void runTest(ushort port)
{
	MongoClient client = connectMongoDB("127.0.0.1", port);

	// inject the real provider; swapping it for a libmongocrypt-backed one is the
	// only change a full CSFLE deployment would make.
	immutable(ubyte)[] masterKey = () { ubyte[96] k; foreach (i; 0 .. 96) k[i] = cast(ubyte)(i * 7 + 3); return k.idup; }();
	auto ce = new ClientEncryption("encryption.__keyVault",
		["local": Bson(["key": Bson("0123456789abcdef0123456789abcdef0123456789abcdef")])],
		new LocalCryptProvider(masterKey));

	// (1) encrypt -> store -> read back -> decrypt, through a real collection.
	auto coll = client.getCollection("test.csfle_demo");
	try coll.drop; catch (Exception) {}

	EncryptOptions opts;
	opts.algorithm = EncryptionAlgorithm.random;
	opts.keyAltName = "ssn-key";
	auto encSsn = ce.encrypt(Bson("123-45-6789"), opts);

	coll.insertOne(Bson(["_id": Bson(1), "name": Bson("Alice"), "ssn": Bson(encSsn)]));

	auto stored = coll.findOne(Bson(["_id": Bson(1)]));
	assert(stored["ssn"].type == Bson.Type.binData,
		"server-stored ssn is not binData");
	assert(stored["ssn"].get!BsonBinData.type == encryptedBinarySubtype,
		"server-stored ssn binary subtype is not the CSFLE one (0x06)");

	auto decSsn = ce.decrypt(stored["ssn"].get!BsonBinData);
	assert(decSsn == Bson("123-45-6789"),
		"round-trip of server-stored payload mismatch, got: " ~ decSsn.toString());
	logInfo("encrypted %s (AES-256-CBC-HMAC-SHA-512), stored in and read back from mongo, decrypted OK", decSsn.get!string);

	// For confidentiality at rest the stored bytes don't contain the plaintext, and a
	// different key can't decrypt them.
	auto rawCipher = stored["ssn"].get!BsonBinData.rawData;
	assert(!rawCipher.canFind(cast(immutable(ubyte)[]) "123-45-6789"),
		"plaintext SSN leaked into the stored ciphertext!");
	auto wrongKey = () { ubyte[96] k; foreach (i; 0 .. 96) k[i] = cast(ubyte)(200 - i); return k.idup; }();
	auto attacker = new LocalCryptProvider(wrongKey);
	bool attackerFailed = false;
	try attacker.decrypt(stored["ssn"].get!BsonBinData); catch (Exception) attackerFailed = true;
	assert(attackerFailed, "a wrong-key provider must NOT be able to decrypt the stored ciphertext");
	logInfo("at rest: ciphertext does not contain the plaintext and the wrong key cannot decrypt it");

	// (2) store the createDataKey id in a key-vault collection and read it back.
	auto vault = client.getCollection("encryption.__keyVault");
	try vault.drop; catch (Exception) {}

	auto keyId = ce.createDataKey("local");
	assert(keyId.type == BsonBinData.Type.uuid,
		"data key id is not a UUID binary, got subtype " ~ (cast(int) keyId.type).to!string);

	vault.insertOne(Bson([
		"_id": Bson(keyId),
		"masterKey": Bson(["provider": Bson("local")]),
		"keyAltNames": Bson([Bson("ssn-key")]),
	]));

	auto storedKey = vault.findOne(Bson(["_id": Bson(keyId)]));
	assert(storedKey["_id"].get!BsonBinData.type == BsonBinData.Type.uuid,
		"stored key-vault _id is not a UUID binary");
	logInfo("key-vault round-trip OK");

	// (3) with no provider injected, the crypto methods must refuse rather than
	// store plaintext.
	auto unconfigured = new ClientEncryption("encryption.__keyVault",
		["local": Bson(["key": Bson("k")])]);
	bool threw = false;
	try
		unconfigured.encrypt(Bson("123-45-6789"), opts);
	catch (Exception e) {
		threw = true;
		assert(e.msg.canFind("libmongocrypt"),
			"error should mention libmongocrypt, got: " ~ e.msg);
		logInfo("no-provider encrypt refused as expected");
	}
	assert(threw, "encrypt() without a provider must throw");

	// drop so reruns start clean.
	try coll.drop; catch (Exception) {}
	try vault.drop; catch (Exception) {}

	logInfo("all checks passed");
}

void main(string[] args)
{
	ushort port = args.length > 1
		? args[1].to!ushort
		: MongoClientSettings.defaultPort;
	runTest(port);
}
