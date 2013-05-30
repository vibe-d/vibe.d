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

import std.conv;
import std.datetime;
import std.digest.md;
import std.file;
import std.string;


/**
	Returns a request handler that serves files from the specified directory.

	See_Also: serveStaticFile
*/
HTTPServerRequestDelegate serveStaticFiles(Path local_path, HTTPFileServerSettings settings = null)
{
	if (!settings) settings = new HTTPFileServerSettings;
	if (!settings.serverPathPrefix.endsWith("/")) settings.serverPathPrefix ~= "/";

	void callback(HTTPServerRequest req, HTTPServerResponse res)
	{
		string srv_path;
		if (auto pp = "pathMatch" in req.params) srv_path = *pp;
		else if (req.path.length > 0) srv_path = req.path;
		else srv_path = req.requestURL;

		if (!srv_path.startsWith(settings.serverPathPrefix)) {
			logDebug("path '%s' not starting with '%s'", srv_path, settings.serverPathPrefix);
			return;
		}
		
		auto rel_path = srv_path[settings.serverPathPrefix.length .. $];
		auto rpath = Path(rel_path);
		logTrace("Processing '%s'", srv_path);
		rpath.normalize();
		logDebug("Path '%s' -> '%s'", rel_path, rpath.toNativeString());
		if (rpath.empty) {
			// TODO: support searching for an index file
			return;
		} else if (rpath[0] == "..") return; // don't respond to relative paths outside of the root path

		sendFile(req, res, local_path ~ rpath, settings);
	}

	return &callback;
}
/// ditto
HTTPServerRequestDelegate serveStaticFiles(string local_path, HTTPFileServerSettings settings = null)
{
	return serveStaticFiles(Path(local_path), settings);
}


/**
	Returns a request handler that serves a specific file on disk.

	See_Also: serveStaticFiles
*/
HTTPServerRequestDelegate serveStaticFile(Path local_path, HTTPFileServerSettings settings = null)
{
	if (!settings) settings = new HTTPFileServerSettings;
	assert(settings.serverPathPrefix == "/", "serverPathPrefix is not supported for single file serving.");

	void callback(HTTPServerRequest req, HTTPServerResponse res)
	{
		sendFile(req, res, local_path, settings);
	}

	return &callback;
}
/// ditto
HTTPServerRequestDelegate serveStaticFile(string local_path, HTTPFileServerSettings settings = null)
{
	return serveStaticFile(Path(local_path), settings);
}


/**
	Configuration options for the static file server.
*/
class HTTPFileServerSettings {
	string serverPathPrefix = "/";
	Duration maxAge = hours(24);
	bool failIfNotFound = false;
	
	/**
		Called just before headers and data are sent.
		Allows headers to be customized, or other custom processing to be performed.

		Note: Any changes you make to the response, physicalPath, or anything
		else during this function will NOT be verified by Vibe.d for correctness.
		Make sure any alterations you make are complete and correct according to HTTP spec.
	*/
	void delegate(HTTPServerRequest req, HTTPServerResponse res, ref string physicalPath) preWriteCallback = null;

	this() {}

	this(string path_prefix)
	{
		serverPathPrefix = path_prefix;
	}
} 

/// Compatibility alias, will be deprecated soon.
alias HttpFileServerSettings = HTTPFileServerSettings;


private void sendFile(HTTPServerRequest req, HTTPServerResponse res, Path path, HTTPFileServerSettings settings)
{
	auto pathstr = path.toNativeString();

	// return if the file does not exist
	if( !exists(pathstr) ){
		if( settings.failIfNotFound ) throw new HTTPStatusException(HTTPStatus.NotFound);
		else return;
	}

	DirEntry dirent;
	try dirent = dirEntry(pathstr);
	catch(FileException){
		throw new HTTPStatusException(HTTPStatus.InternalServerError, "Failed to get information for the file due to a file system error.");
	}

	auto lastModified = toRFC822DateTimeString(dirent.timeLastModified.toUTC());
	
	if( auto pv = "If-Modified-Since" in req.headers ) {
		if( *pv == lastModified ) {
			res.statusCode = HTTPStatus.NotModified;
			res.writeVoidBody();
			return;
		}
	}

	// simple etag generation
	auto etag = "\"" ~ hexDigest!MD5(pathstr ~ ":" ~ lastModified ~ ":" ~ to!string(dirent.size)).idup ~ "\"";
	if( auto pv = "If-None-Match" in req.headers ) {
		if ( *pv == etag ) {
			res.statusCode = HTTPStatus.NotModified;
			res.writeVoidBody();
			return;
		}
	}

	res.headers["Etag"] = etag;

	auto mimetype = getMimeTypeForFile(pathstr);
	// avoid double-compression
	if( isCompressedFormat(mimetype) && "Content-Encoding" in res.headers )
		res.headers.remove("Content-Encoding");
	res.headers["Content-Type"] = mimetype;
	res.headers["Content-Length"] = to!string(dirent.size);
	
	res.headers["Last-Modified"] = lastModified;
	if( settings.maxAge > seconds(0) ){
		auto expireTime = Clock.currTime(UTC()) + settings.maxAge;
		res.headers["Expires"] = toRFC822DateTimeString(expireTime);
		res.headers["Cache-Control"] = "max-age="~to!string(settings.maxAge);
	}
	
	if(settings.preWriteCallback)
		settings.preWriteCallback(req, res, pathstr);
	
	// for HEAD responses, stop here
	if( res.isHeadResponse() ){
		res.writeVoidBody();
		assert(res.headerWritten);
		logDebug("sent file header %d, %s!", dirent.size, res.headers["Content-Type"]);
		return;
	}
	
	// else write out the file contents
	//logTrace("Open file '%s' -> '%s'", srv_path, pathstr);
	FileStream fil;
	try {
		fil = openFile(path);
	} catch( Exception e ){
		// TODO: handle non-existant files differently than locked files?
		logDebug("Failed to open file %s: %s", pathstr, e.toString());
		return;
	}
	scope(exit) fil.close();

	if( "Content-Encoding" in res.headers )
		res.bodyWriter.write(fil);
	else res.writeRawBody(fil);
	logTrace("sent file %d, %s!", fil.size, res.headers["Content-Type"]);
}