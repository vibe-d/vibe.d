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
import vibe.inet.message;
import vibe.inet.url;
import vibe.textfilter.urlencode;

// needed for registerFormInterface stuff:
import vibe.http.rest;
import vibe.http.server;
import vibe.http.router;


import std.array;
import std.exception;
import std.string;

// needed for registerFormInterface stuff:
import std.traits;
import std.conv;

struct FilePart  {
	InetHeaderMap headers;
	PathEntry filename;
	Path tempPath;
}

/**
	Parses the form given by 'content_type' and 'body_reader'.
*/
bool parseFormData(ref string[string] fields, ref FilePart[string] files, string content_type, InputStream body_reader, size_t max_line_length)
{
	auto ct_entries = content_type.split(";");
	if( !ct_entries.length ) return false;

	if( ct_entries[0].strip() == "application/x-www-form-urlencoded" ){
		auto bodyStr = cast(string)body_reader.readAll();
		parseUrlEncodedForm(bodyStr, fields);
		return true;
	}
	if( ct_entries[0].strip() == "multipart/form-data" ){
		parseMultiPartForm(fields, files, content_type, body_reader, max_line_length);
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
	string content_type, InputStream body_reader, size_t max_line_length)
{
	auto pos = content_type.indexOf("boundary=");			
	enforce(pos >= 0 , "no boundary for multipart form found");
	auto boundary = content_type[pos+9 .. $];
	auto firstBoundary = cast(string)body_reader.readLine(max_line_length);
	enforce(firstBoundary == "--" ~ boundary, "Invalid multipart form data!");

	while( parseMultipartFormPart(body_reader, fields, files, "\r\n--" ~ boundary, max_line_length) ) {}
}

private bool parseMultipartFormPart(InputStream stream, ref string[string] form, ref FilePart[string] files, string boundary, size_t max_line_length)
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
	return stream.readLine(max_line_length) != "--";
}


/**
	Generates a form based interface to the given instance.

	Each function is callable with either GET or POST using form encoded
	parameters.  All methods of I that start with "get", "query", "add", "create",
	"post" are made available via url: url_prefix~method_name.  A method named
	"index" will be made available via url_prefix.  All these methods might take a
	HttpServerRequest parameter and a HttpServerResponse parameter, but don't have
	to.

	All additional parameters will be filled with available form-data fields.
	Every parameters name has to match a form field name. The registered handler
	will throw an exception if no overload is found that is compatible with all
	available form data fields.

	See_Also: registerFormMethod

	Params:
		router = The router the found methods are registered with.

		instance = The instance which methods should be called via the registered URLs.

		url_prefix = The prefix before the method name. A method named getWelcomePage
		with a given url_prefix="/mywebapp/welcomePage/" would be made available as
		"/mywebapp/welcomePage/getWelcomePage" if MethodStyle is Unaltered.

		style = How the url part representing the method name should be altered.
*/
void registerFormInterface(I)(UrlRouter router, I instance, string url_prefix,
		MethodStyle style = MethodStyle.Unaltered)
{
	foreach( method; formMethodRange(__traits(allMembers, I)) ){
		registerFormMethod(router, instance, url_prefix, method, style);
	}
}
/**
	Registers just a single method.

	For details see registerFormInterface. This method does exactly the
	same, but instead of registering found methods that match a scheme it just
	registers the method specified.  See_Also: registerFormInterface

	Params:
		method = The name of the method to register. It might be
		overloaded, any overload has to match any given form data.
*/
void registerFormMethod(string method, I)(UrlRouter router, I instance, string url_prefix, MethodStyle style = MethodStyle.Unaltered) 
{
	string url(string name) {
		return url_prefix ~ adjustMethodStyle(name, style);
	}
	
	auto handler=formMethodHandler!(I, method)(instance);
	router.get(url(method), handler);
	router.post(url(method), handler);
}


/**
	Generate a HttpServerRequestDelegate from a generic function with arbitrary arguments.
	The arbitrary arguments will be filled in with data from the form in req. For details see applyParametersFromAssociativeArrays.
	See_Also: applyParametersFromAssociativeArrays
	Params:
		delegate = Some function, which some arguments which must be constructible from strings with to!ArgType(some_string), except one optional parameter
		of type HttpServerRequest and one of type HttpServerResponse which are passed over.

	Returns: A HttpServerRequestDelegate which passes over any form data to the given function.
*/
HttpServerRequestDelegate formMethodHandler(DelegateType)(DelegateType func) if(isCallable!DelegateType) 
{
	void handler(HttpServerRequest req, HttpServerResponse res)
	{
		string error;
		enforce(applyParametersFromAssociativeArray(req, res, func, error), error);
	}
	return &handler;
}

