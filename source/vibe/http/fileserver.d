/**
	A static HTTP file server.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.http.fileserver;

import vibe.core.file;
import vibe.core.log;
import vibe.http.server;
import vibe.inet.message;
import vibe.inet.mimetypes;
import vibe.inet.url;
import vibe.crypto.md5;

import std.conv;
import std.datetime;
import std.file;
import std.string;


/**
	Configuration options for the static file server.
*/
class HttpFileServerSettings {
	string serverPathPrefix = "/";
	long maxAge = 60*60*24; // 24 hours
	bool failIfNotFound = false;

	this() {}

	this( string path_prefix )
	{
		serverPathPrefix = path_prefix;
	}
} 

/**
	Returns a request handler that serves files from the specified directory.
*/
HttpServerRequestDelegate serveStaticFiles(string local_path, HttpFileServerSettings settings = null)
{
	if( !settings ) settings = new HttpFileServerSettings;
	if( !local_path.endsWith("/") ) local_path ~= "/";
	if( !settings.serverPathPrefix.endsWith("/") ) settings.serverPathPrefix ~= "/";

	auto lpath = Path(local_path);

	void callback(HttpServerRequest req, HttpServerResponse res)
	{
		string srv_path;
		if( auto pp = "pathMatch" in req.params ) srv_path = *pp;
		else if( req.path.length > 0 ) srv_path = req.path;
		else srv_path = req.requestUrl;

		if( !srv_path.startsWith(settings.serverPathPrefix) ){
			logDebug("path '%s' not starting with '%s'", srv_path, settings.serverPathPrefix);
			return;
		}
		
		auto rel_path = srv_path[settings.serverPathPrefix.length .. $];
		auto rpath = Path(rel_path);
		logTrace("Processing '%s'", srv_path);
		rpath.normalize();
		logDebug("Path '%s' -> '%s'", rel_path, rpath.toNativeString());
		if( rpath.empty ){
			// TODO: support searching for an index file
			return;
		} else if( rpath[0] == ".." ) return; // don't respond to relative paths outside of the root path

		string path = (lpath ~ rpath).toNativeString();

		// return if the file does not exist
		if( !exists(path) ){
			if( settings.failIfNotFound ) throw new HttpStatusException(HttpStatus.NotFound);
			else return;
		}

		DirEntry dirent;
		try dirent = dirEntry(path);
		catch(FileException){
			throw new HttpStatusException(HttpStatus.InternalServerError, "Failed to get information for the file due to a file system error.");
		}

		auto lastModified = toRFC822DateTimeString(dirent.timeLastModified.toUTC());
		
		if( auto pv = "If-Modified-Since" in req.headers ) {
			if( *pv == lastModified ) {
				res.statusCode = HttpStatus.NotModified;
				res.writeVoidBody();
				return;
			}
		}

		// simple etag generation
		auto etag = "\"" ~ md5(path ~ ":" ~ lastModified ~ ":" ~ to!string(dirent.size)) ~ "\"";
		if( auto pv = "If-None-Match" in req.headers ) {
			if ( *pv == etag ) {
				res.statusCode = HttpStatus.NotModified;
				res.writeVoidBody();
				return;
			}
		}

		res.headers["Etag"] = etag;

		auto mimetype = getMimeTypeForFile(path);
		// avoid double-compression
		if( isCompressedFormat(mimetype) && "Content-Encoding" in res.headers )
			res.headers.remove("Content-Encoding");
		res.headers["Content-Type"] = mimetype;
		res.headers["Content-Length"] = to!string(dirent.size);
		
		res.headers["Last-Modified"] = lastModified;
		if( settings.maxAge > 0 ){
			auto expireTime = Clock.currTime().toUTC() + dur!"seconds"(settings.maxAge);
			res.headers["Expires"] = toRFC822DateTimeString(expireTime);
			res.headers["Cache-Control"] = "max-age="~to!string(settings.maxAge);
		}

		// for HEAD responses, stop here
		if( res.isHeadResponse() ){
			res.writeVoidBody();
			assert(res.headerWritten);
			logDebug("sent file header %d, %s!", dirent.size, res.headers["Content-Type"]);
			return;
		}
		
		// else write out the file contents
		logTrace("Open file '%s' -> '%s'", srv_path, path);
		FileStream fil;
		try {
			fil = openFile(path);
		} catch( Exception e ){
			// TODO: handle non-existant files differently than locked files?
			logDebug("Failed to open file %s: %s", path, e.toString());
			return;
		}
		scope(exit) fil.close();

		if( "Content-Encoding" in res.headers )
			res.bodyWriter.write(fil);
		else res.writeRawBody(fil);
		logTrace("sent file %d, %s!", fil.size, res.headers["Content-Type"]);
	}
	return &callback;
}
