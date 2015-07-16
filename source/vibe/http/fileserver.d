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
import std.string;


/**
	Returns a request handler that serves files from the specified directory.

	See_Also: serveStaticFile
*/
HTTPServerRequestDelegateS serveStaticFiles(Path local_path, HTTPFileServerSettings settings = null)
{
	if (!settings) settings = new HTTPFileServerSettings;
	if (!settings.serverPathPrefix.endsWith("/")) settings.serverPathPrefix ~= "/";

	void callback(scope HTTPServerRequest req, scope HTTPServerResponse res)
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
		if (rpath.absolute) {
			logDebug("Path is absolute, not responding");
			return;
		} else if (!rpath.empty && rpath[0] == "..")
			return; // don't respond to relative paths outside of the root path

		sendFile(req, res, local_path ~ rpath, settings);
	}

	return &callback;
}
/// ditto
HTTPServerRequestDelegateS serveStaticFiles(string local_path, HTTPFileServerSettings settings = null)
{
	return serveStaticFiles(Path(local_path), settings);
}

///
unittest {
	import vibe.http.fileserver;
	import vibe.http.router;
	import vibe.http.server;

	void setupServer()
	{
		auto router = new URLRouter;
		// add other routes here
		router.get("*", serveStaticFiles("public/"));

		auto settings = new HTTPServerSettings;
		listenHTTP(settings, router);
	}
}

/** This example serves all files in the "public" sub directory
	with an added prefix "static/" so that they don't interfere
	with other registered routes.
*/
unittest {
	import vibe.http.fileserver;
	import vibe.http.router;
	import vibe.http.server;

	void setupRoutes()
	{
	 	auto router = new URLRouter;
		// add other routes here

		auto fsettings = new HTTPFileServerSettings;
		fsettings.serverPathPrefix = "/static";
		router.get("static/*", serveStaticFiles("public/", fsettings));

		auto settings = new HTTPServerSettings;
		listenHTTP(settings, router);
	}
}


/**
	Returns a request handler that serves a specific file on disk.

	See_Also: serveStaticFiles
*/
HTTPServerRequestDelegateS serveStaticFile(Path local_path, HTTPFileServerSettings settings = null)
{
	if (!settings) settings = new HTTPFileServerSettings;
	assert(settings.serverPathPrefix == "/", "serverPathPrefix is not supported for single file serving.");

	void callback(scope HTTPServerRequest req, scope HTTPServerResponse res)
	{
		sendFile(req, res, local_path, settings);
	}

	return &callback;
}
/// ditto
HTTPServerRequestDelegateS serveStaticFile(string local_path, HTTPFileServerSettings settings = null)
{
	return serveStaticFile(Path(local_path), settings);
}


/**
	Configuration options for the static file server.
*/
class HTTPFileServerSettings {
	string serverPathPrefix = "/";
	Duration maxAge;// = hours(24);
	HTTPFileServerOption options = HTTPFileServerOption.defaults; /// additional options
	string[string] encodingFileExtension;

	/**
		Called just before headers and data are sent.
		Allows headers to be customized, or other custom processing to be performed.

		Note: Any changes you make to the response, physicalPath, or anything
		else during this function will NOT be verified by Vibe.d for correctness.
		Make sure any alterations you make are complete and correct according to HTTP spec.
	*/
	void delegate(scope HTTPServerRequest req, scope HTTPServerResponse res, ref string physicalPath) preWriteCallback = null;

	this()
	{
		// need to use the contructor because the Ubuntu 13.10 GDC cannot CTFE dur()
		maxAge = 24.hours;
	}

	this(string path_prefix)
	{
		this();
		serverPathPrefix = path_prefix;
	}

	deprecated("Use .options and HTTPFileServerOption.failIfNotFound instead.")
	@property bool failIfNotFound() const { return options & HTTPFileServerOption.failIfNotFound; }

	deprecated("Use .options and HTTPFileServerOption.failIfNotFound instead.")
	@property void failIfNotFound(bool val) {
		if (val)
			options |= HTTPFileServerOption.failIfNotFound;
		else
			options &= ~HTTPFileServerOption.failIfNotFound;
	}
}


