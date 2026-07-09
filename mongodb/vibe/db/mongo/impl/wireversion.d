/**
	MongoDB wire-version compatibility: the wire version enum, the UDAs that mark
	option fields with version constraints, and the routine that enforces them.

	Kept in a dedicated leaf module so the option modules (crud, index) and the
	driver modules can share it without an import cycle.

	Copyright: © 2020-2022 Jan Jurzitza
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Jurzitza
*/
module vibe.db.mongo.impl.wireversion;

import std.conv : to;
import std.format : format;
import std.traits : getUDAs;
import std.typecons : Nullable;

import vibe.core.log;
import vibe.data.bson;
import vibe.db.mongo.connection : MongoException;

enum WireVersion : int
{
	old = 0,
	v26 = 1,
	v26_2 = 2,
	v30 = 3,
	v32 = 4,
	v34 = 5,
	v36 = 6,
	v40 = 7,
	v42 = 8,
	v44 = 9,
	v49 = 12,
	v50 = 13,
	v51 = 14,
	v52 = 15,
	v53 = 16,
	v60 = 17,
	v61 = 18,
	v62 = 19,
	v70 = 21,
	v71 = 22,
	v72 = 23,
	v73 = 24,
	v80 = 25
}

/// UDA to unset a nullable field if the server wire version doesn't at least
/// match the given version. (inclusive)
///
/// Use with $(LREF enforceWireVersionConstraints)
struct MinWireVersion
{
	///
	WireVersion v;
}

/// ditto
MinWireVersion since(WireVersion v) @safe { return MinWireVersion(v); }

/// UDA to warn when a nullable field is set and the server wire version matches
/// the given version. (inclusive)
///
/// Use with $(LREF enforceWireVersionConstraints)
struct DeprecatedSinceWireVersion
{
	///
	WireVersion v;
}

/// ditto
DeprecatedSinceWireVersion deprecatedSince(WireVersion v) @safe { return DeprecatedSinceWireVersion(v); }

/// UDA to throw a MongoException when a nullable field is set and the server
/// wire version doesn't match the version. (inclusive)
///
/// Use with $(LREF enforceWireVersionConstraints)
struct ErrorBeforeWireVersion
{
	///
	WireVersion v;
}

/// ditto
ErrorBeforeWireVersion errorBefore(WireVersion v) @safe { return ErrorBeforeWireVersion(v); }

/// UDA to unset a nullable field if the server wire version is newer than the
/// given version. (inclusive)
///
/// Use with $(LREF enforceWireVersionConstraints)
struct MaxWireVersion
{
	///
	WireVersion v;
}
/// ditto
MaxWireVersion until(WireVersion v) @safe { return MaxWireVersion(v); }

/// Unsets nullable fields not matching the server version as defined per UDAs.
void enforceWireVersionConstraints(T)(ref T field, int serverVersion,
	string file = __FILE__, size_t line = __LINE__)
@safe {
	import std.traits : getUDAs;

	string exception;

	foreach (i, ref v; field.tupleof) {
		enum minV = getUDAs!(field.tupleof[i], MinWireVersion);
		enum maxV = getUDAs!(field.tupleof[i], MaxWireVersion);
		enum deprecateV = getUDAs!(field.tupleof[i], DeprecatedSinceWireVersion);
		enum errorV = getUDAs!(field.tupleof[i], ErrorBeforeWireVersion);

		static foreach (depr; deprecateV)
			if (serverVersion >= depr.v && !v.isNull)
				logInfo("User-set field '%s' is deprecated since MongoDB %s (from %s:%s)",
					T.tupleof[i].stringof, depr.v, file, line);

		static foreach (err; errorV)
			if (serverVersion < err.v && !v.isNull)
				exception ~= format("User-set field '%s' is not supported before MongoDB %s\n",
					T.tupleof[i].stringof, err.v);

		static foreach (min; minV)
			if (serverVersion < min.v)
				v.nullify();

		static foreach (max; maxV)
			if (serverVersion > max.v)
				v.nullify();
	}

	if (exception.length)
		throw new MongoException(exception ~ "from " ~ file ~ ":" ~ line.to!string);
}

version (unittest)
{
	struct SinceUntilCmd
	{
		@embedNullable @since(WireVersion.v34)
		Nullable!int a;

		@embedNullable @until(WireVersion.v30)
		Nullable!int b;
	}

	struct ErrorBeforeCmd
	{
		@embedNullable @errorBefore(WireVersion.v44)
		Nullable!int field;
	}

	struct DeprecatedCmd
	{
		@embedNullable @deprecatedSince(WireVersion.v40)
		Nullable!int oldField;
	}

	struct CombinedCmd
	{
		@embedNullable @errorBefore(WireVersion.v44)
		Nullable!bool allowDiskUse;

		@embedNullable @since(WireVersion.v32)
		Nullable!long maxAwaitTimeMS;

		@embedNullable @deprecatedSince(WireVersion.v40)
		Nullable!long maxScan;
	}

	struct SinceDeprecatedCmd
	{
		@embedNullable @since(WireVersion.v32)
		Nullable!long maxAwaitTimeMS;

		@embedNullable @deprecatedSince(WireVersion.v40)
		Nullable!long maxScan;
	}
}

