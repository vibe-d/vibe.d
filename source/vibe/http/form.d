/**
	Contains HTTP form parsing and construction routines.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.form;

import vibe.core.driver;
import vibe.core.log;
import vibe.inet.rfc5322;
import vibe.inet.url;
import vibe.textfilter.urlencode;

import std.c.stdio;
import std.exception;
import std.string;


struct FilePart  {
	InetHeaderMap headers;
	string filename;
	Path tempPath;
}


/**
	Parses the form given by 
*/
bool parseFormData(ref string[string] fields, ref FilePart[string] files, string content_type, InputStream body_reader)
{
	if( content_type == "application/x-www-form-urlencoded" ){
		auto bodyStr = cast(string)body_reader.readAll();
		parseUrlEncodedForm(bodyStr, fields);
		return true;
	}
	if( content_type.startsWith("multipart/form-data") ){
		parseMultiPartForm(fields, files, content_type, body_reader);
		return true;
	}
	return false;
}


void parseUrlEncodedForm(string str, ref string[string] params)
{
	while(str.length > 0){
		// name part
		auto idx = str.indexOf('=');
		enforce(idx > 0, "Expected ident=value.");
		string name = urlDecode(str[0 .. idx]);
		str = str[idx+1 .. $];

		// value part
		for( idx = 0; idx < str.length && str[idx] != '&' && str[idx] != ';'; idx++) {}
		string value = urlDecode(str[0 .. idx]);
		params[name] = value;
		str = idx < str.length ? str[idx+1 .. $] : null;
	}
}

private void parseMultiPartForm(ref string[string] fields, ref FilePart[string] files,
	string content_type, InputStream body_reader)
{
	auto pos = content_type.indexOf("boundary=");			
	enforce(pos >= 0 , "no boundary for multipart form found");
	auto boundary = content_type[pos+9 .. $];
	auto firstBoundary = cast(string)body_reader.readLine();
	enforce(firstBoundary == "--" ~ boundary, "Invalid multipart form data!");

	while( parseMultipartFormPart(body_reader, fields, files, "\r\n--" ~ boundary) ) {}
}

private bool parseMultipartFormPart(InputStream stream, ref string[string] form, ref FilePart[string] files, string boundary)
{
	InetHeaderMap headers;
	stream.parseRfc5322Header(headers);
	auto pv = "Content-Disposition" in headers;
	enforce(pv, "invalid multipart");
	auto cd = *pv;
	string name;
	auto pos = cd.indexOf("name=\"");
	if( pos >= 0 ) {
		cd = cd[pos+6 .. $];
		pos = cd.indexOf("\"");
		name = cd[0 .. pos];
	}
	string filename;
	pos = cd.indexOf("filename=\"");
	if( pos >= 0 ) {
		cd = cd[pos+10 .. $];
		pos = cd.indexOf("\"");
		filename = cd[0 .. pos];
	}

	if( filename.length > 0 ) {
		FilePart fp;
		fp.headers = headers;
		fp.filename = filename;

		char[] tmp = new char[L_tmpnam];
		tmpnam(tmp.ptr);
		logDebug("tmp %s", tmp);
		//TODO store upload in tempfile and pass path in FilePart struct.
		//fp.tempPath = Path(cast(string)tmp);
		//auto file = openFile(fp.tempPath.toString());
		//file.write(stream.readUntil(cast(ubyte[])boundary));
		stream.readUntil(cast(ubyte[])boundary);
		//logDebug("file: %s", fp.tempPath.toString());
		//file.close();
	} else {
		auto data = cast(string)stream.readUntil(cast(ubyte[])boundary);
		form[name] = data;
	}
	return stream.readLine() != "--";
}

