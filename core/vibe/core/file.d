/**
	File handling functions and types.

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.file;

public import vibe.core.stream;

import vibe.core.drivers.threadedfile; // temporarily needed tp get mkstemps to work
import vibe.core.driver;

import core.stdc.stdio;
import std.datetime;
import std.exception;
import std.file;
import std.path;
import std.string;

version(Posix){
	private extern(C) int mkstemps(char* templ, int suffixlen);
}

@safe:


/**
	Opens a file stream with the specified mode.
*/
FileStream openFile(Path path, FileMode mode = FileMode.read)
{
	return getEventDriver().openFile(path, mode);
}
/// ditto
FileStream openFile(string path, FileMode mode = FileMode.read)
{
	return openFile(Path(path), mode);
}


/**
	Read a whole file into a buffer.

	If the supplied buffer is large enough, it will be used to store the
	contents of the file. Otherwise, a new buffer will be allocated.

	Params:
		path = The path of the file to read
		buffer = An optional buffer to use for storing the file contents
*/
ubyte[] readFile(Path path, ubyte[] buffer = null, size_t max_size = size_t.max)
{
	auto fil = openFile(path);
	scope (exit) fil.close();
	enforce(fil.size <= max_size, "File is too big.");
	auto sz = cast(size_t)fil.size;
	auto ret = sz <= buffer.length ? buffer[0 .. sz] : new ubyte[sz];
	fil.read(ret);
	return ret;
}
/// ditto
ubyte[] readFile(string path, ubyte[] buffer = null, size_t max_size = size_t.max)
{
	return readFile(Path(path), buffer, max_size);
}


/**
	Write a whole file at once.
*/
void writeFile(Path path, in ubyte[] contents)
{
	auto fil = openFile(path, FileMode.createTrunc);
	scope (exit) fil.close();
	fil.write(contents);
}
/// ditto
void writeFile(string path, in ubyte[] contents)
{
	writeFile(Path(path), contents);
}

/**
	Convenience function to append to a file.
*/
void appendToFile(Path path, string data) {
	auto fil = openFile(path, FileMode.append);
	scope(exit) fil.close();
	fil.write(data);
}
/// ditto
void appendToFile(string path, string data)
{
	appendToFile(Path(path), data);
}

/**
	Read a whole UTF-8 encoded file into a string.

	The resulting string will be sanitized and will have the
	optional byte order mark (BOM) removed.
*/
string readFileUTF8(Path path)
{
	import vibe.utils.string;

	return stripUTF8Bom(sanitizeUTF8(readFile(path)));
}
/// ditto
string readFileUTF8(string path)
{
	return readFileUTF8(Path(path));
}


/**
	Write a string into a UTF-8 encoded file.

	The file will have a byte order mark (BOM) prepended.
*/
void writeFileUTF8(Path path, string contents)
{
	static immutable ubyte[] bom = [0xEF, 0xBB, 0xBF];
	auto fil = openFile(path, FileMode.createTrunc);
	scope (exit) fil.close();
	fil.write(bom);
	fil.write(contents);
}

/**
	Creates and opens a temporary file for writing.
*/
FileStream createTempFile(string suffix = null)
{
	version(Windows){
		import std.conv : to;
		string tmpname;
		() @trusted {
			auto fn = tmpnam(null);
			enforce(fn !is null, "Failed to generate temporary name.");
			tmpname = to!string(fn);
		} ();
		if( tmpname.startsWith("\\") ) tmpname = tmpname[1 .. $];
		tmpname ~= suffix;
		return openFile(tmpname, FileMode.createTrunc);
	} else {
		enum pattern ="/tmp/vtmp.XXXXXX";
		scope templ = new char[pattern.length+suffix.length+1];
		templ[0 .. pattern.length] = pattern;
		templ[pattern.length .. $-1] = (suffix)[];
		templ[$-1] = '\0';
		assert(suffix.length <= int.max);
		auto fd = () @trusted { return mkstemps(templ.ptr, cast(int)suffix.length); } ();
		enforce(fd >= 0, "Failed to create temporary file.");
		return new ThreadedFileStream(fd, Path(templ[0 .. $-1].idup), FileMode.createTrunc);
	}
}

/**
	Moves or renames a file.

	Params:
		from = Path to the file/directory to move/rename.
		to = The target path
		copy_fallback = Determines if copy/remove should be used in case of the
			source and destination path pointing to different devices.
*/
void moveFile(Path from, Path to, bool copy_fallback = false)
{
	moveFile(from.toNativeString(), to.toNativeString(), copy_fallback);
}
/// ditto
void moveFile(string from, string to, bool copy_fallback = false)
{
	if (!copy_fallback) {
		std.file.rename(from, to);
	} else {
		try {
			std.file.rename(from, to);
		} catch (FileException e) {
			std.file.copy(from, to);
			std.file.remove(from);
		}
	}
}

