/**
	A static HTTP file server.

	Copyright: © 2012-2015 Sönke Ludwig
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

import std.ascii : isWhite;
import std.algorithm;
import std.conv;
import std.datetime;
import std.digest.md;
import std.exception;
import std.range : popFront, empty, drop;
import std.string;
import std.typecons : Flag, Yes, No;

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
		else if (req.requestPath != InetPath.init) srv_path = (cast(PosixPath)req.requestPath).toString();
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
		router.get("/static/*", serveStaticFiles("public/", fsettings));

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
	with the necessary `"Etag"` (generated from size and last modification time
	of the file) and `"Last-Modified"` headers.

	The cache control directives `"Expires"` and/or `"Cache-Control"` will also be
	emitted if the `HTTPFileServerSettings.maxAge` field is set to a positive
	duration and/or `HTTPFileServerSettings.cacheControl` has been set.

	Finally, HEAD requests will automatically be handled without reading the
	actual file contents. Am empty response body is written instead.

	Params:
		req = The incoming HTTP request - cache and modification headers of the
			request can influence the generated response.
		res = The response object to write to.
		path = Path to the file to be sent.
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

	/** Cache control to control where cache can be saved, if at all, such as
		proxies, the storage, etc.

		Leave null or empty to not emit any cache control directives other than
		max-age if maxAge is set.

		Common values include: public for making a shared resource cachable across
		multiple users or private for a response that should only be cached for a
		single user.

		See https://developer.mozilla.org/de/docs/Web/HTTP/Headers/Cache-Control
	*/
	string cacheControl = null;

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
			throw new HTTPStatusException(HTTPStatus.notFound);
		return;
	}

	FileInfo dirent;
	try dirent = getFileInfo(pathstr);
	catch(Exception){
		throw new HTTPStatusException(HTTPStatus.internalServerError, "Failed to get information for the file due to a file system error.");
	}

	if (dirent.isDirectory) {
		if (settings.options & HTTPFileServerOption.serveIndexHTML)
			return sendFileImpl(req, res, path ~ "index.html", settings);
		logDebugV("Hit directory when serving files, ignoring: %s", pathstr);
		if (settings.options & HTTPFileServerOption.failIfNotFound)
			throw new HTTPStatusException(HTTPStatus.notFound);
		return;
	}

	if (handleCacheFile(req, res, dirent, settings.cacheControl, settings.maxAge)) {
		return;
	}

	auto mimetype = res.headers.get("Content-Type", getMimeTypeForFile(pathstr));

	// avoid double-compression
	if ("Content-Encoding" in res.headers && isCompressedFormat(mimetype))
		res.headers.remove("Content-Encoding");

	if (!("Content-Type" in res.headers))
		res.headers["Content-Type"] = mimetype;

	res.headers.addField("Accept-Ranges", "bytes");
	RangeSpec range;
	if (auto prange = "Range" in req.headers) {
		range = parseRangeHeader(*prange, dirent.size, res);

		// potential integer overflow with rangeEnd - rangeStart == size_t.max is intended. This only happens with empty files, the + 1 will then put it back to 0
		res.headers["Content-Length"] = to!string(range.max - range.min);
		res.headers["Content-Range"] = "bytes %s-%s/%s".format(range.min, range.max - 1, dirent.size);
		res.statusCode = HTTPStatus.partialContent;
	} else res.headers["Content-Length"] = dirent.size.to!string;

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
			throw new HTTPStatusException(HTTPStatus.internalServerError, "Failed to get information for the file due to a file system error.");
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

	if (range.max > range.min) {
		fil.seek(range.min);
		fil.pipe(res.bodyWriter, range.max - range.min);
		logTrace("partially sent file %d-%d, %s!", range.min, range.max - 1, res.headers["Content-Type"]);
	} else {
		if (pce && !encodedFilepath.length)
			fil.pipe(res.bodyWriter);
		else res.writeRawBody(fil);
		logTrace("sent file %d, %s!", fil.size, res.headers["Content-Type"]);
	}
}

/**
	Calls $(D handleCache) with prefilled etag and lastModified value based on a file.

	See_Also: handleCache

	Returns: $(D true) if the cache was already handled and no further response must be sent or $(D false) if a response must be sent.
*/
bool handleCacheFile(scope HTTPServerRequest req, scope HTTPServerResponse res,
		string file, string cache_control = null, Duration max_age = Duration.zero)
{
	return handleCacheFile(req, res, NativePath(file), cache_control, max_age);
}

