/**
	MongoDB authentication mechanisms

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Christian Schneider
*/
module vibe.db.mongo.auth;

import vibe.data.bson;
import vibe.db.mongo.connection;

import std.string;
import std.digest.md;


class MongoAuthCR : IMongoAuthenticator
{
  package this() {}
  @property string name() { return "MONGODB-CR"; }

  void authenticate(MongoConnection connection, string username, string digest, string database = "admin")
  {
    Reply rep;
    Bson cmd, doc;
    string cn = (database == string.init ? "admin" : database) ~ ".$cmd";

    cmd = Bson(["getnonce":Bson(1)]);
    rep = connection.query(cn, QueryFlags.None, 0, -1, cmd);
    if ((rep.flags & ReplyFlags.QueryFailure) || rep.documents.length != 1)
    {
      throw new MongoDriverException("Calling getNonce failed.");
    }
    doc = rep.documents[0];
    if (doc["ok"].get!double != 1.0)
    {
      throw new MongoDriverException("getNonce failed.");
    }
    string nonce = doc["nonce"].get!string;
    string key = toLower(toHexString(md5Of(nonce ~ username ~ digest)).idup);
    cmd = Bson.EmptyObject;
    cmd["authenticate"] = Bson(1);
    cmd["nonce"] = Bson(nonce);
    cmd["user"] = Bson(username);
    cmd["key"] = Bson(key);
    rep = connection.query(cn, QueryFlags.None, 0, -1, cmd);
    if ((rep.flags & ReplyFlags.QueryFailure) || rep.documents.length != 1)
    {
      throw new MongoDriverException("Calling authenticate failed.");
    }
    doc = rep.documents[0];
    if (doc["ok"].get!double != 1.0)
    {
      throw new MongoAuthException("Authentication failed.");
    }
  }
}