/**
	Copies a file.

	Note that attributes and time stamps are currently not retained.

	Params:
		from = Path of the source file
		to = Path for the destination file
		overwrite = If true, any file existing at the destination path will be
			overwritten. If this is false, an exception will be thrown should
			a file already exist at the destination path.

	Throws:
		An Exception if the copy operation fails for some reason.
*/
void copyFile(Path from, Path to, bool overwrite = false)
{
	{
		auto src = openFile(from, FileMode.read);
		scope(exit) src.close();
		enforce(overwrite || !existsFile(to), "Destination file already exists.");
		auto dst = openFile(to, FileMode.createTrunc);
		scope(exit) dst.close();
		src.pipe(dst);
	}

	// TODO: retain attributes and time stamps
}
/// ditto
void copyFile(string from, string to)
{
	copyFile(Path(from), Path(to));
}

/**
	Removes a file
*/
void removeFile(Path path)
{
	removeFile(path.toNativeString());
}
/// ditto
void removeFile(string path)
{
	std.file.remove(path);
}

/**
	Checks if a file exists
*/
bool existsFile(Path path) nothrow
{
	return existsFile(path.toNativeString());
}
/// ditto
bool existsFile(string path) nothrow
{
	return std.file.exists(path);
}

/** Stores information about the specified file/directory into 'info'

	Throws: A `FileException` is thrown if the file does not exist.
*/
FileInfo getFileInfo(Path path)
@trusted {
	auto ent = DirEntry(path.toNativeString());
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
void listDirectory(Path path, scope bool delegate(FileInfo info) del)
@trusted {
	foreach( DirEntry ent; dirEntries(path.toNativeString(), SpanMode.shallow) )
		if( !del(makeFileInfo(ent)) )
			break;
}
/// ditto
void listDirectory(string path, scope bool delegate(FileInfo info) del)
{
	listDirectory(Path(path), del);
}
/// ditto
int delegate(scope int delegate(ref FileInfo)) iterateDirectory(Path path)
{
	int iterator(scope int delegate(ref FileInfo) del){
		int ret = 0;
		listDirectory(path, (fi){
			ret = del(fi);
			return ret == 0;
		});
		return ret;
	}
	return &iterator;
}
/// ditto
int delegate(scope int delegate(ref FileInfo)) iterateDirectory(string path)
{
	return iterateDirectory(Path(path));
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

/**
	Returns the current working directory.
*/
Path getWorkingDirectory()
{
	return Path(() @trusted { return std.file.getcwd(); } ());
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
	read,
	/// The file is opened for read-write random access.
	readWrite,
	/// The file is truncated if it exists or created otherwise and then opened for read-write access.
	createTrunc,
	/// The file is opened for appending data to it and created if it does not exist.
	append
}

/**
	Accesses the contents of a file as a stream.
*/
interface FileStream : RandomAccessStream {
@safe:

	/// The path of the file.
	@property Path path() const nothrow;

	/// Determines if the file stream is still open
	@property bool isOpen() const;

	/// Closes the file handle.
	void close();
}


/**
	Interface for directory watcher implementations.

	Directory watchers monitor the contents of a directory (wither recursively or non-recursively)
	for changes, such as file additions, deletions or modifications.
*/
interface DirectoryWatcher {
@safe:

	/// The path of the watched directory
	@property Path path() const;

	/// Indicates if the directory is watched recursively
	@property bool recursive() const;

	/** Fills the destination array with all changes that occurred since the last call.

		The function will block until either directory changes have occurred or until the
		timeout has elapsed. Specifying a negative duration will cause the function to
		wait without a timeout.

		Params:
			dst = The destination array to which the changes will be appended
			timeout = Optional timeout for the read operation

		Returns:
			If the call completed successfully, true is returned.
	*/
	bool readChanges(ref DirectoryChange[] dst, Duration timeout = dur!"seconds"(-1));
}


/** Specifies the kind of change in a watched directory.
*/
enum DirectoryChangeType {
	/// A file or directory was added
	added,
	/// A file or directory was deleted
	removed,
	/// A file or directory was modified
	modified
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
@trusted {
	FileInfo ret;
	ret.name = baseName(ent.name);
	if( ret.name.length == 0 ) ret.name = ent.name;
	assert(ret.name.length > 0);
	ret.size = ent.size;
	ret.timeModified = ent.timeLastModified;
	version(Windows) ret.timeCreated = ent.timeCreated;
	else ret.timeCreated = ent.timeLastModified;
	ret.isSymlink = ent.isSymlink;
	ret.isDirectory = ent.isDir;
	return ret;
}