/// @since nullifies field when server version is below minimum
@safe unittest
{
	SinceUntilCmd cmd;
	cmd.a = 1;
	cmd.b = 2;

	auto test = cmd;
	enforceWireVersionConstraints(test, WireVersion.v30);
	assert(test.a.isNull);
	assert(!test.b.isNull);
}

/// @until nullifies field when server version exceeds maximum
@safe unittest
{
	SinceUntilCmd cmd;
	cmd.a = 1;
	cmd.b = 2;

	auto test = cmd;
	enforceWireVersionConstraints(test, WireVersion.v32);
	assert(test.a.isNull);
	assert(test.b.isNull);
}

/// @since preserves field when server version meets minimum
@safe unittest
{
	SinceUntilCmd cmd;
	cmd.a = 1;
	cmd.b = 2;

	auto test = cmd;
	enforceWireVersionConstraints(test, WireVersion.v34);
	assert(!test.a.isNull);
	assert(test.b.isNull);
}

/// @errorBefore throws when field is set and server version is below threshold
@safe unittest
{
	ErrorBeforeCmd cmd;
	cmd.field = 42;
	try {
		enforceWireVersionConstraints(cmd, WireVersion.v40);
		assert(false, "Should have thrown");
	} catch (MongoException e) {
	}
}

/// @errorBefore does not throw when field is set and server version is at threshold
@safe unittest
{
	ErrorBeforeCmd cmd;
	cmd.field = 42;
	enforceWireVersionConstraints(cmd, WireVersion.v44);
	assert(!cmd.field.isNull);
}

/// @errorBefore does not throw when field is set and server version is above threshold
@safe unittest
{
	ErrorBeforeCmd cmd;
	cmd.field = 42;
	enforceWireVersionConstraints(cmd, WireVersion.v60);
	assert(!cmd.field.isNull);
}

/// @errorBefore does not throw when field is not set
@safe unittest
{
	ErrorBeforeCmd cmd;
	enforceWireVersionConstraints(cmd, WireVersion.v30);
	assert(cmd.field.isNull);
}

/// @deprecatedSince preserves field and only logs at deprecated version
@safe unittest
{
	DeprecatedCmd cmd;
	cmd.oldField = 10;
	enforceWireVersionConstraints(cmd, WireVersion.v40);
	assert(!cmd.oldField.isNull);
	assert(cmd.oldField.get == 10);
}

/// @deprecatedSince preserves field above deprecated version
@safe unittest
{
	DeprecatedCmd cmd;
	cmd.oldField = 10;
	enforceWireVersionConstraints(cmd, WireVersion.v60);
	assert(!cmd.oldField.isNull);
}

/// @deprecatedSince preserves field below deprecated version without warning
@safe unittest
{
	DeprecatedCmd cmd;
	cmd.oldField = 10;
	enforceWireVersionConstraints(cmd, WireVersion.v36);
	assert(!cmd.oldField.isNull);
}

/// @deprecatedSince does nothing when field is not set
@safe unittest
{
	DeprecatedCmd cmd;
	enforceWireVersionConstraints(cmd, WireVersion.v60);
	assert(cmd.oldField.isNull);
}

/// Combined UDAs where @errorBefore throws while @since and @deprecatedSince still apply
@safe unittest
{
	CombinedCmd cmd;
	cmd.allowDiskUse = true;
	cmd.maxAwaitTimeMS = 5000;
	cmd.maxScan = 100;

	auto t1 = cmd;
	try {
		enforceWireVersionConstraints(t1, WireVersion.v30);
		assert(false, "Should have thrown due to errorBefore(v44)");
	} catch (MongoException e) {
	}
}

/// Combined UDAs with all fields valid at v44, @deprecatedSince only logs
@safe unittest
{
	CombinedCmd cmd;
	cmd.allowDiskUse = true;
	cmd.maxAwaitTimeMS = 5000;
	cmd.maxScan = 100;

	enforceWireVersionConstraints(cmd, WireVersion.v44);
	assert(!cmd.allowDiskUse.isNull);
	assert(!cmd.maxAwaitTimeMS.isNull);
	assert(!cmd.maxScan.isNull);
}

/// Combined UDAs where @since nullifies field below minimum while others are independent
@safe unittest
{
	SinceDeprecatedCmd cmd;
	cmd.maxAwaitTimeMS = 5000;
	cmd.maxScan = 100;

	enforceWireVersionConstraints(cmd, WireVersion.v30);
	assert(cmd.maxAwaitTimeMS.isNull);
	assert(!cmd.maxScan.isNull);
}

/// Combined UDAs where @since preserves field at sufficient version
@safe unittest
{
	SinceDeprecatedCmd cmd;
	cmd.maxAwaitTimeMS = 5000;
	cmd.maxScan = 100;

	enforceWireVersionConstraints(cmd, WireVersion.v34);
	assert(!cmd.maxAwaitTimeMS.isNull);
	assert(!cmd.maxScan.isNull);
}