/// ditto
bool handleCacheFile(scope HTTPServerRequest req, scope HTTPServerResponse res,
		NativePath file, string cache_control = null, Duration max_age = Duration.zero)
{
	if (!existsFile(file)) {
		return false;
	}

	FileInfo ent;
	try {
		ent = getFileInfo(file);
	} catch (Exception) {
		throw new HTTPStatusException(HTTPStatus.internalServerError,
				"Failed to get information for the file due to a file system error.");
	}

	return handleCacheFile(req, res, ent, cache_control, max_age);
}

/// ditto
bool handleCacheFile(scope HTTPServerRequest req, scope HTTPServerResponse res,
		FileInfo dirent, string cache_control = null, Duration max_age = Duration.zero)
{
	import std.bitmanip : nativeToLittleEndian;
	import std.digest.md : MD5, toHexString;

	SysTime lastModified = dirent.timeModified;
	const weak = cast(Flag!"weak") dirent.isDirectory;
	auto etag = ETag.md5(weak, lastModified.stdTime.nativeToLittleEndian, dirent.size.nativeToLittleEndian);

	return handleCache(req, res, etag, lastModified, cache_control, max_age);
}

/**
	Processes header tags in a request and writes responses given on requested cache status.

	Params:
		req = the client request used to determine cache control flow.
		res = the response to write cache headers to.
		etag = if set to anything except .init, adds a Etag header to the response and enables handling of If-Match and If-None-Match cache control request headers.
		last_modified = if set to anything except .init, adds a Last-Modified header to the response and enables handling of If-Modified-Since and If-Unmodified-Since cache control request headers.
		cache_control = if set, adds or modifies the Cache-Control header in the response to this string. Might get an additional max-age value appended if max_age is set.
		max_age = optional duration to set the Expires header and Cache-Control max-age part to. (if no existing `max-age=` part is given in the cache_control parameter)

	Returns: $(D true) if the cache was already handled and no further response must be sent or $(D false) if a response must be sent.
*/
bool handleCache(scope HTTPServerRequest req, scope HTTPServerResponse res, ETag etag,
		SysTime last_modified, string cache_control = null, Duration max_age = Duration.zero)
{
	// https://tools.ietf.org/html/rfc7232#section-4.1
	// and
	// https://tools.ietf.org/html/rfc7232#section-6
	string lastModifiedString;
	if (last_modified != SysTime.init) {
		lastModifiedString = toRFC822DateTimeString(last_modified);
		res.headers["Last-Modified"] = lastModifiedString;
	}

	if (etag != ETag.init) {
		res.headers["Etag"] = etag.toString;
	}

	if (max_age > Duration.zero) {
		res.headers["Expires"] = toRFC822DateTimeString(Clock.currTime(UTC()) + max_age);
	}

	if (cache_control.length) {
		if (max_age > Duration.zero && !cache_control.canFind("max-age=")) {
			res.headers["Cache-Control"] = cache_control
				~ ", max-age=" ~ to!string(max_age.total!"seconds");
		} else {
			res.headers["Cache-Control"] = cache_control;
		}
	} else if (max_age > Duration.zero) {
		res.headers["Cache-Control"] = text("max-age=", max_age.total!"seconds");
	}

	// https://tools.ietf.org/html/rfc7232#section-3.1
	string ifMatch = req.headers.get("If-Match");
	if (ifMatch.length) {
		if (!cacheMatch(ifMatch, etag, No.allowWeak)) {
			res.statusCode = HTTPStatus.preconditionFailed;
			res.writeVoidBody();
			return true;
		}
	}
	else if (last_modified != SysTime.init) {
		// https://tools.ietf.org/html/rfc7232#section-3.4
		string ifUnmodifiedSince = req.headers.get("If-Unmodified-Since");
		if (ifUnmodifiedSince.length) {
			const check = lastModifiedString != ifUnmodifiedSince
				|| last_modified > parseRFC822DateTimeString(ifUnmodifiedSince);
			if (check) {
				res.statusCode = HTTPStatus.preconditionFailed;
				res.writeVoidBody();
				return true;
			}
		}
	}

	// https://tools.ietf.org/html/rfc7232#section-3.2
	string ifNoneMatch = req.headers.get("If-None-Match");
	if (ifNoneMatch.length) {
		if (cacheMatch(ifNoneMatch, etag, Yes.allowWeak)) {
			if (req.method.among!(HTTPMethod.GET, HTTPMethod.HEAD))
				res.statusCode = HTTPStatus.notModified;
			else
				res.statusCode = HTTPStatus.preconditionFailed;
			res.writeVoidBody();
			return true;
		}
	}
	else if (last_modified != SysTime.init && req.method.among!(HTTPMethod.GET, HTTPMethod.HEAD)) {
		// https://tools.ietf.org/html/rfc7232#section-3.3
		string ifModifiedSince = req.headers.get("If-Modified-Since");
		if (ifModifiedSince.length) {
			const check = lastModifiedString == ifModifiedSince ||
				last_modified <= parseRFC822DateTimeString(ifModifiedSince);
			if (check) {
				res.statusCode = HTTPStatus.notModified;
				res.writeVoidBody();
				return true;
			}
		}
	}

	// TODO: support If-Range here

	return false;
}

