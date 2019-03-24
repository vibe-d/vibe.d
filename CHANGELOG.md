Changelog
=========

v0.8.5 - 2019-03-24
-------------------

### Features and improvements ###

- The TLS package was updated to use OpenSSL 1.1.x by default - [pull #2190][issue2190]
    - Using OpenSSL 1.1.0a on Windows
    - Auto-detecting the OpenSSL version on Posix systems, falling back to 1.1.x if that fails (by Sebastian Wilzbach) - [issue #2053][issue2053]
    - The exact version can still be pre-selected using the build configuration of "vibe-d:tls"
- Compiles on DMD 2.076.1 up to 2.085.0 and LDC 1.14.0
- Added support for OpenSSL 1.1.1 (by Jan Jurzitza aka WebFreak001) - [issue #2214][issue2214], [pull #2226][issue2226]
- `URL.port` now returns the value of `defaultPort`, if no explicit port was specified (by Szabo Bogdan aka gedaiu) - [pull #2176][issue2176]
- Changed `Bson.opEquals` to yield true for objects with the same fields but different field order (by Igor Stepanov) - [pull #2183][issue2183]
- Removed the DNS lookup cache from the libevent driver (by Márcio Martins) - [pull #2257][issue2257]
- Added an overload of `serveRestJSClient` that uses server-relative URIs (by Oleg B. aka deviator) - [issue #2222][issue2222], [pull #2223][issue2223]
- Added `StdFileStream.stdFile` property (by Benjamin Schaaf) - [pull #2248][issue2248]
- `vibe.web.common.WebParamAttribute` and `PathAttribute` are now public for external introspection purposes (by Robert Schadek) - [pull #2250][issue2250], [pull #2263][issue2263]
- Added an overload of `BsonDate.toSysTime` taking a time zone (by Jan Jurzitza aka WebFreak001) - [pull #2252][issue2252]
- Added `MemoryStream.truncate` and enable `seek` to be used to grow the stream size - [pull #2251][issue2251]
- Array parameters for the web interface generator can now be sent as form parameters without explicit index (by Steven Schveighoffer) - [pull #2247][issue2247]
- `vibe.utils.hashmap.HashMap` now supports singleton allocators without an object wrapper - [pull #2236][issue2236]

### Bug fixes ###

- Fixed `RestInterfaceSettings.dup` to properly duplicate the `httpClientSettings` field (by Vitali Karabitski aka vitalka200)- [pull #2197][issue2197]
- Fixed a compile error in `Bson.get!BsonRegex` (by Tuukka Kurtti aka Soletek) - [pull #2224][issue2224]
- Fixed host name string conversion for `SyslogLogger` (by Tomáš Chaloupka) - [pull #2220][issue2220]
- Fixed invalid ALPN string conversion in `OpenSSLStream` (by Francesco Galla) - [issue #2235][issue2235], [pull #2235][issue2235]
- Fixed a null pointer access in `OpenSSLStream` if `read` was called after `close` (by Francesco Galla) - [pull #2238][issue2238]
- Fixed detection of broken quoted-printable encodings (by Adam Williams) - [pull #2237][issue2237]
- Fixed `Json.clone` for fields of type array (by Szabo Bogdan) - [pull #2249][issue2249]
- Fixed erroneous writing of a response body for certain status codes in the REST interface generator (by Tomáš Chaloupka) - [issue #2268][issue2268], [pull #2269][issue2269]
- Fixed concurrent outgoing WebSocket connections and a socket descriptor leak - [issue #2169][issue2169], [pull #2265][issue2265]
- Fixed `@safe` inference for `JsonStringSerializer` (by Tomáš Chaloupka) - [pull #2274][issue2274], [issue #1941][issue1942]

[issue1941]: https://github.com/vibe-d/vibe.d/issues/1941
[issue2053]: https://github.com/vibe-d/vibe.d/issues/2053
[issue2169]: https://github.com/vibe-d/vibe.d/issues/2169
[issue2176]: https://github.com/vibe-d/vibe.d/issues/2176
[issue2183]: https://github.com/vibe-d/vibe.d/issues/2183
[issue2190]: https://github.com/vibe-d/vibe.d/issues/2190
[issue2214]: https://github.com/vibe-d/vibe.d/issues/2214
[issue2226]: https://github.com/vibe-d/vibe.d/issues/2226
[issue2222]: https://github.com/vibe-d/vibe.d/issues/2222
[issue2223]: https://github.com/vibe-d/vibe.d/issues/2223
[issue2197]: https://github.com/vibe-d/vibe.d/issues/2197
[issue2224]: https://github.com/vibe-d/vibe.d/issues/2224
[issue2220]: https://github.com/vibe-d/vibe.d/issues/2220
[issue2235]: https://github.com/vibe-d/vibe.d/issues/2235
[issue2235]: https://github.com/vibe-d/vibe.d/issues/2235
[issue2236]: https://github.com/vibe-d/vibe.d/issues/2236
[issue2237]: https://github.com/vibe-d/vibe.d/issues/2237
[issue2238]: https://github.com/vibe-d/vibe.d/issues/2238
[issue2247]: https://github.com/vibe-d/vibe.d/issues/2247
[issue2248]: https://github.com/vibe-d/vibe.d/issues/2248
[issue2249]: https://github.com/vibe-d/vibe.d/issues/2249
[issue2250]: https://github.com/vibe-d/vibe.d/issues/2250
[issue2251]: https://github.com/vibe-d/vibe.d/issues/2251
[issue2252]: https://github.com/vibe-d/vibe.d/issues/2252
[issue2257]: https://github.com/vibe-d/vibe.d/issues/2257
[issue2263]: https://github.com/vibe-d/vibe.d/issues/2263
[issue2265]: https://github.com/vibe-d/vibe.d/issues/2265
[issue2268]: https://github.com/vibe-d/vibe.d/issues/2268
[issue2269]: https://github.com/vibe-d/vibe.d/issues/2269
[issue2274]: https://github.com/vibe-d/vibe.d/issues/2274


v0.8.4 - 2018-06-02
-------------------

Small release with official support for DMD 2.080.0 and LDC 1.9.0, which contains a number of fixes and improvements. 

### Features and improvements ###

- Compiles on DMD DMD 2.074.1 up to 2.080.0 and LDC 1.9.0
- Added `RestInterfaceClient.requestBodyFilter` to be able to add request headers based on the body contents - [pull #2136][issue2136]
- Added an optional `status` parameter to `vibe.web.web.redirect` (by Sebastian Wilzbach) - [pull #1948][issue1948]
- Added support for `string` return values as body contents for the web interface generator (by Sebastian Wilzbach) - [pull #1854][issue1854]
- Added full support for Redis URLs (by Sebastian Wilzbach) - [pull #1842][issue1842]
- Added `RedisZSet.rangeByLex` and `.countByLex` (by Geoffrey-A) - [pull #2141][issue2141]
- Added `MongoClientSettings.maxConnections` (by Denis Feklushkin aka denizzzka) - [pull #2145][issue2145]
- Added handling of `UUID` values in the JSON serializer (serialized as string) (by Benjamin Schaaf) - [pull #2088][issue2088], [pull #2158][issue2158]
- Added `FixedRingBuffer.putFront` - [pull #2114][issue2114]
- Added support for `UUID` parameters in the REST interface generator (by Tomáš Chaloupka) - [pull #2162][issue2162]
- Added support for `UUID` BSON serialization (by Tomáš Chaloupka) - [issue #2161][issue2161], [pull #2163][issue2163]
- The JSON serializer now ignores object fields with undefined values (by Szabo Bogdan aka gedaiu) - [pull #2149][issue2149]
- Empty request bodies are now handled gracefully when accessing `req.json` (by Sebastian Wilzbach) - [pull #2042][issue2042]
- Eliminated a few GC allocations and redundant operations (by Boris Barboris) - [pull #2135][issue2135], [pull #2138][issue2138]
- On Linux, uses the `getrandom` syscall instead of /dev/urandom, if possible (by Nathan Sashihara aka n8sh) - [pull #2093][issue2093]
- Uses `secure_arc4random` on Android (by Nathan Sashihara aka n8sh) - [pull #2113][issue2113]

### Bug fixes ###

- Fixed serialization of single-element tuples - [issue #2110][issue2110], [pull #2111][issue2111]
- Fixed closing of non-keepalive HTTP client connections, if set from the response callback - [pull #2112][issue2112]
- Fixed handling of enum types with base type `string` in the web interface generator (by Thibaut Charles) - [pull #2100][issue2100]
- Fixed handling of regular TLS stream remote shutdown in `OpenSSLStream.leastSize` and `.empty` - [pull #2117][issue2117]
- Fixed TLS peer certificate validation failures for certain certificates (by Márcio Martins) - [pull #2121][issue2121]
- Fixed delayed connection close in `OpenSSLStream` and `HTTPClient` - [064ddd66][commit064ddd66], [064ddd66][commite3a0d3a1]
- Fixed a range violation error in the Markdown parser for table rows with more column separators than table columns (by Jan Jurzitza WebFreak001) - [issue #2132][issue2132], [pull #2133][issue2133]
- Fixed `Path.bySegment` (the legacy implementation in `vibe-d:core`) to insert an empty segment for absolute Posix paths, like `vibe-core` does - [pull #2143][issue2143]
- Fixed JSON serialization of non-immutable and wide character strings - [issue #2150][issue2150], [pull #2151][issue2151]
- Fixed bogus "mailto" links generated by the Markdown parser - [pull #2165][issue2165]
- Fixed handling of Digest authentication headers with equal signs occurring in a field value (by Geoffrey-A) - [issue #2023][issue2023], [pull #2059][issue2059]
- Fixed behavior for buggy HTTP/1 servers that advertise keep-alive without a content length (by Tomáš Chaloupka) - [pull #2167][issue2167]

[commit064ddd66]: https://github.com/vibe-d/vibe.d/commit/064ddd6638cae017c6882f6ae0067a2dc10cc6c3
[commite3a0d3a1]: https://github.com/vibe-d/vibe.d/commit/e3a0d3a18ff91d7b6e1ff7300a5c039cf7d0bb45
[issue1842]: https://github.com/vibe-d/vibe.d/issues/1842
[issue1854]: https://github.com/vibe-d/vibe.d/issues/1854
[issue1948]: https://github.com/vibe-d/vibe.d/issues/1948
[issue2023]: https://github.com/vibe-d/vibe.d/issues/2023
[issue2042]: https://github.com/vibe-d/vibe.d/issues/2042
[issue2059]: https://github.com/vibe-d/vibe.d/issues/2059
[issue2088]: https://github.com/vibe-d/vibe.d/issues/2088
[issue2093]: https://github.com/vibe-d/vibe.d/issues/2093
[issue2100]: https://github.com/vibe-d/vibe.d/issues/2100
[issue2110]: https://github.com/vibe-d/vibe.d/issues/2110
[issue2111]: https://github.com/vibe-d/vibe.d/issues/2111
[issue2112]: https://github.com/vibe-d/vibe.d/issues/2112
[issue2113]: https://github.com/vibe-d/vibe.d/issues/2113
[issue2114]: https://github.com/vibe-d/vibe.d/issues/2114
[issue2117]: https://github.com/vibe-d/vibe.d/issues/2117
[issue2121]: https://github.com/vibe-d/vibe.d/issues/2121
[issue2132]: https://github.com/vibe-d/vibe.d/issues/2132
[issue2133]: https://github.com/vibe-d/vibe.d/issues/2133
[issue2135]: https://github.com/vibe-d/vibe.d/issues/2135
[issue2136]: https://github.com/vibe-d/vibe.d/issues/2136
[issue2138]: https://github.com/vibe-d/vibe.d/issues/2138
[issue2141]: https://github.com/vibe-d/vibe.d/issues/2141
[issue2143]: https://github.com/vibe-d/vibe.d/issues/2143
[issue2145]: https://github.com/vibe-d/vibe.d/issues/2145
[issue2149]: https://github.com/vibe-d/vibe.d/issues/2149
[issue2150]: https://github.com/vibe-d/vibe.d/issues/2150
[issue2151]: https://github.com/vibe-d/vibe.d/issues/2151
[issue2158]: https://github.com/vibe-d/vibe.d/issues/2158
[issue2161]: https://github.com/vibe-d/vibe.d/issues/2161
[issue2162]: https://github.com/vibe-d/vibe.d/issues/2162
[issue2163]: https://github.com/vibe-d/vibe.d/issues/2163
[issue2165]: https://github.com/vibe-d/vibe.d/issues/2165
[issue2167]: https://github.com/vibe-d/vibe.d/issues/2167


v0.8.3 - 2018-03-08
-------------------

The deprecation phase of the legacy "vibe-d:core" module starts with this release by defaulting to the new "vibe-core" package. Additionally, DMD 2.079.0 is supported and some notable improvements have been made to the HTTP implementation, as well as other parts of the library.

### Features and improvements ###

- The "vibe-core" package is now used by default - the "libevent"/"win32"/"libasync" configurations can still be used to continue using the legacy vibe-d:core package, but beware that it will be removed by the end of the year
- Compiles on DMD 2.073.2 up to 2.079.0 and LDC 1.3.0 up to 1.8.0
- HTTP sub system
    - `URLRouter` has been refactored to avoid fragment the heap during the initialization phase, which can cut process memory usage dramatically - [issue #1359][issue1359], [pull #2043][issue2043]
    - Added `WebSocketCloseReason ` and improved close reason handling (by Andrew Benton) - [pull #1990][issue1990]
    - Added `HTTPClientSettings.tlsContextSetup` to enable more fine-grained TLS settings customization - [pull #2071][issue2071]
    - Added a check in `HTTPServerResponse.redirect` to avoid sending any control characters (e.g. header injections) - [pull #2074][issue2074]
    - Added `createDigestAuthHeader` to create a client header for HTTP digest authentication (by Tomáš Chaloupka) - [pull #1931][issue1931]
    - Deprecated all parsing related `HTTPServerOption` values (by Sebastian Wilzbach) - [pull #1947][issue1947]
    - Changed the HTTP file server to not send cache directives by default - [pull #2031][issue2031]
- Added `RestInterfaceSettings.errorHandler` to enable customization of error responses - [pull #2072][issue2072]
- Reworked MongoDB cursor support to properly support aggregation on 3.6 servers (by Jan Jurzitza aka WebFreak001) - [issue #1718][issue1718], [issue #2036][issue2036], [pull #2037][issue2037]
- Changed the MongoDB code to default to SCRAM-SHA-1 authentication (by Sebastian Wilzbach) - [issue #1967][issue1967], [pull #2027][issue2027]
- Made `remove` and `exists` available from the various `Redis...` container types (by Geoffrey-A) - [pull #2026][issue2026]
- Now uses `arc4random_buf` instead of "/dev/urandom" on systems that support it with a secure hash function (by Nathan Sashihara) - [pull #2063][issue2063]
- Added conversion functions for `Json` <-> `std.json.JSONValue` (by Jan Jurzitza aka WebFreak001) - [issue #1465][issue1465], [pull #1904][issue1904], [pull #2085][issue2085]

### Bug fixes ###

- Fixed compilation on DragonFlyBSD (by Diederik de Groot) - [pull #2028][issue2028]
- Fixed `RedisHash.opIndexAssign!"-"` (by Geoffrey-A) - [pull #2013][issue2013]
- Fixed `DictionaryList` to work with class/interface types (by H. S. Teoh aka quickfur) - [issue #2004][issue2004], [pull #2005][issue2005]
- Fixed compilation of types with `@system` getters/setters in the serialization module - [issue #1991][issue1991], [issue #1941][issue1941], [pull #2001][issue2001]
- Fixed compilation of methods with unsafe return types in the REST interface generator (by Martin Nowak) - [pull #2035][issue2035]
- Fixed a connection leakage in `vibe.inet.urltransfer` (by Martin Nowak) - [pull #2050][issue2050]
- Fixed parsing the host part of `file://` URLs - [issue #2048][issue2048], [pull #2049][issue2049]
- Fixed handling of `https+unix://` URLs in the HTTP client (by Les De Ridder) - [pull #2070][issue2070]
- Fixed the HTTP proxy mode to default to "reverse" (regression in 0.8.2) - [pull #2056][issue2056]
- Fixed the HTTP client to send a valid "Host" header when requesting from an IPv6 URL - [issue #2080][issue2080], [pull #2082][issue2082]
- Fixed the old `Path` implementation to preserve trailing slashes on Windows (by Martin Nowak) - [pull #2079][issue2079]
- Fixed a regression (0.8.2) in `HTTPServerRequest.rootDir` - [pull #2032][issue2032]

[issue1359]: https://github.com/vibe-d/vibe.d/issues/1359
[issue1465]: https://github.com/vibe-d/vibe.d/issues/1465
[issue1718]: https://github.com/vibe-d/vibe.d/issues/1718
[issue1904]: https://github.com/vibe-d/vibe.d/issues/1904
[issue1931]: https://github.com/vibe-d/vibe.d/issues/1931
[issue1941]: https://github.com/vibe-d/vibe.d/issues/1941
[issue1947]: https://github.com/vibe-d/vibe.d/issues/1947
[issue1967]: https://github.com/vibe-d/vibe.d/issues/1967
[issue1990]: https://github.com/vibe-d/vibe.d/issues/1990
[issue1991]: https://github.com/vibe-d/vibe.d/issues/1991
[issue2001]: https://github.com/vibe-d/vibe.d/issues/2001
[issue2004]: https://github.com/vibe-d/vibe.d/issues/2004
[issue2005]: https://github.com/vibe-d/vibe.d/issues/2005
[issue2013]: https://github.com/vibe-d/vibe.d/issues/2013
[issue2026]: https://github.com/vibe-d/vibe.d/issues/2026
[issue2027]: https://github.com/vibe-d/vibe.d/issues/2027
[issue2028]: https://github.com/vibe-d/vibe.d/issues/2028
[issue2031]: https://github.com/vibe-d/vibe.d/issues/2031
[issue2032]: https://github.com/vibe-d/vibe.d/issues/2032
[issue2036]: https://github.com/vibe-d/vibe.d/issues/2036
[issue2037]: https://github.com/vibe-d/vibe.d/issues/2037
[issue2043]: https://github.com/vibe-d/vibe.d/issues/2043
[issue2048]: https://github.com/vibe-d/vibe.d/issues/2048
[issue2049]: https://github.com/vibe-d/vibe.d/issues/2049
[issue2050]: https://github.com/vibe-d/vibe.d/issues/2050
[issue2056]: https://github.com/vibe-d/vibe.d/issues/2056
[issue2063]: https://github.com/vibe-d/vibe.d/issues/2063
[issue2070]: https://github.com/vibe-d/vibe.d/issues/2070
[issue2071]: https://github.com/vibe-d/vibe.d/issues/2071
[issue2072]: https://github.com/vibe-d/vibe.d/issues/2072
[issue2074]: https://github.com/vibe-d/vibe.d/issues/2074
[issue2079]: https://github.com/vibe-d/vibe.d/issues/2079
[issue2080]: https://github.com/vibe-d/vibe.d/issues/2080
[issue2082]: https://github.com/vibe-d/vibe.d/issues/2082
[issue2085]: https://github.com/vibe-d/vibe.d/issues/2085


v0.8.2 - 2017-12-11
-------------------

The major changes in this release are HTTP forward proxy support, handling incoming HTTP requests on custom transports and a MongoDB based session store. On top of that, there are many smaller improvements in the HTTP server, web/REST generator, JSON/BSON support and the TLS sub system.

### Features and improvements ###

- Web/REST framework
    - Added support for `@noRoute` in the REST interface generator - [issue #1934][issue1934]
    - Added support for `@requiresAuth` on REST interfaces in addition to classes - [pull #1939][issue1939]
    - Added global `request`/`response` properties for the web interface generator (by Benjamin Schaaf) - [issue #1937][issue1937], [pull #1938][issue1938]
    - The language list for `@translationContext` can now be specified as a compile-time constant array in addition to a tuple (by Jan Jurzitza aka WebFreak) - [pull #1879][issue1879]
- HTTP sub system
    - Added HTTP forward proxy support based on the existing reverse proxy code (by Matt Remmel) - [pull #1893][issue1893]
    - Deprecated non-`nothrow` WebSocket handler callbacks - [issue #1420][issue1420], [pull #1890][issue1890]
    - Added `handleHTTPConnection` to serve HTTP requests on a custom transport - [pull #1929][issue1929]
    - Added `HTTPServerRequest.requestPath` as an `InetPath` property replacing `.path` to avoid encoding related issues - [pull #1940][issue1940]
    - Added `HTTPClientRequest.remoteAddress`
    - Added `HTTPListener.bindAddresses` property, this allows querying the actual port when passing `0` to `HTTPServerSettings.bindPort` - [issue #1818][issue1818], [pull #1930][issue1930]
    - Added `SysTime`/`Duration` based overloads for `Cookie.expire`/`.maxAge` - [issue #1701][issue1701], [pull #1889][issue1889]
- MongoDB driver
    - Added `MongoSessionStore` for MongoDB based HTTP session storage
    - The MongoDB driver now forwards server error messages (by Martin Nowak) - [pull #1951][issue1951]
- Extended the JSON parser to handle forward ranges in addition to random access ranges (by John Colvin) - [pull #1906][issue1906]
- Added `std.uuid.UUID` conversion support for `Bson` (by Denis Feklushkin) - [pull #1404][issue1404]
- Added "openssl-1.1" and "openssl-0.9" configurations to the vibe-d:tls package to enable switching the OpenSSL target version without having to define version constants - [pull #1965][issue1965]
- Added `NativePath` based overloads of `TLSContext.usePrivateKeyFile` and `.useCertificateChainFile`
- Added `setCommandLineArgs` - can be used together with a `VibeDisableCommandLineParsing` version to customize command line parsing - [pull #1916][issue1916]

### Bug fixes ###

- Fixed getting the X509 certificate for printing certificate errors on OpenSSL 1.1 (by Martin Nowak) - [pull #1921][issue1921]
- Fixed handling of `out` parameters in the REST interface (were erroneously read from the request) - [issue #1933][issue1933], [pull #1935][issue1935]
- Fixed an "orphan format specifier" error in the web interface handling code
- Fixed the JSON parser to work at compile-time (by Benjamin Schaaf) - [pull #1960][issue1960]
- Fixed an error in the Botan TLS provider if used to serve HTTPS - [issue #1918][issue1918], [pull #1964][issue1964]
- Fixed a web interface generator compile error in case of an empty language list in the `@translationContext` - [issue #1955][issue1955], [pull #1956][issue1956]
- Fixed a bogus error during HTTP request finalization - [issue #1966][issue1966]
- Fixed the command line argument parser getting tripped up by druntime arguments ("--DRT-...") (by Martin Nowak) - [pull #1944][issue1944]
- Fixed a possible race condition when stopping a `RedisListener` (by Etienne Cimon) - [pull #1201][issue1201], [pull #1971][issue1971]
- Fixed support for `TCPListenOptions.reusePort` on macOS and FreeBSD - [pull #1972][issue1972]
- Fixed handling of CONNECT requests in the HTTP proxy server - [pull #1973][issue1973]

[issue1701]: https://github.com/vibe-d/vibe.d/issues/1701
[issue1889]: https://github.com/vibe-d/vibe.d/issues/1889
[issue1420]: https://github.com/vibe-d/vibe.d/issues/1420
[issue1890]: https://github.com/vibe-d/vibe.d/issues/1890
[issue1916]: https://github.com/vibe-d/vibe.d/issues/1916
[issue1906]: https://github.com/vibe-d/vibe.d/issues/1906
[issue1929]: https://github.com/vibe-d/vibe.d/issues/1929
[issue1818]: https://github.com/vibe-d/vibe.d/issues/1818
[issue1930]: https://github.com/vibe-d/vibe.d/issues/1930
[issue1934]: https://github.com/vibe-d/vibe.d/issues/1934
[issue1939]: https://github.com/vibe-d/vibe.d/issues/1939
[issue1937]: https://github.com/vibe-d/vibe.d/issues/1937
[issue1938]: https://github.com/vibe-d/vibe.d/issues/1938
[issue1940]: https://github.com/vibe-d/vibe.d/issues/1940
[issue1951]: https://github.com/vibe-d/vibe.d/issues/1951
[issue1404]: https://github.com/vibe-d/vibe.d/issues/1404
[issue1965]: https://github.com/vibe-d/vibe.d/issues/1965
[issue1879]: https://github.com/vibe-d/vibe.d/issues/1879
[issue1893]: https://github.com/vibe-d/vibe.d/issues/1893
[issue1921]: https://github.com/vibe-d/vibe.d/issues/1921
[issue1933]: https://github.com/vibe-d/vibe.d/issues/1933
[issue1935]: https://github.com/vibe-d/vibe.d/issues/1935
[issue1960]: https://github.com/vibe-d/vibe.d/issues/1960
[issue1918]: https://github.com/vibe-d/vibe.d/issues/1918
[issue1964]: https://github.com/vibe-d/vibe.d/issues/1964
[issue1955]: https://github.com/vibe-d/vibe.d/issues/1955
[issue1956]: https://github.com/vibe-d/vibe.d/issues/1956
[issue1966]: https://github.com/vibe-d/vibe.d/issues/1966
[issue1944]: https://github.com/vibe-d/vibe.d/issues/1944
[issue1201]: https://github.com/vibe-d/vibe.d/issues/1201
[issue1971]: https://github.com/vibe-d/vibe.d/issues/1971
[issue1972]: https://github.com/vibe-d/vibe.d/issues/1972
[issue1973]: https://github.com/vibe-d/vibe.d/issues/1973


v0.8.1 - 2017-08-30
-------------------

Apart from removing the old `vibe-d:diet` package in favor of `diet-ng`, this release most notably contains a number of performance improvements in the HTTP server, as well as improvements and fixes in the WebSocket code. Furthermore, initial OpenSSL 1.1.x support has been added and a few `@safe` related issues introduced in 0.8.0 have been fixed.

### Features and improvements ###

- Compiles on DMD 2.071.2 up to DMD 2.076.0-rc1
- Removed vibe-d:diet sub package (superseded by diet-ng) - [pull #1835][issue1835]
- Web framework
    - Added convenience functions `status` and `header` to `vibe.web.web` (by Sebastian Wilzbach) - [pull #1696][issue1696]
    - Added `vibe.web.web.determineLanguageByHeader` and improved the default language determination (by Jan Jurzitza aka WebFreak) - [pull #1850][issue1850]
    - Added `vibe.web.web.language` property to determine the detected language (by Jan Jurzitza aka WebFreak) - [pull #1860][issue1860]
    - Marked the global API functions in `vibe.web.web` as `@safe` - [pull #1886][issue1886]
    - The REST interface generator avoids blindly instantiating serialization code for *all* parameters
    - No stack trace is shown on the generated error page anymore in case of bad (query/form) parameter formatting
- HTTP sub system
    - The HTTP server now accepts a UTF-8 BOM for JSON requests (by Sebanstian Wilzbach) - [pull #1799][issue1799]
    - Most parsing features activated by `HTTPServerOption` (for `HTTPServerRequest`) are now evaluated lazily instead - the corresponding options are now deprecated (by Sebastian Wilzbach):
        - `.json` / `HTTPServerOption.parseJsonBody` - [pull #1677][issue1677]
        - `.cookies` / `HTTPServerOption.parseCookies` - [pull #1801][issue1801]
        - `.form` / `HTTPServerOption.parseFormBody` - [pull #1801][issue1801]
        - `.files` / `HTTPServerOption.parseMultiPartBody` - [pull #1801][issue1801]
        - `.query` / `HTTPServerOption.parseQueryString` - [pull #1821][issue1821]
        - `.queryString`, `.username` and `.password` are now always filled, regardless of `HTTPServerOption.parseURL` - [pull #1821][issue1821]
    - `HTTPServerRequest.peer` is now computed lazily
    - Deprecated `HTTPServerOption.distribute` because of its non-thread-safe design
    - The `HTTPServerSettings` constructor now accepts a convenient string to set the bind address - [pull #1810][issue1810]
    - `listenHTTP` accepts the same convenience string as `HTTPServerSettings` (by Sebastian Wilzbach) - [pull #1816][issue1816]
    - Added `HTTPReverseProxySettings.destination` (`URL`) to made UDS destinations work (by Georgi Dimitrov) - [pull #1813][issue1813]
    - Increased the network output chunk sizes from 256 to 1024 in the HTTP client/server
    - WebSocket messages now produce only a single network packet of possible (header and payload sent at once) - [issue #1791][issue1791], [pull #1792][issue1792]
    - WebSocket API improvements (by Mathias Lang aka Geod24) - [pull #1534][issue1534], [pull #1836][issue1836]
    - Renamed `HTTPServerRequest.requestURL` to `requestURI`
    - Added `HTTPClientRequest.peerCertificate` property
- Serialization
    - Added deserialization support for unnamed `Tuple!(...)` (by Dentcho Bankov) - [pull #1693][issue1693]
    - Added serialization support for named `Tuple!(...)` (by Dentcho Bankov) - [pull #1662][issue1662]
- Added UDP multicast properties (implemented for libevent, by Sebastian Koppe) - [pull #1806][issue1806]
- Markdown embedded URLs are now filtered by a whitelist to avoid URL based XSS exploits - [issue #1845][issue1845], [pull #1846][issue1846]
- `lowerPrivileges` is now marked `@safe` (by Sebastian Wilzbach) - [pull #1807][issue1807]
- Improved `urlDecode` to return a slice of its input if possible - [pull #1828][issue1828]
- Added `DictionaryList.toString` and deprecated `alias byKeyValue this` - [issue #1873][issue1873]
- Added support for defining a compatibility version `VibeUseOpenSSL11` to build against OpenSSL 1.1.0 instead of 1.0.x (by Robert Schadek aka burner) - [issue #1651][issue1651], [issue #1748][issue1748], [issue #1758][issue1758], [pull #1759][issue1759]
- Added a Meson project file analogous to the 0.7.x branch (by Matthias Klumpp aka ximion) - [pull #1894][issue1894]
- The functions in `vibe.stream.operations` now compile with non-`@safe` streams and ranges - [pull #1902][issue1902]
- Added `TLSCertificateInformation._x509` as an temporary means to access the raw certificate (`X509*` for OpenSSL)

### Bug fixes ###

- Fixed "SSL_read was unsuccessful with ret 0" errors in the OpenSSL TLS implementation (by machindertech) - [issue #1124][issue1124], [pull #1395][issue1395]
- Fixed the JSON generator to output valid JSON for `Json.undefined` values (by Tomáš Chaloupka) - [pull #1737][issue1737], [issue #1735][issue1735]
- Fixed using HTTP together with USDS sockets in the HTTP client (by Johannes Pfau aka jpf91) - [pull #1747][issue1747]
- Fixed handling of `Nullable!T` in the web interface generator - invalid values are treated as an error now instead of as a 
null value
- Fixed a compilation error in the Botan based TLS implementation
- Fixed an assertion in the HTTP client by using a custom allocator instead of the buggy `RegionAllocator`
- Fixed sending of WebSocket messages with a payload length of 65536
- Fixed an intermittent failure at shutdown when using libasync - [pull #1837][issue1837]
- Fixed MongoDB SASL authentication when used within `shared static this` (by Sebastian Wilzbach) - [pull #1841][issue1841]
- Fixed authentication with default settings on modern MongoDB versions by defaulting to SCRAM-SHA-1 (by Sebastian Wilzbach) - [issue #1785][issue1785], [issue #1843][issue1843]
- Fixed the WebSocket ping logic - [issue #1471][issue1471], [pull #1848][issue1848]
- Fixed a cause of "dwarfeh(224) fatal error" during fatal app exit and possible an infinite loop by using `abort()` instead of `exit()`
- Fixed `URLRouter.match` to accept delegate literals (by Sebastian Wilzbach) - [pull #1866][issue1866]
- Fixed a possible range error in the libasync driver
- Fixed serialization of recursive data types to JSON (by Jan Jurzitza aka WebFreak) - [issue #1855][issue1855]
- Fixed `MongoCursor.limit` and made the API `@safe` (by Jan Jurzitza aka WebFreak) - [issue #967][issue967], [pull #1871][issue1871]
- Fixed determining the host name in `SyslogLogger` (by Jan Jurzitza aka WebFreak) - [pull #1874][issue1874]

[issue967]: https://github.com/vibe-d/vibe.d/issues/967
[issue1124]: https://github.com/vibe-d/vibe.d/issues/1124
[issue1395]: https://github.com/vibe-d/vibe.d/issues/1395
[issue1471]: https://github.com/vibe-d/vibe.d/issues/1471
[issue1534]: https://github.com/vibe-d/vibe.d/issues/1534
[issue1651]: https://github.com/vibe-d/vibe.d/issues/1651
[issue1662]: https://github.com/vibe-d/vibe.d/issues/1662
[issue1674]: https://github.com/vibe-d/vibe.d/issues/1674
[issue1677]: https://github.com/vibe-d/vibe.d/issues/1677
[issue1691]: https://github.com/vibe-d/vibe.d/issues/1691
[issue1692]: https://github.com/vibe-d/vibe.d/issues/1692
[issue1693]: https://github.com/vibe-d/vibe.d/issues/1693
[issue1696]: https://github.com/vibe-d/vibe.d/issues/1696
[issue1735]: https://github.com/vibe-d/vibe.d/issues/1735
[issue1737]: https://github.com/vibe-d/vibe.d/issues/1737
[issue1747]: https://github.com/vibe-d/vibe.d/issues/1747
[issue1748]: https://github.com/vibe-d/vibe.d/issues/1748
[issue1758]: https://github.com/vibe-d/vibe.d/issues/1758
[issue1759]: https://github.com/vibe-d/vibe.d/issues/1759
[issue1785]: https://github.com/vibe-d/vibe.d/issues/1785
[issue1791]: https://github.com/vibe-d/vibe.d/issues/1791
[issue1792]: https://github.com/vibe-d/vibe.d/issues/1792
[issue1799]: https://github.com/vibe-d/vibe.d/issues/1799
[issue1801]: https://github.com/vibe-d/vibe.d/issues/1801
[issue1806]: https://github.com/vibe-d/vibe.d/issues/1806
[issue1807]: https://github.com/vibe-d/vibe.d/issues/1807
[issue1810]: https://github.com/vibe-d/vibe.d/issues/1810
[issue1813]: https://github.com/vibe-d/vibe.d/issues/1813
[issue1816]: https://github.com/vibe-d/vibe.d/issues/1816
[issue1821]: https://github.com/vibe-d/vibe.d/issues/1821
[issue1828]: https://github.com/vibe-d/vibe.d/issues/1828
[issue1835]: https://github.com/vibe-d/vibe.d/issues/1835
[issue1836]: https://github.com/vibe-d/vibe.d/issues/1836
[issue1837]: https://github.com/vibe-d/vibe.d/issues/1837
[issue1841]: https://github.com/vibe-d/vibe.d/issues/1841
[issue1843]: https://github.com/vibe-d/vibe.d/issues/1843
[issue1845]: https://github.com/vibe-d/vibe.d/issues/1845
[issue1846]: https://github.com/vibe-d/vibe.d/issues/1846
[issue1848]: https://github.com/vibe-d/vibe.d/issues/1848
[issue1850]: https://github.com/vibe-d/vibe.d/issues/1850
[issue1855]: https://github.com/vibe-d/vibe.d/issues/1855
[issue1860]: https://github.com/vibe-d/vibe.d/issues/1860
[issue1866]: https://github.com/vibe-d/vibe.d/issues/1866
[issue1871]: https://github.com/vibe-d/vibe.d/issues/1871
[issue1873]: https://github.com/vibe-d/vibe.d/issues/1873
[issue1874]: https://github.com/vibe-d/vibe.d/issues/1874
[issue1886]: https://github.com/vibe-d/vibe.d/issues/1886
[issue1894]: https://github.com/vibe-d/vibe.d/issues/1894
[issue1902]: https://github.com/vibe-d/vibe.d/issues/1902


v0.8.0 - 2017-07-10
-------------------

The 0.8.x branch marks the final step before switching each individual sub package to version 1.0.0. This has already been done for the Diet template module (now [`diet-ng`][diet-ng]) and for the new [vibe-core][vibe-core] package that is released simultaneously. The most prominent changes in this release are a full separation of all sub modules into individual folders, as well as the use of `@safe` annotations throughout the code base. The former change may require build adjustments for projects that don't use DUB to build vibe.d, the latter leads to some breaking API changes.

### Features and improvements ###

- Compiles on DMD 2.070.2 up to DMD 2.075.0-b1, this release also adds support for `-m32mscoff` builds ("x86_mscoff")
- Global API changes
    - Split up the library into fully separate sub packages/folders
    - Added a "vibe-core" configuration to "vibe-d" and "vibe-d:core" that uses the new [vibe-core][vibe-core] package
    - Added `@safe` and `nothrow` annotations in many places of the API - this is a breaking change in cases where callbacks were annotated - [pull #1618][issue1618], [issue 1595][issue1595]
    - Reworked the buffered I/O stream API
        - The `InputStream` based overload of `OutputStream.write` has been moved to a global function `pipe()`
        - `read` and `write` now accept an optional `IOMode` parameter (only `IOMode.all` is supported for the original `vibe:core`, but `vibe-core` supports all modes)
        - `InputStream.leastSize` and `.dataAvailableForRead` are scheduled for deprecation - `IOMode.immediate` and `IOMode.once` can be used in their place
    - Added forward compatibility code to "vibe:core" so that dependent code can use either that or [vibe-core][vibe-core] as a drop-in replacement
- HTTP server
    - Server contexts are now managed thread-locally, which means that multiple threads will attempt to listen on the same port if requested to do so - use `HTTPServerOption.reusePort` if necessary
    - Added support for simple range queries in the HTTP file server (by Jan Jurzitza aka WebFreak001) - [issue #716][issue716], [pull #1634][issue1634], [pull #1636][issue1636]
    - The HTTP file server only sets a default content type header if none was already set (by Remi A. Solås aka rexso) - [pull #1642][issue1642]
    - `HTTPServerResponse.writeJsonBody` only sets a default content type header if none was already set
    - Added `HTTPServerResponse.writePrettyJsonBody`
    - `HTTPServerResponse.writeBody` only sets a default content type if none is already set - [issue #1655][issue1655]
    - Added `Session.remove` to remove session keys (by Sebastian Wilzbach) - [pull #1670][issue1670]
    - Added `WebSocket.closeCode` and `closeReason` properties (by Andrei Zbikowski aka b1naryth1ef) - [pull #1675][issue1675]
    - Added a `Variant` dictionary as `HTTPServerRequest.context` for custom value storage by high level code - [issue1529][issue1529] [pull #1550][issue1550]
        - Usability improvements by Harry T. Vennik aka thaven - [pull #1745][issue1745]
    - Added `checkBasicAuth` as a non-enforcing counterpart of `performBasicAuth` - [issue #1449][issue1449], [pull #1687][issue1687]
    - Diet templates are rendered as pretty HTML by default if "diet-ng" is used (can be disabled using `VibeOutputCompactHTML`) - [issue #1616][issue1616]
    - Added `HTTPClientRequest.writeFormBody`
    - Disabled stack traces on the default error page for non-debug builds by default (`HTTPServerOption.defaults`)
- REST interface generator
    - Added single-argument `@bodyParam` to let a single parameter represent the whole request body (by Sebastian Wilzbach) - [issue #1549][issue1549], [pull #1723][issue1723]
    - Boolean parameters now accept "1" and case insensitive "true" as `true` - [pull #1712][issue1712]
    - Server responses now output prettified JSON if built in debug mode
    - Stack traces are only written in debug mode - [issue #1623][issue1623]
    - Reduced the number of chunks written by `StreamOutputRange.put` for large input buffers (affects WebSockets and chunked HTTP responses)
- Switched to `std.experimental.allocator` instead of the integrated `vibe.utils.memory` module
- The string sequence `</` is now encoded as `<\/` by the JSON module to avoid a common XSS attack vector
- Reduced synchronization overhead in the libevent driver for entities that are single-threaded
- Added support for MongoDB SCRAM-SHA1 authentication (by Nicolas Gurrola) - [pull #1632][issue1632]
- Added `RedisCollection.initialize`
- The trigger mode for `FileDescriptorEvent` can now be configured (by Jack Applegame) - [pull #1596][issue1596]
- Enabled minimal delegate syntax for `URLRouter` (e.g. `URLRouter.get("/", (req, res) { ... });`) - [issue #1668][issue1668]
- Added serialization support for string based enum types as associative array keys (by Tomoya Tanjo) - [issue #1660][issue1660], [pull #1663][issue1663]
- Added serialization support for `Typedef!T` - [pull #1617][issue1617]
- Added `DictionaryList!T.byKeyValue` to replace `opApply` based iteration
- Added `.byValue`/`.byKeyValue`/`.byIndexValue` properties to `Bson` and `Json` as a replacement for `opApply` based iteration (see [issue #1688][issue1688])
- Added `StreamOutputRange.drop()`
- Updated the Windows OpenSSL binaries to 1.0.2k
- The session life time in `RedisSessionStore` is now refreshed on every access to the session (by Steven Schveighoffer) - [pull #1778][issue1778]
- Reduced session storage overhead in `RedisSessionStore` (by Steven Schveighoffer) - [pull #1777][issue1777]
- Enabled `HashMap`'s postblit constructor, supported by a reference counting + copy-on-write strategy

### Bug fixes ###

- Fixed compile error for deserializing optional class/struct fields
- Fixed GET requests in the REST client to not send a body
- Fixed REST request responses that return void to send an empty body (see also [issue #1682](issue1682))
- Fixed a possible idle loop in `Task.join()` if called from outside of an event loop
- Fixed `TaskPipe.waitForData` to actually time out if a timeout value was passed - [issue #1605][issue1605]
- Fixed a compilation error for GDC master - [issue #1602][issue1602]
- Fixed a linker issue for LDC on Windows - [issue #1629][issue1629]
- Fixed a (single-threaded) concurrent AA iteration/write issue that could result in an access violation in the Win32 driver - [issue #1608][issue1608]
- Fixed the JavaScript REST client generator to handle XHR errors (by Timoses) - [pull #1645][issue1645], [pull #1646][issue1646]
- Fixed a possible `InvalidMemoryOperationError` in `SystemRNG`
- Fixed `runApplication` to be able to handle extraneous command line arguments
- Fixed a possible crash in `RedisSubscriber.blisten` due to a faulty shutdown procedure
- Fixed detection of non-keep-alive connections in the HTTP server (upgraded connections were treated as keep-alive)
- Fixed bogus static assertion failure in `RestInterfaceClient!I` when `I` is annotated with `@requiresAuth` - [issue #1648][issue1648]
- Fixed a missing `toRedis` conversion in `RedisHash.setIfNotExist` (by Tuukka Kurtti aka Soletek) - [pull #1659][issue1659]
- Fixed `createTempFile` on Windows
- Fixed the HTTP reverse proxy to send 502 (bad gateway) instead of 500 (internal server error) for upstream errors
- Fixed a possible `InvalidMemoryOperationError` on shutdown for failed MongoDB requests - [issue #1707][issue1707]
- Fixed `readOption!T` to work for array types - [issue #1713][issue1713]
- Fixed handling of remote TCP connection close during concurrent read/write - [issue #1726][issue1726], [pull #1727][issue1727]
- Fixed libevent driver to properly handle allocator `null` return values
- Fixed invoking vibe.d functionality from a plain `Fiber` - [issue #1742][issue1742]
- Fixed parsing of "tcp://" URLs - [issue #1732][issue1732], [pull #1733][issue1733]
- Fixed handling `@before` attributes on REST interface classes and intermediate interfaces - [issue #1753][issue1753], [pull #1754][issue1754]
- Fixed a deadlock situation in the libevent driver - [pull #1756][issue1756]
- Fixed `readUntilSmall`/`readLine` to handle alternating availability of a peek buffer - [issue #1741][issue1741], [pull #1761][issue1761]
- Fixed `parseMultiPartForm` to handle unquoted strings in the "Content-Disposition" header (by Tomáš Chaloupka) - [issue #1562][issue1562] [pull #1725][issue1725]
- Fixed `HTTPServerRequest.fullURL` for IPv6 address based host strings
- Fixed building on Windows with x86_mscoff (the win32 configuration is chosen by default now) - [issue #1771][issue1771]

[issue716]: https://github.com/vibe-d/vibe.d/issues/716
[issue1449]: https://github.com/vibe-d/vibe.d/issues/1449
[issue1529]: https://github.com/vibe-d/vibe.d/issues/1529
[issue1549]: https://github.com/vibe-d/vibe.d/issues/1549
[issue1550]: https://github.com/vibe-d/vibe.d/issues/1550
[issue1562]: https://github.com/vibe-d/vibe.d/issues/1562
[issue1595]: https://github.com/vibe-d/vibe.d/issues/1595
[issue1596]: https://github.com/vibe-d/vibe.d/issues/1596
[issue1602]: https://github.com/vibe-d/vibe.d/issues/1602
[issue1605]: https://github.com/vibe-d/vibe.d/issues/1605
[issue1608]: https://github.com/vibe-d/vibe.d/issues/1608
[issue1616]: https://github.com/vibe-d/vibe.d/issues/1616
[issue1617]: https://github.com/vibe-d/vibe.d/issues/1617
[issue1618]: https://github.com/vibe-d/vibe.d/issues/1618
[issue1623]: https://github.com/vibe-d/vibe.d/issues/1623
[issue1629]: https://github.com/vibe-d/vibe.d/issues/1629
[issue1632]: https://github.com/vibe-d/vibe.d/issues/1632
[issue1634]: https://github.com/vibe-d/vibe.d/issues/1634
[issue1636]: https://github.com/vibe-d/vibe.d/issues/1636
[issue1642]: https://github.com/vibe-d/vibe.d/issues/1642
[issue1645]: https://github.com/vibe-d/vibe.d/issues/1645
[issue1646]: https://github.com/vibe-d/vibe.d/issues/1646
[issue1648]: https://github.com/vibe-d/vibe.d/issues/1648
[issue1655]: https://github.com/vibe-d/vibe.d/issues/1655
[issue1659]: https://github.com/vibe-d/vibe.d/issues/1659
[issue1660]: https://github.com/vibe-d/vibe.d/issues/1660
[issue1663]: https://github.com/vibe-d/vibe.d/issues/1663
[issue1668]: https://github.com/vibe-d/vibe.d/issues/1668
[issue1670]: https://github.com/vibe-d/vibe.d/issues/1670
[issue1675]: https://github.com/vibe-d/vibe.d/issues/1675
[issue1682]: https://github.com/vibe-d/vibe.d/issues/1682
[issue1687]: https://github.com/vibe-d/vibe.d/issues/1687
[issue1688]: https://github.com/vibe-d/vibe.d/issues/1688
[issue1707]: https://github.com/vibe-d/vibe.d/issues/1707
[issue1712]: https://github.com/vibe-d/vibe.d/issues/1712
[issue1713]: https://github.com/vibe-d/vibe.d/issues/1713
[issue1723]: https://github.com/vibe-d/vibe.d/issues/1723
[issue1725]: https://github.com/vibe-d/vibe.d/issues/1725
[issue1726]: https://github.com/vibe-d/vibe.d/issues/1726
[issue1727]: https://github.com/vibe-d/vibe.d/issues/1727
[issue1732]: https://github.com/vibe-d/vibe.d/issues/1732
[issue1733]: https://github.com/vibe-d/vibe.d/issues/1733
[issue1741]: https://github.com/vibe-d/vibe.d/issues/1741
[issue1742]: https://github.com/vibe-d/vibe.d/issues/1742
[issue1745]: https://github.com/vibe-d/vibe.d/issues/1745
[issue1753]: https://github.com/vibe-d/vibe.d/issues/1753
[issue1754]: https://github.com/vibe-d/vibe.d/issues/1754
[issue1756]: https://github.com/vibe-d/vibe.d/issues/1756
[issue1761]: https://github.com/vibe-d/vibe.d/issues/1761
[issue1771]: https://github.com/vibe-d/vibe.d/issues/1771
[issue1777]: https://github.com/vibe-d/vibe.d/issues/1777
[issue1778]: https://github.com/vibe-d/vibe.d/issues/1778
[vibe-core]: https://github.com/vibe-d/vibe-core


v0.7.31 - 2017-04-10
--------------------

This release is a backport release of the smaller changes that got into 0.8.0. The 0.7.x branch will continue to be maintained for a short while, but only bug fixes will be included from now on. Applications should switch to the 0.8.x branch as soon as possible.

### Features and improvements ###

- Compiles on DMD 2.068.2 up to DMD 2.074.0
- HTTP server
  - Added support for simple range queries in the HTTP file server (by Jan Jurzitza aka WebFreak001) - [issue #716][issue716], [pull #1634][issue1634], [pull #1636][issue1636]
  - The HTTP file server only sets a default content type header if none was already set (by Remi A. Solås aka rexso) - [pull #1642][issue1642]
  - `HTTPServerResponse.writeJsonBody` only sets a default content type header if none was already set
  - `HTTPServerResponse.writeBody` only sets a default content type if none is already set - [issue #1655][issue1655]
  - Added `HTTPServerResponse.writePrettyJsonBody`
  - Diet templates are rendered as pretty HTML by default if diet-ng is used (can be disabled using `VibeOutputCompactHTML`)
- Reduced synchronization overhead in the libevent driver for entities that are single-threaded
- The REST interface server now responds with prettified JSON if built in debug mode
- Stack traces are only written in REST server responses in debug mode - [issue #1623][issue1623]
- The trigger mode for `FileDescriptorEvent` can now be configured (by Jack Applegame) - [pull #1596][issue1596]
- Added `.byValue`/`.byKeyValue`/`.byIndexValue` properties to `Bson` and `Json` as a replacement for `opApply` based iteration (see [issue #1688][issue1688])

### Bug fixes ###

- Fixed compile error for deserializing optional `class`/ struct` fields
- Fixed GET requests in the REST client to not send a body
- Fixed REST request responses that return void to not send a body
- Fixed a possible idle loop in `Task.join()` if called from outside of an event loop
- Fixed `TaskPipe.waitForData` to actually time out if a timeout value was passed - [issue #1605][issue1605]
- Fixed a compilation error for GDC master - [issue #1602][issue1602]
- Fixed a linker issue for LDC on Windows - [issue #1629][issue1629]
- Fixed a (single-threaded) concurrent AA iteration/write issue that could result in an access violation in the Win32 driver - [issue #1608][issue1608]
- Fixed the JavaScript REST client generator to handle XHR errors (by Timoses) - [pull #1645][issue1645], [pull #1646][issue1646]
- Fixed a possible `InvalidMemoryOperationError` in `SystemRNG`
- Fixed `runApplication` to be able to handle extraneous command line arguments
- Fixed a possible crash in `RedisSubscriber.blisten` due to a faulty shutdown procedure
- Fixed detection of non-keep-alive connections in the HTTP server (upgraded connections were treated as keep-alive)
- Fixed bogus static assertion failure in `RestInterfaceClient!I` when `I` is annotated with `@requiresAuth` - [issue #1648][issue1648]
- Fixed a missing `toRedis` conversion in `RedisHash.setIfNotExist` (by Tuukka Kurtti aka Soletek) - [pull #1659][issue1659]
- Fixed an assertion failure for malformed HTML form upload filenames - [issue #1630][issue1630]
- Fixed the HTTP server to not use chunked encoding for HTTP/1.0 requests - [issue #1721][issue1721], [pull #1722][issue1722]

[issue716]: https://github.com/vibe-d/vibe.d/issues/716
[issue1596]: https://github.com/vibe-d/vibe.d/issues/1596
[issue1602]: https://github.com/vibe-d/vibe.d/issues/1602
[issue1605]: https://github.com/vibe-d/vibe.d/issues/1605
[issue1608]: https://github.com/vibe-d/vibe.d/issues/1608
[issue1623]: https://github.com/vibe-d/vibe.d/issues/1623
[issue1629]: https://github.com/vibe-d/vibe.d/issues/1629
[issue1630]: https://github.com/vibe-d/vibe.d/issues/1630
[issue1634]: https://github.com/vibe-d/vibe.d/issues/1634
[issue1636]: https://github.com/vibe-d/vibe.d/issues/1636
[issue1642]: https://github.com/vibe-d/vibe.d/issues/1642
[issue1645]: https://github.com/vibe-d/vibe.d/issues/1645
[issue1646]: https://github.com/vibe-d/vibe.d/issues/1646
[issue1648]: https://github.com/vibe-d/vibe.d/issues/1648
[issue1655]: https://github.com/vibe-d/vibe.d/issues/1655
[issue1659]: https://github.com/vibe-d/vibe.d/issues/1659
[issue1688]: https://github.com/vibe-d/vibe.d/issues/1688
[issue1721]: https://github.com/vibe-d/vibe.d/issues/1721
[issue1722]: https://github.com/vibe-d/vibe.d/issues/1722


v0.7.30 - 2016-10-31
--------------------

### Features and improvements ###

- General changes
  - Compiles on DMD 2.068.2 up to 2.072.0
  - Added `runApplication` as a single API entry point to properly initialize and run a vibe.d application (this will serve as the basis for slowly phasing out the `VibeDefaultMain` convenience mechanism)
  - Started using an SDLang based DUB package recipe (upgrade to DUB 1.0.0 if you haven't already)
  - Defining both, `VibeDefaultMain` and `VibeCustomMain`, results in a compile-time error to help uncover hidden build issues (by John Colvin) - [pull #1551][issue1551]
- Web/REST interface generator
  - Added `vibe.web.auth` as a generic way to express authorization rules and to provide a common hook for authentication
  - Added `@noRoute` attribute for `registerWebInterface` to keep methods from generating a HTTP endpoint
  - Added `@nestedNameStyle` to choose between the classical underscore mapping and D style mapping for form parameter names in `registerWebInterface`
- Serialization framework
  - All hooks now get a traits struct that carries additional information, such as user defined attributes - note that this is a breaking change for any serializer implementation! - [pull #1542][issue1542]
  - Added `beginWriteDocument` and `endWriteDocument` hooks - [pull #1542][issue1542]
  - Added `(begin/end)WriteDictionaryEntry` and `(begin/end)WriteArrayEntry` hooks - [pull #1542][issue1542]
  - Exposed `vibe.data.serialization.DefaultPolicy` publicly
- HTTP server
  - Added `HTTPServerSettings.accessLogger` to enable using custom logger implementations
  - Added support for the "X-Forwarded-Port" header used by reverse proxies (by Mihail-K) - [issue #1409][issue1490], [pull #1491][issue1491]
  - Added an overload of `HTTPServerResponse.writeJsonBody` that doesn't set the response status (by Irenej Marc) - [pull #1488][issue1488]
- Can now use the new [diet-ng][diet-ng] package in `render()`
  - To force using it on existing projects, simply add "diet-ng" as a dependency
  - "diet-ng" is an optional dependency of vibe.d that is chosen by default - to avoid that, remove the "diet-ng" entry from dub.selections.json.
  - Related issues [issue #1554][issue1554], [issue #1555][issue1555]
- Added partial Unix client socket support, HTTP client support in particular (use `http+unix://...`) (by Sebastian Koppe) - [pull #1547][issue1547]
- Removed `Json.opDispatch` and `Bson.opDispatch`
- Added `Bson.remove` to remove elements from a BSON object - [issue #345][issue345]
the use of `VibeDefaultMain`)
- Added support for tables in the Markdown compiler - [issue #1493][issue1493]
- Added `MongoCollection.distinct()`
- The `std.concurrency` integration code now let's the behavior of `spawn()` be configurable, defaulting now to `runWorkerTask` instead of the previous `runTask`
- Using `VibeNoSSL` now also disables Botan support in addition to OpenSSL (by Martin Nowak) - [pull #1444][issue1444]
- Use a minimum protocol version of TLS 1.0 for Botan, fixes compilation on Botan 1.12.6 (by Tomáš Chaloupka) - [pull #1553][issue1553]
- Some more `URLRouter` memory/performance optimization
- Corrected the naming convention of `vibe.db.mongo.flags.IndexFlags` - [issue #1571][issue1571]
- Added `connectRedisDB`, taking a Redis database URL
- `FileDescriptorEvent.wait()` now returns which triggers have fired (by Jack Applegame) - [pull #1586][issue1586]

### Bug fixes ###

- Fixed a compile error that happened when using the JavaScript REST interface generator for sub interfaces - [issue #1506][issue1506]
- Fixed protocol violations in the WebSocket module (by Mathias Lang) - [pull #1508][issue1508], [pull #1511][issue1511]
- The HTTP client now correctly appends the port in the "Host" header - [issue #1507][issue1507], [pull #1510][issue1510]
- Fixed a possible null pointer error in `HTTPServerResponse.switchProtocol` - [issue #1502][issue1502]
- Fixed parsing of indented Markdown code blocks (empty lines don't interrupt the block anymore) - [issue #1527][issue1527]
- Fixed open TCP connections being left alive by `download()` (by Steven Dwy) - [pull #1532][issue1532]
- Fixed the error message for invalid types in `Json.get` (by Charles Thibaut) - [pull #1537][issue1537]
- Fixed the HTTP status code for invalid JSON in the REST interface generator (bad request instead of internal server error) (by Jacob Carlborg) - [pull #1538][issue1538]
- Fixed yielded task execution in case no explicit event loop is used
- Fixed a memory hog/leak in the libasync driver (by Martin Nowak) - [pull #1543][issue1543]
- Fixed the JSON module to output NaN as `null` instead of `undefined` (by John Colvin) - [pull #1548][issue1548], [issue #1442][issue1442], [issue #958][issue958]
- Fixed a possible deadlock in `LocalTaskSemaphore` (by Etienne Cimon) - [pull #1563][issue1563]
- Fixed URL generation for paths with placeholders in the JavaScript REST client generator - [issue #1564][issue1564]
- Fixed code generation errors in the JavaScript REST client generator and added `JSRestClientSettings` (by Oleg B. aka deviator) - [pull #1566][issue1566]
- Fixed a bug in `FixedRingBuffer.removeAt` which potentially affected the task scheduler (by Tomáš Chaloupka) - [pull #1572][issue1572]
- Fixed `validateEmail` to properly use `isEmail` (which used to be broken) (by Stanislav Blinov aka radcapricorn) - [issue #1580][issue1580], [pull #1582][issue1582]
- Fixed `yield()` to always return after a single event loop iteration - [issue #1583][issue1583]
- Fixed parsing of Markdown text nested in blockquotes, code in particular
- Fixed a buffer read overflow in `OpenSSLContext` - [issue #1577][issue1577]


[issue345]: https://github.com/vibe-d/vibe.d/issues/345
[issue958]: https://github.com/vibe-d/vibe.d/issues/958
[issue1442]: https://github.com/vibe-d/vibe.d/issues/1442
[issue1444]: https://github.com/vibe-d/vibe.d/issues/1444
[issue1488]: https://github.com/vibe-d/vibe.d/issues/1488
[issue1490]: https://github.com/vibe-d/vibe.d/issues/1490
[issue1491]: https://github.com/vibe-d/vibe.d/issues/1491
[issue1493]: https://github.com/vibe-d/vibe.d/issues/1493
[issue1502]: https://github.com/vibe-d/vibe.d/issues/1502
[issue1506]: https://github.com/vibe-d/vibe.d/issues/1506
[issue1507]: https://github.com/vibe-d/vibe.d/issues/1507
[issue1508]: https://github.com/vibe-d/vibe.d/issues/1508
[issue1510]: https://github.com/vibe-d/vibe.d/issues/1510
[issue1511]: https://github.com/vibe-d/vibe.d/issues/1511
[issue1527]: https://github.com/vibe-d/vibe.d/issues/1527
[issue1532]: https://github.com/vibe-d/vibe.d/issues/1532
[issue1537]: https://github.com/vibe-d/vibe.d/issues/1537
[issue1538]: https://github.com/vibe-d/vibe.d/issues/1538
[issue1542]: https://github.com/vibe-d/vibe.d/issues/1542
[issue1543]: https://github.com/vibe-d/vibe.d/issues/1543
[issue1547]: https://github.com/vibe-d/vibe.d/issues/1547
[issue1548]: https://github.com/vibe-d/vibe.d/issues/1548
[issue1551]: https://github.com/vibe-d/vibe.d/issues/1551
[issue1553]: https://github.com/vibe-d/vibe.d/issues/1553
[issue1554]: https://github.com/vibe-d/vibe.d/issues/1554
[issue1555]: https://github.com/vibe-d/vibe.d/issues/1555
[issue1563]: https://github.com/vibe-d/vibe.d/issues/1563
[issue1564]: https://github.com/vibe-d/vibe.d/issues/1564
[issue1566]: https://github.com/vibe-d/vibe.d/issues/1566
[issue1571]: https://github.com/vibe-d/vibe.d/issues/1571
[issue1572]: https://github.com/vibe-d/vibe.d/issues/1572
[issue1577]: https://github.com/vibe-d/vibe.d/issues/1577
[issue1580]: https://github.com/vibe-d/vibe.d/issues/1580
[issue1582]: https://github.com/vibe-d/vibe.d/issues/1582
[issue1583]: https://github.com/vibe-d/vibe.d/issues/1583
[diet-ng]: https://github.com/rejectedsoftware/diet-ng


v0.7.29 - 2016-07-04
--------------------

### Features and improvements ###

- Dropped support for DMD frontend versions below 2.067.x - supports 2.067.1 up to 2.071.0 now
- Removed the libev driver
- Removed all deprecated symbols
- Heavily optimized the `URLRouter` (>5x faster initial match graph building and around 60% faster route match performance)
- Added CONNECT and `Connection: Upgrade` support to the reverse proxy module (by Georgi Dimitrov) - [pull #1392][issue1392]
- Added support for using an explicit network interface for outgoing TCP and HTTP connections - [pull #1407][issue1407]
- Cookies are now stored with their raw value, enabling handling of non-base64 encoded values (by Yannick Koechlin) - [pull #1401][issue1401]
- Added HyperLogLog functions to the Redis client (by Yannick Koechlin) - [pull #1435][issue1435]
- Added `RestInterfaceSettings.httpClientSettings`
- Added `HTTPClientSettings.dnsAddressFamily`
- Added `TCPListener.bindAddress`
- Made `@ignore`, `@name`, `@optional`, `@byName` and `@asArray` serialization attributes customizable per serialization policy - [pull #1438][issue1438], [issue #1352][issue1352]
- Added `HTTPStatus.unavailableForLegalReasons` (by Andrew Benton) - [pull #1358][issue1358]
- Added support or logger implementations that can log multiple lines per log call (by Martin Nowak) - [pull #1428][issue1428]
- Added `HTTPServerResponse.connected` (by Alexander Tumin) - [pull #1474][issue1474]
- Added allocation free string conversion methods to `NetworkAddress`
- Added diagnostics in case of connections getting closed during process shutdown (after the driver is already shut down) - [issue #1452][issue1452]
- Added `disableDefaultSignalHandlers` that can be used to avoid vibe.d registering its default signal handlers - [pull #1454][issue1454], [issue #1333][issue1333]
- Added detection of SQLite data base extensions for `getMimeTypeForFile` (by Stefan Koch) - [pull #1456][issue1456]
- The markdown module now emits XHTML compatible `<br/>` tags (by Stefan Schmidt) - [pull #1461][issue1461]
- Added `RedisDatabase.srandMember` overload taking a count (by Yannick Koechlin) - [pull #1447][issue1447]
- The HTTP client now accepts `const` settings
- Removed the libevent/Win64 configuration as the libevent binaries for that platform never existed - [issue #832][issue832]
- Improvements to the WebSockets module, most notably reduction of memory allocations (by Mathias Lang) - [pull #1497][issue1497]
- Added version `VibeNoOpDispatch` to force removal of `opDispatch` for `Json` and `Bson` (by David Monagle) - [pull #1526][issue1526]
- Added a manual deprecation message for `Json.opDispatch`/`Bson.opDispatch` because `deprecated` did not have an effect

### Bug fixes ###

- Fixed the internal `BsonObjectID` counter to be initialized with a random value (by machindertech) - [pull #1128][issue1128]
- Fixed a possible race condition for ID assignment in the libasync driver (by Etienne Cimon) - [pull #1399][issue1399]
- Fixed compilation of `Bson.opt` for both const and non-const AAs/arrays - [issue #1394][issue1394]
- Fixed handling of POST methods in the REST JavaScript client for methods with no parameters - [issue #1434][issue1434]
- Fixed `RedisDatabase.blpop` and `RedisList.removeFrontBlock`
- Fixed a protocol error/assertion failure when a Redis reply threw an exception - [pull #1416][issue1416], [issue #1412][issue1412]
- Fixed possible assertion failures "Manually resuming taks that is already scheduled"
- Fixed FreeBSD and NetBSD support (by Nikolay Tolstokulakov) - [pull #1448][issue1448]
- Fixed handling of multiple methods with `@headerParam` parameters with the same name (by Irenej Marc) - [pull #1453][issue1453]
- Fixed calling `async()` with an unshared delegate or with a callback that returns a `const`/`immutable` result
- Fixed `Tid` to be considered safe to pass between threads (for worker tasks or `vibe.core.concurrency`)
- Fixed the `HTTPClient`/`download()` to properly use TLS when redirects happen between HTTP and HTTPS (by Martin Nowak) - [pull #1265][issue1265]
- Fixed recognizing certain HTTP content encoding strings ("x-gzip" and "") (by Ilya Yaroshenko) - [pull #1477][issue1477]
- Fixed parsing IPv6 "Host" headers in the HTTP server - [issue #1388][issue1388], [issue #1402][issue1402]
- Fixed an assertion failure when using threads together with `VibeIdleCollect` - [issue #1476][issue1476]
- Fixed parsing of `vibe.conf` files that contain a UTF BOM - [issue #1470][issue1470]
- Fixed `@before`/`@after` annotations to work for template member functions
- Fixed "Host" header handling in the HTTP server (now optional for HTTP/1.0 and responds with "bad request" if missing)
- Fixed `Json` to work at CTFE (by Mihail-K) - [pull #1489][issue1489]
- Fixed `adjustMethodStyle` (used throughout `vibe.web`) for method names with trailing upper case characters
- Fixed alignment of the `Json` type on x64, fixes possible dangling pointers due to the GC not recognizing unaligned pointers - [issue #1504][issue1504]
- Fixed serialization policies to work for enums and other built-in types (by Tomáš Chaloupka) - [pull #1500][issue1500]
- Fixed a bogus assertion error in `Win32TCPConnection.tcpNoDelay` and `.keepAlive` (by Денис Хлякин aka aka-demik) - [pull #1514][issue1514]
- Fixed a deadlock in `TaskPipe` - [issue #1501][issue1501]

[issue832]: https://github.com/vibe-d/vibe.d/issues/832
[issue1128]: https://github.com/vibe-d/vibe.d/issues/1128
[issue1265]: https://github.com/vibe-d/vibe.d/issues/1265
[issue1333]: https://github.com/vibe-d/vibe.d/issues/1333
[issue1352]: https://github.com/vibe-d/vibe.d/issues/1352
[issue1358]: https://github.com/vibe-d/vibe.d/issues/1358
[issue1388]: https://github.com/vibe-d/vibe.d/issues/1388
[issue1392]: https://github.com/vibe-d/vibe.d/issues/1392
[issue1394]: https://github.com/vibe-d/vibe.d/issues/1394
[issue1399]: https://github.com/vibe-d/vibe.d/issues/1399
[issue1401]: https://github.com/vibe-d/vibe.d/issues/1401
[issue1402]: https://github.com/vibe-d/vibe.d/issues/1402
[issue1407]: https://github.com/vibe-d/vibe.d/issues/1407
[issue1412]: https://github.com/vibe-d/vibe.d/issues/1412
[issue1416]: https://github.com/vibe-d/vibe.d/issues/1416
[issue1428]: https://github.com/vibe-d/vibe.d/issues/1428
[issue1434]: https://github.com/vibe-d/vibe.d/issues/1434
[issue1435]: https://github.com/vibe-d/vibe.d/issues/1435
[issue1438]: https://github.com/vibe-d/vibe.d/issues/1438
[issue1447]: https://github.com/vibe-d/vibe.d/issues/1447
[issue1448]: https://github.com/vibe-d/vibe.d/issues/1448
[issue1452]: https://github.com/vibe-d/vibe.d/issues/1452
[issue1453]: https://github.com/vibe-d/vibe.d/issues/1453
[issue1454]: https://github.com/vibe-d/vibe.d/issues/1454
[issue1456]: https://github.com/vibe-d/vibe.d/issues/1456
[issue1461]: https://github.com/vibe-d/vibe.d/issues/1461
[issue1470]: https://github.com/vibe-d/vibe.d/issues/1470
[issue1474]: https://github.com/vibe-d/vibe.d/issues/1474
[issue1476]: https://github.com/vibe-d/vibe.d/issues/1476
[issue1477]: https://github.com/vibe-d/vibe.d/issues/1477
[issue1489]: https://github.com/vibe-d/vibe.d/issues/1489
[issue1500]: https://github.com/vibe-d/vibe.d/issues/1500
[issue1504]: https://github.com/vibe-d/vibe.d/issues/1504
[issue1514]: https://github.com/vibe-d/vibe.d/issues/1514
[issue1526]: https://github.com/vibe-d/vibe.d/issues/1526


v0.7.28 - 2016-02-27
--------------------

This is a hotfix release, which fixes two critical regressions. The first one resulted in memory leaks or memory corruption, while the second one could cause TCP connections to hang indefinitely in the `close` method for the libevent driver.

### Bug fixes ###

- Fixed a regression in `FreeListRef` which caused the reference count to live outside of the allocated memory bounds - [issue #1432][issue1432]
- Fixed a task starvation regression in the libevent driver that happened when a connection got closed by the TCP remote peer while there was still data in the write buffer - [pull #1443][issue1443], [issue #1441][issue1441]
- Fixed recognizing "Connection: close" headers for non-lowercase spelling of "close" - [issue #1426][issue1426]
- Fixed the UDP receive timeout to actually work in the libevent driver - [issue #1429][issue1429]
- Fixed handling of the "Connection" header in the HTTP server to be case insensitive - [issue #1426][issue1426]

[issue1426]: https://github.com/vibe-d/vibe.d/issues/1426
[issue1429]: https://github.com/vibe-d/vibe.d/issues/1429
[issue1432]: https://github.com/vibe-d/vibe.d/issues/1432
[issue1441]: https://github.com/vibe-d/vibe.d/issues/1441
[issue1443]: https://github.com/vibe-d/vibe.d/issues/1443


v0.7.27 - 2016-02-09
--------------------

In preparation for a full separation of the individual library components, this release splits up the code logically into multiple DUB sub packages. This enables dependent code to reduce the dependency footprint and compile times. In addition to this and a bunch of further improvements, a lot of performance tuning and some important REST interface additions went into this release.

Note that the integration code for `std.concurrency` has been re-enabled with this release. This means that you can use `std.concurrency` without worrying about blocking the event loop now. However, there are a few incompatibilities between `std.concurrency` and vibe.d's own version in `vibe.core.concurrency`, such as `std.concurrency` not supporting certain `shared(T)` or `Isolated!T` to be passed to spawned tasks. If you hit any issues that cannot be easily resolved, the usual vibe.d behavior is available in the form of "Compat" suffixed functions (i.e. `sendCompat`, `receiveCompat` etc.). But note that these functions operate on separate message queue structures, so mixing the "Compat" functions with non-"Compat" versions will not work.

### Features and improvements ###

- Compiles on DMD frontend versions 2.066.0 up to 2.070.0
- Split up the library into sub packages - this prepares for a deeper split that is going to happen in the next release
- A lot of performance tuning went into the network and HTTP code, leading to a 50% increase in single-core HTTP performance and a lot more in the multi-threaded case over 0.7.26
- Marked more of the API `@safe` and `nothrow`
- Re-enabled the `std.concurrency` integration that went MIA a while ago - `std.concurrency` can now be used transparently in vibe.d applications - [issue #1343][issue1343], [pull #1345][issue1345]
- REST interface generator changes
  - Added support for REST collections with natural D syntax using the new `Collection!I` type - [pull #1268][issue1268]
  - Implemented CORS support for the REST interface server (by Sebastian Koppe) - [pull #1299][issue1299]
  - Conversion errors for path parameters (e.g. `@path("/foo/:someparam")`) in REST interfaces now result in a 404 error instead of 500
- HTTP server/client changes
  - The `URLRouter` now adds a `"routerRootDir"` entry with the relative path to the router base directory to `HTTPServerRequest.params` (by Steven Dwy) - [pull #1301][issue1301]
  - Added a WebSocket client implementation (by Kemonozume) - [pull #1332][issue1332]
  - Added the possibility to access cookie contents as a raw string
  - The HTTP client now retries a request if a keep-alive connection gets closed before the response gets read
  - Added `HTTPServerResponse.finalize` to manually force sending and finalization of the response - [issue #1347][issue1347]
  - Added `scope` callback based overloads of `switchProtocol` in `HTTPServerResponse` and `HTTPClientResponse`
  - Added `ChunkedOutputStream.chunkExtensionCallback` to control HTTP chunk-extensions (by Manuel Frischknecht and Yannick Koechlin) - [pull #1340][issue1340]
  - Passing an empty string to `HTTPClientResponse.switchProtocol` now skips the "Upgrade" header validation
  - Enabled TCP no-delay in the HTTP server
  - Redundant calls to `HTTPServerResponse.terminateSession` are now ignored instead of triggering an assertion - [issue #472][issue472]
  - Added log output for newly registered HTTP virtual hosts - [issue #1271][issue1271]
- The Markdown compiler now adds "id" attributes to headers to enable cross-referencing
- Added `getMarkdownOutline`, which returns a tree of sections in a Markdown document
- Added `Path.relativeToWeb`, a version of `relativeTo` with web semantics
- Added `vibe.core.core.setupWorkerThreads` to customize the number of worker threads on startup (by Jens K. Mueller) - [pull #1350][issue1350]
- Added support for parsing IPv6 URLs (by Mathias L. Baumann aka Marenz) - [pull #1341][issue1341]
- Enabled TCP no-delay in the Redis client (by Etienne Cimon) - [pull #1361][issue1361]
- Switch the `:javascript` Diet filter to use "application/json" as the content type - [issue #717][issue717]
- `NetworkAddress` now accepts `std.socket.AddressFamily` constants in addition to the `AF_` ones - [issue #925][issue925]
- Added support for X509 authentication in the MongoDB client (by machindertech) - [pull #1235][issue1235]
- Added `TCPListenOptions.reusePort` to enable port reuse as an OS supported means for load-balancing (by Soar Qin) - [pull #1379][issue1379]
- Added a `port` parameter to `RedisSessionStore.this()`
- Added code to avoid writing to `HTTPServerResponse.bodyWriter` after a fixed-length response has been fully written

### Bug fixes ###

- Fixed behavior of `ZlibInputStream` in case of premature end of input - [issue #1116][issue1116]
- Fixed a memory leak in `ZlibInputStream` (by Etienne Cimon) - [pull #1116][issue1116]
- Fixed a regression in the OpenSSL certificate validation code - [issue #1325][issue1325]
- Fixed the behavior of `TCPConnection.waitForData` in all drivers - [issue #1326][issue1326]
- Fixed a memory leak in `Libevent2Driver.connectTCP` on connection failure (by Etienne Cimon) - [pull #1322][issue1322], [issue #1321][issue1321]
- Fixed concatenation of static and dynamic class attributes in Diet templates - [issue #1312][issue1312]
- Fixed resource leaks in `connectTCP` for libevent when the task gets interrupted - [issue #1331][issue1331]
- Fixed `ZlibInputStream` in case of the target buffer matching up exactly with the uncompressed data (by Ilya Lyubimov aka villytiger) - [pull #1339][issue1339]
- Fixed some issues with triggering assertions on yielded tasks
- Fixed TLS SNI functionality in the HTTP server
- Fixed excessive CPU usage in the libasync driver (by Etienne Cimon) - [pull #1348][issue1348]
- Fixed exiting multi-thread event loops for the libasync driver (by Etienne Cimon) - [pull #1349][issue1349]
- Fixed the default number of worker threads to equal all logical cores in the system
- Fixed an assertion failure in the WebSocket server (by Ilya Yaroshenko aka 9il) - [pull #1356][issue1356], [issue #1354][issue1354]
- Fixed a range violation error in `InotifyDirectoryWatcher` - [issue #1364][issue1364]
- Fixed `readUntil` to not use the buffer returned by `InputStream.peek()` after a call to `InputStream.read()` - [issue #960][issue960]
- Disabled the case randomization feature of libevent's DNS resolver to work around issues with certain servers - [pull #1366][issue1366]
- Fixed the behavior of multiple `runEventLoop`/`exitEventLoop` calls in sequence for the win32 driver
- Fixed reading response bodies for "Connection: close" connections without a "Content-Length" in the HTTP client - [issue #604][issue604]
- Fixed indentation of `:javascript` blocks in Diet templates - [issue #837][issue837]
- Fixed assertion failure in the win32 driver when sending files over TCP - [issue #932][issue932]
- Fixed `exitEventLoop` having no effect if called while the event loop is in the idle handler
- Fixed an assertion failure in the libevent driver when actively closing a connection that is currently being read from - [issue #1376][issue1376]
- Fixed a null-pointer dereference when `waitForData` gets called on a fully closed TCP connection - [issue #1384][issue1384]
- Fixed a crash at exit caused by a bad module destructor call sequence when `std.parallelism.TaskPool` is used - [issue #1374][issue1374]

[issue472]: https://github.com/vibe-d/vibe.d/issues/472
[issue604]: https://github.com/vibe-d/vibe.d/issues/604
[issue717]: https://github.com/vibe-d/vibe.d/issues/717
[issue837]: https://github.com/vibe-d/vibe.d/issues/837
[issue925]: https://github.com/vibe-d/vibe.d/issues/925
[issue932]: https://github.com/vibe-d/vibe.d/issues/932
[issue960]: https://github.com/vibe-d/vibe.d/issues/960
[issue1116]: https://github.com/vibe-d/vibe.d/issues/1116
[issue1235]: https://github.com/vibe-d/vibe.d/issues/1235
[issue1268]: https://github.com/vibe-d/vibe.d/issues/1268
[issue1271]: https://github.com/vibe-d/vibe.d/issues/1271
[issue1299]: https://github.com/vibe-d/vibe.d/issues/1299
[issue1301]: https://github.com/vibe-d/vibe.d/issues/1301
[issue1312]: https://github.com/vibe-d/vibe.d/issues/1312
[issue1321]: https://github.com/vibe-d/vibe.d/issues/1321
[issue1322]: https://github.com/vibe-d/vibe.d/issues/1322
[issue1325]: https://github.com/vibe-d/vibe.d/issues/1325
[issue1326]: https://github.com/vibe-d/vibe.d/issues/1326
[issue1331]: https://github.com/vibe-d/vibe.d/issues/1331
[issue1332]: https://github.com/vibe-d/vibe.d/issues/1332
[issue1339]: https://github.com/vibe-d/vibe.d/issues/1339
[issue1340]: https://github.com/vibe-d/vibe.d/issues/1340
[issue1341]: https://github.com/vibe-d/vibe.d/issues/1341
[issue1343]: https://github.com/vibe-d/vibe.d/issues/1343
[issue1345]: https://github.com/vibe-d/vibe.d/issues/1345
[issue1347]: https://github.com/vibe-d/vibe.d/issues/1347
[issue1348]: https://github.com/vibe-d/vibe.d/issues/1348
[issue1349]: https://github.com/vibe-d/vibe.d/issues/1349
[issue1350]: https://github.com/vibe-d/vibe.d/issues/1350
[issue1354]: https://github.com/vibe-d/vibe.d/issues/1354
[issue1356]: https://github.com/vibe-d/vibe.d/issues/1356
[issue1361]: https://github.com/vibe-d/vibe.d/issues/1361
[issue1364]: https://github.com/vibe-d/vibe.d/issues/1364
[issue1366]: https://github.com/vibe-d/vibe.d/issues/1366
[issue1374]: https://github.com/vibe-d/vibe.d/issues/1374
[issue1376]: https://github.com/vibe-d/vibe.d/issues/1376
[issue1379]: https://github.com/vibe-d/vibe.d/issues/1379
[issue1384]: https://github.com/vibe-d/vibe.d/issues/1384


v0.7.26 - 2015-11-04
--------------------

A large revamp of the REST interface generator was done in this release, which will enable faster future developments. The new JavaScript client generator is the first feature made possible by this. Apart from a good chunk of functional improvements in various areas, a notable change on the build level is that the `VibeCustomMain` version is no longer required for projects that implement their own `main` function.

### Features and improvements ###

- Compiles on 2.066.x up to 2.069.0
- Removed deprecated symbols and deprecated those that were scheduled for deprecation
- The `VibeCustomMain` version identifier is now a no-op and the new default behavior
- Added a JavaScript REST client generator to `vibe.web.rest` - [pull #1209][issue1209]
- Added translation support for plural forms in `vibe.web.i18n` (by Nathan Coe) - [pull #1290][issue1290]
- Added a fiber compatible read-write mutex implementation (`TaskReadWriteMutex`) (by Manuel Frischknecht) - [pull #1287][issue1287]
- Added `vibe.http.fileserver.sendFile`
- Added ALPN support to the TLS module (by Etienne Cimon)
- Added an optional [Botan](https://github.com/etcimon/botan) based TLS implementation (by Etienne Cimon)
- Switched the `vibe.core.log` module to support allocation-less logging (range like interface)
- Removed all intrinsic dynamic allocations in all built-in logger implementations - this makes it possible to log from within class finalizers
- Added `Cookie.toString()` (by Etienne Cimon)
- Added `MarkdownSettings.urlFilter` in order to be able to customize contained links
- Made `Json.toString` `@safe` so that `Json` values can be logged using `std.experimental.logger`
- Added `HTTPServerRequest.noLog`, usable to disable access logging for particular requests (by Márcio Martins) - [pull #1281][issue1281]
- Added support for static array parameters in `vibe.web.web`
- Added `LocalTaskSemaphore`, a single-threaded task-compatible semaphore implementation (by Etienne Cimon)
- Added `ConnectionPool.maxConcurrency` (by Etienne Cimon)
- Added `MongoCollection.findAndModifyExt`, which takes a parameter with custom options - [issue #911][issue911]
- `TLSVersion.any` now only matches TLS 1.0 and up; SSL 3 is explicitly excluded (by Márcio Martins) - [pull #1280][issue1280]
- Removed some bad dependencies to prepare for splitting up the library (dependency cycles between low-level and high-level packages)
- Implemented timer support for the libev driver - [pull #1206][issue1206]
- Improved the method prefix semantics in the web/REST interface generators, so that only whole words are recognized
- Mime type `"application/vnd.api+json"` is now recognized to have a JSON body in the HTTP server (by Szabo Bogdan) - [pull #1296][issue1296]

### Bug fixes ###

- Fixes in the libasync driver (by Etienne Cimon)
  - Various correctness and crash fixes
  - Fixed handling files with non-ASCII characters on Windows - [pull #1273][issue1273]
  - Fixed timers with a zero timeout - [pull #1204][issue1204]
  - Fixed a possible TCP connection stall for blocking writes - [pull #1247][issue1247]
  - Fixed partially dropped data for TCP connections - [issue #1297][issue1297], [pull #1298][issue1298]
  - Fixed properly waiting for blocking operations - [issue #1227][issue1227]
- Missing HTML form parameters are now properly handled by `@errorDisplay` in the web interface generator
- Fixed bogus Diet template dependencies caused by interpreting *all* lines that started with "extends ..." as extension directives
- Fixed `runWorkerTaskH` to be callable outside of a task context - [pull #1206][issue1206]
- Fixed `LibevManualEvent` to actually work across threads - [pull #1206][issue1206]
- Fixed a bug in the shutdown sequence that could cause the application to hang if worker threads had been started - [pull #1206][issue1206]
- Fixed multiple loggers not working - [issue #1294][issue1294]
- Fixed `workerThreadCount` to always return a non-zero number by letting it start up the workers if necessary
- Fixed `Path.toString()` to output trailing slashes if required for empty paths
- Fixed an TLS connection failure in the OpenSSL based implementation when no `peer_name` was set
- Fixed linking on Debian, which has removed certain public OpenSSL functions (by Luca Niccoli) - [issue #1315][issue1315], [pull #1316][issue1316]
- Fixed an assertion happening when parsing malformed URLs - [issue #1318][issue1318]

[issue911]: https://github.com/vibe-d/vibe.d/issues/911
[issue1204]: https://github.com/vibe-d/vibe.d/issues/1204
[issue1206]: https://github.com/vibe-d/vibe.d/issues/1206
[issue1209]: https://github.com/vibe-d/vibe.d/issues/1209
[issue1273]: https://github.com/vibe-d/vibe.d/issues/1273
[issue1280]: https://github.com/vibe-d/vibe.d/issues/1280
[issue1281]: https://github.com/vibe-d/vibe.d/issues/1281
[issue1287]: https://github.com/vibe-d/vibe.d/issues/1287
[issue1290]: https://github.com/vibe-d/vibe.d/issues/1290
[issue1294]: https://github.com/vibe-d/vibe.d/issues/1294
[issue1227]: https://github.com/vibe-d/vibe.d/issues/1227
[issue1247]: https://github.com/vibe-d/vibe.d/issues/1247
[issue1296]: https://github.com/vibe-d/vibe.d/issues/1296
[issue1297]: https://github.com/vibe-d/vibe.d/issues/1297
[issue1298]: https://github.com/vibe-d/vibe.d/issues/1298
[issue1315]: https://github.com/vibe-d/vibe.d/issues/1315
[issue1316]: https://github.com/vibe-d/vibe.d/issues/1316
[issue1318]: https://github.com/vibe-d/vibe.d/issues/1318


v0.7.25 - 2015-09-20
--------------------

Mostly a bugfix release, including a regression fix in the web form parser, this release also drops official support for the DMD 2.065.0 front end (released February 2014). Most functionality will probably still stay functional on 2.065.0 for a while.

### Features and improvements ###

- Contains some compile fixes for the upcoming 2.069 version of DMD
- The REST interface generator adds support for `out`/`ref` `@headerParam` parameters
- Stripping `id`/`_id` fields for `RedisStripped!T` is now optional
- `registerWebInterface` and `registerRestInterface` now return the `URLRouter` instance to enable method chaining (by Martin Nowak) - [pull #1208][issue1208]

### Bug fixes ###

- Fixed parsing of multi-part forms when a `Content-Length` part header is present (by sigod) - [issue #1220][issue1220], [pull #1221][issue1221]
- Fixed parsing of multi-part forms that don't end in `"--\r\n"` (by Etienne Cimon) - [pull #1232][issue1232]
- Fixed an exception occurring in `waitForData()` when calling `Libevent2TCPConnection.close()` concurrently (by machindertech) - [pull #1205][issue1205]
- Fixed handling of `WebInterfaceSettings.ignoreTrailingSlash` for sub interfaces (by Marc Schütz) - [pull #1237][issue1237]
- Fixed an alignment issue in conjunction with atomic operations on the upcoming LDC 0.16.0 (by Kai Nacke aka redstar) - [pull #1255][issue1255]
- Fixed parsing of empty HTTP request headers - [issue #1254][issue1254]
- Fixed using the MongoDB client on a mongos instance - [pull #1246][issue1246]
- Fixed using `LibasyncUDPConnection.recv` without a timeout (by Daniel Kozak) - [pull #1242][issue1242]
- Fixed a regression in `RestInterfaceClient`, where a `get(T id)` method would result in a URL with two consecutive underscores

[issue1205]: https://github.com/vibe-d/vibe.d/issues/1205
[issue1220]: https://github.com/vibe-d/vibe.d/issues/1220
[issue1221]: https://github.com/vibe-d/vibe.d/issues/1221
[issue1232]: https://github.com/vibe-d/vibe.d/issues/1232
[issue1237]: https://github.com/vibe-d/vibe.d/issues/1237
[issue1242]: https://github.com/vibe-d/vibe.d/issues/1242
[issue1246]: https://github.com/vibe-d/vibe.d/issues/1246
[issue1254]: https://github.com/vibe-d/vibe.d/issues/1254
[issue1255]: https://github.com/vibe-d/vibe.d/issues/1255


v0.7.24 - 2015-08-10
--------------------

Adds DMD 2.068.0 compatibility and contains a number of additions and fixes in all parts of the library. Some notable changes are the addition of WebSocket support in the `vibe.web.web` module and the planned deprecation of `opDispatch` for `Json` and `Bson`, as well as the rename of all "SSL" symbols to "TLS". HTTP request handlers can, and should, now take the request/response parameters as `scope`, which will later allow to improve performance without compromising safety.

### Features and improvements ###

 - Fixed compilation on DMD 2.068 (most fixes by Mathias Lang)
 - Web interface generator (`vibe.web.web`)
   - Added support for `WebSocket` routes - [issue #952][issue952]
   - Doesn't intercept `HTTPStatusException`s thrown during parameter assembly anymore
   - Replaced the deprecated form interface example project with a `vibe.web.web` based "web_ajax" example
   - Added support for the `@path` attribute on registered classes - [issue #1036][issue1036]
 - REST interface generator (`vibe.web.rest`)
   - Removed support for `index()` methods (use `get()` or `@path("/")`) (by Mathias Lang) - [pull #1010][issue1010]
   - Deprecated the `@rootPath` attribute (use `@path` instead) (by Mathias Lang) - [pull #999][issue999]
 - Deprecated symbols that were scheduled for deprecation and removed deprecated symbols
 - Added version `VibeNoDefaultArgs` to disable the built-in command line options
 - Renamed "SSL" to "TLS" in most places
 - Scheduled `Json.opDispatch` and `Bson.opDispatch` for deprecation (use `opIndex` instead)
 - Added `Bson.tryIndex` (by Marc Schütz) - [pull #1032][issue1032]
 - Added support for all standard HTTP methods (RFC) (by Szabo Bogdan) - [pull #1068][issue1068], [pull #1082][issue1082]
 - Added overloads for `scope` based HTTP server callbacks
   - These will later be used for safe, allocation-less HTTP request processing
   - Always prefer this over the non-`scope` callbacks, as these will imply a performance impact in later versions
 - Added `vibe.core.stream.nullSink` as a convenient way to get a generic data sink stream
 - Added overloads of `writeFormData` and `writeFormBody` that accept ranges of key/value tuples (by Tobias Pankrath)
 - Added `HTTPClientResponse.switchProtocol` (by Luca Niccoli) - [pull #945][issue945]
 - `listenHTTP` now returns a `HTTPListener` instance that can be used to stop listening - [issue #1074][issue1074]
 - Added an `AppenderResetMode` parameter to `MemoryOutputStream.reset()` (by Etienne Cimon)
 - Changed `urlEncode` to only allocate if necessary (by Marc Schütz) - [pull #1076][issue1076]
 - Optimize multi-part form decoding for cases where "Content-Length" is given (by Etienne Cimon) - [pull #1101][issue1101]
 - Added serialization support for `std.typecons.BitFlags!T`
 - Removed the `HTTPRouter` interface (now just a compatibility alias to `URLRouter`) (by Mathias Lang) - [pull #1106][issue1106]
 - Added `HTTPStatus.tooManyRequests` (by Jack Applegame) - [pull #1103][issue1103]
 - Added optional `code` and `reason` parameters to `WebSocket.close()` (by Steven Dwy) - [pull #1107][issue1107]
 - Added an optional copy+delete fallback to `moveFile()` (by Etienne Cimon and Martin Nowak)
 - Let `ConnectionProxyStream` work without an underlying `ConnectionStream` (by Etienne Cimon)
 - Added a `ConnectionProxyStream` constructor taking separate input and output streams
 - Updated the OpenSSL Windows binaries to 1.0.1m
 - Added `BigInt` support to the JSON module (by Igor Stepanov) - [pull #1118][issue1118]
 - The event loop of the win32 driver can now be stopped by sending a `WM_QUIT` message (by Денис Хлякин aka aka-demik) - [pull #1120][issue1120]
 - Marked `vibe.inet.path` as `pure` and removed casts that became superfluous
 - Added an `InputStream` based overload of `HTTPServerResponse.writeBody` - [issue #1594][issue1594]
 - Added all Redis modules to the `vibe.vibe` module
 - Added a version of `FixedRingBuffer.opApply` that supports an index (by Tomáš Chaloupka) - [pull #1198][issue1198]

### Bug fixes ###

 - Fixed listening on IPv6 interfaces for the win32 driver
 - Fixed `URL.localURI` updating the query string and anchor parts properly - [issue #1044][issue1044]
 - Fixed `Task.join()` to work outside of a running event loop
 - Fixed the automatic redirection in `vibe.web.web` in case of mismatching trailing slash
 - Fixed `MongoCollection.count()` when used with MongoDB 3.x - [issue #1058][issue1058]
 - Fixed detection of non-copyable, but movable types for `runTask`
 - Fixed processing of translation strings with escape sequences in `vibe.web.web` (by Andrey Zelenchuk) - [pull #1067][issue1067]
 - Fixed unnecessarily closing HTTP client connections
 - Fixed using `TCPConnection.close()` with a concurrent `read()` operation (libevent driver)
 - Fixed parsing of HTTP digest authentication headers with different whitespace padding or differing case (by Денис Хлякин aka aka-demik) - [pull 1083][issue1083]
 - Fixed parsing various HTTP request headers case insensitively
 - Fixed validation of untrusted certificates without `TLSPeerValidationMode.checkTrust` for `OpenSSLStream`
 - Fixed TLS certificate host/address validation in the SMTP client
 - Fixed `@bodyParam` parameters with default value in the REST interface generator (by Mathias Lang) - [issue #1125][issue1125], [pull #1129][issue1129]
 - Fixed running the TLS context setup for STARTTLS SMTP connections (by Nathan Christenson) - [pull #1132][issue1132]
 - Fixed JSON serialization of `const(Json)` (by Jack Applegame) - [pull #1109][issue1109]
 - Fixed runtime error for Windows GUI apps that use the Visual Studio runtime
 - Various fixes in the libasync event driver (by Etienne Cimon)
 - Fixed the REST interface generator to treat `get`/`post`/... methods as `@path("/")` (by Mathias Lang) - [pull #1135][issue1135]
 - Fixed `URL`'s internal encoding of the path string (by Igor Stepanov) - [pull #1148][issue1148]
 - Fixed decoding query parameters in the REST interface generator (by Igor Stepanov) - [pull #1143][issue1143]
 - Fixed a possible range violation when writing long HTTP access log messages (by Márcio Martins) - [pull #1156][issue1156]
 - Fixed support of typesafe variadic methods in the REST interface generator (by Mathias Lang) - [issue #1144][issue1144], [pull #1159][issue1159]
 - Fixed `getConfig`, `setConfig` and `configResetStat` in `RedisClient` (by Henning Pohl) - [pull #1158][issue1158]
 - Fixed possible CPU hog in timer code for periodic timer events that were triggered too fast
 - Fixed a possible memory leak and wrongly reported request times for HTTP connections that get terminated before finishing a response - [issue #1157][issue1157]
 - Fixed `vibe.web.web.redirect()` to work properly for relative paths with query strings
 - Fixed invalid JSON syntax in dub.json - [issue #1172][issue1172]
 - Fixed `LibasyncFileStream` when used with `FileMode.createTrunc` (by Etienne Cimon) - [pull #1176][issue1176]
 - Fixed `deserialize` when operating on a struct/class that is annotated with `@asArray` (by Colden Cullen) - [pull #1182][issue1182]
 - Fixed parsing quoted HTTP multi part form boundaries (by Mathias L. Baumann aka Marenz) - [pull #1183][issue1183]
 - Fixed `LibasyncFileStream.peek()` to always return `null` (by Etienne Cimon) - [pull #1179][issue1179]
 - Fixed `ThreadedFile.seek` for 32-bit Windows applications (libevent driver) - [issue #1189][issue1189]
 - Fixed parsing of relative `file://` URLs
 - Fixed a possible `RangeError` in the JSON parser (by Takaaki Seki) - [pull #1199][issue1199]
 - Fixed a possible resource leak in `HashMap` (destructors not run)
 - Fixed `pipeRealtime` to always adhere to the maximum latency
 - Fixed deserialization of `immutable` fields (by Jack Applegame) - [pull #1190][issue1190]


[issue945]: https://github.com/vibe-d/vibe.d/issues/945
[issue952]: https://github.com/vibe-d/vibe.d/issues/952
[issue999]: https://github.com/vibe-d/vibe.d/issues/999
[issue1010]: https://github.com/vibe-d/vibe.d/issues/1010
[issue1032]: https://github.com/vibe-d/vibe.d/issues/1032
[issue1036]: https://github.com/vibe-d/vibe.d/issues/1036
[issue1044]: https://github.com/vibe-d/vibe.d/issues/1044
[issue1058]: https://github.com/vibe-d/vibe.d/issues/1058
[issue1067]: https://github.com/vibe-d/vibe.d/issues/1067
[issue1068]: https://github.com/vibe-d/vibe.d/issues/1068
[issue1074]: https://github.com/vibe-d/vibe.d/issues/1074
[issue1076]: https://github.com/vibe-d/vibe.d/issues/1076
[issue1082]: https://github.com/vibe-d/vibe.d/issues/1082
[issue1083]: https://github.com/vibe-d/vibe.d/issues/1083
[issue1101]: https://github.com/vibe-d/vibe.d/issues/1101
[issue1103]: https://github.com/vibe-d/vibe.d/issues/1103
[issue1106]: https://github.com/vibe-d/vibe.d/issues/1106
[issue1107]: https://github.com/vibe-d/vibe.d/issues/1107
[issue1109]: https://github.com/vibe-d/vibe.d/issues/1109
[issue1118]: https://github.com/vibe-d/vibe.d/issues/1118
[issue1120]: https://github.com/vibe-d/vibe.d/issues/1120
[issue1125]: https://github.com/vibe-d/vibe.d/issues/1125
[issue1129]: https://github.com/vibe-d/vibe.d/issues/1129
[issue1132]: https://github.com/vibe-d/vibe.d/issues/1132
[issue1135]: https://github.com/vibe-d/vibe.d/issues/1135
[issue1143]: https://github.com/vibe-d/vibe.d/issues/1143
[issue1144]: https://github.com/vibe-d/vibe.d/issues/1144
[issue1148]: https://github.com/vibe-d/vibe.d/issues/1148
[issue1156]: https://github.com/vibe-d/vibe.d/issues/1156
[issue1157]: https://github.com/vibe-d/vibe.d/issues/1157
[issue1158]: https://github.com/vibe-d/vibe.d/issues/1158
[issue1159]: https://github.com/vibe-d/vibe.d/issues/1159
[issue1172]: https://github.com/vibe-d/vibe.d/issues/1172
[issue1176]: https://github.com/vibe-d/vibe.d/issues/1176
[issue1179]: https://github.com/vibe-d/vibe.d/issues/1179
[issue1182]: https://github.com/vibe-d/vibe.d/issues/1182
[issue1183]: https://github.com/vibe-d/vibe.d/issues/1183
[issue1189]: https://github.com/vibe-d/vibe.d/issues/1189
[issue1190]: https://github.com/vibe-d/vibe.d/issues/1190
[issue1198]: https://github.com/vibe-d/vibe.d/issues/1198
[issue1199]: https://github.com/vibe-d/vibe.d/issues/1199


v0.7.23 - 2015-03-25
--------------------

Apart from fixing compilation on DMD 2.067 and revamping the `vibe.core.sync` module to support `nothrow`, notable changes are extended parameter support in `vibe.web.rest`, improved translation support in `vibe.web.web` and new support for policy based customization of (de-)serialization. The Diet template parser has also received a good chunk of fixes and improvements in this release.

### Features and improvements ###

 - Compiles on DMD frontend 2.065 up to 2.067 (most fixes for 2.067 are by Mathias Lang) - [pull #972][pull 972], [pull #992][issue992]
 - Changed semantics of `TaskMutex` and `TaskCondition` - **this can be a breaking change for certain applications**
   - The classes are now `nothrow` to stay forward compatible with D's `Mutex` and `Condition` classes,
   - Interruption using `Task.interrupt()` now gets deferred to the next wait/yield operation
   - The old behavior can be achieved using the new `InterruptipleTaskMutex` and `InterruptibleTaskCondition` classes
 - Definition of either `VibeCustomMain` or `VibeDefaultMain` is now a hard requirement - this is the final deprecation phase for `VibeCustomMain`
 - Added an overload of `lowerPrivileges` that takes explicit user/group arguments (by Darius Clark) - [pull #948][issue948]
 - Added `handleWebSocket` as a procedural alternative to `handleWebSockets` (by Luca Niccoli) - [pull #946][issue946]
 - Added support for "msgctxt" in .po files for the `vibe.web.web` translation framework (by Nathan Coe) - [pull #896][issue896]
 - Added overloads of `HTTPServerResponse.writeBody` and `writeRawBody` with an additional status code parameter (by Martin Nowak) - [pull #980][issue980]
 - Added `@queryParam` and `@bodyParam` to the `vibe.web.rest` module (by Mathias Lang) - [pull #969][issue969]
 - Added support for serving an "index.html" file when requesting a directory (by Martin Nowak) - [pull #902][issue902]
 - Added policy based customization for `vibe.data.serialization` (by Luca Niccoli) - [pull #937][issue937]
 - Added `SSLStream.peerCertificate` and `HTTPServerRequest.clientCertificate` properties (by Rico Huijbers) - [pull #965][issue965]
 - Added `RedisDatabase.zrangeByLex` (by Etienne Cimon) - [pull #993][issue993]
 - Added support for HTTP digest authentication (by Kai Nacke aka redstar) - [pull #1000][issue1000]
 - Diet template features
 	- Added support for plain text lines starting with `<` (plain HTML lines) (by Kai Nacke aka redstar) - [pull #1007][issue1007]
 	- Added support for default and "prepend" modes for blocks (help from Kai Nacke aka redstar) - [issue #905][issue905], [pull #1002][issue1002]
 	- Multiple "id" attributes are now explicitly disallowed (by Kai Nacke aka redstar) - [pull #1008][issue1008]

### Bug fixes ###

 - Fixed ping handling for WebSockets and added automatic keep-alive pinging (by Luca Niccoli) - [pull #947][issue947]
 - Fixed wrapped texts in .po files for the `vibe.web.web` translation framework (by Nathan Coe) - [pull #896][issue896]
 - Fixed a crash issue when storing a `Timer` in a class instance that does not get destroyed before application exit - [issue #978][issue978]
 - Fixed `HTTPRouter.any` to match all supported HTTP verbs (by Szabo Bogdan) - [pull #984][issue984]
 - Fixed setting `TCPConnection.localAddr` in the libasync driver (by Etienne Cimon) - [issue #961][issue961], [pull #962][issue962]
 - Fixed some cases of missing destructor calls in `vibe.utils.memory` (partially by Etienne Cimon) - [pull #987][issue987]
 - Fixed some failed incoming SSL connection attempts by setting a default session context ID (by Rico Huijbers) - [pull #970][issue970]
 - Fixed `RedisSessionStore.create()` (by Yusuke Suzuki) - [pull #996][issue996]
 - Fixed HTML output of `//` style comments in Diet templates (by Kai Nacke) - [pull #1004][issue1004]
 - Fixed the error message for mismatched `@path` placeholder parameters in `vibe.web.rest` (by Mathias Lang aka Geod24) - [issue #949][issue949], [pull #1001][issue1001]
 - Fixed parsing of hidden comments in Diet templates that have no leading space (by Kai Nacke) - [pull #1012][issue1012]
 - Fixed serialization of `const(Json)` values
 - Fixed handling of struct parameter types in `vibe.web.rest` that implicitly convert to `string`, but not vice-versa
 - Fixed HTTP request parsing with uppercase letters in the "Transfer-Encoding" header (by Szabo Bogdan) - [pull #1015][issue1015]
 - Fixed parsing of Diet attributes that are followed by whitespace - [issue #1021][issue1021]
 - Fixed parsing of Diet string literal attributes that contain unbalanced parenthesis - [issue #1033][issue1033]

[issue896]: https://github.com/vibe-d/vibe.d/issues/896
[issue896]: https://github.com/vibe-d/vibe.d/issues/896
[issue902]: https://github.com/vibe-d/vibe.d/issues/902
[issue905]: https://github.com/vibe-d/vibe.d/issues/905
[issue937]: https://github.com/vibe-d/vibe.d/issues/937
[issue946]: https://github.com/vibe-d/vibe.d/issues/946
[issue947]: https://github.com/vibe-d/vibe.d/issues/947
[issue948]: https://github.com/vibe-d/vibe.d/issues/948
[issue949]: https://github.com/vibe-d/vibe.d/issues/949
[issue961]: https://github.com/vibe-d/vibe.d/issues/961
[issue962]: https://github.com/vibe-d/vibe.d/issues/962
[issue965]: https://github.com/vibe-d/vibe.d/issues/965
[issue969]: https://github.com/vibe-d/vibe.d/issues/969
[issue970]: https://github.com/vibe-d/vibe.d/issues/970
[issue978]: https://github.com/vibe-d/vibe.d/issues/978
[issue980]: https://github.com/vibe-d/vibe.d/issues/980
[issue984]: https://github.com/vibe-d/vibe.d/issues/984
[issue987]: https://github.com/vibe-d/vibe.d/issues/987
[issue992]: https://github.com/vibe-d/vibe.d/issues/992
[issue993]: https://github.com/vibe-d/vibe.d/issues/993
[issue996]: https://github.com/vibe-d/vibe.d/issues/996
[issue1000]: https://github.com/vibe-d/vibe.d/issues/1000
[issue1001]: https://github.com/vibe-d/vibe.d/issues/1001
[issue1002]: https://github.com/vibe-d/vibe.d/issues/1002
[issue1004]: https://github.com/vibe-d/vibe.d/issues/1004
[issue1007]: https://github.com/vibe-d/vibe.d/issues/1007
[issue1008]: https://github.com/vibe-d/vibe.d/issues/1008
[issue1012]: https://github.com/vibe-d/vibe.d/issues/1012
[issue1015]: https://github.com/vibe-d/vibe.d/issues/1015
[issue1021]: https://github.com/vibe-d/vibe.d/issues/1021
[issue1033]: https://github.com/vibe-d/vibe.d/issues/1033


v0.7.22 - 2015-01-12
--------------------

A small release mostly fixing compilation issues on DMD 2.065, LDC 0.14.0 and GDC. It also contains the new optional libasync based event driver for initial testing.

### Features and improvements ###

 - Added a new event driver based on the [libasync](https://github.com/etcimon/libasync) native D event loop abstraction library (by Etienne Cimon) - [pull #814][issue814]
 - Added support for `@headerParam` in the REST interface generator (by Mathias Lang aka Geod24) - [pull #908][issue908]
 - Added `font/woff` as a recognized compressed MIME type to avoid redundant compression for HTTP transfers (by Márcio Martins) - [pull #923][issue923]
 - The BSON deserialization routines now transparently convert from `long` to `int` where required (by David Monagle) - [pull #913][issue913]

### Bug fixes ###

 - Fixed an overload conflict for `urlEncode` introduced in 0.7.21
 - Fixed a compilation issue with `Exception` typed `_error` parameters in web interface methods (by Denis Hlyakin) - [pull #900][issue900]
 - Fixed conversion of `Bson.Type.undefined` to `Json` (by Márcio Martins) - [pull #922][issue922]
 - Fixed messages leaking past the end of a task to the next task handled by the same fiber (by Luca Niccoli) - [pull #934][issue934]
 - Fixed various compilation errors and ICEs for DMD 2.065, GDC and LDC 0.14.0 (by Martin Nowak) - [pull #901][issue901], [pull #907][issue907], [pull #927][issue927]

[issue814]: https://github.com/vibe-d/vibe.d/issues/814
[issue900]: https://github.com/vibe-d/vibe.d/issues/900
[issue901]: https://github.com/vibe-d/vibe.d/issues/901
[issue907]: https://github.com/vibe-d/vibe.d/issues/907
[issue908]: https://github.com/vibe-d/vibe.d/issues/908
[issue913]: https://github.com/vibe-d/vibe.d/issues/913
[issue922]: https://github.com/vibe-d/vibe.d/issues/922
[issue923]: https://github.com/vibe-d/vibe.d/issues/923
[issue927]: https://github.com/vibe-d/vibe.d/issues/927
[issue934]: https://github.com/vibe-d/vibe.d/issues/934


v0.7.21 - 2014-11-18
--------------------

Due to a number of highly busy months (more to come), this release got delayed far more than planned. However, development didn't stall and, finally, a huge list of over 150 changes found its way into the new version. Major changes are all over the place, including some notable changes in the SSL/TLS support and the web interface generator.

### Features and improvements ###

 - SSL/TLS support
	 - Added support for TLS server name indication (SNI) to the SSL support classes and the HTTP client and server implementation
	 - Changed `SSLPeerValidationMode` into a set of bit flags (different modes can now be combined)
	 - Made the SSL implementation pluggable (currently only OpenSSL is supported)
	 - Moved all OpenSSL code into a separate module to avoid importing the OpenSSL headers in `vibe.stream.ssl` (by Martin Nowak) - [pull #757][issue757]
	 - Added support for a `VibeUseOldOpenSSL` version to enable use with pre 1.0 versions of OpenSSL
	 - Upgraded the included OpenSSL Windows binaries to 1.0.1j
 - Web interface generator
	 - Added support for `Json` as a return type for web interface methods (by Stefan Koch) - [pull #684][issue684]
	 - Added support for a `@contentType` attribute for web interface methods (by Stefan Koch) - [pull #684][issue684]
	 - Added `vibe.web.web.trWeb` for runtime string translation support
	 - Added support for nesting web interface classes using properties that return a class instance
	 - Added support for `@before`/`@after` attributes for web interface methods
	 - Added a `PrivateAccessProxy` mixin as a way to enable use of private and non-static methods for `@before` in web interfaces
	 - Added support for validating parameter types to `vibe.web.web` (`vibe.web.validation`)
	 - Added the possibility to customize the language selection in the translation context for web interface translations
	 - Added optional support for matching request paths with mismatching trailing slash in web interfaces
	 - `SessionVar`, if necessary, now starts a new session also for read accesses
 - HTTP sessions
	 - Added a check to disallow storing types with aliasing in sessions
	 - Session values are now always returned as `const` to avoid unintended mutation of the returned temporary
	 - Added initial support for JSON and BSON based session stores
	 - Added a Redis based HTTP session store (`vibe.db.redis.sessionstore.RedisSessionStore`)
	 - Deprecated index operator based access of session values (recommended to use `vibe.web.web.SessionVar` instead)
 - Redis database driver
	 - Added some missing Redis methods and rename `RedisClient.flushAll` to `deleteAll`
	 - Added the `vibe.db.redis.types` module for type safe access of Redis keys
	 - `RedisReply` is now a typed output range
	 - Added a module for Redis with common high level idioms (`vibe.db.redis.idioms`)
	 - Improved the Redis interface with better template constraints, support for interval specifications and support for `Nullable!T` to determine key existence
	 - Made the `member` argument to the sorted set methods in `RedisDatabase` generic instead of `string` - [issue #811][issue811]
	 - Added support for `ubyte[]` as a return type for various Redis methods (by sinkuu) - [pull #761][issue761]
 - MongoDB database driver
	 - `MongoConnection.defaultPort` is now an `ushort` (by Martin Nowak) - [pull #725][issue725]
	 - Added support for expiring indexes and dropping indexes/collections in the MongoDB client (by Márcio Martins) - [pull #799][issue799]
	 - Added `MongoClient.getDatabases` (by Peter Eisenhower) - [pull #822][issue822]
	 - Added an array based overload of `MongoCollection.ensureIndex` - [issue #824][issue824]
	 - Added `MongoCursor.skip` as an alternative to setting the skip value using an argument to `find` (by Martin Nowak) - [pull 888][issue888]
 - HTTP client
	 - Made the handling of redirect responses more specific in the HTTP client (reject unknown status codes)
	 - Added support for using a proxy server in the HTTP client (by Etienne Cimon) - [pull #731][issue731]
	 - Added `HTTPClientSettings.defaultKeepAliveTimeout` and handle the optional request count limit of keep-alive connections (by Etienne Cimon) - [issue 744][issue744], [pull #756][issue756]
	 - Added an assertion to the HTTP client when a relative path is used for the request URL instead of constructing an invalid request
	 - Avoid using chunked encoding for `HTTPClientRequest.writeJsonBody`
 - HTTP server
	 - Added support for IP based client certificate validation in the HTTP server (by Eric Cornelius) - [pull #723][issue723]
	 - Avoid using chunked encoding for `HTTPServerResponse.writeJsonBody` - [issue #619][issue619]
	 - Added `HTTPServerResponse.waitForConnectionClose` to support certain kinds of long-polling applications
 - Compiles on DMD 2.064 up to DMD 2.067.0-b1
 - All external dependencies are now version based (OpenSSL/libevent/libev)
 - Removed deprecated symbols of 0.7.20
 - Increased the default fiber stack size to 512 KiB (32-bit) and 16 MiB (64-bit) respectively - [issue #861][issue861]
 - Enabled the use of `shared` delegates for `runWorkerTask` and avoid creation of a heap delegate
 - Added support for more parameter types in `runTask`/`runWorkerTask` by avoiding `Variant`
 - Added an initial implementation of a `Future!T` (future/promise) in `vibe.core.concurrency`
 - Deprecated the output range interface of `OutputStream`, use `vibe.stream.wrapper.StreamOutputRange` instead
 - Prefer `.toString()` to `cast(string)` when converting values to string in Diet templates (changes how `Json` values are converted!) - [issue #714][issue714]
 - Added variants of the `vibe.utils.validation` functions that don't throw
 - Added `UDPConnection.close()`
 - Deprecated `registerFormInterface` and `registerFormMethod`
 - Added support for implicit parameter conversion of arguments passed to `runTask`/`runWorkerTask` (by Martin Nowak) - [pull #719][issue719]
 - Added `vibe.stream.stdio` for vibe.d compatible wrapping of stdin/stdout and `std.stdio.File` (by Eric Cornelius) - [pull #729][issue729]
 - Added `vibe.stream.multicast.MultiCastStream` for duplicating a stream to multiple output streams (by Eric Cornelius) - [pull #732][issue732]
 - Added support for an `inotify` based directory watcher in the libevent driver (by Martin Nowak) - [pull #743][issue743]
 - Added support for `Nullable!T` in `vibe.data.serialization` - [issue #752][issue752]
 - Added a constructor for `BsonObjectID` that takes a specific time stamp (by Martin Nowak) - [pull #759][issue759]
 - Added output range based overloads of `std.stream.operations.readUntil` and `readLine`
 - Added `vibe.data.json.serializeToJsonString`
 - Added `vibe.inet.webform.formEncode` for encoding a dictionary/AA as a web form (by Etienne Cimon) - [pull #748][issue748]
 - `BsonObjectID.fromString` now throws an `Exception` instead of an `AssertError` for invalid inputs
 - Avoid using initialized static array for storing task parameters (by Михаил Страшун aka Dicebot) - [pull #778][issue778]
 - Deprecated the simple password hash functions due to their weak security - [issue #794][issue794]
 - Added support for serializing tuple fields
 - Added `convertJsonToASCII` to force escaping of all Unicode characters - see [issue #809][issue809]
 - Added a parameter to set the information log format for `setLogFormat` (by Márcio Martins) - [pull #808][issue808]
 - Serializer implementations now get the number of dictionary elements passed up front (by Johannes Pfau) - [pull #823][issue823]
 - Changed `readRequiredOption` to not throw when the `--help` switch was passed (by Jack Applegame) - [pull #803][issue803]
 - Added `RestInterfaceSettings` as the new way to configure REST interfaces
 - Implemented optional stripping of trailing underscores for REST parameters (allows the use of keywords as parameter names)
 - Made the `message` parameter of `enforceHTTP` `lazy` (by Mathias Lang aka Geod24) - [pull #839][issue839]
 - Improve the format of JSON parse errors to enable IDE go-to-line support
 - Removed all console and file system output from unit tests (partially by Etienne Cimon, [pull #852][issue852])
 - Improved performance of libevent timers by avoiding redundant rescheduling of the master timer

### Bug fixes ###

 - Fixed BSON custom serialization of `const` classes
 - Fixed serialization of `DictionaryList` - [issue #621][issue621]
 - Fixed a bogus deprecation message for Diet script/style blocks without child nodes
 - Fixed an infinite loop in `HTTPRouter` when no routes were registered - [issue #691][issue691]
 - Fixed iterating over `const(DictionaryList)` (by Mathias Lang aka Geod24) - [pull #693][issue693]
 - Fixed an assertion in the HTTP file server that was triggered when drive letters were contained in the request path - [pull #694][issue694]
 - Fixed recognizing `application/javascript` in script tags to trigger the block syntax deprecation message
 - Fixed support for boolean parameters in web interfaces
 - Fixed falling back to languages without country suffix in the web interface generator
 - Fixed alignment of the backing memory for a `TaskLocal!T`
 - Fixed the port reported by `UDPConnection.bindAddress` when 0 was specified as the bind port (libevent)
 - Fixed busy looping the event loop when there is unprocessed UDP data - [issue #715][issue715]
 - Fixed `exitEventLoop()` to work when there is a busy tasks that calls `yield()` - [issue #720][issue720]
 - Avoid querying the clock when processing timers and no timers are pending (performance bug)
 - Fixed `ManualEvent.wait()` to work outside of a task (fixes various secondary facilities that use `ManualEvent` implicitly) - [issue #663][issue663]
 - Fixed encoding of `StreamOutputRange.put(dchar)` (by sinkuu) - [pull #733][issue733]
 - Fixed treating `undefined` JSON values as `null` when converting to a string - [issue #735][issue735]
 - Fixed using an `id` parameter together with `@path` in REST interfaces - [issue #738][issue738]
 - Fixed handling of multi-line responses in the SMTP client (by Etienne Cimon) - [pull #746][issue746]
 - Fixed compile error for certain uses of `Nullable!T` in web interfaces
 - Enable use of non-virtual access of the event driver using `VibeUseNativeDriverType`
 - Fixed building the "libev" configuration (by Lionello Lunesu) - [pull #755][issue755]
 - Fixed `TaskLocal!T` top properly call destructors after a task has ended (by Etienne Cimon) - [issue #753][issue753], [pull #754][issue754]
 - Fixed the name of `RedisDatabase.zcard` (was `Zcard`)
 - Fixed a possible race condition causing a hang in `MessageQueue.receive`/`receiveTimeout`(by Ilya Lyubimov) - [pull #760][issue760]
 - Fixed `RangeCounter` to behave properly when inserting single `char` values
 - Fixed `RedisDatabase.getSet` (by Stephan Dilly) - [pull #769][issue769]
 - Fixed out-of-range array access in the Diet template compiler when the last attribute of a tag is value-less (by Martin Nowak) - [pull #771][issue771]
 - Fixed output of line breaks in the Markdown compiler
 - Fixed handling of the `key` argument of `getRange`, `lrem` and `zincrby` in `RedisDatabase` (by sinkuu) - [pull #772][issue772]
 - Fixed handling of `Nullable!T` and `isISOExtStringSerializable` parameters in REST interfaces
 - Fixed escaping of Diet tag attributes with string interpolations (by sinkuu) - [pull #779][issue779]
 - Fixed handling a timeout smaller or equal to zero (infinity) for `RedisSubscriber.blisten` (by Etienne Cimon aka etcimon) - [issue #776][issue776], [pull #781][issue781]
 - Fixed handling of Unicode escape sequences in the JSON parser (by Etienne Cimon aka etcimon) - [pull #782][issue782]
 - Fixed `HTTPServerRequest.fullURL` for requests without a `Host` header - [issue #786][issue786]
 - Fixed `RedisClient` initialization for servers that require authentication (by Pedro Yamada aka yamadapc) - [pull #785][issue785]
 - Fixed the JSON parser to not accept numbers containing ':'
 - Removed an invalid assertion in `HTTPServerResponse.writeJsonBody` - [issue #788][issue788]
 - Fixed handling of explicit "identity" content encoding in the HTTP client (by sinkuu) - [pull #789][issue789]
 - Fixed `HTTPServerRequest.fullURL` for HTTPS requests with a non-default port (by Arjuna aka arjunadeltoso) - [pull #790][issue790]
 - Fixed detection of string literals in Diet template attributes - [issue #792][issue792]
 - Fixed output of Diet attributes using `'` as the string delimiter
 - Fixed detection of numeric types in `BsonSerializer` (do not treat `Nullable!T` as numeric)
 - Fixed the REST interface client to accept 201 responses (by Yuriy Glukhov) - [pull #806][issue806]
 - Fixed some potential lock related issues in the worker task handler loop
 - Fixed memory corruption when `TCPListenOptions.disableAutoClose` is used and the `TCPConnection` outlives the accepting task - [issue #807][issue807]
 - Fixed a range violation when parsing JSON strings that end with `[` or `{` - [issue #805][issue805]
 - Fixed compilation of `MongoCollection.aggregate` and support passing an array instead of multiple parameters - [issue #783][issue783]
 - Fixed compilation and formatting issues in the HTTP logger (by Márcio Martins) - [pull #808][issue808]
 - Fixed assertion condition in `DebugAllocator.realloc`
 - Fixed shutdown when daemon threads are involved - [issue #758][issue758]
 - Fixed some serialization errors for structs with variadic constructors or properties or with nested type declarations/aliases (by Rene Zwanenburg) - [pull #817][issue817], [issue #818][issue818], [pull #819][issue819]
 - The HTTP server now terminates a connection if the response was not completely written to avoid protocol errors
 - Fixed an assertion triggered by a `vibe.web.rest` server trying to write an error message when a response had already been made - [issue #821][issue821]
 - Fixed using `TaskLocal!T` with types that have certain kinds of "copy constructors" - [issue #825][issue825]
 - Fixed `-version=VibeNoSSL` (by Dragos Carp) - [pull #834][issue834]
 - Use "bad request" replies instead of "internal server error" for various cases where a HTTP request is invalid (by Marc Schütz) - [pull #827][issue827]
 - Removed a leading newline in compiled Diet templates
 - Fixed serialization of nested arrays as JSON (by Rene Zwanenburg) - [issue #840][issue840], [pull #841][issue841]
 - Fixed OpenSSL error messages in certain cases (by Andrea Agosti) - [pull #796][issue796]
 - Fixed parsing of MongoDB URLs containing `/` in the password field (by Martin Nowak) - [pull #843][issue843]
 - Fixed an assertion in `TCPConnection.waitForData` when called outside of a task (libevent) - [issue #829][issue829]
 - Fixed an `InvalidMemoryOperationError` in `HTTPClientResponse.~this()`
 - Fixed a memory corruption issue for HTTPS servers (by Etienne Cimon) - [issue #846][issue846], [pull #849][issue849]
 - Fixed low-precision floating point number output in `JsonStringSerializer`
 - Fixed compilation in release mode (not recommended for safety reasons!) - [issue #847][issue847]
 - Fixed low-precision floating point number output in the Redis client - [issue #857][issue857]
 - Fixed handling of NaN in the JSON module (output as `undefined`) (by David Monagle)- [pull #860][issue860]
 - Fixed the Redis subscriber implementation (by Etienne Cimon) - [issue #855][issue855], [pull #815][issue815]
 - Fixed compilation of the `Isolated!T` framework - [issue #801][issue801]
 - Fixed an `InvalidMemoryOperationError` in `DebugAllocator` (by Etienne Cimon) - [pull #848][issue848]
 - Fixed detection of numeric types in `JsonSerializer` (do not treat `Nullable!T` as numeric) (by Jack Applegame) - [issue #686][issue868], [pull #869][issue869]
 - Fixed error handling in `Win32TCPConnection.connect` and improved error messages
 - Fixed ping handling of WebSocket ping messages (by Vytautas Mickus aka Eximius) - [pull #883][issue883]
 - Fixed always wrapping the e-mail address in angular brackets in the SMTP client (by ohenley) - [pull #887][issue887]
 - Fixed custom serialization of `const` instances (by Jack Applegame) - [pull #879][issue879]
 - Fixed the `RedisDatabase.set*X` to properly test the success condition (by Stephan Dilly aka Extrawurst) - [pull #890][issue890]
 - Fixed `sleep(0.seconds)` to be a no-op instead of throwing an assertion error
 - Fixed a potential resource leak in `HashMap` by using `freeArray` instead of directly deallocating the block of memory (by Etienne Cimon) - [pull #893][issue893]

[issue619]: https://github.com/vibe-d/vibe.d/issues/619
[issue621]: https://github.com/vibe-d/vibe.d/issues/621
[issue663]: https://github.com/vibe-d/vibe.d/issues/663
[issue684]: https://github.com/vibe-d/vibe.d/issues/684
[issue684]: https://github.com/vibe-d/vibe.d/issues/684
[issue691]: https://github.com/vibe-d/vibe.d/issues/691
[issue693]: https://github.com/vibe-d/vibe.d/issues/693
[issue694]: https://github.com/vibe-d/vibe.d/issues/694
[issue714]: https://github.com/vibe-d/vibe.d/issues/714
[issue715]: https://github.com/vibe-d/vibe.d/issues/715
[issue719]: https://github.com/vibe-d/vibe.d/issues/719
[issue720]: https://github.com/vibe-d/vibe.d/issues/720
[issue723]: https://github.com/vibe-d/vibe.d/issues/723
[issue725]: https://github.com/vibe-d/vibe.d/issues/725
[issue729]: https://github.com/vibe-d/vibe.d/issues/729
[issue731]: https://github.com/vibe-d/vibe.d/issues/731
[issue732]: https://github.com/vibe-d/vibe.d/issues/732
[issue733]: https://github.com/vibe-d/vibe.d/issues/733
[issue735]: https://github.com/vibe-d/vibe.d/issues/735
[issue738]: https://github.com/vibe-d/vibe.d/issues/738
[issue743]: https://github.com/vibe-d/vibe.d/issues/743
[issue744]: https://github.com/vibe-d/vibe.d/issues/744
[issue746]: https://github.com/vibe-d/vibe.d/issues/746
[issue748]: https://github.com/vibe-d/vibe.d/issues/748
[issue752]: https://github.com/vibe-d/vibe.d/issues/752
[issue753]: https://github.com/vibe-d/vibe.d/issues/753
[issue754]: https://github.com/vibe-d/vibe.d/issues/754
[issue755]: https://github.com/vibe-d/vibe.d/issues/755
[issue756]: https://github.com/vibe-d/vibe.d/issues/756
[issue757]: https://github.com/vibe-d/vibe.d/issues/757
[issue758]: https://github.com/vibe-d/vibe.d/issues/758
[issue759]: https://github.com/vibe-d/vibe.d/issues/759
[issue760]: https://github.com/vibe-d/vibe.d/issues/760
[issue761]: https://github.com/vibe-d/vibe.d/issues/761
[issue769]: https://github.com/vibe-d/vibe.d/issues/769
[issue771]: https://github.com/vibe-d/vibe.d/issues/771
[issue772]: https://github.com/vibe-d/vibe.d/issues/772
[issue776]: https://github.com/vibe-d/vibe.d/issues/776
[issue778]: https://github.com/vibe-d/vibe.d/issues/778
[issue779]: https://github.com/vibe-d/vibe.d/issues/779
[issue781]: https://github.com/vibe-d/vibe.d/issues/781
[issue782]: https://github.com/vibe-d/vibe.d/issues/782
[issue783]: https://github.com/vibe-d/vibe.d/issues/783
[issue785]: https://github.com/vibe-d/vibe.d/issues/785
[issue786]: https://github.com/vibe-d/vibe.d/issues/786
[issue788]: https://github.com/vibe-d/vibe.d/issues/788
[issue789]: https://github.com/vibe-d/vibe.d/issues/789
[issue790]: https://github.com/vibe-d/vibe.d/issues/790
[issue792]: https://github.com/vibe-d/vibe.d/issues/792
[issue794]: https://github.com/vibe-d/vibe.d/issues/794
[issue796]: https://github.com/vibe-d/vibe.d/issues/796
[issue799]: https://github.com/vibe-d/vibe.d/issues/799
[issue801]: https://github.com/vibe-d/vibe.d/issues/801
[issue803]: https://github.com/vibe-d/vibe.d/issues/803
[issue805]: https://github.com/vibe-d/vibe.d/issues/805
[issue806]: https://github.com/vibe-d/vibe.d/issues/806
[issue807]: https://github.com/vibe-d/vibe.d/issues/807
[issue808]: https://github.com/vibe-d/vibe.d/issues/808
[issue808]: https://github.com/vibe-d/vibe.d/issues/808
[issue809]: https://github.com/vibe-d/vibe.d/issues/809
[issue811]: https://github.com/vibe-d/vibe.d/issues/811
[issue815]: https://github.com/vibe-d/vibe.d/issues/815
[issue817]: https://github.com/vibe-d/vibe.d/issues/817
[issue818]: https://github.com/vibe-d/vibe.d/issues/818
[issue819]: https://github.com/vibe-d/vibe.d/issues/819
[issue821]: https://github.com/vibe-d/vibe.d/issues/821
[issue822]: https://github.com/vibe-d/vibe.d/issues/822
[issue823]: https://github.com/vibe-d/vibe.d/issues/823
[issue824]: https://github.com/vibe-d/vibe.d/issues/824
[issue825]: https://github.com/vibe-d/vibe.d/issues/825
[issue827]: https://github.com/vibe-d/vibe.d/issues/827
[issue829]: https://github.com/vibe-d/vibe.d/issues/829
[issue834]: https://github.com/vibe-d/vibe.d/issues/834
[issue839]: https://github.com/vibe-d/vibe.d/issues/839
[issue840]: https://github.com/vibe-d/vibe.d/issues/840
[issue841]: https://github.com/vibe-d/vibe.d/issues/841
[issue843]: https://github.com/vibe-d/vibe.d/issues/843
[issue845]: https://github.com/vibe-d/vibe.d/issues/845
[issue846]: https://github.com/vibe-d/vibe.d/issues/846
[issue847]: https://github.com/vibe-d/vibe.d/issues/847
[issue848]: https://github.com/vibe-d/vibe.d/issues/848
[issue849]: https://github.com/vibe-d/vibe.d/issues/849
[issue855]: https://github.com/vibe-d/vibe.d/issues/855
[issue860]: https://github.com/vibe-d/vibe.d/issues/860
[issue861]: https://github.com/vibe-d/vibe.d/issues/861
[issue868]: https://github.com/vibe-d/vibe.d/issues/868
[issue869]: https://github.com/vibe-d/vibe.d/issues/869
[issue879]: https://github.com/vibe-d/vibe.d/issues/879
[issue883]: https://github.com/vibe-d/vibe.d/issues/883
[issue887]: https://github.com/vibe-d/vibe.d/issues/887
[issue888]: https://github.com/vibe-d/vibe.d/issues/888
[issue890]: https://github.com/vibe-d/vibe.d/issues/890
[issue893]: https://github.com/vibe-d/vibe.d/issues/893


v0.7.20 - 2014-06-03
--------------------

The `vibe.web.web` web interface generator module has been extended with some important features, making it a full replacement (and more) of the old `registerFormInterface` functionality. Other important changes include the use of strong TLS ciphers out of the box, as well as a heavily optimized `URLRouter` implementation and support for compile-time localization of Diet templates.

### Features and improvements ###

 - Web interface generator and Diet template system
	- Added `vibe.web.web.terminateSession()` and `redirect()`
	- Added support for `struct` and array parameters, as well as `Nullable!T` in `vibe.web.web`
	- Added the `@errorDisplay` annotation to `vibe.web.web` to enable automatic exception display using an existing request handler
	- Added built-in, compile-time, gettext compatible localization support for Diet templates using the `tag& text` syntax
 - HTTP router
	- Implemented a new match tree based routing algorithm for `URLRouter`, resulting in great speedups for complex routing setups
	- Added `URLRouter.prefix` to configure a prefix to append to every route
	- The `HTTPRouter` router interface is scheduled for removal
 - Serialization system
	- Added `@asArray` to force serialization of composite types as arrays instead of dictionaries
	- Added support for using a pre-allocated buffer for `serializeToBson`
	- Added support for custom serialization representations of user defined types using `toRepresentation`/`fromRepresentation` methods - [issue #618][issue618]
	- Made `DictionaryList` serializable as an array by adding `toRepresentation`/`fromRepresentation` - [issue #621][issue621]
 - SSL/TLS
	- Using only strong ciphers by default for SSL server contexts
	- Added out-of-the box support for perfect forward secrecy (PFS) (by Martin Nowak) - [pull #630][issue630]
	- Changed the default from `SSLVersion.tls1` (fixed TLS 1.0) to `SSLVersion.any` (SSL 3 and up, including TLS 1.1 and TLS 1.2)
	- Added `SMTPClientSettings.sslContextSetup` to enable customization of the SSL context (e.g. adding trusted certificates)
	- Upgraded the Windows OpenSSL binaries to 1.0.1g
 - Performance tuning
	- Added `HTTPServerOption.errorStackTraces` to make costly stack trace generation optional
	- Arguments to the logging functions are now evaluated lazily to avoid computations when messages are not actually logged
	- Added support for direct de-serialization of MongoDB query results
	- Reduced memory allocations in the HTTP logger module
	- Heavily reduced the number of memory allocations happening in the MongoDB driver - see [issue #633][issue633]
 - General
	- Removed deprecated symbols and deprecated symbols that were scheduled for deprecation
	- Added `runWorkerTaskH` to run a worker task and return its handle in one step (by Luca Niccoli aka lultimouomo) - [pull #601][issue601]
	- Added `createTestHTTPServerRequest` and `createTestHTTPServerResponse` to support writing unit tests
	- Added `vibe.core.file.readFile`, `readFileUTF8`, `writeFile` and `writeFileUTF8`
	- Added a limited overload of `RedisDatabase.zrevRangeByScore` and fix the type of the `start`/`end` parameters (by Jens K. Mueller) - [pull #637][issue637]
	- Added `TCPListenOptions.disableAutoClose` to make incoming TCP connections independent of the initial handler task
	- Added `vibe.core.concurrency.thisTid` as an alias to `Task.getThis()` for improved API compatibility to `std.concurrency`
	- Added an overload of `UDPConnection.recv` taking a timeout parameter - [issue #540][issue540]
	- Added `toString` to `HTTPRequest` and `HTTPResponse` for convenient logging
	- Added `MarkdownSettings` with additional support of setting the base heading level of the generated HTML
	- Added `TCPConnection.keepAlive` to set the `SO_KEEPALIVE` option - [issue #622][issue622]
	- `Error` derived exceptions are not caught anymore (use `-version=VibeDebugCatchAll` to get the old unsafe behavior)
	- Annotated some basic modules with `@safe`/`@trusted`/`pure`
	- Extended `ProxyStream` to optionally take distinct streams for input and output
	- Replaced all remaining uses of `renderCompat` with `render`
	- Removed unused variables and made `Bson.toString` `const` (thanks to Brian Schott aka Hackerpilot) - [issue #659][issue659]

### Bug fixes ###

 - Fixed the order of events reported by `setTaskEventCallback` when new tasks are started within an existing task
 - Fixed HTTP multi-file uploads by changing `HTTPServerRequest.files` to a `DictionaryList`
 - Fixed `@byName` to work for serializing (associative) arrays of enums
 - Fixed SSL based SMTP connections (by Martin Nowak) - [pull #609][issue609]
 - Fixed Diet text blocks (`tag.` style) to properly remove the input file indentation - [issue #614][issue614]
 - Fixed `isStronglyIsolated!T` to work for interface types
 - Fixed `filterURLEncode` to encode certain special characters (such as "{") - [issue #632][issue632]
 - Fixed a crash when accessing vibe.d event functionality from within `shared static ~this`
 - Fixed `Task.join` and `Task.interrupt` to work when called from outside of the event loop (e.g. when `processEvents` is used instead of `runEventLoop`) - [issue #443][issue443]
 - Fixed serialization of `const` class instances (by Jack Applegame) - [issue #653][issue653]
 - Fixed compilation of `renderCompat!()` on GDC (invalid use of `va_list`/`void*`)
 - Fixed handling of paths with empty path entries (e.g. "/some///path") - [issue #410][issue410]
 - Fixed a crash caused by `GCAllocator` - `GC.extend` is now used instead of `GC.realloc` to sidestep the issue - [issue #470][issue470]
 - Fixed rendering of Markdown links with styled captions
 - Fixed `Path.relativeTo` step over devices for UNC paths on Windows
 - Fixed compilation on 2.064 frontend based GDC - [issue #647][issue647]
 - Fixed output of empty lines in "tag." style Diet template text blocks

[issue410]: https://github.com/vibe-d/vibe.d/issues/410
[issue443]: https://github.com/vibe-d/vibe.d/issues/443
[issue470]: https://github.com/vibe-d/vibe.d/issues/470
[issue540]: https://github.com/vibe-d/vibe.d/issues/540
[issue601]: https://github.com/vibe-d/vibe.d/issues/601
[issue609]: https://github.com/vibe-d/vibe.d/issues/609
[issue614]: https://github.com/vibe-d/vibe.d/issues/614
[issue618]: https://github.com/vibe-d/vibe.d/issues/618
[issue621]: https://github.com/vibe-d/vibe.d/issues/621
[issue622]: https://github.com/vibe-d/vibe.d/issues/622
[issue630]: https://github.com/vibe-d/vibe.d/issues/630
[issue632]: https://github.com/vibe-d/vibe.d/issues/632
[issue633]: https://github.com/vibe-d/vibe.d/issues/633
[issue637]: https://github.com/vibe-d/vibe.d/issues/637
[issue647]: https://github.com/vibe-d/vibe.d/issues/647
[issue653]: https://github.com/vibe-d/vibe.d/issues/653
[issue659]: https://github.com/vibe-d/vibe.d/issues/659


v0.7.19 - 2014-04-09
--------------------

Apart from working on the latest DMD versions, this release includes an important security enhancement in the form of new experimental code for SSL certificate validation. Other major changes include many improvements to the Diet template compiler, various performance improvements, a new `FileDescriptorEvent` to interface with other I/O libraries, a new web interface generator similar to the REST interface generator, many improvements to the Redis client, and a bunch of other fixes and additions.

### Features and improvements ###

 - Compiles with DMD 2.065 (and the current DMD HEAD)
 - API improvements for the SSL support code
 - Implemented SSL certificate validation (partially by David Nadlinger aka klickverbot, [pull #474][issue474])
 - Removed the old `EventedObject` interface
 - Implemented support for string includes in Diet templates (idea by Stefan Koch aka Uplink_Coder) - [issue #482][issue482]
 - JSON answers in the REST interface generator are now directly serialized, improving performance and memory requirements
 - Reimplemented the timer code to guarantee light weight timers on all event drivers
 - `Libevent2TCPConnection` now has a limited read buffer size to avoid unbounded memory consumption
 - Fixed the semantics of `ConnectionStream.empty` and `connected` - `empty` is generally useful for read loops and `connected` for write loops
 - Added an overload of `runTask` that takes a delegate with additional parameters to bind to avoid memory allocations in certain situations
 - Added `vibe.core.core.createFileDescriptorEvent` to enable existing file descriptors to be integrated into vibe.d's event loop
 - HTTP response compression is now disabled by default (controllable by the new `HTTPServerSettings.useCompressionIfPossible)
 - Removed the deprecated `sslKeyFile` and `sslCertFile` fields from `HTTPServerSettings`
 - Removed the compatibility alias `Signal` (alias for `ManualEvent`)
 - `:htmlescape` in Diet templates is now processed at compile time if possible
 - Added support for `Rebindable!T` in `isStronglyIsolated` and `isWeaklyIsolated` - [issue #421][issue421]
 - Added `RecursiveTaskMutex`
 - `Throwable` is now treated as weakly isolated to allow passing exceptions using `vibe.core.concurrency.send`
 - `exitEventLoop` by default now only terminates the current thread's event loop and always works asynchronously
 - `Session` is now a `struct` instead of a `class`
 - Added support for storing arbitrary types in `Session`
 - Moved the REST interface generator from `vibe.http.rest` to `vibe.web.rest`
 - Added a new web interface generator (`vibe.web.web`), similar to `vibe.http.form`, but with full support for attribute based customization
 - Added a compile time warning when neither `VibeCustomMain`, nor `VibeDefaultMain` versions are specified - starts the transition from `VibeCustomMain` to `VibeDefaultMain`
 - Added `requireBoundsCheck` to the build description
 - Added assertions to help debug accessing uninitialized `MongoConnection` values
 - Added `logFatal` as a shortcut to `log` called with `LogLevel.fatal` (by Daniel Killebrew aka gittywithexcitement) - [pull #441][issue441]
 - Empty JSON request bodies are now handled gracefully in the HTTP server (by Ryan Scott aka Archytaus) - [pull #440][issue440]
 - Improved documentation of `sleep()` - [issue #434][issue434]
 - The libevent2 and Win32 event drivers now outputs proper error messages for socket errors
 - Changed `setTaskEventCallback` to take a delegate with a `Task` parameter instead of `Fiber`
 - Added a `Task.taskCounter` property
 - `AutoFreeListAllocator.realloc` can now reuse blocks of memory and uses `realloc` on the base allocator if possible
 - HTML forms now support multiple values per key
 - Inverted the `no_dns` parameter of `EventDriver.resolveHost` to `use_dns` to be consistent with `vibe.core.net.resolveHost` - [issue #430][issue430]
 - `Task` doesn't `alias this` to `TaskFiber` anymore, but forwards just a selected set of methods
 - Added `vibe.core.args.readRequiredOption - [issue #442][issue442]
 - `NetworkAddress` is now fully `pure nothrow`
 - Refactored the Redis client to use much less allocations and a much shorter source code
 - Added `Bson.toString()` (by David Nadlinger aka klickverbot) - [pull #468][issue468]
 - Added `connectTCP(NetworkAddress)` and `NetworkAddress.toString()` (by Stefan Koch aka Uplink_Coder) - [pull #485][issue485]
 - Added `NetworkAddress.toAddressString` to output only the address portion (without the port number)
 - Added `compileDietFileIndent` to generate indented HTML output
 - Added Travis CI integration (by Martin Nowak) - [pull #486][issue486]
 - Added `appendToFile` to conveniently append to a file without explicitly opening it (by Stephan Dilly aka extrawurst) - [pull #489][issue489]
 - Tasks started before starting the event loop are now deferred until after the loop has been started
 - Worker threads are started lazily instead of directly on startup
 - Added `MongoCursor.limit()` to limit the amount of documents returned (by Damian Ziemba aka nazriel) - [pull #499][issue499]
 - The HTTP client now sets a basic-auth header when the request URL contains a username/password (by Damian Ziemba aka nazriel) - [issue #481][issue481], [pull #501][issue501]
 - Added `RedisClient.redisVersion` (by Fabian Wallentowitz aka fabsi88) - [pull #502][issue502]
 - Implemented handling of doctypes other than HTML 5 in the Diet compiler (by Damian Ziemba aka nazriel) - [issue #505][issue505], [pull #509][issue509]
 - Boolean attributes in Diet templates are now written without value for HTML 5 documents (by Damian Ziemba aka nazriel) - [issue #475][issue475], [pull #512][issue512]
 - Empty "class" attributes in Diet templates are not written to the final HTML output (by Damian Ziemba aka nazriel) - [issue #372][issue372], [pull #519][issue519]
 - Implemented PUB/SUB support for the Redis client (by Michael Eisendle with additional fixes by Etienne Cimon aka etcimon)
 - The logging functions take now any kind of string instead of only `string` (by Mathias Lang aka Geod24) - [pull #532][issue532]
 - Added `SMTPClientSettings.peerValidationMode` (by Stephan Dilly aka Extrawurst) - [pull #528][issue528]
 - Diet templates that are set to `null` are now omitted in the HTML output (by Damian Ziemba aka nazriel) - [issue #520][issue520], [pull #521][issue521]
 - Extended the REST interface generator to cope with any type of error response and to always throw a `RestException` on error (by Stephan Dilly aka Extrawurst) - [pull #533][issue533]
 - Added support for [text blocks](http://jade-lang.com/reference/#blockinatag) in Diet templates (by Damian Ziemba aka nazriel) - [issue #510][issue510], [pull #518][issue518]
 - Added `RedisClient.blpop` and changed all numbers to `long` to be in line with Redis (by Etienne Cimon aka etcimon) - [pull #527][issue527]
 - Changed `WebSocket.receiveBinary` and `WebSocket.receiveText` to strictly expect the right type by default (by Martin Nowak) - [pull #543][issue543]
 - Avoid using an exception to signal HTTP 404 errors for unprocessed requests, resulting in a large performance increas for that case
 - Modernized the Diet templates used for the example projects (by Damian Ziemba aka nazriel) - [pull #551][issue551]
 - Added WebDAV HTTP status codes to the `HTTPStatusCode` enum (by Dmitry Mostovenko aka TrueBers) - [pull #574][issue574]
 - Added support for multiple recipient headers (including "CC" and "BCC") in `sendMail` (by Stephan Dilly aka Extrawurst) - [pull #582][issue582]
 - Added support for comma separated recipients in `sendMail`
 - Added SSL support for the MongoDB client (by Daniel Killebrew aka gittywithexcitement) - [issue #575][issue575], [pull #587][issue587]
 - Made all overloads of `listenHTTPPlain` private (as they were supposed to be since a year)
 - Added using `-version=VibeDisableCommandLineParsing` to disable default command line argument interpretation
 - Added using `-version=VibeNoSSL` to disable using OpenSSL and added free functions to create SSL contexts/streams
 - Functions in `vibe.data.json` now throw a `JSONException` instead of a bare `Exception` (by Luca Niccoli aka lultimouomo) - [pull #590][issue590]
 - Functions in `vibe.http.websocket` now throw a `WebSocketException` instead of a bare `Exception` (by Luca Niccoli aka lultimouomo) - [pull #590][issue590]

### Bug fixes ###

 - Fixed a condition under which a `WebSocket` could still be used after its handler function has thrown an exception - [issue #407][issue407]
 - Fixed a `null` pointer dereference in `Libevent2TCPConnection` when trying to read from a closed connection
 - Fixed the HTTP client to still properly shutdown the connection when an exception occurs during the shutdown
 - Fixed `SSLStream` to perform proper locking for multi-threaded servers
 - Fixed the signature of `TaskLocal.opAssign` - [issue #432][issue432]
 - Fixed thread shutdown in cases where multiple threads are used - [issue #419][issue419]
 - Fixed SIGINT/SIGTERM application shutdown - [issue #419][issue419]
 - Fixed `HashMap` to properly handle `null` keys
 - Fixed processing WebSocket requests sent from IE 10 and IE 11
 - Fixed the HTTP client to assume keep-alive for HTTP/1.1 connections that do not explicitly specify something else (by Daniel Killebrew aka gittywithexcitement) - [issue #448][issue448], [pull #450][issue450]
 - Fixed `Win32FileStream` to report itself as readable for `FileMode.createTrunc`
 - Fixed a possible memory corruption bug for an assertion in `AllocAppender`
 - Fixed clearing of cookies on old browsers - [issue #453][issue453]
 - Fixed handling of `yield()`ed tasks so that events are guaranteed to be processed
 - Fixed `Libevent2EventDriver.resolveHost` to take the local hosts file into account (by Daniel Killebrew aka gittywithexcitement) - [issue #289][issue289], [pull #460][issue460]
 - Fixed `RedisClient.zcount` to issue the right command (by David Nadlinger aka klickverbot) - [pull #467][issue467]
 - Fixed output of leading white space in the `HTMLLogger` - now replaced by `&nbsp;`
 - Fixed serialization of AAs with `const(string)` or `immutable(string)` keys (by David Nadlinger aka klickverbot) - [pull #473][issue473]
 - Fixed double-URL-decoding of path parameters in `URLRouter`
 - Fixed `URL.toString()` to output username/password, if set
 - Fixed a crash caused by a double-free when an SSL handshake had failed
 - Fixed `Libevent2UDPConnection.recv` to work inside of a `Task`
 - Fixed handling of "+" in the path part of URLs (is *not* replaced by a space) - [issue #498][issue498]
 - Fixed handling of `<style>` tags with inline content in the Diet compiler - [issue #507][issue507]
 - Fixed some possible sources for stale TCP sockets when an error occurred in the close sequence
 - Fixed the Win64 build (using the "win32" driver) that failed due to user32.dll not being linked
 - Fixed `URLRouter` to expose all overloads of `match()` - see also [pull #535][issue535]
 - Fixed deserialization of unsigned integers in the BSON serializer (by Anton Gushcha aka NCrashed) - [issue #538][issue538], [pull #539][issue539]
 - Fixed deserialization of unsigned integers in the JSON serializer
 - Fixed serialization of nested composite types in the JSON serializer
 - Fixed two bogus assertions in the win32 event driver (one in the timer code and one for socket events after a socket has been closed)
 - Fixed `WebSocket.waitForData` to always obey the given timeout value (by Martin Nowak) - [issue #544][issue544], [pull #545][issue545]
 - Fixed the high level tests in the "tests/" directory (by Mathias Lang aka Geod24) - [pull #541][issue541]
 - Fixed `HashMap` to always use the supplied `Traits.equals` for comparison
 - Fixed the example projects and switched from "package.json" to "dub.json" (by Mathias Lang aka Geod24) - [pull #552][issue552]
 - Fixed emitting an idle event when using `processEvents` to run the event loop
 - Fixed `Path.relativeTo` to retain a possible trailing slash
 - Fixed image links with titles in the Markdown compiler (by Mike Wey) - [pull #563][issue563]
 - Fixed a possible stale TCP connection after finalizing a HTTP client request had failed
 - Fixed `makeIsolated` to work for structs
 - Fixed `listenHTTP` to throw an exception if listening on all supplied bind addresses has failed
 - Fixed a possible crash or false pointers in `HashMap` due to a missing call to `GC.removeRange` - [issue #591][issue591]
 - Fixed non-working disconnect of keep-alive connections in the HTTP server (by Stephan Dilly aka Extrawurst) - [pull #597][issue597]
 - Fixed a possible source for orphaned TCP connections in the libevent driver
 - Fixed `exitEventLoop` to work when called in a task that has been started just before `runEventLoop` was called
 - Fixed `isWeaklyIsolated` to work properly for interface types (by Luca Niccoli aka lultimouomo) - [pull #602](issue602)
 - Fixed the `BsonSerializer` to correctly serialize `SysTime` as a `BsonDate` instead of as a `string`

Note that some fixes have been left out because they are related to changes within the development cycle of this release.

[issue289]: https://github.com/vibe-d/vibe.d/issues/289
[issue289]: https://github.com/vibe-d/vibe.d/issues/289
[issue372]: https://github.com/vibe-d/vibe.d/issues/372
[issue407]: https://github.com/vibe-d/vibe.d/issues/407
[issue407]: https://github.com/vibe-d/vibe.d/issues/407
[issue419]: https://github.com/vibe-d/vibe.d/issues/419
[issue419]: https://github.com/vibe-d/vibe.d/issues/419
[issue421]: https://github.com/vibe-d/vibe.d/issues/421
[issue430]: https://github.com/vibe-d/vibe.d/issues/430
[issue432]: https://github.com/vibe-d/vibe.d/issues/432
[issue434]: https://github.com/vibe-d/vibe.d/issues/434
[issue440]: https://github.com/vibe-d/vibe.d/issues/440
[issue441]: https://github.com/vibe-d/vibe.d/issues/441
[issue442]: https://github.com/vibe-d/vibe.d/issues/442
[issue448]: https://github.com/vibe-d/vibe.d/issues/448
[issue450]: https://github.com/vibe-d/vibe.d/issues/450
[issue453]: https://github.com/vibe-d/vibe.d/issues/453
[issue460]: https://github.com/vibe-d/vibe.d/issues/460
[issue467]: https://github.com/vibe-d/vibe.d/issues/467
[issue468]: https://github.com/vibe-d/vibe.d/issues/468
[issue473]: https://github.com/vibe-d/vibe.d/issues/473
[issue474]: https://github.com/vibe-d/vibe.d/issues/474
[issue475]: https://github.com/vibe-d/vibe.d/issues/475
[issue481]: https://github.com/vibe-d/vibe.d/issues/481
[issue482]: https://github.com/vibe-d/vibe.d/issues/482
[issue485]: https://github.com/vibe-d/vibe.d/issues/485
[issue486]: https://github.com/vibe-d/vibe.d/issues/486
[issue489]: https://github.com/vibe-d/vibe.d/issues/489
[issue498]: https://github.com/vibe-d/vibe.d/issues/498
[issue499]: https://github.com/vibe-d/vibe.d/issues/499
[issue501]: https://github.com/vibe-d/vibe.d/issues/501
[issue502]: https://github.com/vibe-d/vibe.d/issues/502
[issue505]: https://github.com/vibe-d/vibe.d/issues/505
[issue507]: https://github.com/vibe-d/vibe.d/issues/507
[issue509]: https://github.com/vibe-d/vibe.d/issues/509
[issue510]: https://github.com/vibe-d/vibe.d/issues/510
[issue512]: https://github.com/vibe-d/vibe.d/issues/512
[issue518]: https://github.com/vibe-d/vibe.d/issues/518
[issue519]: https://github.com/vibe-d/vibe.d/issues/519
[issue520]: https://github.com/vibe-d/vibe.d/issues/520
[issue521]: https://github.com/vibe-d/vibe.d/issues/521
[issue527]: https://github.com/vibe-d/vibe.d/issues/527
[issue528]: https://github.com/vibe-d/vibe.d/issues/528
[issue532]: https://github.com/vibe-d/vibe.d/issues/532
[issue533]: https://github.com/vibe-d/vibe.d/issues/533
[issue535]: https://github.com/vibe-d/vibe.d/issues/535
[issue538]: https://github.com/vibe-d/vibe.d/issues/538
[issue539]: https://github.com/vibe-d/vibe.d/issues/539
[issue541]: https://github.com/vibe-d/vibe.d/issues/541
[issue543]: https://github.com/vibe-d/vibe.d/issues/543
[issue544]: https://github.com/vibe-d/vibe.d/issues/544
[issue545]: https://github.com/vibe-d/vibe.d/issues/545
[issue551]: https://github.com/vibe-d/vibe.d/issues/551
[issue552]: https://github.com/vibe-d/vibe.d/issues/552
[issue563]: https://github.com/vibe-d/vibe.d/issues/563
[issue574]: https://github.com/vibe-d/vibe.d/issues/574
[issue575]: https://github.com/vibe-d/vibe.d/issues/575
[issue582]: https://github.com/vibe-d/vibe.d/issues/582
[issue587]: https://github.com/vibe-d/vibe.d/issues/587
[issue590]: https://github.com/vibe-d/vibe.d/issues/590
[issue591]: https://github.com/vibe-d/vibe.d/issues/591
[issue597]: https://github.com/vibe-d/vibe.d/issues/597
[issue602]: https://github.com/vibe-d/vibe.d/issues/602


v0.7.18 - 2013-11-26
--------------------

The new release adds support for DMD 2.064 and contains an impressive number of almost 90 additions and bug fixes. Some notable improvements are a better serialization system, reworked WebSocket support, native MongoDB query sorting support and vastly improved stability of the HTTP client and other parts of the system.

### Features and improvements ###

 - Compiles using DMD 2.064 (and DMD 2.063.2)
 - Added `vibe.data.serialization` with support for annotations to control serialization (replaces/extends the serialization code in `vibe.data.json` and `vibe.data.bson`)
 - Added range based allocation free (de-)serialization for JSON strings and more efficient BSON serialization
 - Added `File.isOpen`
 - Added a `ConnectionStream` interface from which `TCPConnection` and `TaskPipe` now derive
 - Added `BsonDate.fromStdTime` and improve documentation to avoid time zone related bugs
 - Added a `TaskMutex.this(Object)` constructor to be able to use them as object monitors
 - Added a non-blocking (infinitely buffering) mode for `TaskPipe`
 - Added (de)serialization support for AAs with string serializable key types (with `toString`/`fromString` methods) (by Daniel Davidson) - [pull #333][issue333]
 - Added (de)serialization support for scalar types as associative array keys
 - Added `setLogFormat` as a more flexible replacement for `setPlainLogging`
 - Added `MongoCollection.aggregate()` (by Jack Applegame) - [pull #348][issue348]
 - Added `WebSocket.request` to enable access to the original HTTP request and add scoped web socket callbacks for avoiding GC allocations
 - Added `HTTPServerRequest.clientAddress` to get the full remote address including the port - [issue #357][issue357]
 - Added `vibe.stream.wrapper.ProxyStream` to enable dynamically switching the underlying stream
 - Added `vibe.stream.wrapper.StreamInputRange` to provide a buffered input range interface for an `InputStream`
 - Added `vibe.stream.wrapper.ConnectionProxyStream` that allows wrapping a `ConnectionStream` along with a `Stream` to allow forwarding connection specific functionality together with a wrapped stream
 - Added `URL` based overloads for `HTTPServerResponse.redirect` and `staticRedirect`
 - Added `RedisClient.hset` (by Martin Mauchauffée aka moechofe) - [pull #386][issue386]
 - Added a WebSockets example project
 - Added `MongoCursor.sort` to allow sorted queries using the same syntax as other MongoDB drivers (by Jack Applegame) - [pull #353][issue353]
 - Added random number generators suited for cryptographic applications, which is now used for session ID generation (by Ilya Shipunov) - [pull #352][issue352], [pull #364][issue364], [issue #350][issue350]
 - Added parameter and return value modifier user attributes for the REST interface generator and refactor meta programming facilities (by Михаил Страшун aka Dicebot) - [pull #340][issue340], [pull #344][issue344], [pull #349][issue349]
 - Added `vibe.stream.operations.pipeRealtime` for piping stream data with a defined maximum latency
 - `OutgoingWebSocketMessage` is now automatically finalized
 - `HTTPServerResponse.switchProtocol` now returns a `ConnectionStream` to allow controlling the underlying TCP connection
 - `HTTPServerResponse.startSession` now sets the "HttpOnly" attribute by default to better prevent session theft (by Ilya Shipunov) - [issue #368][issue368], [pull #373][issue373]
 - `HTTPServerResponse.startSession` now automatically sets the "Secure" attribute by default when a HTTPS connection was used to initiate the session - [issue #368][issue368]
 - Implemented Scalate whitespace stripping syntax for Diet templates (by Jack Applegame) - [pull #362][issue362]
 - `htmlAttribEscape` and friends now also escape single quotes (') - [issue #377][issue377]
 - `vibe.stream.operations.readAll()` now preallocates if possible
 - Optimized HTML escaping performance (by Martin Nowak) - [pull #327][issue327]
 - Adjusted naming of `Bson.Type` and `Json.Type` members for naming conventions
 - `render!()` for rendering Diet templates is assumed to be safe starting with DMD 2.064
 - Improved `Json` usability by enabling `~=` and some more use cases for `~`
 - Added a workaround for excessive compile times for large static arrays (by Martin Nowak) - [pull #341][issue341]
 - Improved the HTTP reverse proxy by handling HEAD requests correctly, avoiding GC allocations and optionally disabling transfer compression
 - `HashMap` now moves elements when resizing instead of copying
 - Added a new mode for `parseRFC5322Header` that outputs multiple fields with the same value as separate fields instead of concatenating them as per RFC 822 and use the new behavior for the HTTP server - [issue #380][issue380]
 - `ThreadedFileStream` now uses `yield()` to avoid stalling the event loop
 - Improved the performance of `yield()` by using a singly linked list instead of a dynamic array to store yielded tasks (incl. bugfix by Martin Nowak, see [pull #402][issue402] and [issue #401][issue401])

### Bug fixes ###

 - Fixed wrongly triggering assertions on Windows when `INVALID_SOCKET` is returned
 - Fixed issues with `vibe.stream.zlib` by reimplementing everything using zlib directly instead of `std.zlib`
 - Fixed an exception in the HTTP file server when downloading a compressed file with no content transfer encoding requested
 - Fixed compilation in release and unit test modes
 - Fixed a data corruption bug caused by changed alignment in memory returned by `GC.realloc`
 - Fixed the libevent driver to avoid infinite buffering of output data - [issue #191][issue191]
 - Fixed (de)serialization of BSON/JSON with (to/from)(String/Json) methods (by Jack Applegame) - [pull #309][issue309]
 - Fixed possible finalization errors and possible interleaved requests in `HTTPClient.request`
 - Fixed a possible access violation in `Libevent2TCPConnection` when the connection was closed by the remote peer - [issue #321][issue321]
 - Fixed `Win32TCPConnection.connect` to wait for the connection to be established (and throw proper exceptions on failure)
 - Fixed HTTP client requests for URLs with an empty path component (ending directly with the host name)
 - Fixed out-of-range errors when parsing JSON with malformed keywords
 - Fixed an exception when disconnecting HTTP client connections where the remote has already disconnected
 - Fixed `vibe.core.args.getOption` to return true when an option was found (by Martin Nowak) - [pull #331][issue331]
 - Fixed command line options to have precedence over configuration settings for `getOption`
 - Fixed `Cookie.maxAge` having no effect (by Jack Applegame) - [pull #334][issue334], [issue #330][issue330]
 - Fixed request/response delays in `Libevent2TCPConnection` (by Martin Nowak) - [issue #338][issue338]
 - Fixed conditional use of `std.net.isemail` to validate emails
 - Fixed an assertion triggering for very small wait timeouts
 - Fixed markdown `[ref][]` style links (by Martin Nowak) - [pull #343][issue343]
 - Fixed cache headers in the HTTP file server and sending a "Date" header for all HTTP server responses
 - Fixed interleaved HTTP client requests when dropping a previous response has failed for some reason
 - Fixed opening files with `FileMode.readWrite` and `FileMode.createTrunc` to allow both, reading and writing - [issue #337][issue337], [issue #354][issue354]
 - Fixed documentation of some parameters - [issue #322][issue322]
 - Fixed `HTTPServerRequest.fullURL` to properly set the port - [issue #365][issue365]
 - Fixed `vibe.core.concurrency.send`/`receive` in conjunction with `immutable` values
 - Fixed an assertion in `Libevent2ManualEvent` caused by an AA bug
 - Fixed a possible crash in `Libevent2ManualEvent` when using deterministic destruction
 - Fixed a resource/memory leak in the libevent2 driver
 - Fixed the "http-request" example to use the recommended `requestHTTP` function - [issue #374][issue374]
 - Fixed appending of `Path` values to preserve the trailing slash, if any
 - Fixed deserialization of JSON integer values as floating point values as FP values often end up without a decimal point
 - Fixed `yield()` to be a no-op when called outside of a fiber
 - Fixed a crash when WebSockets were used over a HTTPS connection - [issue #385][issue385]
 - Fixed a crash in `SSLStream` that occurred when the server certificate was rejected by the client - [issue #384][issue384]
 - Fixed a number of bogus error messages when a connection was terminated before a HTTP request was fully handled
 - Fixed the console logger to be disabled on Windows application without a console (avoids crashing)
 - Fixed `HTTPLogger` avoid mixing line contents by using a mutex
 - Fixed the semantics of `WebSocket.connected` and added `WebSocket.waitForData` - [issue #370][issue370]
 - Fixed a memory leak and keep-alive connection handling in the HTTP client
 - Fixed settings of path placeholder values when "*" is used in `URLRouter` routes
 - Fixed a memory leak where unused fibers where never recycled
 - Fixed handling "Connection: close" HTTP client requests
 - Fixed the WebSockets code to accept requests without "Origin" headers as this is only required for web browser clients - [issue #389][issue389]
 - Fixed the markdown compiler to be CTFEable again (by Martin Nowak) - see [pull #398][issue398]
 - Fixed fixed markdown named links containing square brackets in their name - see [pull #399][issue399]
 - Fixed a crash (finalization error) in the HTTP client when an SSL read error occurs
 - Fixed a race condition during shutdown in `Libevent2ManualEvent`
 - Fixed the `Task.this(in Task)` constructor to preserve the task ID

[issue191]: https://github.com/vibe-d/vibe.d/issues/191
[issue309]: https://github.com/vibe-d/vibe.d/issues/309
[issue321]: https://github.com/vibe-d/vibe.d/issues/321
[issue322]: https://github.com/vibe-d/vibe.d/issues/322
[issue327]: https://github.com/vibe-d/vibe.d/issues/327
[issue330]: https://github.com/vibe-d/vibe.d/issues/330
[issue331]: https://github.com/vibe-d/vibe.d/issues/331
[issue333]: https://github.com/vibe-d/vibe.d/issues/333
[issue334]: https://github.com/vibe-d/vibe.d/issues/334
[issue336]: https://github.com/vibe-d/vibe.d/issues/336
[issue337]: https://github.com/vibe-d/vibe.d/issues/337
[issue338]: https://github.com/vibe-d/vibe.d/issues/338
[issue340]: https://github.com/vibe-d/vibe.d/issues/340
[issue341]: https://github.com/vibe-d/vibe.d/issues/341
[issue343]: https://github.com/vibe-d/vibe.d/issues/343
[issue344]: https://github.com/vibe-d/vibe.d/issues/344
[issue348]: https://github.com/vibe-d/vibe.d/issues/348
[issue349]: https://github.com/vibe-d/vibe.d/issues/349
[issue350]: https://github.com/vibe-d/vibe.d/issues/350
[issue352]: https://github.com/vibe-d/vibe.d/issues/352
[issue353]: https://github.com/vibe-d/vibe.d/issues/353
[issue354]: https://github.com/vibe-d/vibe.d/issues/354
[issue357]: https://github.com/vibe-d/vibe.d/issues/357
[issue362]: https://github.com/vibe-d/vibe.d/issues/362
[issue364]: https://github.com/vibe-d/vibe.d/issues/364
[issue365]: https://github.com/vibe-d/vibe.d/issues/365
[issue368]: https://github.com/vibe-d/vibe.d/issues/368
[issue370]: https://github.com/vibe-d/vibe.d/issues/370
[issue373]: https://github.com/vibe-d/vibe.d/issues/373
[issue374]: https://github.com/vibe-d/vibe.d/issues/374
[issue377]: https://github.com/vibe-d/vibe.d/issues/377
[issue380]: https://github.com/vibe-d/vibe.d/issues/380
[issue384]: https://github.com/vibe-d/vibe.d/issues/384
[issue385]: https://github.com/vibe-d/vibe.d/issues/385
[issue386]: https://github.com/vibe-d/vibe.d/issues/386
[issue389]: https://github.com/vibe-d/vibe.d/issues/389
[issue398]: https://github.com/vibe-d/vibe.d/issues/398
[issue399]: https://github.com/vibe-d/vibe.d/issues/399
[issue401]: https://github.com/vibe-d/vibe.d/issues/401
[issue402]: https://github.com/vibe-d/vibe.d/issues/402


v0.7.17 - 2013-09-09
--------------------

This release fixes compiling on DMD 2.063.2 and DMD HEAD and performs a big API cleanup by removing a lot of deprecated functionality and deprecating some additional symbols. New is also a better task local storage support, a SyslogLogger class and a number of smaller additions and bug fixes.

### Features and improvements ###

 - Compiles using DMD 2.063.2 and DMD HEAD
 - Removed a big chunk of deprecated functionality and marked declarations "scheduled for deprecation" as actually deprecated
 - Implemented `TaskPipe` to support piping of data between tasks/threads (usable for converting synchronous I/O to asynchronous I/O)
 - Implemented `TaskLocal!T` for faster and safer task local storage
 - Implemented a `SyslogLogger` class (by Jens K. Mueller) - [pull #294][issue294]
 - Implement support for transferring pre-compressed files in the HTTP file server (by Jens K. Mueller) - [pull #270][issue270]
 - Implemented a first version of `writeFormBody` (by Ben Gradham aka SerialVelocity) - [pull #288][issue288]
 - Implemented `vibe.inet.message.decodeMessage` for decoding an internet message body
 - Implemented a moving `opCast` for `IsolatedRef!T` to allow safe casting to base or derived classes and a boolean `opCast` to allow checking for `null`
 - Implemented a basic version of a WinRT based driver 
 - Added `localAddress` and `remoteAddress` properties to `TCPConnection`
 - Added `localAddress` property and a `connect(NetworkAddress)` overload to `UDPConnection`
 - Added `localAddress` property to `HTTPClientRequest`
 - Added `setTaskEventCallback` to support task level debugging
 - Added `RedisClient.rpush` and `RedisClient.rpushx` (by Martin Mauchauffée aka moechofe) - [pull #280][issue280]
 - Added a write buffer size limit to `ChunkedOutputStream`
 - Added `HTTPClientResponse.disconnect` to force disconnecting the client during request handling
 - Deprecated the `index()` special method for the REST interface generator in favor of `@path` (by Михаил Страшун aka Dicebot)
 - `MongoDatabase.runCommand` is now publicly accessible - [issue #261][issue261]
 - Cookies are now cleared on the client if set to `null` (by Sergey Shamov) - [pull #293][issue293]
 - The optional `do_flush` argument of `OutputStream.write` has been removed - flushing needs to be done explicitly now

### Bug fixes ###

 - Fixed the HTTP file server to ignore directories (so that other handlers can e.g. generate an index page) - [issue #256][issue256]
 - Fixed BSON/JSON (de)serialization of string type enum values
 - Fixed inversion of boolean values when converting from `Json` to `Bson` (by Nicolas Sicard aka biozic) - [pull #260][issue260]
 - Fixed a possible source for memory corruption by making allocators shared between threads
 - Fixed `parseRFC822DateTimeString` (by Nathan M. Swan) - [pull #264][issue264]
 - Fixed `adjustMethodStyle` to cope with non-ASCII characters and fixed conversion of identifiers starting with acronyms
 - Fixed preferring compression over non-chunked transfer when both are requested for `HTTPServerResponse.bodyWriter` (by Jens K. Mueller) - [pull #268][issue268]
 - Fixed assertion in `HTTPClientReponse.~this` (was causing an `InvalidMemoryOperationError` instead of the expected `AssertError`) - [issue #273][issue273]
 - Fixed the VibeDist support code to match the latest VibeDist version (still WIP)
 - Fixed `validateIdent` to properly check validity of the first character
 - Fixed handling of RFC2616 HTTP chunk extensions (ignoring them for now, by Nathan M. Swan) - [pull #274][issue274]
 - Fixed `RedisClient.smembers` (by Nicolas Sigard aka biozic) - [pull #277][issue277]
 - Fixed `RedisClient.echo` and `RedisClient.lpop` (by Martin Mauchauffée aka moechofe) - [pull #279][issue279]
 - Fixed `FixedRingBuffer.put` (used for message passing)
 - Fixed handling of out-of-memory situations in `MallocAllocator`
 - Fixed sending of `Isolated!T` values using `vibe.core.concurrency`
 - Fixed several concurrency related bugs in `ChunkedOutputStream` and `Libevent2ManualEvent`
 - Fixed handling of the `max_lenger` parameter in `validateEmail` (by Mike Wey) - [pull #296][issue296]
 - Fixed possible failed listen attempts in the example projects - [issue #8][issue8], [issue #249][issue249], [issue #298][issue298]
 - Fixed compilation of the libevent2 driver on Win64

[issue8]: https://github.com/vibe-d/vibe.d/issues/8
[issue249]: https://github.com/vibe-d/vibe.d/issues/249
[issue256]: https://github.com/vibe-d/vibe.d/issues/256
[issue260]: https://github.com/vibe-d/vibe.d/issues/260
[issue261]: https://github.com/vibe-d/vibe.d/issues/261
[issue264]: https://github.com/vibe-d/vibe.d/issues/264
[issue268]: https://github.com/vibe-d/vibe.d/issues/268
[issue270]: https://github.com/vibe-d/vibe.d/issues/270
[issue273]: https://github.com/vibe-d/vibe.d/issues/273
[issue274]: https://github.com/vibe-d/vibe.d/issues/274
[issue277]: https://github.com/vibe-d/vibe.d/issues/277
[issue279]: https://github.com/vibe-d/vibe.d/issues/279
[issue280]: https://github.com/vibe-d/vibe.d/issues/280
[issue288]: https://github.com/vibe-d/vibe.d/issues/288
[issue293]: https://github.com/vibe-d/vibe.d/issues/293
[issue294]: https://github.com/vibe-d/vibe.d/issues/294
[issue296]: https://github.com/vibe-d/vibe.d/issues/296
[issue298]: https://github.com/vibe-d/vibe.d/issues/298


v0.7.16 - 2013-06-26
--------------------

This release finally features support for DMD 2.063. It also contains two breaking changes by removing support for the "vibe" script (aka VPM) and switching to an implicit task ownership model for streams (no more explicit acquire/release). It requires DUB 0.9.15 or later to build.

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

[issue200]: https://github.com/vibe-d/vibe.d/issues/200
[issue206]: https://github.com/vibe-d/vibe.d/issues/206
[issue223]: https://github.com/vibe-d/vibe.d/issues/223
[issue227]: https://github.com/vibe-d/vibe.d/issues/227
[issue229]: https://github.com/vibe-d/vibe.d/issues/229
[issue230]: https://github.com/vibe-d/vibe.d/issues/230
[issue234]: https://github.com/vibe-d/vibe.d/issues/234
[issue238]: https://github.com/vibe-d/vibe.d/issues/238
[issue75dub]: https://github.com/rejectedsoftware/dub/issues/75


v0.7.15 - 2013-04-27
--------------------

This release cleans up the API in several places (scheduling some symbols for deprecation) and largely improves the multi-threading primitives. It also features initial support for Win64 and a revamped logging system, as well as authentication support for the MongoDB client and a lot of smaller enhancements.

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

[issue190]: https://github.com/vibe-d/vibe.d/issues/190
[issue199]: https://github.com/vibe-d/vibe.d/issues/199
[issue203]: https://github.com/vibe-d/vibe.d/issues/203
[issue204]: https://github.com/vibe-d/vibe.d/issues/204
[issue205]: https://github.com/vibe-d/vibe.d/issues/205
[issue207]: https://github.com/vibe-d/vibe.d/issues/207
[issue210]: https://github.com/vibe-d/vibe.d/issues/210
[issue211]: https://github.com/vibe-d/vibe.d/issues/211
[issue213]: https://github.com/vibe-d/vibe.d/issues/213
[issue218]: https://github.com/vibe-d/vibe.d/issues/218
[issue220]: https://github.com/vibe-d/vibe.d/issues/220


v0.7.14 - 2013-03-22
--------------------

A lot has been improved on the performance and multi-threading front. The HTTP server benchmark jumped from around 17k req/s up to 48k req/s on a certain quad-core test system and >10k connections can now be handled at the same time (on 64-bit systems due to virtual memory requirements).

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

[issue109]: https://github.com/vibe-d/vibe.d/issues/109
[issue182]: https://github.com/vibe-d/vibe.d/issues/182
[issue189]: https://github.com/vibe-d/vibe.d/issues/189
[issue195]: https://github.com/vibe-d/vibe.d/issues/195


v0.7.13 - 2013-02-24
--------------------

This release solves some issues with the `HttpClient` in conjunction with SSL connection and contains a lot of cleaning up. Many modules and symbols have been deprecated or renamed to streamline the API and reduce redundant functionality with Phobos.

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
 - Fixed cross-thread invocations of `vibe.core.signal.Signal` in the Win32 driver
 - Fixed compilation on DMD 2.062 - [issue #183][issue183], [issue #184][issue184]

[issue183]: https://github.com/vibe-d/vibe.d/issues/183
[issue184]: https://github.com/vibe-d/vibe.d/issues/184


v0.7.12 - 2013-02-11
--------------------

Main changes are a refactored MiongoDB client, important fixes to the `HttpClient` and memory alignment fixes in the custom allocators. The library and all examples are now also valid DUB* packages as a first step to remove the 'vibe' script in favor of the more powerful 'dub'.

### Features and improvements ###

 - Big refactoring of the MongoDB interface to be more consistent with its API (by Михаил Страшун aka Dicebot) - [pull #171][issue171]
 - Added a range interface to `MongoCursor` - redo of [pull #172][issue172]
 - Added a [dub](https://github.com/rejectedsoftware/dub) compatible "package.json" file for vibe.d and all example projects
 - Parameters can be made optional for `registerFormInterface` now (by Robert Klotzner aka eskimor) - [issue #156][issue156]
 - The REST interface generator also supports optional parameters by defining default parameter values
 - Added `Task.interrupt()`, `Task.join()` and `Task.running`
 - Improved detection of needed imports in the REST interface generator (by Михаил Страшун aka Dicebot) - [pull #164][issue164]
 - Partially implemented zero-copy file transfers (still disabled for libevent) - [issue #143][issue143]
 - Added `HttpRequest.contentType` and `contentTypeParameters` to avoid errors by direct comparison with the "Content-Type" header - [issue #154][issue154]
 - Added a small forward compatibility fix for [DUB](https://github.com/rejectedsoftware/dub) packages ("vibe.d" is ignored as a dependency)
 - Cleaned up the function names for writing out `Json` objects as a string and added convenience methods (partially done in [pull #166][issue166] by Joshua Niehus)
 - Renamed `HttpRequest.url` to `HttpRequest.requestUrl` and added `HttpRequest.fullUrl`
 - Added the possibility to write a request body in chunked transfer mode in the `HttpClient`
 - Added `HttpServerRequest.ssl` to determine if a request was sent encrypted
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
 - Fixed passing of misaligned base pointers to `free()` in `MallocAllocator` - at least 32-bit Linux seems to choke on it - [issue #157][issue157]
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

[issue137]: https://github.com/vibe-d/vibe.d/issues/137
[issue143]: https://github.com/vibe-d/vibe.d/issues/143
[issue154]: https://github.com/vibe-d/vibe.d/issues/154
[issue155]: https://github.com/vibe-d/vibe.d/issues/155
[issue156]: https://github.com/vibe-d/vibe.d/issues/156
[issue157]: https://github.com/vibe-d/vibe.d/issues/157
[issue159]: https://github.com/vibe-d/vibe.d/issues/159
[issue161]: https://github.com/vibe-d/vibe.d/issues/161
[issue164]: https://github.com/vibe-d/vibe.d/issues/164
[issue166]: https://github.com/vibe-d/vibe.d/issues/166
[issue168]: https://github.com/vibe-d/vibe.d/issues/168
[issue169]: https://github.com/vibe-d/vibe.d/issues/169
[issue171]: https://github.com/vibe-d/vibe.d/issues/171
[issue172]: https://github.com/vibe-d/vibe.d/issues/172
[issue173]: https://github.com/vibe-d/vibe.d/issues/173
[issue176]: https://github.com/vibe-d/vibe.d/issues/176
[issue177]: https://github.com/vibe-d/vibe.d/issues/177
[issue178]: https://github.com/vibe-d/vibe.d/issues/178
[issue180]: https://github.com/vibe-d/vibe.d/issues/180


v0.7.11 - 2013-01-05
--------------------

Improves installation on Linux and fixes a configuration file handling error, as well as a hang in conjunction with Nginx used as a reverse proxy.

### Features and improvements ###

 - The `setup-linux.sh` script now installs to `/usr/local/share` and uses any existing `www-data` user for its config if possible (by Jordi Sayol) - [issue #150][issue150], [issue #152][issue152], [issue #153][issue153]

### Bug fixes ###

 - Fixed hanging HTTP 1.1 requests with "Connection: close" when no "Content-Length" or "Transfer-Encoding" header is set - [issue #147][issue147]
 - User/group for privilege lowering are now specified as "user"/"group" in vibe.conf instead of "uid"/"gid" - see [issue #133][issue133]
 - Invalid uid/gid now actually cause the application startup to fail

[issue133]: https://github.com/vibe-d/vibe.d/issues/133
[issue147]: https://github.com/vibe-d/vibe.d/issues/147
[issue150]: https://github.com/vibe-d/vibe.d/issues/150
[issue152]: https://github.com/vibe-d/vibe.d/issues/152
[issue153]: https://github.com/vibe-d/vibe.d/issues/153


v0.7.10 - 2013-01-03
--------------------

The Win32 back end now has working TCP socket support. Also, the form and REST interface generators have been improved and Diet templates support arbitrary D expressions for attribute values. Finally, everything compiles now on Win64 using DMD 2.061.

### Features and improvements ###

 - TCP sockets in the Win32 back end work now
 - Added support for struct and array parameters to `registerFormInterface` (by Robert Klotzner aka eskimor) - [issue #138][issue138], [issue #139][issue139], [issue #140][issue140]
 - `registerFormInterface` now ignores static methods (by Robert Klotzner aka eskimor) - [issue #136][issue136]
 - Added support for arbitrary expressions for attributes in Diet templates
 - Added `RedisClient.zrangebyscore` and fixed the return type of `RedistClient.ttl` (`long`) (by Simon Kerouack aka ekyo) - [issue #141][issue141]
 - `renderCompat()` does not require the parameter values to be wrapped in a Variant anymore
 - Added a `BsonObjectID.timeStamp` property that extracts the Unix time part
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

 - Fixed forwarding of non-ASCII Unicode characters in `htmlEscape`
 - Fixed the Diet template parser to accept underscores in ID and class identifiers
 - Fixed HEAD requests properly falling back to GET routes in the `UrlRouter`
 - Fixed parsing of Unicode escape sequences in the JSON parser - [issue #146][issue146]
 - Made `vibe.core.mutex.Mutex` actually pass its unit tests
 - Fixed compile errors occurring when using the field selector parameter of `MongoDB.find/findOne/findAndModify`
 - Fixed some cases of `InvalidMemoryOperationError` in ConnectionPool/LockedConnection - possibly [issue #117][issue117]
 - Avoid passing `0x8000` (`O_BINARY`) on non-Windows systems to `open()`, as this may cause the call to fail (by Martin Nowak) - [issue #142][issue142]
 - Fixed creation of HTTP sessions (were not created before at least one key was set)
 - Fixed the error detection code (safe mode) for the MongoDB client
 - `int` values are now correctly serialized as `Bson.Type.Int` instead of `Bson.Type.Long`
 - Fixed handling of the "X-Forwarded-For" header in the reverse proxy server in case of a proxy chain
 - During the build, temporary executables are now built in `%TEMP%/.rdmd/source` so they pick up the right DLL versions
 - Fixed the daytime example (`readLine` was called with a maximum line length of zero) - [issue #122][issue122], [issue #123][issue123]

[issue117]: https://github.com/vibe-d/vibe.d/issues/117
[issue122]: https://github.com/vibe-d/vibe.d/issues/122
[issue123]: https://github.com/vibe-d/vibe.d/issues/123
[issue126]: https://github.com/vibe-d/vibe.d/issues/126
[issue133]: https://github.com/vibe-d/vibe.d/issues/133
[issue136]: https://github.com/vibe-d/vibe.d/issues/136
[issue138]: https://github.com/vibe-d/vibe.d/issues/138
[issue139]: https://github.com/vibe-d/vibe.d/issues/139
[issue140]: https://github.com/vibe-d/vibe.d/issues/140
[issue141]: https://github.com/vibe-d/vibe.d/issues/141
[issue142]: https://github.com/vibe-d/vibe.d/issues/142
[issue146]: https://github.com/vibe-d/vibe.d/issues/146


v0.7.9 - 2012-10-30
-------------------

The new release contains major improvements to the Win32 back end, as well as to the Diet template compiler. The REST interface has gotten more robust in its type handling and a new HTML form interface generator has been added. The zip file release now also includes HTML API docs.

### Features and improvements ###

 - Implemented an automated HTML form interface generator in `vibe.http.form` (by Robert Klotzner aka eskimor) - [issue #106][issue106]
 - The REST interface now uses fully qualified names and local imports to resolve parameter/return types, making it much more robust (by Михаил Страшун aka mist) - [issue #108][issue108]
 - The Diet template compiler now supports includes and recursive extensions/layouts - [issue #32][issue32], 
 - Added support for WebSocket binary messages and closing connections (by kyubuns) - [issue #118][issue118]
 - Implemented a directory watcher for the Win32 driver
 - Removed `vibe.textfilter.ddoc` - now in <http://github.com/rejectedsoftware/ddox>
 - Cleaned up command line handling (e.g. application parameters are now separated from vibe parameters by --)
 - Dependencies in package.json can now have "~master" as the version field to take the latest master version instead of a tagged version
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
 - Implemented a GitHub like variant of Markdown more suitable for marking up conversation comments
 - The Markdown parser now takes flags to control its behavior
 - Made ATX header and automatic link detection in the Markdown parser stricter to avoid false detections
 - Added `setPlainLogging()` - avoids output of thread and task id
 - Avoiding some bogus error messages in the HTTP server (when a peer closes a connection actively)
 - Renamed the string variant of `filterHtmlAllEscape()` to `htmlAllEscape()` to match similar functions
 - `connectMongoDB()` will now throw if the connection is not possible - this was deferred to the first command up to now
 - By default a `MongoDB` connection will now have the 'safe' flag set
 - The default max cache age for the HTTP file server is now 1 day instead of 30 days
 - Implemented `MemoryStream` - a random access stream operating on a `ubyte[]` array.
 - The form parser in the HTTP server now enforces the maximum input line width
 - A lot of documentation improvements

### Bug fixes ###

 - Fixed a possible endless loop in `ZlibInputStream` - now triggers an assertion instead; Still suffering from [DMD bug 8779](http://d.puremagic.com/issues/show_bug.cgi?id=8779) - [issue #56][issue56]
 - Fixed handling of escaped characters in Diet templates and disallowed use of "##" to escape "#"
 - Fixed "undefined" appearing in the stringified version of JSON arrays or objects (they are now filtered out)
 - Fixed the error message for failed connection attempts
 - Fixed a bug in `PoolAllocator.realloc()` that could cause a range violation or corrupted memory - [issue #107][issue107]
 - Fixed '//' comments in the Diet template compiler
 - Fixed and optimized `readUntil` - it now also obeys the byte limit, if given
 - Fixed parsing of floating-point numbers with exponents in the JSON parser
 - Fixed some HTML output syntax errors in the Markdown compiler

[issue32]: https://github.com/vibe-d/vibe.d/issues/32
[issue56]: https://github.com/vibe-d/vibe.d/issues/56
[issue106]: https://github.com/vibe-d/vibe.d/issues/106
[issue107]: https://github.com/vibe-d/vibe.d/issues/107
[issue108]: https://github.com/vibe-d/vibe.d/issues/108
[issue118]: https://github.com/vibe-d/vibe.d/issues/118


v0.7.8 - 2012-10-01
-------------------

This release adds support for UDP sockets and contains a rather large list of smaller fixes and improvements.

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
 - `OutputStream` now has an output range interface for the types `ubyte` and `char`
 - The logging functions use 'auto ref' instead of 'lazy' now to avoid errors of the kind "this(this) is not nothrow"
 - The markdown text filter now emits XHTML compatible `<br/>` tags instead of `<br>` (by cybevnm) - [issue #98][issue98]
 - The REST interface generator now uses plain strings instead of JSON for query strings and path parameters, if possible
 - The `UrlRouter` now URL-decodes all path parameters

### Bug fixes ###

 - Fixed a null dereference for certain invalid HTTP requests that caused the application to quit
 - Fixed `setTaskStackSize()` to actually do anything (the argument was ignored somewhere along the way to creating the fiber)
 - Fixed parameter name parsing in the REST interface generator for functions with type modifiers on their return type (will be obsolete once __traits(parameterNames) works)
 - Fixed a too strict checking of email addresses and using `std.net.isemail` now to perform proper checking on DMD 2.060 and up - [issue #103][issue103]
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
 - Fixed parsing of Unicode character sequences in JSON strings
 - Fixed the 100-continue response to end with an empty line

[issue3]: https://github.com/vibe-d/vibe.d/issues/3
[issue84]: https://github.com/vibe-d/vibe.d/issues/84
[issue88]: https://github.com/vibe-d/vibe.d/issues/88
[issue89]: https://github.com/vibe-d/vibe.d/issues/89
[issue95]: https://github.com/vibe-d/vibe.d/issues/95
[issue96]: https://github.com/vibe-d/vibe.d/issues/96
[issue98]: https://github.com/vibe-d/vibe.d/issues/98
[issue99]: https://github.com/vibe-d/vibe.d/issues/99
[issue103]: https://github.com/vibe-d/vibe.d/issues/103


v0.7.7 - 2012-08-05
-------------------

Brings some general improvements and DMD 2.060 compatibility.

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

[issue70]: https://github.com/vibe-d/vibe.d/issues/70
[issue73]: https://github.com/vibe-d/vibe.d/issues/73
[issue77]: https://github.com/vibe-d/vibe.d/issues/77
[issue80]: https://github.com/vibe-d/vibe.d/issues/80
[issue81]: https://github.com/vibe-d/vibe.d/issues/81


v0.7.6 - 2012-07-15
-------------------

The most important improvements are easier setup on Linux and Mac and an important bug fix for TCP connections. Additionally, a lot of performance tuning - mostly reduction of memory allocations - has been done.

### Features and improvements ###
 
 - A good amount of performance tuning of the HTTP server
 - Implemented `vibe.core.core.yield()`. This can be used to break up long computations into smaller parts to reduce latency for other tasks
 - Added setup-linux.sh and setup-mac.sh scripts that set a symlink in /usr/bin and a configuration file in /etc/vibe (Thanks to Jordi Sayol)
 - Installed VPM modules are now passed as version identifiers "VPM_package_xyz" to the application to allow for optional features
 - Improved serialization of structs/classes to JSON/BSON - properties are now serialized and all non-field/property members are now ignored
 - Added directory handling functions to `vibe.core.file` (not using asynchronous operations, yet)
 - Improved the vibe shell script's compatibility

### Bug fixes ###
 
 - Fixed `TcpConnection.close()` for the libevent driver - this caused hanging page loads in some browsers
 - Fixed MongoDB connection handling to avoid secondary assertions being triggered in case of exceptions during the communication
 - Fixed JSON (de)serialization of structs and classes (member names were wrong) - [issue #72][issue72]
 - Fixed `(filter)urlEncode` for character values < 0x10 - [issue #65][issue65]

[issue65]: https://github.com/vibe-d/vibe.d/issues/65
[issue72]: https://github.com/vibe-d/vibe.d/issues/72

 
v0.7.5 - 2012-06-05
-------------------

This is a maintainance release primaily to make the examples work again and to improve permission issues when vibe is installed in a read-only location.

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
 - The Diet parser now supports generic `:filters` using `registerDietTextFilter()` - `:css`, `:javascript` and `:markdown` are already built-in
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

[issue52]: https://github.com/vibe-d/vibe.d/issues/52

 
v0.7.3 - 2012-05-22
-------------------

 - Hotfix release, fixes a bug that could cause a connection to be dropped immediately after accept

 
v0.7.2 - 2012-05-22
-------------------

 - Added support for timers and `sleep()`
 - Proper timeout handling for Connection: keep-alive is in place - fixes "Operating on closed connection" errors - [issue #20][issue20], [issue #43][issue43]
 - Setting DFLAGS to change compiler options now actually works
 - Implemented `SslStream`, which is now used instead of libevent's SSL code - fixes a hang on Linux/libevent-2.0.16 - [issue #29][issue29]
 - The REST interface generator now supports `index()` methods and 'id' parameters to customize the protocol
 - Changed the type for durations from `int/double` to `Duration` - [issue #18][issue18]
 - Using Deimos bindings now instead of the custom ones - [issue #48][issue48]

[issue18]: https://github.com/vibe-d/vibe.d/issues/18
[issue20]: https://github.com/vibe-d/vibe.d/issues/20
[issue29]: https://github.com/vibe-d/vibe.d/issues/29
[issue43]: https://github.com/vibe-d/vibe.d/issues/43
[issue48]: https://github.com/vibe-d/vibe.d/issues/48

 
v0.7.1 - 2012-05-18
-------------------

 - Performance tuning
 - Added `vibe.utils.validation`
 - Various fixes and improvements

 
v0.7.0 - 2012-05-06
-------------------

 - Initial development release version
