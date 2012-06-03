/**
	File handling.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.file;

public import vibe.core.driver;
public import vibe.inet.url;

import vibe.core.core;
import vibe.core.log;

import std.conv;
import std.c.stdio;
import std.file;
import std.string;


/**
	Opens a file stream with the specified mode.
*/
FileStream openFile(Path path, FileMode mode = FileMode.Read)
{
	return openFile(path.toNativeString(), mode);
}
/// ditto
FileStream openFile(string path, FileMode mode = FileMode.Read)
{
	return getEventDriver().openFile(path, mode);
}

/**
	Creates and opens a temporary file for writing.
*/
FileStream createTempFile()
{
	char[L_tmpnam] tmp;
	tmpnam(tmp.ptr);
	auto tmpname = to!string(tmp.ptr);
	if( tmpname.startsWith("\\") ) tmpname = tmpname[1 .. $];
	logDebug("tmp %s", tmp);
	return openFile(tmpname, FileMode.CreateTrunc);
}

/**
	Moves or renames a file.
*/
void moveFile(Path from, Path to)
{
	moveFile(from.toNativeString(), to.toNativeString());
}
//
void moveFile(string from, string to)
{
	std.file.rename(from, to);
}

/**
	Removes a file
*/
void removeFile(Path path)
{
	removeFile(path.toNativeString());
}

void removeFile(string path) {
	std.file.remove(path);
}

/**
	Checks if a file exists
*/
bool existsFile(Path path) {
	return existsFile(path.toNativeString());
}

bool existsFile(string path)
{
	return std.file.exists(path);
}