/**
	Represents an Entity-Tag value for use inside HTTP Cache headers.

	Standards: https://tools.ietf.org/html/rfc7232#section-2.3
*/
struct ETag
{
	bool weak;
	string tag;

	static ETag parse(string s)
	{
		enforce!ConvException(s.endsWith('"'));

		if (s.startsWith(`W/"`)) {
			ETag ret = { weak: true, tag: s[3 .. $ - 1] };
			return ret;
		} else if (s.startsWith('"')) {
			ETag ret;
			ret.tag = s[1 .. $ - 1];
			return ret;
		} else {
			throw new ConvException(`ETag didn't start with W/" nor with " !`);
		}
	}

	string toString() const @property
	{
		return text(weak ? `W/"` : `"`, tag, '"');
	}

	/**
		Encodes the bytes with URL Base64 to a human readable string and returns an ETag struct wrapping it.
	 */
	static ETag fromBytesBase64URLNoPadding(scope const(ubyte)[] bytes, Flag!"weak" weak = No.weak)
	{
		import std.base64 : Base64URLNoPadding;

		return ETag(weak, Base64URLNoPadding.encode(bytes).idup);
	}

	/**
		Hashes the input bytes with md5 and returns an URL Base64 encoded representation as ETag.
	 */
	static ETag md5(T...)(Flag!"weak" weak, T data)
	{
		import std.digest.md : md5Of;

		return fromBytesBase64URLNoPadding(md5Of(data), weak);
	}
}

/**
	Matches a given match expression with a specific ETag. Can allow or disallow weak ETags and supports multiple tags.

	Standards: https://tools.ietf.org/html/rfc7232#section-2.3.2
*/
bool cacheMatch(string match, ETag etag, Flag!"allowWeak" allow_weak)
{
	if (match == "*") {
		return true;
	}

	if ((etag.weak && !allow_weak) || !match.length) {
		return false;
	}

	auto allBytes = match.representation;
	auto range = allBytes;

	while (!range.empty)
	{
		range = range.stripLeft!isWhite;
		bool isWeak = range.skipOver("W/");
		if (!range.skipOver('"'))
			return false; // malformed

		auto end = range.countUntil('"');
		if (end == -1)
			return false; // malformed

		const check = range[0 .. end];
		range = range[end .. $];

		if (allow_weak || !isWeak) {
			if (check == etag.tag) {
				return true;
			}
		}

		range.skipOver('"');
		range = range.stripLeft!isWhite;

		if (!range.skipOver(","))
			return false; // malformed
	}

	return false;
}

