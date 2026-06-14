/**
	MongoDB client-side field level encryption (CSFLE) configuration data model
	and explicit-encryption facade.

	Holds the CSFLE configuration data model together with the `ClientEncryption`
	facade, which delegates the actual cryptographic work to an injected
	`MongoCryptProvider` (a libmongocrypt-backed implementation can be supplied).
	Without a provider, the crypto methods throw.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.encryption;

import vibe.data.bson;
import std.typecons : Nullable;

@safe:

/**
	Auto-encryption configuration bundle attached to a Mongo client.

	See_Also: https://www.mongodb.com/docs/manual/core/csfle/
*/
struct AutoEncryptionOptions {
	/// The `db.collection` namespace of the key-vault collection holding the data encryption keys.
	string keyVaultNamespace;
	/// Per-provider KMS credentials keyed by provider name (e.g. `"local"`).
	Bson[string] kmsProviders;
	/// When `true`, skips automatic encryption while still permitting automatic decryption.
	bool bypassAutoEncryption;
	/// When `true`, skips query analysis but still performs automatic encryption and decryption.
	bool bypassQueryAnalysis;
	/// Per-collection JSON schemas keyed by `db.collection` namespace.
	Bson[string] schemaMap;
	/// Per-collection encrypted-field configs keyed by `db.collection` namespace.
	Bson[string] encryptedFieldsMap;
	/// Extra options controlling the `mongocryptd` / crypt-shared library backend.
	AutoEncryptionExtraOptions extraOptions;

	/// Validates the configuration by checking that `keyVaultNamespace` is a well-formed `db.collection` namespace and that KMS provider credentials carry their required fields.
	void validate() const @safe {
		import std.exception : enforce;
		enum localMasterKeyLength = 96;
		enforce(isValidNamespace(keyVaultNamespace),
			"keyVaultNamespace must be a 'db.collection' namespace, got: " ~ keyVaultNamespace);
		auto local = "local" in kmsProviders;
		if (!local)
			return;
		auto key = local.tryIndex("key");
		enforce(!key.isNull,
			"kmsProviders['local'] requires a 'key' field");
		enforce(key.get.type == Bson.Type.binData && key.get.get!BsonBinData.rawData.length == localMasterKeyLength,
			"kmsProviders['local']['key'] must be 96 bytes of binary key material");
	}
}

private bool isValidNamespace(string ns) @safe {
	import std.string : indexOf;
	auto dot = ns.indexOf('.');
	return dot > 0 && dot < ns.length - 1;
}

/**
	Extra auto-encryption options controlling the encryption backend.
*/
struct AutoEncryptionExtraOptions {
	/// Path to the `crypt_shared` library used for automatic encryption.
	string cryptSharedLibPath;
	/// Connection URI of the `mongocryptd` process.
	string mongocryptdURI;
	/// When `true`, the driver does not spawn a `mongocryptd` process.
	bool mongocryptdBypassSpawn;
}

unittest {
	AutoEncryptionOptions options;
	options.keyVaultNamespace = "encryption.__keyVault";
	assert(options.keyVaultNamespace == "encryption.__keyVault");
}

unittest {
	import vibe.data.bson;
	AutoEncryptionOptions options;
	options.kmsProviders["local"] = Bson(["key": Bson(BsonBinData(BsonBinData.Type.generic, cast(immutable(ubyte)[]) "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"))]);
	assert("local" in options.kmsProviders);
	assert(options.kmsProviders["local"]["key"].type == Bson.Type.binData);
}

unittest {
	AutoEncryptionOptions options;
	options.schemaMap["db.coll"] = Bson(["bsonType": Bson("object")]);
	options.encryptedFieldsMap["db.secure"] = Bson(["fields": Bson.emptyArray]);
	assert("db.coll" in options.schemaMap);
	assert(options.schemaMap["db.coll"]["bsonType"].get!string == "object");
	assert("db.secure" in options.encryptedFieldsMap);
}

