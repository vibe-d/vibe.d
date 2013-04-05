/**
	Handles and applies the uid/gid/user/group configuration settings.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.setuid;

import vibe.core.log;
import vibe.core.args;

import std.exception;

version(Posix)
{
	import core.sys.posix.unistd;
	import core.sys.posix.pwd;

	static if( __traits(compiles, {import core.sys.posix.grp; getgrgid(0);}) ){
		import core.sys.posix.grp;
	} else {
		extern(C){
			struct group
			{
				char*   gr_name;
				char*   gr_passwd;
				gid_t   gr_gid;
				char**  gr_mem;
			}
			group* getgrgid(gid_t);
			group* getgrnam(in char*);
		}
	}

	private bool isRoot() { return geteuid()==0; }

	private void setUID(int uid, int gid)
	{
		logInfo("Lowering privileges to uid=%d, gid=%d...", uid, gid);
		if( gid >= 0 ){
			enforce(getgrgid(gid) !is null, "Invalid group id!");
			enforce(setegid(gid) == 0, "Error setting group id!");
		}
		//if( initgroups(const char *user, gid_t group);
		if( uid >= 0 ){
			enforce(getpwuid(uid) !is null, "Invalid user id!");
			enforce(seteuid(uid) == 0, "Error setting user id!");
		}
	}

	private int getUID(string name)
	{
		auto pw = getpwnam(name.toStringz());
		enforce(pw !is null, "Unknown user name: "~name);
		return pw.pw_uid;
	}

	private int getGID(string name)
	{
		auto gr = getgrnam(name.toStringz());
		enforce(gr !is null, "Unknown group name: "~name);
		return gr.gr_gid;
	}
} else version(Windows){
	private bool isRoot() { return false; }

	private void setUID(int uid, int gid)
	{
		enforce(false, "UID/GID not supported on Windows.");
	}

	private int getUID(string name)
	{
		enforce(false, "Privilege lowering not supported on Windows.");
		assert(false);
	}

	private int getGID(string name)
	{
		enforce(false, "Privilege lowering not supported on Windows.");
		assert(false);
	}
}

shared static this()
{
	string uname, gname;
	getOption("uid|user" , &uname);
	getOption("gid|group", &gname);

	if (uname || gname)
	{
		static bool tryParse(T)(string s, out T n) { import std.conv; n = parse!T(s); return s.length==0; }
		int uid = -1, gid = -1;
		if (uname && !tryParse(uname, uid)) uid = getUID(uname);
		if (gname && !tryParse(gname, gid)) gid = getGID(gname);
		setUID(uid, gid);
	}
	else
	{
		if (isRoot())
			logWarn("Vibe was run as root, and no user/group has been specified for privilege lowering.");
	}
}
