/**
	MongoDB Stable API (Versioned API) command decoration.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.serverapi;

import std.typecons : Nullable;
import vibe.data.bson;

@safe:

/// The MongoDB Stable API version. (`version` is a D keyword, so the field/type avoid it.)
enum ServerApiVersion : string { v1 = "1" }

/// Stable API (Versioned API) configuration.
struct ServerApi
{
	ServerApiVersion apiVersion;
	Nullable!bool strict;
	Nullable!bool deprecationErrors;
}

/** Assembles and validates a Stable API config from parsed URL options.

	Returns false for an unsupported apiVersion or when apiStrict/apiDeprecationErrors
	appear without apiVersion. On success, `result` holds the config (null when no
	Stable API option was present).
*/
bool buildServerApi(bool sawApiVersion, string apiVersionValue,
	Nullable!bool strict, Nullable!bool deprecationErrors,
	out Nullable!ServerApi result) @safe
{
	if (!sawApiVersion)
		return strict.isNull && deprecationErrors.isNull;

	if (apiVersionValue != ServerApiVersion.v1)
		return false;

	ServerApi api;
	api.apiVersion = ServerApiVersion.v1;
	api.strict = strict;
	api.deprecationErrors = deprecationErrors;
	result = api;
	return true;
}

/// buildServerApi yields a v1 config when apiVersion=1 is present.
unittest
{
	Nullable!ServerApi result;
	assert(buildServerApi(true, "1", Nullable!bool.init, Nullable!bool.init, result));
	assert(!result.isNull, "apiVersion populates the config");
	assert(result.get.apiVersion == ServerApiVersion.v1, "apiVersion=1 selects v1");
}

/// buildServerApi rejects an unsupported apiVersion value.
unittest
{
	Nullable!ServerApi result;
	assert(!buildServerApi(true, "2", Nullable!bool.init, Nullable!bool.init, result),
		"apiVersion other than 1 is rejected");
}

/// buildServerApi carries strict and deprecationErrors onto the config.
unittest
{
	Nullable!ServerApi result;
	assert(buildServerApi(true, "1", Nullable!bool(true), Nullable!bool(true), result));
	assert(result.get.strict.get == true, "strict flag carried through");
	assert(result.get.deprecationErrors.get == true, "deprecationErrors flag carried through");
}

/// buildServerApi rejects strict or deprecationErrors without apiVersion.
unittest
{
	Nullable!ServerApi result;
	assert(!buildServerApi(false, "", Nullable!bool(true), Nullable!bool.init, result),
		"apiStrict without apiVersion is rejected");
	assert(!buildServerApi(false, "", Nullable!bool.init, Nullable!bool(true), result),
		"apiDeprecationErrors without apiVersion is rejected");
}

/// buildServerApi leaves the config null when no Stable API option is present.
unittest
{
	Nullable!ServerApi result;
	assert(buildServerApi(false, "", Nullable!bool.init, Nullable!bool.init, result),
		"absence of all Stable API options is valid");
	assert(result.isNull, "no config produced when nothing was set");
}

/// Attaches the Stable API fields to a command (apiVersion always; strict/deprecationErrors when set).
Bson applyServerApi(Bson command, ServerApi api) @safe
{
	Bson result = command;
	result["apiVersion"] = Bson(cast(string) api.apiVersion);
	if (!api.strict.isNull)
		result["apiStrict"] = Bson(api.strict.get);
	if (!api.deprecationErrors.isNull)
		result["apiDeprecationErrors"] = Bson(api.deprecationErrors.get);
	return result;
}

/// Overload for optional configs. Applies the Stable API fields only when a config is present.
Bson applyServerApi(Bson command, Nullable!ServerApi api) @safe
{
	return api.isNull ? command : applyServerApi(command, api.get);
}

/// applyServerApi attaches the configured apiVersion to the command.
unittest
{
	Bson cmd = Bson.emptyObject;
	cmd["find"] = Bson("people");

	auto result = applyServerApi(cmd, ServerApi(ServerApiVersion.v1));

	assert(result["apiVersion"] == Bson("1"),
		"applyServerApi attaches apiVersion 1");
}

/// applyServerApi attaches apiStrict true when strict is set.
unittest
{
	auto api = ServerApi(ServerApiVersion.v1);
	api.strict = true;

	Bson cmd = Bson.emptyObject;
	cmd["find"] = Bson("people");

	auto result = applyServerApi(cmd, api);

	assert(result["apiStrict"].get!bool == true,
		"applyServerApi attaches apiStrict when strict is set");
}

/// applyServerApi attaches apiDeprecationErrors true when deprecationErrors is set.
unittest
{
	auto api = ServerApi(ServerApiVersion.v1);
	api.deprecationErrors = true;

	Bson cmd = Bson.emptyObject;
	cmd["find"] = Bson("people");

	auto result = applyServerApi(cmd, api);

	assert(result["apiDeprecationErrors"].get!bool == true,
		"applyServerApi attaches apiDeprecationErrors when set");
}

/// applyServerApi with no config leaves the command unchanged.
unittest
{
	Bson cmd = Bson.emptyObject;
	cmd["find"] = Bson("people");

	auto result = applyServerApi(cmd, Nullable!ServerApi.init);

	assert(result["apiVersion"].type == Bson.Type.null_,
		"no server API config leaves the command unchanged");
	assert(result["find"] == Bson("people"),
		"the original command is preserved when no config");
}