unittest {
	AutoEncryptionOptions options;
	assert(options.bypassAutoEncryption == false);
	assert(options.bypassQueryAnalysis == false);
	options.bypassAutoEncryption = true;
	options.bypassQueryAnalysis = true;
	assert(options.bypassAutoEncryption);
	assert(options.bypassQueryAnalysis);
}

unittest {
	AutoEncryptionOptions options;
	options.extraOptions.cryptSharedLibPath = "/usr/lib/mongo_crypt_v1.so";
	options.extraOptions.mongocryptdURI = "mongodb://localhost:27020";
	options.extraOptions.mongocryptdBypassSpawn = true;
	assert(options.extraOptions.cryptSharedLibPath == "/usr/lib/mongo_crypt_v1.so");
	assert(options.extraOptions.mongocryptdURI == "mongodb://localhost:27020");
	assert(options.extraOptions.mongocryptdBypassSpawn);
}

unittest {
	import std.exception : assertThrown;
	AutoEncryptionOptions options;
	options.keyVaultNamespace = "no_dot";
	assertThrown(options.validate());
}

unittest {
	AutoEncryptionOptions options;
	options.keyVaultNamespace = "encryption.__keyVault";
	options.validate();
}

unittest {
	import std.exception : assertThrown;
	AutoEncryptionOptions emptyDb;
	emptyDb.keyVaultNamespace = ".coll";
	assertThrown(emptyDb.validate());
	AutoEncryptionOptions emptyCollection;
	emptyCollection.keyVaultNamespace = "db.";
	assertThrown(emptyCollection.validate());
}

// validate() rejects a "local" KMS provider missing its "key" field
unittest {
	import std.exception : assertThrown;
	AutoEncryptionOptions options;
	options.keyVaultNamespace = "encryption.__keyVault";
	options.kmsProviders["local"] = Bson.emptyObject;
	assertThrown(options.validate());
}