unittest
{
	// from RFC 7232 Section 2.3.2
	// +--------+--------+-------------------+-----------------+
	// | ETag 1 | ETag 2 | Strong Comparison | Weak Comparison |
	// +--------+--------+-------------------+-----------------+
	// | W/"1"  | W/"1"  | no match          | match           |
	// | W/"1"  | W/"2"  | no match          | no match        |
	// | W/"1"  | "1"    | no match          | match           |
	// | "1"    | "1"    | match             | match           |
	// +--------+--------+-------------------+-----------------+

	assert(!cacheMatch(`W/"1"`, ETag(Yes.weak, "1"), No.allowWeak));
	assert( cacheMatch(`W/"1"`, ETag(Yes.weak, "1"), Yes.allowWeak));

	assert(!cacheMatch(`W/"1"`, ETag(Yes.weak, "2"), No.allowWeak));
	assert(!cacheMatch(`W/"1"`, ETag(Yes.weak, "2"), Yes.allowWeak));

	assert(!cacheMatch(`W/"1"`, ETag(No.weak, "1"), No.allowWeak));
	assert( cacheMatch(`W/"1"`, ETag(No.weak, "1"), Yes.allowWeak));

	assert(cacheMatch(`"1"`, ETag(No.weak, "1"), No.allowWeak));
	assert(cacheMatch(`"1"`, ETag(No.weak, "1"), Yes.allowWeak));

	assert(cacheMatch(`"xyzzy","r2d2xxxx", "c3piozzzz"`, ETag(No.weak, "xyzzy"), No.allowWeak));
	assert(cacheMatch(`"xyzzy","r2d2xxxx", "c3piozzzz"`, ETag(No.weak, "xyzzy"), Yes.allowWeak));

	assert(!cacheMatch(`"xyzzy","r2d2xxxx", "c3piozzzz"`, ETag(No.weak, "xyzzz"), No.allowWeak));
	assert(!cacheMatch(`"xyzzy","r2d2xxxx", "c3piozzzz"`, ETag(No.weak, "xyzzz"), Yes.allowWeak));

	assert(cacheMatch(`"xyzzy","r2d2xxxx", "c3piozzzz"`, ETag(No.weak, "r2d2xxxx"), No.allowWeak));
	assert(cacheMatch(`"xyzzy","r2d2xxxx", "c3piozzzz"`, ETag(No.weak, "r2d2xxxx"), Yes.allowWeak));

	assert(cacheMatch(`"xyzzy","r2d2xxxx", "c3piozzzz"`, ETag(No.weak, "c3piozzzz"), No.allowWeak));
	assert(cacheMatch(`"xyzzy","r2d2xxxx", "c3piozzzz"`, ETag(No.weak, "c3piozzzz"), Yes.allowWeak));

	assert(!cacheMatch(`"xyzzy","r2d2xxxx", "c3piozzzz"`, ETag(No.weak, ""), No.allowWeak));
	assert(!cacheMatch(`"xyzzy","r2d2xxxx", "c3piozzzz"`, ETag(No.weak, ""), Yes.allowWeak));

	assert(!cacheMatch(`"xyzzy",W/"r2d2xxxx", "c3piozzzz"`, ETag(Yes.weak, "r2d2xxxx"), No.allowWeak));
	assert( cacheMatch(`"xyzzy",W/"r2d2xxxx", "c3piozzzz"`, ETag(Yes.weak, "r2d2xxxx"), Yes.allowWeak));
	assert(!cacheMatch(`"xyzzy",W/"r2d2xxxx", "c3piozzzz"`, ETag(No.weak, "r2d2xxxx"), No.allowWeak));
	assert( cacheMatch(`"xyzzy",W/"r2d2xxxx", "c3piozzzz"`, ETag(No.weak, "r2d2xxxx"), Yes.allowWeak));
}

private RangeSpec parseRangeHeader(string range_spec, ulong file_size, scope HTTPServerResponse res)
{
	RangeSpec ret;

	auto range = range_spec.chompPrefix("bytes=");
	if (range.canFind(','))
		throw new HTTPStatusException(HTTPStatus.notImplemented);
	auto s = range.split("-");
	if (s.length != 2)
		throw new HTTPStatusException(HTTPStatus.badRequest);

	// https://tools.ietf.org/html/rfc7233
	// Range can be in form "-\d", "\d-" or "\d-\d"
	try {
		if (s[0].length) {
			ret.min = s[0].to!ulong;
			ret.max = s[1].length ? s[1].to!ulong + 1 : file_size;
		} else if (s[1].length) {
			ret.min = file_size - min(s[1].to!ulong, file_size);
			ret.max = file_size;
		} else {
			throw new HTTPStatusException(HTTPStatus.badRequest);
		}
	} catch (ConvException) {
		throw new HTTPStatusException(HTTPStatus.badRequest);
	}

	if (ret.max > file_size) ret.max = file_size;

	if (ret.min >= ret.max) {
		res.headers["Content-Range"] = "bytes */%s".format(file_size);
		throw new HTTPStatusException(HTTPStatus.rangeNotSatisfiable);
	}

	return ret;
}

unittest {
	auto res = createTestHTTPServerResponse();
	assertThrown(parseRangeHeader("bytes=2-1", 10, res));
	assertThrown(parseRangeHeader("bytes=10-10", 10, res));
	assertThrown(parseRangeHeader("bytes=0-0", 0, res));
	assert(parseRangeHeader("bytes=10-20", 100, res) == RangeSpec(10, 21));
	assert(parseRangeHeader("bytes=0-0", 1, res) == RangeSpec(0, 1));
	assert(parseRangeHeader("bytes=0-20", 2, res) == RangeSpec(0, 2));
	assert(parseRangeHeader("bytes=1-20", 2, res) == RangeSpec(1, 2));
}

private struct RangeSpec {
	ulong min, max;
}
