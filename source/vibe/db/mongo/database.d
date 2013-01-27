/**
 * MongoDatabase class representing common database for group of collections.
 * Technically it is very special collection with common query functions
 * disabled and some service commands provided.
 */
module vibe.db.mongo.database;

import vibe.db.mongo.client;
import vibe.db.mongo.collection;
import vibe.data.bson;

struct MongoDatabase
{ 
	private:
		string m_name;
		MongoClient m_client;

package:
		// http://www.mongodb.org/display/DOCS/Commands
		Bson runCommand(Bson commandAndOptions)
		{
			return m_client.getCollection(m_name ~ ".$cmd").findOne(commandAndOptions);
		}

	public:
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

		@property string name()
		{
			return m_name;
		}

		@property MongoClient client()
		{
			return m_client;
		}

		/**
		 * Returns: child collection of this database named "name"
		 */
		MongoCollection opIndex(string name)
		{
			return MongoCollection(this, name);
		}

		/**
		 * Returns: struct storing data from MongoDB db.getLastErrorObj() object
		 *
		 * Exact object format is not documented. MongoErrorDescription signature will be
		 * updated upon any issues. Note that this method will execute a query to service
		 * collection and thus is far from being "free".
	 	*/
		MongoErrorDescription getLastError()
		{
			return m_client.lockConnection().getLastError(m_name);
		}

		/* See $(LINK http://www.mongodb.org/display/DOCS/getLog+Command)
         *
		 * Returns: Bson document with recent log messages from MongoDB service.
		 * Params:
		 *  mask = "global" or "rs" or "startupWarnings". Refer to official MongoDB docs.
	 	 */
		Bson getLog(string mask)
		{
			return runCommand(Bson(["getLog" : Bson(mask)]));
		}

		/* See $(LINK http://www.mongodb.org/display/DOCS/fsync+Command)
         *
		 * Returns: check documentation
	 	 */
		Bson fsync(bool async = false)
		{
			return runCommand(Bson(["fsync" : Bson(1), "async" : Bson(async)]));
		}	
}
