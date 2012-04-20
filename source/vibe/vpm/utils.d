/**
	...
	
	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module vibe.vpm.utils;

// todo: cleanup imports.
import std.array;
import std.file;
import std.exception;
import std.algorithm;
import std.zip;
import std.typecons;
import std.conv;

import vibe.core.log;
import vibe.core.file;
import vibe.data.json;
import vibe.inet.url;

package bool isEmptyDir(Path p) {
	foreach(DirEntry e; dirEntries(to!string(p), SpanMode.shallow))
		return false;
	return true;
}

package Json jsonFromFile(Path file) {
	auto f = openFile(to!string(file), FileMode.Read);
	scope(exit) f.close();
	ubyte[] b = new ubyte[cast(uint)f.leastSize];
	f.read(b);
	string r = cast(string) b;
	return parseJson( r );
}

package Json jsonFromZip(string zip, string filename) {
	auto f = openFile(zip, FileMode.Read);
	ubyte[] b = new ubyte[cast(uint)f.leastSize];
	f.read(b);
	f.close();
	auto archive = new ZipArchive(b);
	auto jsonData = archive.expand(archive.directory[filename]);
	string s = cast(string) jsonData;
	return parseJson( s );
}

package bool isPathFromZip(string p) {
	enforce(p.length > 0);
	return p[$-1] == '/';
}
