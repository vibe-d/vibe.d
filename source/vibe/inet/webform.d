/**
	Contains HTML/urlencoded form parsing and construction routines.

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.inet.webform;

import vibe.core.file;
import vibe.core.log;
import vibe.inet.message;
import vibe.stream.operations;
import vibe.textfilter.urlencode;
import vibe.utils.string;
import vibe.utils.dictionarylist;

import std.array;
import std.exception;
import std.string;


/**
	Parses the form given by content_type and body_reader.
*/
bool parseFormData(ref FormFields fields, ref FilePartFormFields files, string content_type, InputStream body_reader, size_t max_line_length)
{
	auto ct_entries = content_type.split(";");
	if (!ct_entries.length) return false;

	switch (ct_entries[0].strip()) {
		default:
			return false;
		case "application/x-www-form-urlencoded":
			parseURLEncodedForm(body_reader.readAllUTF8(), fields);
			break;
		case "multipart/form-data":
			parseMultiPartForm(fields, files, content_type, body_reader, max_line_length);
			break;
	}
	return false;
}

/**
	Parses a url encoded form (query string format) and puts the key/value pairs into params.
*/
void parseURLEncodedForm(string str, ref FormFields params)
{
	while (str.length > 0) {
		// name part
		auto idx = str.indexOf("=");
		if (idx == -1) {
			idx = str.indexOfAny("&;");
			if (idx == -1) {
				params.addField(formDecode(str[0 .. $]), "");
				return;
			} else {
				params.addField(formDecode(str[0 .. idx]), "");
				str = str[idx+1 .. $];
				continue;
			}
		} else {
			auto idx_amp = str.indexOfAny("&;");
			if (idx_amp > -1 && idx_amp < idx) {
				params.addField(formDecode(str[0 .. idx_amp]), "");
				str = str[idx_amp+1 .. $];
				continue;				
			} else {
				string name = formDecode(str[0 .. idx]);
				str = str[idx+1 .. $];
				// value part
				for( idx = 0; idx < str.length && str[idx] != '&' && str[idx] != ';'; idx++) {}
				string value = formDecode(str[0 .. idx]);
				params.addField(name, value);
				str = idx < str.length ? str[idx+1 .. $] : null;
			}
		}
	}
}

unittest
{
	FormFields dst;
	parseURLEncodedForm("a=b;c;dee=asd&e=fgh&f=j%20l", dst);
	assert("a" in dst && dst["a"] == "b");
	assert("c" in dst && dst["c"] == "");
	assert("dee" in dst && dst["dee"] == "asd");
	assert("e" in dst && dst["e"] == "fgh");
	assert("f" in dst && dst["f"] == "j l");
}


/**
	Parses a form in "multipart/form-data" format.

	If any _files are contained in the form, they are written to temporary _files using
	vibe.core.file.createTempFile and returned in the files field.
*/
void parseMultiPartForm(ref FormFields fields, ref FilePartFormFields files,
	string content_type, InputStream body_reader, size_t max_line_length)
{
	auto pos = content_type.indexOf("boundary=");			
	enforce(pos >= 0 , "no boundary for multipart form found");
	auto boundary = content_type[pos+9 .. $];
	auto firstBoundary = cast(string)body_reader.readLine(max_line_length);
	enforce(firstBoundary == "--" ~ boundary, "Invalid multipart form data!");

	while (parseMultipartFormPart(body_reader, fields, files, "\r\n--" ~ boundary, max_line_length)) {}
}

alias FormFields = DictionaryList!(string, true, 16);
alias FilePartFormFields = DictionaryList!(FilePart, true, 1);

struct FilePart {
	InetHeaderMap headers;
	PathEntry filename;
	Path tempPath;
}


private bool parseMultipartFormPart(InputStream stream, ref FormFields form, ref FilePartFormFields files, string boundary, size_t max_line_length)
{
	InetHeaderMap headers;
	stream.parseRFC5322Header(headers);
	auto pv = "Content-Disposition" in headers;
	enforce(pv, "invalid multipart");
	auto cd = *pv;
	string name;
	auto pos = cd.indexOf("name=\"");
	if (pos >= 0) {
		cd = cd[pos+6 .. $];
		pos = cd.indexOf("\"");
		name = cd[0 .. pos];
	}
	string filename;
	pos = cd.indexOf("filename=\"");
	if (pos >= 0) {
		cd = cd[pos+10 .. $];
		pos = cd.indexOf("\"");
		filename = cd[0 .. pos];
	}

	if (filename.length > 0) {
		FilePart fp;
		fp.headers = headers;
		fp.filename = PathEntry(filename);

		auto file = createTempFile();
		fp.tempPath = file.path;
		stream.readUntil(file, cast(ubyte[])boundary);
		logDebug("file: %s", fp.tempPath.toString());
		file.close();

		files.addField(name, fp);

		// TODO: temp files must be deleted after the request has been processed!
	} else {
		auto data = cast(string)stream.readUntil(cast(ubyte[])boundary);
		form.addField(name, data);
	}
	return stream.readLine(max_line_length) != "--";
}
