/**
	MongoDatabase class representing common database for group of collections.

	Technically it is very special collection with common query functions
	disabled and some service commands provided.

	Copyright: © 2012-2014 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.database;

import vibe.db.mongo.client;
import vibe.db.mongo.collection;
import vibe.data.bson;

import core.time;

/** Represents a single database accessible through a given MongoClient.
*/
struct MongoDatabase
{
@safe:

	private {
		string m_name;
		MongoClient m_client;
	}

	//@disable this();

	this(MongoClient client, string name)
	{
		import std.algorithm;

		assert(client !is null);
		m_client = client;

		assert(
				!canFind(name, '.'),
				"Compound collection path provided to MongoDatabase constructor instead of single database name"
		  );
		m_name = name;
	}

	/// The name of this database
	@property string name()
	{
		return m_name;
	}

	/// The client which represents the connection to the database server
	@property MongoClient client()
	{
		return m_client;
	}

	/** Accesses the collections of this database.

		Returns: The collection with the given name
	*/
	MongoCollection opIndex(string name)
	{
		return MongoCollection(this, name);
	}

	/** Retrieves the last error code (if any) from the database server.

		Exact object format is not documented. MongoErrorDescription signature will be
		updated upon any issues. Note that this method will execute a query to service
		collection and thus is far from being "free".

		Returns: struct storing data from MongoDB db.getLastErrorObj() object
 	*/
	MongoErrorDescription getLastError()
	{
		return m_client.lockConnection().getLastError(m_name);
	}

	/** Returns recent log messages for this database from the database server.

		See $(LINK http://www.mongodb.org/display/DOCS/getLog+Command).

	 	Params:
	 		mask = "global" or "rs" or "startupWarnings". Refer to official MongoDB docs.

	 	Returns: Bson document with recent log messages from MongoDB service.
 	 */
	Bson getLog(string mask)
	{
		static struct CMD {
			string getLog;
		}
		CMD cmd;
		cmd.getLog = mask;
		return runCommandChecked(cmd);
	}

	/** Performs a filesystem/disk sync of the database on the server.

		This method can only be called on the admin database.

		See $(LINK http://www.mongodb.org/display/DOCS/fsync+Command)

		Returns: check documentation
 	 */
	Bson fsync(bool async = false)
	{
		static struct CMD {
			int fsync = 1;
			bool async;
		}
		CMD cmd;
		cmd.async = async;
		return runCommandChecked(cmd);
	}

	deprecated("use runCommandChecked or runCommandUnchecked instead")
	Bson runCommand(T)(T command_and_options,
		string errorInfo = __FUNCTION__, string errorFile = __FILE__, size_t errorLine = __LINE__)
	{
		return runCommandUnchecked(command_and_options, errorInfo, errorFile, errorLine);
	}

	/** Generic means to run commands on the database.

		See $(LINK http://www.mongodb.org/display/DOCS/Commands) for a list
		of possible values for command_and_options.

		Note that some commands return a cursor instead of a single document.
		In this case, use `runListCommand` instead of `runCommandChecked` or
		`runCommandUnchecked` to be able to properly iterate over the results.

		Usually commands respond with a `double ok` field in them, the `Checked`
		version of this function checks that they equal to `1.0`. The `Unchecked`
		version of this function does not check that parameter.

		With cursor functions on `runListCommand` the error checking is well
		defined.

		Params:
			command_and_options = Bson object containing the command to be executed
				as well as the command parameters as fields

		Returns: The raw response of the MongoDB server
	*/
	Bson runCommandChecked(T, ExceptionT = MongoDriverException)(
		T command_and_options,
		string errorInfo = __FUNCTION__,
		string errorFile = __FILE__,
		size_t errorLine = __LINE__
	)
	{
		Bson cmd;
		static if (is(T : Bson))
			cmd = command_and_options;
		else
			cmd = command_and_options.serializeToBson;
		return m_client.lockConnection().runCommand!(Bson, ExceptionT)(
			m_name, cmd, errorInfo, errorFile, errorLine);
	}

	/// ditto
	Bson runCommandUnchecked(T, ExceptionT = MongoDriverException)(
		T command_and_options,
		string errorInfo = __FUNCTION__,
		string errorFile = __FILE__,
		size_t errorLine = __LINE__
	)
	{
		Bson cmd;
		static if (is(T : Bson))
			cmd = command_and_options;
		else
			cmd = command_and_options.serializeToBson;
		return m_client.lockConnection().runCommandUnchecked!(Bson, ExceptionT)(
			m_name, cmd, errorInfo, errorFile, errorLine);
	}

	/// ditto
	MongoCursor!R runListCommand(R = Bson, T)(T command_and_options, int batchSize = 0, Duration getMoreMaxTime = Duration.max)
	{
		Bson cmd;
		static if (is(T : Bson))
			cmd = command_and_options;
		else
			cmd = command_and_options.serializeToBson;
		cmd["$db"] = Bson(m_name);

		return MongoCursor!R(m_client, cmd, batchSize, getMoreMaxTime);
	}
}