// validate() accepts a "local" KMS provider carrying a 96-byte "key" field
unittest {
	auto key96 = BsonBinData(BsonBinData.Type.generic, cast(immutable(ubyte)[]) "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
	AutoEncryptionOptions options;
	options.keyVaultNamespace = "encryption.__keyVault";
	options.kmsProviders["local"] = Bson(["key": Bson(key96)]);
	options.validate();
}

// validate() rejects a "local" KMS provider whose "key" is shorter than 96 bytes
unittest {
	import std.exception : assertThrown;
	auto shortKey = BsonBinData(BsonBinData.Type.generic, cast(immutable(ubyte)[]) "too-short-key");
	AutoEncryptionOptions options;
	options.keyVaultNamespace = "encryption.__keyVault";
	options.kmsProviders["local"] = Bson(["key": Bson(shortKey)]);
	assertThrown(options.validate());
}

/**
	Field-level encryption algorithm identifiers used when marking fields for encryption.
*/
enum EncryptionAlgorithm : string {
	deterministic = "AEAD_AES_256_CBC_HMAC_SHA_512-Deterministic",
	random = "AEAD_AES_256_CBC_HMAC_SHA_512-Random",
	indexed = "Indexed",
	unindexed = "Unindexed",
	range = "Range"
}

/**
	Range index bounds for `Range`-algorithm encrypted fields.
*/
struct RangeOptions {
	/// The inclusive lower bound of the queryable range.
	Nullable!Bson min;
	/// The inclusive upper bound of the queryable range.
	Nullable!Bson max;
	/// Controls the sparsity of the range index.
	Nullable!long sparsity;
	/// The number of decimal digits of precision for floating-point bounds.
	Nullable!int precision;
	/// The number of high-order bits trimmed from the range index.
	Nullable!int trimFactor;
}

/**
	Per-field explicit encryption options selecting the data encryption key and algorithm.
*/
struct EncryptOptions {
	/// The encryption algorithm applied to the field value.
	EncryptionAlgorithm algorithm;
	/// The data encryption key identified by its UUID, when keyed by id.
	Nullable!BsonBinData keyId;
	/// The data encryption key identified by its alternate name, when keyed by name.
	Nullable!string keyAltName;
	/// The range bounds applied when `algorithm` is `EncryptionAlgorithm.range`.
	Nullable!RangeOptions rangeOptions;
	/// The contention factor applied to randomized encryption, when set.
	Nullable!long contentionFactor;

	/// Validates that exactly one of `keyId` or `keyAltName` is set and that `rangeOptions` and `contentionFactor` are only used with their permitted algorithms.
	void validate() const @safe {
		import std.exception : enforce;
		enforce(keyId.isNull != keyAltName.isNull,
			"EncryptOptions requires exactly one of keyId or keyAltName");
		enforce(rangeOptions.isNull || algorithm == EncryptionAlgorithm.range,
			"rangeOptions is only valid with the 'range' algorithm");
		enforce(contentionFactor.isNull || algorithm == EncryptionAlgorithm.indexed || algorithm == EncryptionAlgorithm.range,
			"contentionFactor is only valid with the 'indexed' or 'range' algorithm");
	}
}

struct DataKeyOptions {
	/// The KMS provider specific master key document.
	Bson masterKey;
	/// The alternate names assigned to the created data encryption key.
	string[] keyAltNames;
	/// The optional raw key material to import instead of generating a new key.
	Nullable!BsonBinData keyMaterial;
}

unittest {
	assert(EncryptionAlgorithm.deterministic == "AEAD_AES_256_CBC_HMAC_SHA_512-Deterministic");
	assert(EncryptionAlgorithm.random == "AEAD_AES_256_CBC_HMAC_SHA_512-Random");
	assert(EncryptionAlgorithm.indexed == "Indexed");
	assert(EncryptionAlgorithm.unindexed == "Unindexed");
	assert(EncryptionAlgorithm.range == "Range");
}

unittest {
	import std.typecons : Nullable;

	EncryptOptions byId;
	byId.algorithm = EncryptionAlgorithm.deterministic;
	byId.keyId = BsonBinData(BsonBinData.Type.uuid, cast(immutable(ubyte)[]) "0123456789abcdef"); // 16-byte UUID
	assert(byId.algorithm == EncryptionAlgorithm.deterministic);
	assert(!byId.keyId.isNull);
	assert(byId.keyId.get.type == BsonBinData.Type.uuid);

	EncryptOptions byName;
	byName.algorithm = EncryptionAlgorithm.random;
	byName.keyAltName = "ssn-encryption-key";
	assert(byName.keyAltName.get == "ssn-encryption-key");
}

// contentionFactor is an optional long that round-trips
unittest {
	import std.typecons : Nullable;

	EncryptOptions opts;
	opts.algorithm = EncryptionAlgorithm.indexed;
	opts.keyAltName = "search-key";
	opts.contentionFactor = 8L;
	assert(!opts.contentionFactor.isNull);
	assert(opts.contentionFactor.get == 8);
}

// validate() rejects neither-set and both-set key selectors
unittest {
	import std.exception : assertThrown;

	EncryptOptions neither;
	neither.algorithm = EncryptionAlgorithm.deterministic;
	assertThrown(neither.validate());

	EncryptOptions both;
	both.algorithm = EncryptionAlgorithm.deterministic;
	both.keyId = BsonBinData(BsonBinData.Type.uuid, cast(immutable(ubyte)[]) "0123456789abcdef");
	both.keyAltName = "ssn-key";
	assertThrown(both.validate());
}

// validate() accepts exactly one key selector, by id or by alt name
unittest {
	import std.typecons : Nullable;

	EncryptOptions byId;
	byId.algorithm = EncryptionAlgorithm.deterministic;
	byId.keyId = BsonBinData(BsonBinData.Type.uuid, cast(immutable(ubyte)[]) "0123456789abcdef");
	byId.validate();

	EncryptOptions byName;
	byName.algorithm = EncryptionAlgorithm.random;
	byName.keyAltName = "ssn-key";
	byName.validate();
}

// RangeOptions carries the optional range bounds and EncryptOptions exposes them
unittest {
	import std.typecons : Nullable;

	RangeOptions range;
	range.min = Bson(0);
	range.max = Bson(200);
	range.sparsity = 1L;
	range.precision = 2;
	range.trimFactor = 4;
	assert(range.min.get == Bson(0));
	assert(range.max.get == Bson(200));
	assert(range.sparsity.get == 1);
	assert(range.precision.get == 2);
	assert(range.trimFactor.get == 4);

	EncryptOptions opts;
	opts.algorithm = EncryptionAlgorithm.range;
	opts.keyAltName = "age-key";
	opts.rangeOptions = range;
	assert(!opts.rangeOptions.isNull);
	assert(opts.rangeOptions.get.max.get == Bson(200));
}

// validate() rejects rangeOptions paired with a non-range algorithm and accepts it with range
unittest {
	import std.exception : assertThrown;

	EncryptOptions wrongAlgorithm;
	wrongAlgorithm.algorithm = EncryptionAlgorithm.deterministic;
	wrongAlgorithm.keyAltName = "age-key";
	wrongAlgorithm.rangeOptions = RangeOptions.init;
	assertThrown(wrongAlgorithm.validate());

	EncryptOptions rangeAlgorithm;
	rangeAlgorithm.algorithm = EncryptionAlgorithm.range;
	rangeAlgorithm.keyAltName = "age-key";
	rangeAlgorithm.rangeOptions = RangeOptions.init;
	rangeAlgorithm.validate();
}

// validate() rejects contentionFactor with a deterministic algorithm and accepts it with indexed
unittest {
	import std.exception : assertThrown;

	EncryptOptions deterministic;
	deterministic.algorithm = EncryptionAlgorithm.deterministic;
	deterministic.keyAltName = "ssn-key";
	deterministic.contentionFactor = 8L;
	assertThrown(deterministic.validate());

	EncryptOptions indexed;
	indexed.algorithm = EncryptionAlgorithm.indexed;
	indexed.keyAltName = "ssn-key";
	indexed.contentionFactor = 8L;
	indexed.validate();
}

// DataKeyOptions carries masterKey, keyAltNames and optional keyMaterial
unittest {
	import std.typecons : Nullable;

	DataKeyOptions options;
	options.masterKey = Bson(["region": Bson("us-east-1"), "key": Bson("arn:aws:kms:...")]);
	options.keyAltNames = ["ssn-key", "primary-key"];
	options.keyMaterial = BsonBinData(BsonBinData.Type.generic, cast(immutable(ubyte)[]) "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");

	assert(options.masterKey["region"].get!string == "us-east-1");
	assert(options.keyAltNames == ["ssn-key", "primary-key"]);
	assert(!options.keyMaterial.isNull);
}

/// The BSON binary subtype (0x06) tagging a client-side-encrypted field payload.
enum BsonBinData.Type encryptedBinarySubtype = cast(BsonBinData.Type) 0x06;

// encryptedBinarySubtype is the 0x06 BSON binary subtype tagging an encrypted payload
unittest {
	assert(encryptedBinarySubtype == 6);
	immutable(ubyte)[] cipher = [1, 2, 3];
	auto payload = BsonBinData(encryptedBinarySubtype, cipher);
	assert(payload.type == encryptedBinarySubtype);
}

/**
	Backend that performs the actual CSFLE cryptographic operations (normally
	backed by the native libmongocrypt library). Inject an implementation into
	`ClientEncryption` to enable encryption; without one, the crypto methods throw.
*/
interface MongoCryptProvider {
@safe:
	BsonBinData encrypt(Bson value, EncryptOptions options);
	Bson decrypt(BsonBinData value);
	BsonBinData createDataKey(string kmsProvider, DataKeyOptions options);
}

/**
	Seam to the key-vault collection that stores the data encryption keys. A real
	implementation wraps the `keyVaultNamespace` collection; inject one into
	`ClientEncryption` to have `createDataKey` write each new key through it.
*/
interface KeyVault {
@safe:
	void insertDataKey(Bson keyDocument);
	Nullable!Bson findDataKeyByAltName(string altName);
}

/**
	Explicit client-side field level encryption entry point.

	The crypto methods delegate to the injected `MongoCryptProvider`; if none was
	provided they throw a libmongocrypt-required error.
*/
class ClientEncryption {
@safe:
	private string m_keyVaultNamespace;
	private Bson[string] m_kmsProviders;
	private MongoCryptProvider m_provider;
	private KeyVault m_keyVault;

	this(string keyVaultNamespace, Bson[string] kmsProviders, MongoCryptProvider provider = null, KeyVault keyVault = null) {
		m_keyVaultNamespace = keyVaultNamespace;
		m_kmsProviders = kmsProviders;
		m_provider = provider;
		m_keyVault = keyVault;
	}

	/// Encrypts a single value. Delegates to the injected provider, or throws if none is set.
	BsonBinData encrypt(Bson value, EncryptOptions options) {
		options.validate();
		resolveKeyAltName(options);
		requireProvider("encrypt");
		return m_provider.encrypt(value, options);
	}

	/// Decrypts a single encrypted payload back to plaintext. Delegates to the injected provider, or throws if none is set.
	Bson decrypt(BsonBinData value) {
		requireProvider("decrypt");
		return m_provider.decrypt(value);
	}

	/// Creates a new data encryption key and returns its id. Delegates to the injected provider, or throws if none is set.
	BsonBinData createDataKey(string kmsProvider, DataKeyOptions options = DataKeyOptions.init) {
		import std.exception : enforce;
		enforce(kmsProvider in m_kmsProviders,
			"createDataKey: KMS provider '" ~ kmsProvider ~ "' is not configured");
		requireProvider("createDataKey");
		auto keyId = m_provider.createDataKey(kmsProvider, options);
		if (m_keyVault !is null)
			m_keyVault.insertDataKey(buildDataKeyDocument(keyId, options));
		return keyId;
	}

	private void requireProvider(string op) @safe {
		if (m_provider is null)
			throw libmongocryptRequired(op);
	}

	/// Resolves a keyAltName selector to its keyId via the key vault, leaving keyId-based options untouched.
	private void resolveKeyAltName(ref EncryptOptions options) @safe {
		if (options.keyAltName.isNull || m_keyVault is null)
			return;
		auto keyDoc = m_keyVault.findDataKeyByAltName(options.keyAltName.get);
		if (keyDoc.isNull)
			return;
		options.keyId = keyDoc.get["_id"].get!BsonBinData;
		options.keyAltName = Nullable!string.init;
	}
}

private Bson buildDataKeyDocument(BsonBinData keyId, DataKeyOptions options) @safe {
	import std.algorithm : map;
	import std.array : array;
	return Bson([
		"_id": Bson(keyId),
		"keyAltNames": Bson(options.keyAltNames.map!(name => Bson(name)).array)
	]);
}

private Exception libmongocryptRequired(string op) @safe {
	return new Exception("ClientEncryption." ~ op ~ " requires the native libmongocrypt library, which is not available in this build");
}

// ClientEncryption.encrypt delegates to an injected MongoCryptProvider
unittest {
	static class FakeCryptProvider : MongoCryptProvider {
	@safe:
		BsonBinData encrypt(Bson value, EncryptOptions options) {
			immutable(ubyte)[] cipher = ['E', 'N', 'C'];
			return BsonBinData(encryptedBinarySubtype, cipher);
		}
		Bson decrypt(BsonBinData value) { return Bson("plain"); }
		BsonBinData createDataKey(string kmsProvider, DataKeyOptions options) {
			immutable(ubyte)[] keyId = cast(immutable(ubyte)[]) "0123456789abcdef";
			return BsonBinData(BsonBinData.Type.uuid, keyId);
		}
	}

	auto provider = new FakeCryptProvider();
	auto ce = new ClientEncryption("encryption.__keyVault",
		["local": Bson(["key": Bson("k")])], provider);

	EncryptOptions opts;
	opts.algorithm = EncryptionAlgorithm.deterministic;
	opts.keyAltName = "ssn-key";

	auto cipher = ce.encrypt(Bson("secret-value"), opts);
	assert(cipher.type == encryptedBinarySubtype);
}

// ClientEncryption.encrypt rejects EncryptOptions with neither key selector before delegating
unittest {
	import std.exception : assertThrown;

	static class PermissiveCryptProvider : MongoCryptProvider {
	@safe:
		BsonBinData encrypt(Bson value, EncryptOptions options) {
			immutable(ubyte)[] cipher = ['x'];
			return BsonBinData(encryptedBinarySubtype, cipher);
		}
		Bson decrypt(BsonBinData value) { return Bson.init; }
		BsonBinData createDataKey(string kmsProvider, DataKeyOptions options) {
			immutable(ubyte)[] keyId = ['k'];
			return BsonBinData(BsonBinData.Type.uuid, keyId);
		}
	}

	auto ce = new ClientEncryption("encryption.__keyVault",
		["local": Bson(["key": Bson("k")])], new PermissiveCryptProvider());

	EncryptOptions invalid;
	invalid.algorithm = EncryptionAlgorithm.deterministic;

	assertThrown(ce.encrypt(Bson("secret"), invalid));
}

// ClientEncryption.encrypt throws a libmongocrypt-requirement error
unittest {
	import std.exception : collectException;
	import std.algorithm : canFind;

	auto ce = new ClientEncryption("encryption.__keyVault",
		["local": Bson(["key": Bson("base64-master-key")])]);

	EncryptOptions opts;
	opts.algorithm = EncryptionAlgorithm.deterministic;
	opts.keyAltName = "ssn-key";

	auto ex = collectException(ce.encrypt(Bson("secret-value"), opts));
	assert(ex !is null, "encrypt() should throw without libmongocrypt");
	assert(ex.msg.canFind("libmongocrypt"), "error should mention libmongocrypt, got: " ~ ex.msg);
}

// ClientEncryption.decrypt and createDataKey throw the same libmongocrypt-requirement error
unittest {
	import std.exception : collectException;
	import std.algorithm : canFind;

	auto ce = new ClientEncryption("encryption.__keyVault",
		["local": Bson(["key": Bson("base64-master-key")])]);

	immutable(ubyte)[] cipher = [1, 2, 3];
	auto decryptError = collectException(ce.decrypt(BsonBinData(encryptedBinarySubtype, cipher)));
	assert(decryptError !is null, "decrypt() should throw without libmongocrypt");
	assert(decryptError.msg.canFind("libmongocrypt"), "error should mention libmongocrypt, got: " ~ decryptError.msg);

	auto createKeyError = collectException(ce.createDataKey("local"));
	assert(createKeyError !is null, "createDataKey() should throw without libmongocrypt");
	assert(createKeyError.msg.canFind("libmongocrypt"), "error should mention libmongocrypt, got: " ~ createKeyError.msg);
}

// ClientEncryption.decrypt delegates to an injected MongoCryptProvider
unittest {
	static class FakeCryptProvider : MongoCryptProvider {
	@safe:
		BsonBinData encrypt(Bson value, EncryptOptions options) {
			immutable(ubyte)[] cipher = ['E', 'N', 'C'];
			return BsonBinData(encryptedBinarySubtype, cipher);
		}
		Bson decrypt(BsonBinData value) { return Bson("decrypted-value"); }
		BsonBinData createDataKey(string kmsProvider, DataKeyOptions options) {
			immutable(ubyte)[] keyId = ['k'];
			return BsonBinData(BsonBinData.Type.uuid, keyId);
		}
	}

	auto ce = new ClientEncryption("encryption.__keyVault",
		["local": Bson(["key": Bson("k")])], new FakeCryptProvider());

	immutable(ubyte)[] cipher = ['E', 'N', 'C'];
	auto plain = ce.decrypt(BsonBinData(encryptedBinarySubtype, cipher));
	assert(plain == Bson("decrypted-value"));
}

// ClientEncryption.createDataKey delegates to an injected MongoCryptProvider
unittest {
	static class FakeCryptProvider : MongoCryptProvider {
	@safe:
		BsonBinData encrypt(Bson value, EncryptOptions options) {
			immutable(ubyte)[] cipher = ['E', 'N', 'C'];
			return BsonBinData(encryptedBinarySubtype, cipher);
		}
		Bson decrypt(BsonBinData value) { return Bson("plain"); }
		BsonBinData createDataKey(string kmsProvider, DataKeyOptions options) {
			immutable(ubyte)[] keyId = cast(immutable(ubyte)[]) "0123456789abcdef";
			return BsonBinData(BsonBinData.Type.uuid, keyId);
		}
	}

	auto ce = new ClientEncryption("encryption.__keyVault",
		["local": Bson(["key": Bson("k")])], new FakeCryptProvider());

	DataKeyOptions dko;
	dko.masterKey = Bson(["provider": Bson("local")]);
	auto keyId = ce.createDataKey("local", dko);
	assert(keyId.type == BsonBinData.Type.uuid);
}

// ClientEncryption.createDataKey inserts the generated data-key document into the injected key vault
unittest {
	static class FakeCryptProvider : MongoCryptProvider {
	@safe:
		BsonBinData encrypt(Bson value, EncryptOptions options) {
			immutable(ubyte)[] cipher = ['E', 'N', 'C'];
			return BsonBinData(encryptedBinarySubtype, cipher);
		}
		Bson decrypt(BsonBinData value) { return Bson("plain"); }
		BsonBinData createDataKey(string kmsProvider, DataKeyOptions options) {
			immutable(ubyte)[] keyId = cast(immutable(ubyte)[]) "0123456789abcdef";
			return BsonBinData(BsonBinData.Type.uuid, keyId);
		}
	}

	static class FakeKeyVault : KeyVault {
	@safe:
		Bson[] insertedKeys;
		void insertDataKey(Bson keyDocument) {
			insertedKeys ~= keyDocument;
		}
		Nullable!Bson findDataKeyByAltName(string altName) { return typeof(return).init; }
	}

	auto keyVault = new FakeKeyVault();
	auto ce = new ClientEncryption("encryption.__keyVault",
		["local": Bson(["key": Bson("k")])], new FakeCryptProvider(), keyVault);

	ce.createDataKey("local");
	assert(keyVault.insertedKeys.length == 1, "createDataKey should insert exactly one data-key document into the key vault");
}

// ClientEncryption.createDataKey records DataKeyOptions.keyAltNames in the inserted key-vault document
unittest {
	import std.algorithm : map;
	import std.array : array;

	static class FakeCryptProvider : MongoCryptProvider {
	@safe:
		BsonBinData encrypt(Bson value, EncryptOptions options) {
			immutable(ubyte)[] cipher = ['E', 'N', 'C'];
			return BsonBinData(encryptedBinarySubtype, cipher);
		}
		Bson decrypt(BsonBinData value) { return Bson("plain"); }
		BsonBinData createDataKey(string kmsProvider, DataKeyOptions options) {
			immutable(ubyte)[] keyId = cast(immutable(ubyte)[]) "0123456789abcdef";
			return BsonBinData(BsonBinData.Type.uuid, keyId);
		}
	}

	static class FakeKeyVault : KeyVault {
	@safe:
		Bson[] insertedKeys;
		void insertDataKey(Bson keyDocument) {
			insertedKeys ~= keyDocument;
		}
		Nullable!Bson findDataKeyByAltName(string altName) { return typeof(return).init; }
	}

	auto keyVault = new FakeKeyVault();
	auto ce = new ClientEncryption("encryption.__keyVault",
		["local": Bson(["key": Bson("k")])], new FakeCryptProvider(), keyVault);

	DataKeyOptions options;
	options.keyAltNames = ["ssn-key"];
	ce.createDataKey("local", options);

	auto altNames = keyVault.insertedKeys[0]["keyAltNames"].get!(Bson[]).map!(name => name.get!string).array;
	assert(altNames == ["ssn-key"], "inserted key document should carry keyAltNames");
}

// ClientEncryption.createDataKey rejects a kmsProvider name not in the configured kmsProviders
unittest {
	import std.exception : assertThrown;

	static class FakeCryptProvider : MongoCryptProvider {
	@safe:
		BsonBinData encrypt(Bson value, EncryptOptions options) {
			immutable(ubyte)[] cipher = ['E', 'N', 'C'];
			return BsonBinData(encryptedBinarySubtype, cipher);
		}
		Bson decrypt(BsonBinData value) { return Bson("plain"); }
		BsonBinData createDataKey(string kmsProvider, DataKeyOptions options) {
			immutable(ubyte)[] keyId = cast(immutable(ubyte)[]) "0123456789abcdef";
			return BsonBinData(BsonBinData.Type.uuid, keyId);
		}
	}

	static class FakeKeyVault : KeyVault {
	@safe:
		Bson[] insertedKeys;
		void insertDataKey(Bson keyDocument) {
			insertedKeys ~= keyDocument;
		}
		Nullable!Bson findDataKeyByAltName(string altName) { return typeof(return).init; }
	}

	auto keyVault = new FakeKeyVault();
	auto ce = new ClientEncryption("encryption.__keyVault",
		["local": Bson(["key": Bson("k")])], new FakeCryptProvider(), keyVault);

	assertThrown(ce.createDataKey("aws"));
}

// ClientEncryption.encrypt resolves keyAltName to the key vault's keyId before delegating to the provider
unittest {
	immutable(ubyte)[] uuidBytes = cast(immutable(ubyte)[]) "fedcba9876543210";
	auto resolvedKeyId = BsonBinData(BsonBinData.Type.uuid, uuidBytes);

	static class LookupKeyVault : KeyVault {
	@safe:
		Nullable!Bson findDataKeyByAltName(string altName) {
			immutable(ubyte)[] keyBytes = cast(immutable(ubyte)[]) "fedcba9876543210";
			if (altName == "ssn-key")
				return Nullable!Bson(Bson(["_id": Bson(BsonBinData(BsonBinData.Type.uuid, keyBytes))]));
			return Nullable!Bson.init;
		}
		void insertDataKey(Bson keyDocument) {}
	}

	static class RecordingProvider : MongoCryptProvider {
	@safe:
		EncryptOptions lastOptions;
		BsonBinData encrypt(Bson value, EncryptOptions options) {
			lastOptions = options;
			immutable(ubyte)[] cipher = ['E', 'N', 'C'];
			return BsonBinData(encryptedBinarySubtype, cipher);
		}
		Bson decrypt(BsonBinData value) { return Bson("plain"); }
		BsonBinData createDataKey(string kmsProvider, DataKeyOptions options) {
			immutable(ubyte)[] keyId = cast(immutable(ubyte)[]) "0123456789abcdef";
			return BsonBinData(BsonBinData.Type.uuid, keyId);
		}
	}

	auto provider = new RecordingProvider();
	auto ce = new ClientEncryption("encryption.__keyVault",
		["local": Bson(["key": Bson("k")])], provider, new LookupKeyVault());

	EncryptOptions opts;
	opts.algorithm = EncryptionAlgorithm.deterministic;
	opts.keyAltName = "ssn-key";

	ce.encrypt(Bson("secret"), opts);

	assert(!provider.lastOptions.keyId.isNull, "encrypt should resolve keyAltName to a keyId via the key vault");
	assert(provider.lastOptions.keyId.get == resolvedKeyId, "encrypt should pass the vault-resolved keyId to the provider");
}
