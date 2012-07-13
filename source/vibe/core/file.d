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
import std.datetime;
import std.file;
import std.path;
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
/// ditto
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
/// ditto
void removeFile(string path) {
	std.file.remove(path);
}

/**
	Checks if a file exists
*/
bool existsFile(Path path) {
	return existsFile(path.toNativeString());
}
/// ditto
bool existsFile(string path)
{
	return std.file.exists(path);
}

/** Stores information about the specified file/directory into 'info'

	Returns false if the file does not exist.
*/
FileInfo getFileInfo(Path path)
{
	auto ent = std.file.dirEntry(path.toNativeString());
	return makeFileInfo(ent);
}
/// ditto
FileInfo getFileInfo(string path)
{
	return getFileInfo(Path(path));
}

/**
	Creates a new directory.
*/
void createDirectory(Path path)
{
	mkdir(path.toNativeString());
}
/// ditto
void createDirectory(string path)
{
	createDirectory(Path(path));
}

/** Enumerates all files in the specified directory. */
void listDirectory(Path path, bool delegate(FileInfo info) del)
{
	foreach( DirEntry ent; dirEntries(path.toNativeString(), SpanMode.shallow) )
		if( !del(makeFileInfo(ent)) )
			break;
}
/// ditto
void listDirectory(string path, bool delegate(FileInfo info) del)
{
	listDirectory(Path(path), del);
}


struct FileInfo {
	string name;
	ulong size;
	SysTime timeModified;
	SysTime timeCreated;
	bool isSymlink;
	bool isDirectory;
}

private FileInfo makeFileInfo(DirEntry ent)
{
	FileInfo ret;
	ret.name = baseName(ent.name);
	ret.size = ent.size;
	ret.timeModified = ent.timeLastModified;
	version(Windows) ret.timeCreated = ent.timeCreated;
	else ret.timeCreated = ent.timeLastModified;
	ret.isSymlink = ent.isSymlink;
	ret.isDirectory = ent.isDir;
	return ret;
}