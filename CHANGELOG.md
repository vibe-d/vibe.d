Changelog
=========

v0.7.17 - 2013-
--------------------

### Features and improvements ###

 - Implemented a basic version of a WinRT based driver 
 - Removed a big chunk of deprecated functionality and deprecated schediuled declarations

### Bug fixes ###

 - 


v0.7.16 - 2013-06-26
--------------------

### Features and improvements ###

 - Fiber ownership of network connections and file streams is now handled implicitly to be more in line with classic blocking I/O and to lower the code overhead to share/pass connections between threads
 - Removed support for the "vibe" script (aka "VPM") in favor of DUB
 - Uses external Deimos packages instead of the included copies for binding to external C libraries
 - Improvements on the REST interface front (by Михаил Страшун aka Dicebot):
     - `registerRestInterface` deduces the base interface from a passed class instance
     - New overload of `registerRestInterface` for use with `@rootPath`
 - Added an overload of `handleWebSockets` that takes a function pointer
 - Improved documentation of `vibe.core.log` and re-enabled logging of date/time to plain text log files
 - Compiles with the release version of DMD 2.063 (various authors involved)
 - The idle handler is now called after processing all events in a spinning round after `yield()` call
 - Added `serveStaticFile` in addition to `serveStaticFiles` - [issue #227][issue227]
 - The thread/fiber ID is logged again by default if verbose logging is enabled

### Bug fixes ###

 - Fixed "INCR" and "DECR" methods in the Redis client - [issue #200][issue200], [issue #206][issue206]
 - Fixed the utility `HashMap` to properly call `GC.addRange` on manually allocated memory
 - Fixed erroneous crosstalk between multiple `ManualEvent` instances in the libevent driver
 - Fixed self-sending of messages to the caller in `vibe.core.concurrency`
 - Fixed syntax errors in the documentation of `URLRouter` - [issue #223][issue223]
 - Fixed calling the HTML logger from a thread that is not registered with the D runtime
 - Fixed `exitEventLoop` with no call to `enableWorkerThreads`, as well as when called from the idle handler
 - Fixed `HTTPServerRequest.path` to contain the URL-decoded version of the path - [issue #229][issue229]
 - Fixed `URLRouter` to not extract parameters of partial matches - [issue #230][issue230]
 - Fixed documentation example of `registerFormInterface`
 - Fixed lax indentation style checking in the Diet template compiler
 - Fixed unit tests for `parseMongoDBUrl` after the recently added support for digest authentication
 - Fixed construction of `Bson.Type.Regex` `Bson` objects (by Rene Zwanenburg) - [issue #238][issue238]
 - Fixed handling of Windows UNC paths - [See DUB issue #75][issue75dub]
 - Fixed the Redis methods taking varargs - [issue #234][issue234]
 - Fixed failure to free memory after an `SSLStream` has failed to initiate the tunnel

[issue200]: https://github.com/rejectedsoftware/vibe.d/issues/200
[issue206]: https://github.com/rejectedsoftware/vibe.d/issues/206
[issue223]: https://github.com/rejectedsoftware/vibe.d/issues/223
[issue227]: https://github.com/rejectedsoftware/vibe.d/issues/227
[issue229]: https://github.com/rejectedsoftware/vibe.d/issues/229
[issue230]: https://github.com/rejectedsoftware/vibe.d/issues/230
[issue234]: https://github.com/rejectedsoftware/vibe.d/issues/234
[issue238]: https://github.com/rejectedsoftware/vibe.d/issues/238
[issue75dub]: https://github.com/rejectedsoftware/dub/issues/75


v0.7.15 - 2013-04-27
--------------------

### Features and improvements ###
 
 - Improved the logging system with pluggable loggers, more specified verbose log levels, an HTML logger, and proper use of stdout/stderr
 - Added basic compile support for 64-bit Windows (using the "win32" driver)
 - Add a scoped alternative version of `vibe.core.concurrency.lock` (used for safe access to `shared` objects with unshared methods)
 - Add support to repeat the idle event until a new message arrives
 - Task is now weakly isolated and can thus be passed to other threads using `runWorkerTask`
 - Implemented digest authentication in the MongoDB client (by Christian Schneider aka HowToMeetLadies) - [pull #218][issue218]
 - The number of worker threads is now `core.cpuid.threadsPerCPU`
 - `TaskMutex` is now fully thread safe and has much lower overhead when no contention happens
 - `TaskCondition` now also works with a plain `Mutex` in addition to a `TaskMutex`
 - Removed the deprecated `Mutex` alias
 - Renamed `Signal` to `ManualEvent` to avoid confusion with other kinds of "signals"
 - `MemoryStream` now supports dynamically growing to the buffer limit
 - `HttpServer` will now drop incoming connections that don't send data within 10 seconds after the connection has been established
 - Added a new `createTimer` overload that doesn't automatically arm the timer after creation
 - `exitEventLoop` now by default also shuts down the worker threads (if `enableWorkerThreads` was called)
 - Added new command line options "--vv", "--vvv" and "--vvvv" to specify more verbose logging
 - Added connection pooling to the Redis client (by Junho Nurminen aka jupenur) - [pull #199][issue199]
 - Various documentation improvements and better adherence to the [style guide](http://vibed.org/style-guide)
 - Compiles with DMD 2.063 (mostly by Vladimir Panteleev aka CyberShadow) - [pull #207][issue207]
 - All examples now use exact imports rather than using `import vibe.vibe;` or `import vibe.d;`
 - Moved basic WWW form parsing from `vibe.http.form` to `vibe.inet.webform` to reduce intermodule dependencies and improve compile time
 - MongoDB URL parsing code uses `vibe.inet.webform` to parse query string arguments now instead of `std.regex` - improves compile time
 - Much more complete REST interface generator example (by Михаил Страшун aka Dicebot) - [pull #210][issue210]
 - Updated OpenSSL DLLs to 1.0.1e (important security fixes)
 - Renamed `EventedObject.isOwner` to `amOwner`
 - Improved intermodule dependencies, configuration option/file handling and added `pragma(lib)` (using "--version=VibePragmaLib") for more comfortable building without dub/vibe (by Vladimir Panteleev aka CyberShadow) - [pull #211][issue211]
 - Implemented an automatic command line help screen (inferred from calls to `vibe.core.args.getOption`)
 - Added meaningful error messages when the connection to a MongoDB or Redis server fails
 - Deprecated `vibe.http.server.startListening`, which is not necessary anymore

### Bug fixes ###

 - Fixed `vibe.core.concurrency.receiveTimeout` to actually work at all
 - Fixed `Win32Timer.stop` to reset the `pending` state and allow repeated calls
 - Fixed `HttpClient` to avoid running into keep-alive timeouts (will close the connection 2 seconds before the timeout now)
 - Fixed `HttpClient` to properly handle responses without a "Keep-Alive" header
 - Fixed `isWeaklyIsolated` for structs containing functions
 - Fixed all invalid uses of `countUntil` where `std.string.indexOf` should have been used instead - [issue #205][issue205]
 - Fixed spelling of the "--distport" command line switch and some documentation - [pull #203][issue203], [pull #204][issue204]
 - Fixed spurious error messages when accepting connections in the libevent driver (by Vladimir Panteleev aka CyberShadow) - [pull #207][issue207]
 - Fixed adjusting of method names in the REST interface generator for sub interfaces (by Михаил Страшун aka Dicebot) - [pull #210][issue210]
 - Fixed falling back to IPv4 if listening on IPv6 fails when calling `listenTCP` without a bind address
 - Fixed `Libevent2MenualEvent.~this` to not access GC memory which may already be finalized
 - Fixed `Win32TCPConnection.peerAddress` and `Win32UDPConnection.bindAddress`
 - Partially fixed automatic event loop exit in the Win32 driver (use -version=VibePartialAutoExit for now) - [pull #213][issue213]
 - Fixed `renderCompat` to work with `const` parameters
 - Fixed an error in the Deimos bindings (by Henry Robbins Gouk) - [pull #220][issue220]
 - Fixed a compilation error in the REST interface client (multiple definitions of "url__")

[issue190]: https://github.com/rejectedsoftware/vibe.d/issues/190
[issue199]: https://github.com/rejectedsoftware/vibe.d/issues/199
[issue203]: https://github.com/rejectedsoftware/vibe.d/issues/203
[issue204]: https://github.com/rejectedsoftware/vibe.d/issues/204
[issue205]: https://github.com/rejectedsoftware/vibe.d/issues/205
[issue207]: https://github.com/rejectedsoftware/vibe.d/issues/207
[issue210]: https://github.com/rejectedsoftware/vibe.d/issues/210
[issue211]: https://github.com/rejectedsoftware/vibe.d/issues/211
[issue213]: https://github.com/rejectedsoftware/vibe.d/issues/213
[issue218]: https://github.com/rejectedsoftware/vibe.d/issues/218
[issue220]: https://github.com/rejectedsoftware/vibe.d/issues/220


v0.7.14 - 2013-03-22
--------------------

### Features and improvements ###

 - Performance tuning for the HTTP server and client
 - Implemented distributed listening and HTTP server request processing (using worker threads to accept connections)
 - Stable memory usage for HTTP client and server (tested for 50 million requests)
 - Implemented new `TaskMutex` and `TaskCondition` classes deriving from Druntime's `Mutex` and `Condition` for drop-in replacement
 - Added a simplified version of the `std.concurrency` API that works with vibe.d's tasks (temporary drop-in replacement)
 - Added support for customizing the HTTP method and path using UDAs in the REST interface generator (by Михаил Страшун aka Dicebot) - [pull #189][issue189]
 - `vibe.core.mutex` and `vibe.core.signal` have been deprecated
 - Added support for WebDAV specific HTTP methods - see also [issue #109][issue109]
 - Compiles on DMD 2.061/2.062 in unit test mode
 - Added `Json.remove()` for JSON objects
 - Added `Isolated!T` in preparation of a fully thread-safe API
 - The package description now exposes a proper set of configurations
 - VPM uses the new download URL schema instead of relying on a `"downloadUrl"` field in the package description to stay forward compatible with DUB
 - The default order to listen is now IPv6 and then IPv4 to avoid the IPv4 listener blocking the IPv6 one on certain systems
 - Added `HttpServerSettings.disableDistHost` to force `listenHttp` to listen immediately, even during initialization
 - Added `WebSocket.receiveBinary` and `WebSocket.receiveText` - [issue #182][issue182]
 - Added `HttpServerResponse.writeRawBody` and `HttpClientResponse.readRwaBody` to allow for verbatim forwarding
 - ".gz" and ".tgz" are now recognized as compressed formats and are not transferred with a compressed "Content-Encoding"
 - Added a pure scoped callback based version of `requestHttp` to allow GC-less operation and also automatic pipelining of requests in the future

### Bug fixes ###

 - Fixed some possible crashes and memory leaks in the `HttpClient`
 - Fixed the `HttpRouter` interface to derive from `HttpServerRequestHandler`
 - Fixed parsing of version ranges in the deprecated VPM
 - Fixed some examples by added a `VibeCustomMain` version to their package.json
 - Fixed a possible range violation in the Diet compiler for raw/filter nodes
 - Fixed detection of horizontal lines in the Markdown parser
 - Fixed handling of one character methods in the REST interface generator - [pull #195][issue195]
 - Fixed the reverse proxy to not drop the "Content-Length" header
 - Fixed `HttpClient` to obey "Connection: close" responses
 - Fixed `Libevent2Signal` to not move tasks between threads

[issue109]: https://github.com/rejectedsoftware/vibe.d/issues/109
[issue182]: https://github.com/rejectedsoftware/vibe.d/issues/182
[issue189]: https://github.com/rejectedsoftware/vibe.d/issues/189
[issue195]: https://github.com/rejectedsoftware/vibe.d/issues/195


v0.7.13 - 2013-02-24
--------------------

### Features and improvements ###

 - Compiles with the latest DUB, which is now the recommended way to build vibe.d projects
 - Changed all public enums to use Phobos' naming convention (except for JSON and BSON)
 - Moved `vibe.http.common.StrMapCI` to `vibe.inet.nessage.InetHeaderMap`
 - Deprecated all hash modules in `vibe.crypto` in favor of `std.digest`
 - Deprecated the `vibe.crypto.ssl` module (functionality moved to `vibe.stream.ssl`)
 - Deprecated a number of functions that are available in Phobos
 - Deprecated the setter methods in the `Cookie` class

### Bug fixes ###

 - Fixed connection unlocking in the `HttpClient`
 - Fixed detection of unsuccessful SSL connection attempts
 - Fixed freeing of SSL/BIO contexts
 - Fixed some places in the deprecated VPM to use `Path.toNativeString()` instead of `Path.toString()`
 - Fixed the `package.json` file of the benchmark project
 - Fixed cross-thread incovations of `vibe.core.signal.Signal` in the Win32 driver
 - Fixed compilation on DMD 2.062 - [issue #183][issue183], [issue #184][issue184]

[issue183]: https://github.com/rejectedsoftware/vibe.d/issues/183
[issue184]: https://github.com/rejectedsoftware/vibe.d/issues/184


v0.7.12 - 2013-02-11
--------------------

### Features and improvements ###

 - Big refactoring of the MongoDB interface to be more consistent with its API (by Михаил Страшун aka Dicebot) - [pull #171][issue171]
 - Added a range interface to `MongoCursor` - redo of [pull #172][issue172]
 - Added a [dub](https://github.com/rejectedsoftware/dub) compatible "package.json" file for vibe.d and all example projects
 - Parameters can be made optional for `registerFormInterface` now (by Robert Klotzner aka eskimor) - [issue #156][issue156]
 - The REST interface generator also supports optional parameters by defining default parameter values
 - Added `Task.interrupt()`, `Task.join()` and `Task.running`
 - Improved detection of needed imports in the REST interface generater (by Михаил Страшун aka Dicebot) - [pull #164][issue164]
 - Partially implemented zero-copy file transfers (still disabled for libevent) - [issue #143][issue143]
 - Added `HttpRequest.contentType` and `contentTypeParameters` to avoid errors by direct comparison with the "Content-Type" header - [issue #154][issue154]
 - Added a small forward compatibility fix for [DUB](https://github.com/rejectedsoftware/dub) packages ("vibe.d" is ignored as a dependency)
 - Cleaned up the function names for writing out `Json` objects as a string and added convenience methods (partially done in [pull #166][issue166] by Joshua Niehus)
 - Renamed `HttpRequest.url` to `HttpRequest.requestUrl` and added `HttpRequest.fullUrl`
 - Added the possibility to write a request body in chunked transfer mode in the `HttpClient`
 - Added `HttpServerRequest.ssl` to determine if a request was sent encryted
 - Changed several interfaces to take `scope` delegates to avoid useless GC allocations
 - Removed the `in_url` parameter from `Path.toString` - now assumed to be `true`
 - `SysTime` and `DateTime` are now specially treated by the JSON/BSON serialization code
 - Refactored the `Cookie` interface to properly use `@property` (by Nick Sabalausky aka Abcissa) - [pull #176][issue176]
 - Added `HttpRouter` as an interface for `UrlRouter` (by Laurie Clark-Michalek aka bluepeppers) - [pull #177][issue177]
 - Changed `HttpFileServerSettings.maxAge` from `long` to `Duration` (by Nick Sabalausky aka Abcissa) - [pull #178][issue178]
 - Added `HttpFileServerSettings.preWriteCallback` (by Nick Sabalausky aka Abcissa) - [pull #180][issue180]

### Bug fixes ###

 - Fixed matching of the host name in `HttpServer` - is case insensitive now
 - Fixed issues in `ConnectionPool` and `HttpClient` that caused `InvalidMemoryOperationError` and invalid multiplexed requests
 - Fixed `GCAllocator` and `PoolAllocator` to enforce proper alignment
 - Fixed passing of misaligned base pointers to `free()` in `MallocAllocator` - at least 32-bit Linux seems to choke on it - [issue #157](issue157)
 - Fixed `listenTcp` without an explicit bind address - now returns an array of listeners with one entry per IP protocol version
 - Fixed "Connection: close" hangs also for HTTP/1.0 clients - those that depended on this behavior are broken anyway - [issue #147][issue147]
 - Fixed possible invalid line markers in the mixin generated by the Diet compiler - [issue #155][issue155]
 - Fixed all uses of `render!()` in the example projects by replacing them with `renderCompat!()` - [issue 159][issue159]
 - Fixed concatenation of `Path` objects, where the LHS is not normalized
 - Fixed `serializeToBson` in conjunction with read-only fields (by  Михаил Страшун aka Dicebot) - [pull #168][issue168]
 - Fixed a possible endless loop caused by `ChunkedOutputStream` due to an inconsistent redundant field
 - Fixed `serializeToJson` in conjunction with read-only fields (same fix as for BSON)
 - Fixed `download` ignoring the `port` property of the target URL
 - Fixed termination of Fibers by exceptions of already terminated tasks
 - Fixed propagation of `HttpStatusException` in the REST interface generator (by  Михаил Страшун aka Dicebot) - [pull #173][issue173]
 - Fixed handling of multiple cookies with the same name `HttpServerRequest.cookies.getAll()` can now be used to query them - fixes [issue #174][issue174]
 - Fixed `WebSocket.connected` - [issue #169][issue169]
 - Fixed accepting of invalid JSON syntax - [issue #161][issue161]
 - Fixed use of `tmpnam` on Posix by replacing with `mkstemps`, still used on Windows - [issue #137][issue137]
 - Fixed `ZlibInputStream.empty` to be consistent with `leastSize`

[issue137]: https://github.com/rejectedsoftware/vibe.d/issues/137
[issue143]: https://github.com/rejectedsoftware/vibe.d/issues/143
[issue154]: https://github.com/rejectedsoftware/vibe.d/issues/154
[issue155]: https://github.com/rejectedsoftware/vibe.d/issues/155
[issue156]: https://github.com/rejectedsoftware/vibe.d/issues/156
[issue157]: https://github.com/rejectedsoftware/vibe.d/issues/157
[issue159]: https://github.com/rejectedsoftware/vibe.d/issues/159
[issue161]: https://github.com/rejectedsoftware/vibe.d/issues/161
[issue164]: https://github.com/rejectedsoftware/vibe.d/issues/164
[issue166]: https://github.com/rejectedsoftware/vibe.d/issues/166
[issue168]: https://github.com/rejectedsoftware/vibe.d/issues/168
[issue169]: https://github.com/rejectedsoftware/vibe.d/issues/169
[issue171]: https://github.com/rejectedsoftware/vibe.d/issues/171
[issue172]: https://github.com/rejectedsoftware/vibe.d/issues/172
[issue173]: https://github.com/rejectedsoftware/vibe.d/issues/173
[issue176]: https://github.com/rejectedsoftware/vibe.d/issues/176
[issue177]: https://github.com/rejectedsoftware/vibe.d/issues/177
[issue178]: https://github.com/rejectedsoftware/vibe.d/issues/178
[issue180]: https://github.com/rejectedsoftware/vibe.d/issues/180


v0.7.11 - 2013-01-05
--------------------

### Features and improvements ###

 - The `setup-linux.sh` script now installs to `/usr/local/share` and uses any existing `www-data` user for its config if possible (by Jordi Sayol) - [issue #150][issue150], [issue #152][issue152], [issue #153][issue153]

### Bug fixes ###

 - Fixed hanging HTTP 1.1 requests with "Connection: close" when no "Content-Length" or "Transfer-Encoding" header is set - [issue #147][issue147]
 - User/group for privilege lowering are now specified as "user"/"group" in vibe.conf instead of "uid"/"gid" - see [issue #133][issue133]
 - Invalid uid/gid now actually cause the application startup to fail

[issue133]: https://github.com/rejectedsoftware/vibe.d/issues/133
[issue147]: https://github.com/rejectedsoftware/vibe.d/issues/147
[issue150]: https://github.com/rejectedsoftware/vibe.d/issues/150
[issue152]: https://github.com/rejectedsoftware/vibe.d/issues/152
[issue153]: https://github.com/rejectedsoftware/vibe.d/issues/153


v0.7.10 - 2013-01-03
--------------------

### Features and improvements ###

 - TCP sockets in the Win32 back end work now
 - Added support for struct and array parameters to `registerFormInterface` (by Robert Klotzner aka eskimor) - [issue #138][issue138], [issue #139][issue139], [issue #140][issue140]
 - `registerFormInterface` now ignores static methods (by Robert Klotzner aka eskimor) - [issue #136][issue136]
 - Added support for arbitrary expressions for attributes in Diet templates
 - Added `RedisClient.zrangebyscore` and fixed the return type of `RedistClient.ttl` (`long`) (by Simon Kerouack aka ekyo) - [issue #141][issue141]
 - `renderCompat()` does not require the parameter values to be wrapped in a Variant anymore
 - Added a `BsonObjectID.timeStamp` property that extracts the unix time part
 - Added a versions of `deserialize(B/J)son` that return the result instead of writing it to an out parameter
 - The REST interface client now can handle more foreign types by searching for all needed module imports recursively
 - `listenTcp` now returns a `TcpListener` object that can be used to stop listening again
 - Added `vibe.inet.message.decodeEncodedWords` and `decodeEmailAddressHeader`
 - Added `compileDietFileMixin` usable for directly mixing in Diet templates (they are instantiated in the caller scope)
 - The SMTP client now prints the last command whenever an error is returned from the server - see [issue #126][issue126]
 - Documentation improvements
 - All examples now use `shared static this` instead of `static this` so that they will behave correctly once multi-threading gets enabled
 - `vibe.core` now only depends on `vibe.inet` and `vibe.utils.memory` and thus is ready to be used as a stand-alone library
 - `Bson.length` is now allowed for `Bson.Type.Object` and added `Bson.EmptyArray`
 - Setting `HttpFileServerSettings.maxAge` to zero will cause the "Expires" and "Cache-Control" headers to be omitted
 - `Url` can now be constructed as `Url(str)` in addition to `Url.parse(str)`
 - The HTTP server logger now logs the requesting host name instead of the selected configuration's host name
 - Using `ParameterIdentifierTuple` now for the REST interface generator, which makes the `_dummy` parameter hack unnecessary
 - Compiles with DMD 2.061 and on Win64
 - User and group names are now accepted in addition to UID/GID in /etc/vibe/vibe.conf - [issue #133][issue133]

### Bug fixes ###

 - Fixed forwarding of non-ASCII unicode characters in `htmlEscape`
 - Fixed the Diet template parser to accept underscores in ID and class identifiers
 - Fixed HEAD requests properly falling back to GET routes in the `UrlRouter`
 - Fixed parsing of unicode escape sequences in the JSON parser - [issue #146][issue146]
 - Made `vibe.core.mutex.Mutex` actually pass its unit tests
 - Fixed compile errors occuring when using the field selector parameter of `MongoDB.find/findOne/findAndModify`
 - Fixed some cases of `InvalidMemoryOperationError` in ConnectionPool/LockedConnection - possibly [issue #117][issue117]
 - Avoid passing `0x8000` (`O_BINARY`) on non-Windows systems to `open()`, as this may cause the call to fail (by Martin Nowak) - [issue #142][issue142]
 - Fixed creation of HTTP sessions (were not created before at least one key was set)
 - Fixed the error detection code (safe mode) for the MongoDB client
 - `int` values are now correctly serialized as `Bson.Type.Int` instead of `Bson.Type.Long`
 - Fixed handling of the "X-Forwarded-For" header in the reverse proxy server in case of a proxy chain
 - During the build, temporary executables are now built in `%TEMP%/.rdmd/source` so they pick up the right DLL versions
 - Fixed the daytime example (`readLine` was called with a maximum line length of zero) - [issue #122][issue122], [issue #123][issue123]

[issue117]: https://github.com/rejectedsoftware/vibe.d/issues/117
[issue122]: https://github.com/rejectedsoftware/vibe.d/issues/122
[issue123]: https://github.com/rejectedsoftware/vibe.d/issues/123
[issue126]: https://github.com/rejectedsoftware/vibe.d/issues/126
[issue133]: https://github.com/rejectedsoftware/vibe.d/issues/133
[issue136]: https://github.com/rejectedsoftware/vibe.d/issues/136
[issue138]: https://github.com/rejectedsoftware/vibe.d/issues/138
[issue139]: https://github.com/rejectedsoftware/vibe.d/issues/139
[issue140]: https://github.com/rejectedsoftware/vibe.d/issues/140
[issue141]: https://github.com/rejectedsoftware/vibe.d/issues/141
[issue142]: https://github.com/rejectedsoftware/vibe.d/issues/142
[issue146]: https://github.com/rejectedsoftware/vibe.d/issues/146


v0.7.9 - 2012-10-30
-------------------

### Features and improvements ###

 - Implemented an automated HTML form interface generator in `vibe.http.form` (by Robert Klotzner aka eskimor) - [issue #106][issue106]
 - The REST interface now uses fully qualified names and local imports to resolve parameter/return types, making it much more robust (by Михаил Страшун aka mist) - [issue #108][issue108]
 - The Diet template compiler now supports includes and recursive extensions/layouts - [issue #32][issue32], 
 - Added support for WebSocket binary messages and closing connections (by kyubuns) - [issue #118][issue118]
 - Implemented a directory watcher for the Win32 driver
 - Removed `vibe.textfilter.ddoc` - now in <http://github.com/rejectedsoftware/ddox>
 - Cleaned up command line handling (e.g. application parameters are now separated from vibe parameters by --)
 - Dependencies in package.json can now have "~master" as the version field to take the lastest master version instead of a tagged version
 - Renamed `UrlRouter.addRoute()` to `UrlRouter.match()`
 - Moved Path into its own module (`vibe.inet.path`)
 - Task local storage is now handled directly by `Task` instead of in `vibe.core.core`
 - (de)serialze(To)(Json/Bson) now support type customization using (to/from)(Json/Bson) methods
 - (de)serialze(To)(Json/Bson) now strip a trailing underscore in field names, if present - allows to use keywords as field names
 - `Json.opt!()` is now much faster in case of non-existent fields
 - Added `Bson.toJson()` and `Bson.fromJson()` and deprecated `Bson.get!Json()` and `cast(Json)bson`
 - Implemented `InputStream.readAllUtf8()` - strips BOM and sanitizes or validates the input
 - Implemented `copyFile()` to supplement `moveFile()`
 - Added RandomAccessStream interface
 - Implemented a github like variant of Markdown more suitable for marking up conversation comments
 - The Markdown parser now takes flags to control its behavior
 - Made ATX header and automatic link detection in the Markdown parser stricter to avoid false detections
 - Added `setPlainLogging()` - avoids output of thread and task id
 - Avoiding some bogous error messages in the HTTP server (when a peer closes a connection actively)
 - Renamed the string variant of `filterHtmlAllEscape()` to `htmlAllEscape()` to match similar functions
 - `connectMongoDB()` will now throw if the connection is not possible - this was deferred to the first command up to now
 - By default a `MongoDB` connection will now have the 'safe' flag set
 - The default max cache age for the HTTP file server is now 1 day instead of 30 days
 - Implemented `MemoryStream` - a rendom access stream operating on a `ubyte[]` array.
 - The form parser in the HTTP server now enforces the maximum input line width
 - A lot of documentation improvements

### Bug fixes ###

 - Fixed a possible endless loop in `ZlibInputStream` - now triggers an assertion instead; Still suffering from [DMD bug 8779](http://d.puremagic.com/issues/show_bug.cgi?id=8779) - [issue #56][issue56]
 - Fixed handling of escaped characters in Diet templates and dissallowed use of "##" to escape "#"
 - Fixed "undefined" appearing in the stringified version of JSON arrays or objects (they are now filtered out)
 - Fixed the error message for failed connection attempts
 - Fixed a bug in `PoolAllocator.realloc()` that could cause a range violation or corrupted memory - [issue #107][issue107]
 - Fixed '//' comments in the Diet template compiler
 - Fixed and optimized `readUntil` - it now also obeys the byte limit, if given
 - Fixed parsing of floating-point numbers with exponents in the JSON parser
 - Fixed some HTML output syntax errors in the Markdown compiler

[issue32]: https://github.com/rejectedsoftware/vibe.d/issues/32
[issue56]: https://github.com/rejectedsoftware/vibe.d/issues/56
[issue106]: https://github.com/rejectedsoftware/vibe.d/issues/106
[issue107]: https://github.com/rejectedsoftware/vibe.d/issues/107
[issue108]: https://github.com/rejectedsoftware/vibe.d/issues/108
[issue118]: https://github.com/rejectedsoftware/vibe.d/issues/118


v0.7.8 - 2012-10-01
-------------------

### Features and improvements ###

 - Added support for UDP sockets
 - The reverse proxy now adds the headers "X-Forwarded-For" and "X-Forwarded-Host"
 - `MongoCollection.findAndModify` returns the resulting object only now instead of the full reply of the protocol
 - Calling `MongoCollection.find()` without arguments now returns all documents of the collection
 - Implemented "vibe init" to generate a new app skeleton (by 1100110) - [issue #95][issue95], [issue #99][issue99]
 - The application's main module can now also be named after the package name instead of 'app.d' (by 1100110) - [issue #88][issue88], [issue #89][issue89]
 - The default user/group used on Linux for privilege lowering has been renamed to 'www-vibe' to avoid name clashes with possibly existing users named 'vibe' (by Jordy Sayol) - [issue #84][issue84]
 - `BsonBinData` is now converted to a Base-64 encoded string when the BSON value is converted to a JSON value
 - `BsonDate` now has `toString`/`fromString` for an ISO extended representation so that its JSON serialization is now a string
 - The Diet parser now supports string interpolations inside of style and script tags.
 - The Diet parser now enforces proper indentation (i.e. the number of spaces used for an indentation level has to be a multiple of the base indent) - see [issue #3][issue3]
 - The Diet parser now supports unescaped string interpolations using !{}
 - The JSON de(serializer) now supports pointer types
 - Upgraded libevent to v2.0.20 and OpenSSL to v1.0.1c on Windows
 - The Win32 driver now has a working Timer implementation
 - `OutputStream` now has an output range interface for the types ubyte and char
 - The logging functions use 'auto ref' instead of 'lazy' now to avoid errors of the kind "this(this) is not nothrow"
 - The markdown text filter now emits XHTML compatible &lt;br/&gt; tags instead of &lt;br&gt; (by cybevnm) - [issue #98][issue98]
 - The REST interface generator now uses plain strings instead of JSON for query strings and path parameters, if possible
 - The `UrlRouter` now URL-decodes all path parameters

### Bug fixes ###

 - Fixed a null dereference for certain invalid HTTP requests that caused the application to quit
 - Fixed `setTaskStackSize()` to actually do anything (the argument was ignored somwhere along the way to creating the fiber)
 - Fixed parameter name parsing in the REST interface generator for functions with type modifiers on their return type (will be obsolete once __traits(parameterNames) works)
 - Fixed a too strict checking of email adresses and using `std.net.isemail` now to perform proper checking on DMD 2.060 and up - [issue #103][issue103]
 - Fixed JSON deserialization of associative arrays with a value type different than 'string'
 - Fixed empty peer fields in `HttpServerRequest` when the request failed to parse properly
 - Fixed `yield()` calls to avoid stack overflows and missing I/O events due to improper recursion
 - Fixed the Diet parser to allow inline HTML as it should
 - Fixed the Diet parser to actually output singular HTML elements as singular elements
 - Fixed tight loops with `yield()` not causing I/O to stop in the win32 back end
 - Fixed code running from within `static this()` not being able to use vibe.d I/O functions
 - Fixed a "memory leak" (an indefinitely growing array)
 - Fixed parsing of one-character JSON strings (by Михаил Страшун aka mist) - [issue #96][issue96]
 - Fixed the Diet parser to not HTML escape attributes and to properly escape quotation marks (complying with Jade's behavior)
 - Fixed the Diet parser to accept an escaped hash (\#) as a way to avoid string interpolations 
 - Fixed a bug in MongoDB cursor end detection causing spurious exceptions
 - Fixed the Markdown parser to now recognize emphasis at the start of a line as an unordered list
 - Fixed the form parsing to to not reject a content type with character set specification
 - Fixed parsing of unicode character sequences in JSON strings
 - Fixed the 100-continue response to end with an empty line

[issue3]: https://github.com/rejectedsoftware/vibe.d/issues/3
[issue84]: https://github.com/rejectedsoftware/vibe.d/issues/84
[issue88]: https://github.com/rejectedsoftware/vibe.d/issues/88
[issue89]: https://github.com/rejectedsoftware/vibe.d/issues/89
[issue95]: https://github.com/rejectedsoftware/vibe.d/issues/95
[issue96]: https://github.com/rejectedsoftware/vibe.d/issues/96
[issue98]: https://github.com/rejectedsoftware/vibe.d/issues/98
[issue99]: https://github.com/rejectedsoftware/vibe.d/issues/99
[issue103]: https://github.com/rejectedsoftware/vibe.d/issues/103


v0.7.7 - 2012-08-05
-------------------

### Features and improvements ###

 - Compiles with DMD 2.060 - [issue #70][issue70]
 - Some considerable improvements and fixes for the REST interface generator - it is now also actually used and tested in another project
 - MongoDB supports `mongodb://` URLs for specifying various connection settings instead of just host/port (by David Eagen) - [issue #80][issue80], [issue #81][issue81]
 - Added `RestInterfaceClient.requestFilter` to enable authentication and similar add-on functionality
 - JSON floating-point numbers are now stringified with higher precision
 - Improved const-correctness if the Bson struct (by cybevnm) - [issue #77][issue77]
 - Added `setIdleHandler()` to enable tasks that run when all events have been processed
 - Putting a '{' at the end of a D statement in a Diet template instead of using indentation for nesting will now give an error
 - API documentation improvements

### Bug Fixes ### 

 - The HTTP server now allows query strings that are not valid forms - [issue #73][issue73]

[issue70]: https://github.com/rejectedsoftware/vibe.d/issues/70
[issue73]: https://github.com/rejectedsoftware/vibe.d/issues/73
[issue77]: https://github.com/rejectedsoftware/vibe.d/issues/77
[issue80]: https://github.com/rejectedsoftware/vibe.d/issues/80
[issue81]: https://github.com/rejectedsoftware/vibe.d/issues/81


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
 - Fixed JSON (de)serialization of structs and classes (member names were wrong) - [issue #72][issue72]
 - Fixed `(filter)urlEncode` for character values < 0x10 - [issue #65][issue65]

[issue65]: https://github.com/rejectedsoftware/vibe.d/issues/65
[issue72]: https://github.com/rejectedsoftware/vibe.d/issues/72

 
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
 - On *nix now uses pkg-config to find linker dependencies if possible (dawgfoto) - [issue #52][issue52]
 - The static HTTP file server now resolves paths with '.' and '..' instead of simply refusing them
 - Implemented handling of `HttpServerSettings.maxRequestTime`
 - Added `setLogFile()`
 - The vibe.cmd script now works with paths containing spaces
 - `Libevent2TcpConnection` now enforces proper use of `acquire()/release()`
 - Improved stability in conjunction with TCP connections
 - Upgraded libevent to 2.0.19 on Windows

[issue52]: https://github.com/rejectedsoftware/vibe.d/issues/52

 
v0.7.3 - 2012-05-22
-------------------

 - Hotfix release, fixes a bug that could cause a connection to be dropped immediately after accept

 
v0.7.2 - 2012-05-22
-------------------

 - Added support for timers and `sleep()`
 - Proper timeout handling for Connection: keep-alive is in place - fixes "Operating on closed connection" errors - [issue #20][issue20], [issue #43][issue43]
 - Setting DFLAGS to change compiler options now actually works
 - Implemented `SslStream`, wich is now used instead of libevent's SSL code - fixes a hang on Linux/libevent-2.0.16 - [issue #29][issue29]
 - The REST interface generator now supports `index()` methods and 'id' parameters to customize the protocol
 - Changed the type for durations from `int/double` to `Duration` - [issue #18][issue18]
 - Using Deimos bindings now instead of the custom ones - [issue #48][issue48]

[issue18]: https://github.com/rejectedsoftware/vibe.d/issues/18
[issue20]: https://github.com/rejectedsoftware/vibe.d/issues/20
[issue29]: https://github.com/rejectedsoftware/vibe.d/issues/29
[issue43]: https://github.com/rejectedsoftware/vibe.d/issues/43
[issue48]: https://github.com/rejectedsoftware/vibe.d/issues/48

 
v0.7.1 - 2012-05-18
-------------------

 - Performance tuning
 - Added `vibe.utils.validation`
 - Various fixes and improvements

 
v0.7.0 - 2012-05-06
-------------------

 - Initial development release version
