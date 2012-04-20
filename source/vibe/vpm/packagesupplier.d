/**
	A package manager.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module vibe.vpm.packagesupplier;

import std.file;
import std.exception;
import std.zip;
import std.conv;

import vibe.core.log;
import vibe.core.file;
import vibe.data.json;
import vibe.inet.url;
import vibe.inet.urltransfer;

import vibe.vpm.utils;
import vibe.vpm.dependency;

/// Supplies packages, this is done by supplying the latest possible version
/// which is available.
interface PackageSupplier {
	/// path: absolute path to store the package (usually in a zip format)
	void storePackage(const Path path, const string packageId, const Dependency dep);
	
	/// returns the metadata for the package
	Json packageJson(const string packageId, const Dependency dep);
}

class FSPackageSupplier : PackageSupplier {
	private { Path m_path; }
	this(Path root) { m_path = root; }
	
	void storePackage(const Path path, const string packageId, const Dependency dep) {
		enforce(path.absolute);
		logInfo("Storing package '"~packageId~"', version requirements: %s", dep);
		auto filename = bestPackageFile(packageId, dep);
		enforce( exists(to!string(filename)) );
		copy(to!string(filename), to!string(path));
	}
	
	Json packageJson(const string packageId, const Dependency dep) {
		auto filename = bestPackageFile(packageId, dep);
		return jsonFromZip(to!string(filename), "package.json");
	}
	
	private Path bestPackageFile( const string packageId, const Dependency dep) const {
		Version bestVersion = Version(Version.RELEASE);
		foreach(DirEntry d; dirEntries(to!string(m_path), packageId~"*", SpanMode.shallow)) {
			Path p = Path(d.name);
			logTrace("Entry: %s", p);
			enforce(to!string(p.head)[$-4..$] == ".zip");
			string vers = to!string(p.head)[packageId.length+1..$-4];
			logTrace("Version string: "~vers);
			Version v = Version(vers);
			if(v > bestVersion && dep.matches(v) ) {
				bestVersion = v;
			}
		}
		
		auto fileName = m_path ~ (packageId ~ "_" ~ to!string(bestVersion) ~ ".zip");
		
		if(bestVersion == Version.RELEASE || !exists(to!string(fileName)))
			throw new Exception("No matching package found");
		
		logDebug("Found best matching package: '%s'", fileName);
		return fileName;
	}
}