/**
	Contains HTTP form parsing and construction routines.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.form;

import vibe.core.driver;
import vibe.core.file;
import vibe.core.log;
import vibe.inet.rfc5322;
import vibe.inet.url;
import vibe.textfilter.urlencode;

import std.exception;
import std.string;


struct FilePart  {
	InetHeaderMap headers;
	PathEntry filename;
	Path tempPath;
}

/**
	Parses the form given by 'content_type' and 'body_reader'.
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

/**
	Parses a url encoded form (query string format) and puts the key/value pairs into params.
*/
void parseUrlEncodedForm(string str, ref string[string] params)
{
	while(str.length > 0){
		// name part
		auto idx = str.indexOf("=");
		if( idx == -1 ) {
			idx = str.indexOf("&");
			if( idx == -1 ) {
				params[urlDecode(str[0 .. $])] = "";
				return;
			} else {
				params[urlDecode(str[0 .. idx])] = "";
				str = str[idx+1 .. $];
				continue;
			}
		} else {
			auto idx_amp = str.indexOf("&");
			if( idx_amp > -1 && idx_amp < idx ) {
				params[urlDecode(str[0 .. idx_amp])] = "";
				str = str[idx_amp+1 .. $];
				continue;				
			} else {
				string name = urlDecode(str[0 .. idx]);
				str = str[idx+1 .. $];
				// value part
				for( idx = 0; idx < str.length && str[idx] != '&' && str[idx] != ';'; idx++) {}
				string value = urlDecode(str[0 .. idx]);
				params[name] = value;
				str = idx < str.length ? str[idx+1 .. $] : null;
			}
		}
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
		fp.filename = PathEntry(filename);

		auto file = createTempFile();
		fp.tempPath = file.path;
		stream.readUntil(file, cast(ubyte[])boundary);
		logDebug("file: %s", fp.tempPath.toString());
		file.close();

		files[name] = fp;

		// TODO: temp files must be deleted after the request has been processed!
	} else {
		auto data = cast(string)stream.readUntil(cast(ubyte[])boundary);
		form[name] = data;
	}
	return stream.readLine() != "--";
}

