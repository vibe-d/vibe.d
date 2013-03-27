/**
	MongoDB authentication adapter

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Christian Schneider
*/
module vibe.db.mongo.auth;
import
  std.string,
  std.digest.md,
  vibe.data.bson,
  vibe.db.mongo.client,
  vibe.db.mongo.database
;

class MongoAuth
{
  private
  {
    MongoClient m_client;
  }

  /**
    Initialize adapter.

    Examples:
      ---
      auto ma = new MongoAuth(mongo);
      bool ok = ma.auth("admin", "guru", "secret");
      ---
   */

  this(MongoClient client)
  {
    m_client = client;
  }

  /**
    Initialize adapter and authenticate this connection.

    Throws:
      Exception if not successfully authenticated.

    Examples:
      ---
      auto ma = new MongoAuth(mongo, "admin", "guru", "secret");
      ---
   */
  this(MongoClient client, string dbname, string username, string password)
  {
    m_client = client;
    bool res = auth(dbname, username, password);
    if (!res) throw new Exception("MongoAuth failed.");
  }

  /**
    Authenticate this connection.

    Examples:
      ---
      auto ma = new MongoAuth(mongo);
      bool ok = ma.auth("admin", "guru", "secret");
      logInfo("auth: %s", ok);
      ---
   */
  bool auth(string dbname, string username, string password)
  {
    auto db = m_client.getDatabase(dbname);
    string nonce = getNonce(db);
    string key = getKey(nonce, username, password);
    Bson cmd = Bson.EmptyObject;
    cmd["authenticate"] = Bson(1);
    cmd["nonce"] = Bson(nonce);
    cmd["user"] = Bson(username);
    cmd["key"] = Bson(key);
    auto res = db.runCommand(cmd);
    if (res["ok"].get!double == 1.0)
      return true;
    return false;
  }

  package string getNonce(MongoDatabase db)
  {
    auto res = db.runCommand(Bson(["getnonce":Bson(1)]));
    return res["nonce"].get!string;
  }

  package string getKey(string nonce, string username, string password)
  {
    return toLower(toHexString(md5Of(nonce ~ username ~ createPasswordDigest(username, password))).idup);
  }

  package string createPasswordDigest(string username, string password)
  {
    return toLower(toHexString(md5Of(username ~ ":mongo:" ~ password)).idup);
  }
}
