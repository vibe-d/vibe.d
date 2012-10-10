/**
	File handling.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.file;

public import vibe.core.driver;
public import vibe.inet.url;

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
	return openFile(path, mode);
}
/// ditto
FileStream openFile(string path, FileMode mode = FileMode.Read)
{
	return getEventDriver().openFile(Path(path), mode);
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

/**
	Enumerates all files in the specified directory.
*/
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

/**
	Starts watching a directory for changes.
*/
DirectoryWatcher watchDirectory(Path path, bool recursive = true)
{
	return getEventDriver().watchDirectory(path, recursive);
}
// ditto
DirectoryWatcher watchDirectory(string path, bool recursive = true)
{
	return watchDirectory(Path(path), recursive);
}


/** Contains general information about a file.
*/
struct FileInfo {
	/// Name of the file (not including the path)
	string name;

	/// Size of the file (zero for directories)
	ulong size;

	/// Time of the last modification
	SysTime timeModified;

	/// Time of creation (not available on all operating systems/file systems)
	SysTime timeCreated;

	/// True if this is a symlink to an actual file
	bool isSymlink;

	/// True if this is a directory or a symlink pointing to a directory
	bool isDirectory;
}

/**
	Specifies how a file is manipulated on disk.
*/
enum FileMode {
	/// The file is opened read-only.
	Read,
	/// The file is opened for read-write random access.
	ReadWrite,
	/// The file is truncated if it exists and created otherwise and the opened for read-write access.
	CreateTrunc,
	/// The file is opened for appending data to it and created if it does not exist.
	Append
}

/**
	Accesses the contents of a file as a stream.
*/
interface FileStream : RandomAccessStream, EventedObject {
	/// The path of the file.
	@property Path path() const;

	/// Closes the file handle.
	void close();
}


/**
	Interface for directory watcher implementations.

	Directory watchers monitor the contents of a directory (wither recursively or non-recursively)
	for changes, such as file additions, deletions or modifications.
*/
interface DirectoryWatcher {
	/// The path of the watched directory
	@property Path path() const;

	/// Indicates if the directory is watched recursively
	@property bool recursive() const;

	/** Waits until a change event occurs in the directory.

		Params:
			timeout = Optional timeout after which the call returns with false if no event occured

		Returns:
			If the wait was successful, true is returned. If either the timeout elapsed before an event 
			occured or a condition arised making it impossible to track changes, false is returned.
	*/
	bool waitForChange();
	/// ditto
	bool waitForChange(Duration timeout);

	/** Fills the destination array with all changes that occured since the last call.

		Params:
			dst = The destination array to which the changes will be appended

		Returns:
			If the call completed successfully, true is returned.
	*/
	bool getChanges(ref DirectoryChange[] dst);
}


/** Specifies the kind of change in a watched directory.
*/
enum DirectoryChangeType {
	/// A file or directory was added
	Added,
	/// A file or directory was deleted
	Removed,
	/// A file or directory was modified
	Modified
}


/** Describes a single change in a watched directory.
*/
struct DirectoryChange {
	/// The type of change
	DirectoryChangeType type;

	/// Path of the file/directory that was changed
	Path path;
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