/**
	Create a delegate handling form data for any matching overload of T.method.

	T is some class or struct. Method some probably overloaded method of T. The returned delegate will try all overloads
	of the passed method with the given method and will only raise an error if no conforming overload is found.
*/
HttpServerRequestDelegate formMethodHandler(T, string method)(T inst)
{
	import std.stdio;
	void handler(HttpServerRequest req, HttpServerResponse res)
	{
		import std.traits;
		string[string] form = req.method == HttpMethod.GET ? req.query : req.form;
//		alias MemberFunctionsTuple!(T, method) overloads;
		string errors;
		foreach(func; __traits(getOverloads, T, method)) {
			string error;
			ReturnType!func delegate(ParameterTypeTuple!func) myoverload=&__traits(getMember, inst, method);
			if(applyParametersFromAssociativeArray!func(req, res, myoverload, error)) {
				return;
			}
			errors~="Overload "~method~typeid(ParameterTypeTuple!func).toString()~" failed: "~error~"\n";
		}
		enforce(false, "No method found that matches the found form data:\n"~errors);
	}
	return &handler;
}

/**
	Tries to apply all named arguments in args to func.

	If it succeeds it calls the function with req, res (if it has one
	parameter of type HttpServerRequest and one of type HttpServerResponse), and
	all the values found in args. 

	If any supplied argument could not be applied or the method has
	requires more arguments than given, the method returns false and does not call
	func.  In this case error gets filled with some string describing which
	parameters could not be applied. Exceptions are not used in this situation,
	because when traversing overloads this might be a quite common scenario.

	Calls: applyParametersFromAssociativeArray!(Func,Func)(req, res, func, error),
	if you want to handle overloads of func, use the second version of this method
	and pass the overload alias as first template parameter. (For retrieving parameter names)
	
	See_Also: formMethodHandler

	Params:
		req = The HttpServerRequest object that gets queried for form
		data (req.query for GET requests, req.form for POST requests) and that is
		passed on to func, if func has a parameter of matching type. Each key in the
		form data must match a parameter name, the corresponding value is then applied.
		HttpServerRequest and HttpServerResponse arguments are excluded as they are
		qrovided by the passed req and res objects.


		res = The response object that gets passed on to func if func
		has a parameter of matching type.

		error = This string will be set to a descriptive message if not all parameters could be matched.

	Returns: true if successful, false otherwise.
*/
private bool applyParametersFromAssociativeArray(Func)(HttpServerRequest req, HttpServerResponse res, Func func, out string error) {
	return applyParametersFromAssociativeArray!(Func, Func)(req, res, func, error);
}
/// Overload which takes additional parameter for handling overloads of func.
private bool applyParametersFromAssociativeArray(alias Overload, Func)(HttpServerRequest req, HttpServerResponse res, Func func, out string error) {
			alias ParameterTypeTuple!Overload ParameterTypes;
			ParameterTypes args;
			string[string] form = req.method == HttpMethod.GET ? req.query : req.form;
			int count=0;
			foreach(i, item; args) {
				static if(is(ParameterTypes[i] : HttpServerRequest)) {
					args[i] = req;
				} 
				else static if(is(ParameterTypes[i] : HttpServerResponse)) {
					args[i] = res;
				}
				else {
					count++;
				}
			}
			if(count!=form.length) {
				error="The form had "~to!string(form.length)~" element(s), but "~to!string(count)~" parameter(s) need to be supplied.";
				return false;
			}
			foreach(i, item; ParameterIdentifierTuple!Overload) {
				static if(!is( typeof(args[i]) : HttpServerRequest) && !is( typeof(args[i]) : HttpServerResponse)) {
					if(item !in form) {
						error="Form misses parameter: "~item;
						return false;
					}
					args[i] = to!(typeof(args[i]))(form[item]);
				}
			}
			func(args);
			return true;
}
/// helper range which filters method names.
/// private
private struct FormMethodRange(InputRange) if(isInputRange!InputRange) {
	this(InputRange input) {
		input_=input;
		gotoNextValid();
	}
	@property front() {
		input_.front();
	}
	void popFront() {
		input_.popFront();
		gotoNextValid();
	}
	@property empty() {
		return input_.empty;
	}
private:
	void gotoNextValid() {
		string current=input_.front;
		while( !(current.startsWith("get") || current.startsWith("query") || current.startsWith("add") 
					|| current.startsWith("create") || current.startsWith("post") || current == "index" ))  {
			input_.popFront();
			current_=input_.front;
		}
	}
	InputRange input_;
}
/// creator method:
/// private
private auto formMethodRange(InputRange)(InputRange range) {
	return FormMethodRange!InputRange(range);
}