/**
   Additional options for the static file server.
 */
enum HTTPFileServerOption {
	none = 0,
	/// respond with 404 if a file was not found
	failIfNotFound = 1 << 0,
	/// serve index.html for directories
	serveIndexHTML = 1 << 1,
	/// default options are serveIndexHTML
	defaults = serveIndexHTML,
}


private void sendFile(scope HTTPServerRequest req, scope HTTPServerResponse res, Path path, HTTPFileServerSettings settings)
{
	auto pathstr = path.toNativeString();

	// return if the file does not exist
	if (!existsFile(pathstr)){
		if (settings.options & HTTPFileServerOption.failIfNotFound)
			throw new HTTPStatusException(HTTPStatus.NotFound);
		return;
	}

	FileInfo dirent;
	try dirent = getFileInfo(pathstr);
	catch(Exception){
		throw new HTTPStatusException(HTTPStatus.InternalServerError, "Failed to get information for the file due to a file system error.");
	}

	if (dirent.isDirectory) {
		if (settings.options & HTTPFileServerOption.serveIndexHTML)
			return sendFile(req, res, path ~ "index.html", settings);
		logDebugV("Hit directory when serving files, ignoring: %s", pathstr);
		if (settings.options & HTTPFileServerOption.failIfNotFound)
			throw new HTTPStatusException(HTTPStatus.NotFound);
		return;
	}

	auto lastModified = toRFC822DateTimeString(dirent.timeModified.toUTC());
	// simple etag generation
	auto etag = "\"" ~ hexDigest!MD5(pathstr ~ ":" ~ lastModified ~ ":" ~ to!string(dirent.size)).idup ~ "\"";

	res.headers["Last-Modified"] = lastModified;
	res.headers["Etag"] = etag;
	if (settings.maxAge > seconds(0)) {
		auto expireTime = Clock.currTime(UTC()) + settings.maxAge;
		res.headers["Expires"] = toRFC822DateTimeString(expireTime);
		res.headers["Cache-Control"] = "max-age="~to!string(settings.maxAge.total!"seconds");
	}

	if( auto pv = "If-Modified-Since" in req.headers ) {
		if( *pv == lastModified ) {
			res.statusCode = HTTPStatus.NotModified;
			res.writeVoidBody();
			return;
		}
	}

	if( auto pv = "If-None-Match" in req.headers ) {
		if ( *pv == etag ) {
			res.statusCode = HTTPStatus.NotModified;
			res.writeVoidBody();
			return;
		}
	}

	auto mimetype = getMimeTypeForFile(pathstr);
	// avoid double-compression
	if ("Content-Encoding" in res.headers && isCompressedFormat(mimetype))
		res.headers.remove("Content-Encoding");
	res.headers["Content-Type"] = mimetype;
	res.headers["Content-Length"] = to!string(dirent.size);

	// check for already encoded file if configured
	string encodedFilepath;
	auto pce = "Content-Encoding" in res.headers;
	if (pce) {
		if (auto pfe = *pce in settings.encodingFileExtension) {
			assert((*pfe).length > 0);
			auto p = pathstr ~ *pfe;
			if (existsFile(p))
				encodedFilepath = p;
		}
	}
	if (encodedFilepath.length) {
		auto origLastModified = dirent.timeModified.toUTC();

		try dirent = getFileInfo(encodedFilepath);
		catch(Exception){
			throw new HTTPStatusException(HTTPStatus.InternalServerError, "Failed to get information for the file due to a file system error.");
		}

		// encoded file must be younger than original else warn
		if (dirent.timeModified.toUTC() >= origLastModified){
			logTrace("Using already encoded file '%s' -> '%s'", path, encodedFilepath);
			path = Path(encodedFilepath);
			res.headers["Content-Length"] = to!string(dirent.size);
		} else {
			logWarn("Encoded file '%s' is older than the original '%s'. Ignoring it.", encodedFilepath, path);
			encodedFilepath = null;
		}
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

	if (pce && !encodedFilepath.length)
		res.bodyWriter.write(fil);
	else res.writeRawBody(fil);
	logTrace("sent file %d, %s!", fil.size, res.headers["Content-Type"]);
}
