Changelog
=========


v0.7.9 - 2012-
-------------------

### Features and improvements ###

 - The Diet template compiler now supports includes and recursive extensions/layouts
 - The REST interface now uses fully qualified names and local imports to resolve parameter/return types, making it much more robust (by Михаил Страшун aka mist)
 - Implemented TCP/UDP sockets for the Win32 driver
 - Implemented a directory watcher for the Win32 driver
 - Removed vibe.textfilter.ddoc - now in <http://github.com/rejectedsoftware/ddox>
 - Cleaned up command line handling (e.g. application parameters are now separated from vibe parameters by --)
 - Dependencies in package.json can now have "~master" as the version field to take the lastest master version instead of a tagged version
 - Renamed `UrlRouter.addRoute()` to UrlRouter.match()
 - Moved Path into its own module (vibe.inet.path)
 - Task local storage is now handled directly by Task instead of in vibe.core.core
 - (de)serialze(To)(Json/Bson) now support type customization using (to/from)(Json/Bson) mmethods
 - (de)serialze(To)(Json/Bson) now strip a trailing underscore in field names, if present - allows to use keywords as field names
 - `Json.opt!()` is now much faster in case of non-existent fields
 - Implemented `InputStream.readAllUtf8()` - strips BOM and sanitizes or validates the input
 - Added RandomAccessStream interface
 - Implemented a github like variant of Markdown more suitable for marking up conversation comments
 - Made ATX header and automatic link detection in the Markdown parser stricter to avoid false detections
 - Added `setPlainLogging()` - avoids output of thread and task id
 - Avoiding some bogous error messages in the HTTP server (when a peer closes a connection actively)
 - Renamed the string variant of `filterHtmlAllEscape()` to `htmlAllEscape()` to match similar functions

### Bug fixes ###

 - Fixed a possible endless loop in `ZlibInputStream` - now triggers anassertion instead. Still sufferign from <http://d.puremagic.com/issues/show_bug.cgi?id=8779>
 - Fixed handling of escaped characters in Diet templates and dissallowed ## to escape #
 - Fixed 'undefined' appearing in the stringified version of JSON arrays or objects (they are now filtered out)
 - Fixed the error message for failed connection attempts
 - Fixed a bug in `PoolAllocator.realloc()` that could cause a range violation or corrupted memory


v0.7.8 - 2012-10-01
-------------------

### Features and improvements ###

 - Added support for UDP sockets
 - The reverse proxy now adds the headers "X-Forwarded-For" and "X-Forwarded-Host"
 - `MongoCollection.findAndModify` returns the resulting object only now instead of the full reply of the protocol
 - Calling `MongoCollection.find()` without arguments now returns all documents of the collection
 - Implemented "vibe init" to generate a new app skeleton (by 1100110)
 - The application's main module can now also be named after the package name instead of 'app.d' (by 1100110)
 - The default user/group used on Linux for priviledge lowering has been renamed to 'www-vibe' to avoid name clashes with possibly existing users named 'vibe' (by Jordy Sayol)
 - `BsonBinData` is now converted to a Base-64 encoded string when the BSON value is converted to a JSON value
 - `BsonDate` now has `toString`/`fromString` for an ISO extended representation so that its JSON serialization is now a string
 - The Diet parser now supports string interpolations inside of style and script tags.
 - The Diet parser now enforces proper indentation (i.e. the number of spaces used for an indentation level has to be a multiple of the base indent)
 - The Diet parser now supports unescaped string interpolations using !{}
 - The JSON de(serializer) now supports pointer types
 - Upgraded libevent to v2.0.20 and OpenSSL to v1.0.1c on Windows
 - The Win32 driver now has a working Timer implementation
 - `OutputStream` now has an output range interface for the types ubyte and char
 - The logging functions use 'auto ref' instead of 'lazy' now to avoid errors of the kind "this(this) is not nothrow"
 - The markdown text filter now emits XHTML compatible <br/> tags instead of <br> (by cybevnm)
 - The REST interface generator now uses plain strings instead of JSON for query strings and path parameters, if possible
 - The `UrlRouter` now URL-decodes all path parameters

