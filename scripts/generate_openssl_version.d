/+ dub.sdl:
 name "script"
 +/

/**
 * This program will attempt to detect which version of openssl is installed
 *
 * End-users might have different versions of OpenSSL installed.
 * The version might ever differ among members of a development team.
 *
 * This script attempts to first calls `pkg-config` to find out the version,
 * then reverts to calling the `openssl` binary if `pkg-config` didn't work.
 *
 * It is called directly as a `preGenerateCommand` of `vibe-d:tls`.
 * To use it with another build system, pass the directory in which to write
 * the `openssl_version.d` file as first and only argument. The directory
 * must exist, this script will not create it.
 *
 * Comptability: Due to a bug in DUB versions prior to v1.27.0,
 * released alongside DMD-2.098.0 (2021-10-10), this script is duplicated
 * in `tls/dub.sdl`. It is however provided here for alternate build systems.
 */
module generate_openssl_version;

import std.algorithm;
import std.conv;
import std.file;
import std.functional;
import std.path;
import std.process;
import std.range;
import std.stdio;
import std.string;
import std.uni;

// file full path is: $SOME_PATH/vibe.d/scripts/generate_openssl_version.d
// We want: $SOME_PATH/vibe.d/tls/
immutable TARGET_DIR_PATH = __FILE_FULL_PATH__
    .dirName.dirName
    .buildPath("tls");

void main(string[] args)
{
    string target;

    if (args.length == 2)
    {
        assert(args[1].isDir(),
               "OpenSSL version detection: Argument '" ~ args[1] ~ "' is not a directory");
        target = args[1].buildPath("openssl_version.d");
    }
    else
    {
        assert(args.length == 1,
               "OpenSSL version detection expects only one argument, " ~
               "a directory path where to write `openssl_version.d`");
        target = TARGET_DIR_PATH.buildPath("openssl_version.d");
    }

	string opensslVersion;
	try {
		const res = execute(["pkg-config", "openssl", "--modversion"]);
		if (res.status == 0)
			opensslVersion = res.output.strip();
	} catch (Exception e) {}

	if (!opensslVersion.length) try
	{
		const res = execute(["openssl", "version"]).output;
		if (res.canFind("OpenSSL ")) {
			opensslVersion = res.splitter(" ").dropOne.front.filter!(not!(std.uni.isAlpha)).text;
		} else if (res.canFind("LibreSSL ")) {
			writeln("\tWarning: Your default openssl binary points to LibreSSL, which is not supported.");
			version (OSX) {
				writeln("\tOn Mac OSX, this is the default behavior.");
				writeln("\tIf you installed openssl via a package manager, you need to tell DUB how to find it.");
				writeln("\tAssuming brew, run [brew link openssl] and follow the instructions for pkg-config.\n");
			}
		}
	} catch (Exception e) {}
	if (!opensslVersion.length)
	{
		 writeln("\tWarning: Could not find OpenSSL version via pkg-config nor by calling the openssl binary.");
		 writeln("\tAssuming version 1.1.0.");
		 writeln("\tYou might need to export PKG_CONFIG_PATH or install the openssl package if you have a library-only package.");
		 opensslVersion = "1.1.0";
	}
	auto data = text("module openssl_version;\nenum OPENSSL_VERSION=\"", opensslVersion, "\";\n");
	if (!target.exists || target.readText.strip != data.strip)
		data.toFile(target);
}
