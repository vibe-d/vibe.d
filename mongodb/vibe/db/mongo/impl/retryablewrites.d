/**
	Retryable write command classification (Node-driver semantics).

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.retryablewrites;

import vibe.data.bson;

@safe:

/// The command name is the first field of the command document, by MongoDB decree.
string commandName(Bson command)
{
	foreach (string key, value; command.byKeyValue)
		return key;
	return null;
}

/// Whether any entry in a Bson `statements` array satisfies `disqualifies`.
/// A non-array (or missing field) yields false: nothing to disqualify.
bool anyStatement(Bson statements, scope bool delegate(Bson) @safe disqualifies)
{
	import std.algorithm : any;

	if (statements.type != Bson.Type.array)
		return false;

	return statements.byValue.any!disqualifies;
}

/// Whether any statement in an `updates` array is a multi-document update.
bool hasMultiStatement(Bson updates)
{
	return anyStatement(updates,
		entry => entry["multi"].type == Bson.Type.bool_ && entry["multi"].get!bool);
}

/// Whether any statement in a `deletes` array is a multi-document delete (limit:0).
bool hasUnlimitedDelete(Bson deletes)
{
	return anyStatement(deletes,
		entry => entry["limit"].type == Bson.Type.int_ && entry["limit"].get!int == 0);
}

/// classifies a command as a retryable write
bool isRetryableWriteCommand(Bson command)
{
	import std.algorithm : among;

	string name = commandName(command);

	if (!name.among("insert", "update", "delete", "findAndModify"))
		return false;

	if (name == "update" && hasMultiStatement(command["updates"]))
		return false;

	return !(name == "delete" && hasUnlimitedDelete(command["deletes"]));
}

/// Stamps a write command with the session id and retryable txnNumber.
Bson applyRetryableWrite(Bson command, Bson lsid, long txnNumber)
{
	Bson result = command;
	result["lsid"] = lsid;
	result["txnNumber"] = Bson(txnNumber);
	return result;
}

/// commandName returns the first field of the command document
unittest {
	Bson cmd = Bson.emptyObject;
	cmd["insert"] = Bson("people");

	assert(commandName(cmd) == "insert",
		"command name must be the first field of the document");
}

/// anyStatement matches an entry, ignores non-array input
unittest {
	Bson marked = Bson.emptyObject;
	marked["flag"] = Bson(true);

	bool delegate(Bson) @safe matchesFlag =
		(Bson entry) @safe => entry["flag"].type == Bson.Type.bool_;

	assert(anyStatement(Bson([marked]), matchesFlag) == true,
		"a matching entry must be detected");
	assert(anyStatement(Bson([Bson.emptyObject]), matchesFlag) == false,
		"a non-matching entry must not be flagged");
	assert(anyStatement(Bson("not-an-array"), matchesFlag) == false,
		"a non-array must yield false");
}

/// hasMultiStatement flags an updates array containing a multi:true entry
unittest {
	Bson upd = Bson.emptyObject;
	upd["multi"] = Bson(true);

	assert(hasMultiStatement(Bson([upd])) == true,
		"a multi:true update statement must be detected");
	assert(hasMultiStatement(Bson([Bson.emptyObject])) == false,
		"an update statement without multi:true must not be flagged");
}

/// an insert command is a retryable write
unittest {
	Bson cmd = Bson.emptyObject;
	cmd["insert"] = Bson("people");

	assert(isRetryableWriteCommand(cmd) == true,
		"insert must be classified as a retryable write command");
}

/// an update command is a retryable write
unittest {
	Bson cmd = Bson.emptyObject;
	cmd["update"] = Bson("people");

	assert(isRetryableWriteCommand(cmd) == true,
		"update must be classified as a retryable write command");
}

/// a find command is not a retryable write
unittest {
	Bson cmd = Bson.emptyObject;
	cmd["find"] = Bson("people");

	assert(isRetryableWriteCommand(cmd) == false,
		"find must not be classified as a retryable write command");
}

/// a multi:true update command is not a retryable write
unittest {
	Bson upd = Bson.emptyObject;
	upd["q"] = Bson.emptyObject;
	upd["u"] = Bson.emptyObject;
	upd["multi"] = Bson(true);

	Bson cmd = Bson.emptyObject;
	cmd["update"] = Bson("people");
	cmd["updates"] = Bson([upd]);

	assert(isRetryableWriteCommand(cmd) == false,
		"multi:true update must not be classified as a retryable write command");
}

/// a limit:0 delete command (deleteMany) is not a retryable write
unittest {
	Bson del = Bson.emptyObject;
	del["q"] = Bson.emptyObject;
	del["limit"] = Bson(0);

	Bson cmd = Bson.emptyObject;
	cmd["delete"] = Bson("people");
	cmd["deletes"] = Bson([del]);

	assert(isRetryableWriteCommand(cmd) == false,
		"limit:0 delete must not be classified as a retryable write command");
}

/// applyRetryableWrite sets lsid and txnNumber on the command
unittest {
	Bson cmd = Bson.emptyObject;
	cmd["insert"] = Bson("people");

	Bson lsid = Bson.emptyObject;
	lsid["id"] = Bson("session-uuid-bytes");

	auto outCmd = applyRetryableWrite(cmd, lsid, 7);

	assert(outCmd["lsid"] == lsid,
		"the lsid document must be attached to the command");
	assert(outCmd["txnNumber"].get!long == 7,
		"the txnNumber must be attached to the command as a long");
}