### Bug fixes ###

 - Fixed a null dereference for certain invalid HTTP requests that caused the application to quit
 - Fixed `setTaskStackSize()` to actually do anything (the argument was ignored somwhere along the way to creating the fiber)
 - Fixed parameter name parsing in the REST interface generator for functions with type modifiers on their return type (will be obsolete once __traits(parameterNames) works)
 - Fixed a too strict checking of email adresses and using `std.net.isemail` now to perform proper checking on DMD 2.060 and up
 - Fixed JSON deserialization of associative arrays with a value type different than 'string'
 - Fixed empty peer fields in `HttpServerRequest` when the request failed to parse properly
 - Fixed `yield()` calls to avoid stack overflows and missing I/O events due to improper recursion
 - Fixed the Diet parser to allow inline HTML as it should
 - Fixed the Diet parser to actually output singular HTML elements as singular elements
 - Fixed tight loops with `yield()` not causing I/O to stop in the win32 back end
 - Fixed code running from within `static this()` not being able to use vibe.d I/O functions
 - Fixed a "memory leak" (an indefinitely growing array)
 - Fixed parsing of one-character JSON strings (by Михаил Страшун aka mist)
 - Fixed the Diet parser to not HTML escape attributes and to properly escape quotation marks (complying with Jade's behavior)
 - Fixed the Diet parser to accept an escaped hash (\#) as a way to avoid string interpolations 
 - Fixed a bug in MongoDB cursor end detection causing spurious exceptions
 - Fixed the Markdown parser to now recognize emphasis at the start of a line as an unordered list
 - Fixed the form parsing to to not reject a content type with character set specification
 - Fixed parsing of unicode character sequences in JSON strings
 - Fixed the 100-continue response to end with an empty line


v0.7.7 - 2012-08-05
-------------------

### Features and improvements ###

 - Compiles with DMD 2.060
 - Some considerable improvements and fixes for the REST interface generator - it is now also actually used and tested in another project
 - MongoDB supports `mongodb://` URLs for specifying various connection settings instead of just host/port (by David Eagen)
 - Added `RestInterfaceClient.requestFilter` to enable authentication and similar add-on functionality
 - JSON floating-point numbers are now stringified with higher precision
 - Improved const-correctness if the Bson struct (by cybevnm)
 - Added `setIdleHandler()` to enable tasks that run when all events have been processed
 - Putting a '{' at the end of a D statement in a Diet template instead of using indentation for nesting will now give an error
 - API documentation improvements

### Bug Fixes ### 

 - The HTTP server now allows query strings that are not valid forms (github issue #73)


v0.7.6 - 2012-07-15
-------------------

### Features and improvements ###
 
 - A good amount of performance tuning of the HTTP server
 - Implemented `vibe.core.core.yield()`. This can be used to break up long computations into smaller parts to reduce latency for other tasks
 - Added setup-linux.sh and setup-mac.sh scripts that set a symlink in /usr/bin and a config file in /etc/vibe (Thanks to Jordi Sayol)
 - Installed VPM modules are now passed as version identifiers "VPM_package_xyz" to the application to allow for optional features
 - Improved serialization of structs/classes to JSON/BSON - properties are now serialized and all non-field/property members are now ignored
 - Added directory handling functions to `vibe.core.file` (not using asynchronous operations, yet)
 - Improved the vibe shell script's compatibility

### Bug fixes ###
 
 - Fixed `TcpConnection.close()` for the libevent driver - this caused hanging page loads in some browsers
 - Fixed MongoDB connection handling to avoid secondary assertions being triggered in case of exceptions during the communication
 - Fixed JSON (de)serialization of structs and classes (member names were wrong)
 - Fixed `(filter)urlEncode` for character values < 0x10

 
v0.7.5 - 2012-06-05
-------------------

 - Restructured the examples - each example is now a regular vibe.d application (also fixes compilation using run_example)
 - The REST interface generator now supports sub interfaces which are mapped to sub paths in the URL
 - Added `InjectedParams!()` to access parameters injected using inject!()
 - The vibe script and VPM now do not write to the application directory anymore if not necessary
 - Implement more robust type handling in the REST client generator
 - Fixed a possible exception in `ZlibInputStream` at the end of the stream


v0.7.4 - 2012-06-03
-------------------

 - Added support for multipart/form-data and file uploads
 - Rewrote the Markdown parser - it now does not emit paragraphs inside list elements if no blank lines are present and handles markdown nested in quotes properly
 - The SMTP client supports STARTTLS and PLAIN/LOGIN authentication
 - The Diet parser now supports generic :filters using `registerDietTextFilter()` - :css, :javascript and :markdown are already built-in
 - VPM now can automatically updates dependencies and does not query the registry at every run anymore
 - Added `vibe.templ.utils.inject` which allows to flexibly stack together request processors and inject variables into the final HTML template (thanks to simendsjo for the kick-off implementation)
 - Removed `InputStream.readAll()` and `readLine()` and replaced them by UFCS-able global functions + added `readUntil()`
 - Added `ConnectionPool` to generically manage reuse of persistent connections (e.g. for databases)
 - The `HttpClient` (and thus the reverse proxy) now uses a connection pool to avoid continuous reconnects
 - On *nix now uses pkg-config to find linker dependencies if possible (dawgfoto)
 - The static HTTP file server now resolves paths with '.' and '..' instead of simply refusing them
 - Implemented handling of `HttpServerSettings.maxRequestTime`
 - Added `setLogFile()`
 - The vibe.cmd script now works with paths containing spaces
 - `Libevent2TcpConnection` now enforces proper use of `acquire()/release()`
 - Improved stability in conjunction with TCP connections
 - Upgraded libevent to 2.0.19 on Windows

 
v0.7.3 - 2012-05-22
-------------------

 - Hotfix release, fixes a bug that could cause a connection to be dropped immediately after accept

 
v0.7.2 - 2012-05-22
-------------------

 - Added support for timers and `sleep()`
 - Proper timeout handling for Connection: keep-alive is in place - fixes "Operating on closed connection" errors
 - Setting DFLAGS to change compiler options now actually works
 - Implemented `SslStream`, wich is now used instead of libevent's SSL code - fixes a hang on Linux/libevent-2.0.16
 - The REST interface generator now supports `index()` methods and 'id' parameters to customize the protocol
 - Changed the type for durations from `int/double` to `Duration`
 - Using Deimos bindings now instead of the custom ones

 
v0.7.1 - 2012-05-18
-------------------

 - Performance tuning
 - Added `vibe.utils.validation`
 - Various fixes and improvements

 
v0.7.0 - 2012-05-06
-------------------

 - Initial development release version
