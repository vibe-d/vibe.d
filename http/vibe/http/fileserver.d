/**
	A static HTTP file server.

	Copyright: © 2012-2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.http.fileserver;

import vibe.core.file;
import vibe.core.log;
import vibe.core.stream : RandomAccessStream, pipe;
import vibe.http.server;
import vibe.inet.message;
import vibe.inet.mimetypes;
import vibe.inet.url;
import vibe.internal.interfaceproxy;

import std.conv;
import std.datetime;
import std.digest.md;
import std.string;
import std.algorithm;

@safe:


/**
	Returns a request handler that serves files from the specified directory.

	See `sendFile` for more information.

	Params:
		local_path = Path to the folder to serve files from.
		settings = Optional settings object enabling customization of how
			the files get served.

	Returns:
		A request delegate is returned, which is suitable for registering in
		a `URLRouter` or for passing to `listenHTTP`.

	See_Also: `serveStaticFile`, `sendFile`
*/
HTTPServerRequestDelegateS serveStaticFiles(NativePath local_path, HTTPFileServerSettings settings = null)
{
	import std.range.primitives : front;
	if (!settings) settings = new HTTPFileServerSettings;
	if (!settings.serverPathPrefix.endsWith("/")) settings.serverPathPrefix ~= "/";

	void callback(scope HTTPServerRequest req, scope HTTPServerResponse res)
	@safe {
		string srv_path;
		if (auto pp = "pathMatch" in req.params) srv_path = *pp;
		else if (req.path.length > 0) srv_path = req.path;
		else srv_path = req.requestURL;

		if (!srv_path.startsWith(settings.serverPathPrefix)) {
			logDebug("path '%s' not starting with '%s'", srv_path, settings.serverPathPrefix);
			return;
		}

		auto rel_path = srv_path[settings.serverPathPrefix.length .. $];
		auto rpath = PosixPath(rel_path);
		logTrace("Processing '%s'", srv_path);

		rpath.normalize();
		logDebug("Path '%s' -> '%s'", rel_path, rpath.toNativeString());
		if (rpath.absolute) {
			logDebug("Path is absolute, not responding");
			return;
		} else if (!rpath.empty && rpath.bySegment.front.name == "..")
			return; // don't respond to relative paths outside of the root path

		sendFileImpl(req, res, local_path ~ rpath, settings);
	}

	return &callback;
}
/// ditto
HTTPServerRequestDelegateS serveStaticFiles(string local_path, HTTPFileServerSettings settings = null)
{
	return serveStaticFiles(NativePath(local_path), settings);
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

	See `sendFile` for more information.

	Params:
		local_path = Path to the file to serve.
		settings = Optional settings object enabling customization of how
			the file gets served.

	Returns:
		A request delegate is returned, which is suitable for registering in
		a `URLRouter` or for passing to `listenHTTP`.

	See_Also: `serveStaticFiles`, `sendFile`
*/
HTTPServerRequestDelegateS serveStaticFile(NativePath local_path, HTTPFileServerSettings settings = null)
{
	if (!settings) settings = new HTTPFileServerSettings;
	assert(settings.serverPathPrefix == "/", "serverPathPrefix is not supported for single file serving.");

	void callback(scope HTTPServerRequest req, scope HTTPServerResponse res)
	{
		sendFileImpl(req, res, local_path, settings);
	}

	return &callback;
}
/// ditto
HTTPServerRequestDelegateS serveStaticFile(string local_path, HTTPFileServerSettings settings = null)
{
	return serveStaticFile(NativePath(local_path), settings);
}


/**
	Sends a file to the given HTTP server response object.

	When serving a file, certain request headers are supported to avoid sending
	the file if the client has it already cached. These headers are
	`"If-Modified-Since"` and `"If-None-Match"`. The client will be delivered
	with the necessary `"Etag"` (generated from the path, size and last
	modification time of the file) and `"Last-Modified"` headers.

	The cache control directives `"Expires"` and `"Cache-Control"` will also be
	emitted if the `HTTPFileServerSettings.maxAge` field is set to a positive
	duration.

	Finally, HEAD requests will automatically be handled without reading the
	actual file contents. Am empty response body is written instead.

	Params:
		req = The incoming HTTP request - cache and modification headers of the
			request can influence the generated response.
		res = The response object to write to.
		settings = Optional settings object enabling customization of how the
			file gets served.
*/
void sendFile(scope HTTPServerRequest req, scope HTTPServerResponse res, NativePath path, HTTPFileServerSettings settings = null)
{
	static HTTPFileServerSettings default_settings;
	if (!settings) {
		if (!default_settings) default_settings = new HTTPFileServerSettings;
		settings = default_settings;
	}

	sendFileImpl(req, res, path, settings);
}


/**
	Configuration options for the static file server.
*/
class HTTPFileServerSettings {
	/// Prefix of the request path to strip before looking up files
	string serverPathPrefix = "/";

	/// Maximum cache age to report to the client (zero by default)
	Duration maxAge = 0.seconds;

	/// General options
	HTTPFileServerOption options = HTTPFileServerOption.defaults; /// additional options

	/** Maps from encoding scheme (e.g. "gzip") to file extension.

		If a request accepts a supported encoding scheme, then the file server
		will look for a file with the extension as a suffix and, if that exists,
		sends it as the encoded representation instead of sending the original
		file.

		Example:
			---
			settings.encodingFileExtension["gzip"] = ".gz";
			---
	*/
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
	}

	this(string path_prefix)
	{
		this();
		serverPathPrefix = path_prefix;
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


private void sendFileImpl(scope HTTPServerRequest req, scope HTTPServerResponse res, NativePath path, HTTPFileServerSettings settings = null)
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
			return sendFileImpl(req, res, path ~ "index.html", settings);
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

	auto mimetype = res.headers.get("Content-Type", getMimeTypeForFile(pathstr));

	// avoid double-compression
	if ("Content-Encoding" in res.headers && isCompressedFormat(mimetype))
		res.headers.remove("Content-Encoding");

	if (!("Content-Type" in res.headers))
		res.headers["Content-Type"] = mimetype;

	res.headers.addField("Accept-Ranges", "bytes");
	ulong rangeStart = 0;
	ulong rangeEnd = 0;
	auto prange = "Range" in req.headers;

	if (prange) {
		auto range = (*prange).chompPrefix("bytes=");
		if (range.canFind(','))
			throw new HTTPStatusException(HTTPStatus.notImplemented);
		auto s = range.split("-");
		if (s.length != 2)
			throw new HTTPStatusException(HTTPStatus.badRequest);
		// https://tools.ietf.org/html/rfc7233
		// Range can be in form "-\d", "\d-" or "\d-\d"
		try {
			if (s[0].length) {
				rangeStart = s[0].to!ulong;
				rangeEnd = s[1].length ? s[1].to!ulong : dirent.size;
			} else if (s[1].length) {
				rangeEnd = dirent.size;
				auto len = s[1].to!ulong;
				if (len >= rangeEnd)
					rangeStart = 0;
				else
					rangeStart = rangeEnd - len;
			} else {
				throw new HTTPStatusException(HTTPStatus.badRequest);
			}
		} catch (ConvException) {
			throw new HTTPStatusException(HTTPStatus.badRequest);
		}
		if (rangeEnd > dirent.size)
			rangeEnd = dirent.size;
		if (rangeStart > rangeEnd)
			rangeStart = rangeEnd;
		if (rangeEnd)
			rangeEnd--; // End is inclusive, so one less than length
		// potential integer overflow with rangeEnd - rangeStart == size_t.max is intended. This only happens with empty files, the + 1 will then put it back to 0
		res.headers["Content-Length"] = to!string(rangeEnd - rangeStart + 1);
		res.headers["Content-Range"] = "bytes %s-%s/%s".format(rangeStart < rangeEnd ? rangeStart : rangeEnd, rangeEnd, dirent.size);
		res.statusCode = HTTPStatus.partialContent;
	} else
		res.headers["Content-Length"] = dirent.size.to!string;

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
			path = NativePath(encodedFilepath);
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
		logDebug("Failed to open file %s: %s", pathstr, () @trusted { return e.toString(); } ());
		return;
	}
	scope(exit) fil.close();

	if (prange) {
		fil.seek(rangeStart);
		fil.pipe(res.bodyWriter, rangeEnd - rangeStart + 1);
		logTrace("partially sent file %d-%d, %s!", rangeStart, rangeEnd, res.headers["Content-Type"]);
	} else {
		if (pce && !encodedFilepath.length)
			fil.pipe(res.bodyWriter);
		else res.writeRawBody(fil);
		logTrace("sent file %d, %s!", fil.size, res.headers["Content-Type"]);
	}
}
