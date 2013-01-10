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
import vibe.stream.operations;
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
import std.typecons;
public import std.typecons : Yes, No;

struct FilePart  {
	InetHeaderMap headers;
	PathEntry filename;
	Path tempPath;
}

/**
	Parses the form given by content_type and body_reader.
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
	"post" are made available via the URL url_prefix~method_name. A method named
	"index" will be made available via url_prefix. method_name is generated from
	the original method name by the same rules as for
	vibe.http.rest.registerRestInterface. All these methods might take a
	HttpServerRequest parameter and a HttpServerResponse parameter, but don't have
	to.

	All additional parameters will be filled with available form-data fields.
	Every parameter name has to match a form field name (or is a fillable
	struct). The registered handler will throw an exception if no overload is
	found that is compatible with all available form data fields.

	If a parameter name is not found in the form data and the parameter is a
	struct, all accessible fields of the struct (might also be properties) will
	be searched in the form, with the parameter (struct) name prefixed. An underscore is
	used as delimiter. So if you have a struct parameter with name 'foo' of type:
	---
	struct FooBar {
		int bar;
		int another_foo;
	}
	---
	the form data must contain the keys 'foo_bar' and 'foo_another_foo'. Their
	corresponding values will be applied to the structure's fields. If not all
	fields of the struct are found, this is considered an error and the next
	overload (if any) will be tried.
	
	The registered handler gives really good error messages if no appropriate
	overload is found, but this comes at the price of some allocations for the
	error messages, which are not used at all if eventually a valid overload is
	found. So because of this and because the search for an appropriate
	overload is done at run time (according to the provided form data) you
	might want to avoid overloads for performance critical sites.

	For a thorough example of how to use this method, see the form_interface
	example in the examples directory.

	See_Also: registerFormMethod, vibe.http.rest.registerRestInterface

	Params:
		router = The router the found methods are registered with.

		instance = The instance whose methods should be called via the registered URLs.

		url_prefix = The prefix before the method name. A method named getWelcomePage
		with a given url_prefix="/mywebapp/welcomePage/" would be made available as
		"/mywebapp/welcomePage/getWelcomePage" if MethodStyle is Unaltered.

		style = How the url part representing the method name should be altered.
        strict = Yes.strict if you want missing parameters in the form to be an error. No.strict if you are happy with the types' default value in this case. 
                (If you have overloads this might cause not the best matching overload to be chosen.)

	Examples:

	---
	class FrontEnd {
		// GET /
		void index(HttpServerResponse res)
		{
			res.render!("index.dt");
		}

		/// GET /files?folder=...
		void getFiles(HttpServerRequest req, HttpServerResponse res, string folder)
		{
			res.render!("files.dt", req, folder);
		}

		/// POST /login
		void postLogin(HttpServerRequest req, HttpServerResponse res, string username,
			string password)
		{
			if( username != "tester" || password != "secret" )
				throw new HttpStatusException(HttpStatus.Unauthorized);
			auto session = req.session;
			if( !session ) session = res.startSession();
			session["username"] = username;
			res.redirect("/");
		}
	}

	static this()
	{
		auto settings = new HttpServerSettings;
		settings.port = 8080;
		auto router = new UrlRouter;
		registerFormInterface(router, new FrontEnd);
		listenHttp(settings, router);
	}
	---

*/
void registerFormInterface(I)(UrlRouter router, I instance, string url_prefix,
		MethodStyle style = MethodStyle.Unaltered, Flag!"strict" strict=Yes.strict)
{
	foreach( method; __traits(allMembers, I) ){
		//pragma(msg, "What: "~"&instance."~method);
		//pragma(msg, "Compiles: "~to!string(__traits(compiles, {mixin("auto dg=&instance."~method);}))); 
		//pragma(msg, "Is function: "~to!string(is(typeof(mixin("I."~method)) == function )));
		//pragma(msg, "Is delegate: "~to!string(is(typeof(mixin("I."~method)) == delegate )));
		static if( is(typeof(mixin("I."~method)) == function) && !__traits(isStaticFunction, mixin("I."~method)) && (method.startsWith("get") || method.startsWith("query") || method.startsWith("add") 
					|| method.startsWith("create") || method.startsWith("post") || method == "index" ))  {
			registerFormMethod!method(router, instance, url_prefix, style, strict);
		}
	}
}
unittest {
	class Test {
		static void f() {
		}
		int h(int a) {
			return a;
		}
		void b()  {
		}
		int c;
	}
	static assert(is(typeof(Test.f) == function));
	static assert(!is(typeof(Test.c) == function));
	static assert(is(typeof(Test.h) == function));
	static assert(is(typeof(Test.b) == function));
	static assert(__traits(isStaticFunction, Test.f));
	static assert(!__traits(isStaticFunction, Test.h));
	static assert(!__traits(isStaticFunction, Test.b));
}


/**
	Registers just a single method.

	For details see registerFormInterface. This method does exactly the
	same, but instead of registering found methods that match a scheme it just
	registers the method specified.

	See_Also: registerFormInterface

	Params:
		method = The name of the method to register. It might be
		overloaded, one overload has to match any given form data, otherwise an error is triggered.
*/
void registerFormMethod(string method, I)(UrlRouter router, I instance, string url_prefix, MethodStyle style = MethodStyle.Unaltered, Flag!"strict" strict=Yes.strict) 
{
	string url(string name) {
		return url_prefix ~ adjustMethodStyle(name, style);
	}
	
	auto handler=formMethodHandler!(I, method)(instance, strict);
	string url_method= method=="index" ? "" : method;
	router.get(url(url_method), handler);
	router.post(url(url_method), handler);
}


/*
	Generate a HttpServerRequestDelegate from a generic function with arbitrary arguments.
	The arbitrary arguments will be filled in with data from the form in req. For details see applyParametersFromAssociativeArrays.
	See_Also: applyParametersFromAssociativeArrays
	Params:
		delegate = Some function, which some arguments which must be constructible from strings with to!ArgType(some_string), except one optional parameter
		of type HttpServerRequest and one of type HttpServerResponse which are passed over.

	Returns: A HttpServerRequestDelegate which passes over any form data to the given function.
*/
/// private
HttpServerRequestDelegate formMethodHandler(DelegateType)(DelegateType func, Flag!"strict" strict=Yes.strict) if(isCallable!DelegateType) 
{
	void handler(HttpServerRequest req, HttpServerResponse res)
	{
		string error;
		enforce(applyParametersFromAssociativeArray(req, res, func, error, strict), error);
	}
	return &handler;
}

/*
	Create a delegate handling form data for any matching overload of T.method.

	T is some class or struct. Method some probably overloaded method of T. The returned delegate will try all overloads
	of the passed method and will only raise an error if no conforming overload is found.
*/
/// private
HttpServerRequestDelegate formMethodHandler(T, string method)(T inst, Flag!"strict" strict)
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
			if(applyParametersFromAssociativeArray!func(req, res, myoverload, error, strict)) {
				return;
			}
			errors~="Overload "~method~typeid(ParameterTypeTuple!func).toString()~" failed: "~error~"\n\n";
		}
		enforce(false, "No method found that matches the found form data:\n"~errors);
	}
	return &handler;
}

/*
	Tries to apply all named arguments in args to func.

	If it succeeds it calls the function with req, res (if it has one
	parameter of type HttpServerRequest and one of type HttpServerResponse), and
	all the values found in args. 

	If any supplied argument could not be applied or the method 
	requires more arguments than given, the method returns false and does not call
	func.  In this case error gets filled with some string describing which
	parameters could not be applied. Exceptions are not used in this situation,
	because when traversing overloads this might be a quite common scenario.

	Applying data happens as follows: 
	
	1. All parameters are traversed
	2. If parameter is of type HttpServerRequest or HttpServerResponse req/res will be applied.
	3. If the parameters name is found in the form, the form data has to be convertible with conv.to to the parameters type, otherwise this method returns false.
	4. If the parameters name is not found in the form, but is a struct, its fields are traversed and searched in the form. The form needs to contain keys in the form: parameterName_structField.
		So if you have a struct paramter foo with a field bar and a field fooBar, the form would need to contain keys: foo_bar and foo_fooBar. The struct fields maybe datafields or properties.
	5. If a struct field is not found in the form or the struct has no fields that are assignable, the method returns false.

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
        strict = Yes.strict if you want missing parameters in the form to be an error. No.strict if you are happy with the types default value in this case.

	Returns: true if successful, false otherwise.
*/
/// private
private bool applyParametersFromAssociativeArray(Func)(HttpServerRequest req, HttpServerResponse res, Func func, out string error, Flag!"strict" strict) {
	return applyParametersFromAssociativeArray!(Func, Func)(req, res, func, error);
}

// Overload which takes additional parameter for handling overloads of func.
/// private
private bool applyParametersFromAssociativeArray(alias Overload, Func)(HttpServerRequest req, HttpServerResponse res, Func func, out string error, Flag!"strict" strict) {
	alias ParameterTypeTuple!Overload ParameterTypes;
	ParameterTypes args;
	string[string] form = req.method == HttpMethod.GET ? req.query : req.form;
	int count=0;
	Error e;
	foreach(i, item; ParameterIdentifierTuple!Overload) {
		static if(is(ParameterTypes[i] : HttpServerRequest)) {
			args[i] = req;
		}
		else static if(is(ParameterTypes[i] : HttpServerResponse)) {
			args[i] = res;
		}
		else {
			count+=loadFormDataRecursiveSingle(form, args[i], item, e, strict);
		}
	}
	error=e.message;
	if(e.missing_parameters.length) {
		error~="The following parameters have not been found in the form data: "~to!string(e.missing_parameters)~"\n";
		error~="Provided form data was: "~to!string(form.keys)~"\n";
	}
	if(count!=form.length) {
		error~="The form had "~to!string(form.length)~" element(s), of which "~to!string(count)~" element(s) were applicable.\n";
	}
	if(error) {
		error="\n------\n"~error~"------";
		return false;
	}
	func(args);
	return true;
}

/**
  * Load form data into fields of a given struct or array.
  *
  * In comparison to registerFormInterface this method can be used in the case
  * you have many optional form fields. It is not an error if not all fields of
  * the struct are filled, but if it is present it must be convertible to the
  * type of the corresponding struct field (properties are not supported). It
  * is also not an error if the form contains more data than applied, the
  * method simply returns the form length and the number of applied elements,
  * so you can decide what todo.
  *
  * The keys in the form must be named like "name_field" for struct, where name
  * is the one passed to this function. If you pass "" for name then the form
  * is queried for "field" where field is the identifier of a field in the
  * struct, as before.
  *
  * If you pass an array to the struct the elements get filled with elements from the form named like:
  * "name0", "name1", ....
  *
  * If the struct/array contains structs/arrays whose identifier can not be
  * found in the form, its fields will be filled recursively.
  *
  * Only dynamic arrays are supported. Their length will be expanded/reduced so
  * the found form data matches exactly. For efficiency reason
  * arr.assumeSafeAppend() gets called by the implementation if the length is
  * reduced. So keep in mind that your data can be overridden.
  *
  * A little example:
   ---
   struct Address {
		string street;
		int door;
		int zipCode;
		string country;
   }
   struct Person {
		string name;
		string surname;
		Address address;
   }
   // Assume form data: [ "customer_name" : "John", "customer_surname" : "Smith", "customer_address_street" : "Broadway", "customer_address_door" : "12", "customer_address_zipCode" : "1002"] 
   void postPerson(HttpServerRequest req, HttpServerResponse res) {
		Person p;
		// We have a default value for country if not provided, so we don't care that it is not:
		p.address.country="Important Country";
		p.name="Jane";
		enforce(loadFormData(req, p, "customer"), "More data than needed provided!");
		// p will now contain the provided form data, non provided data stays untouched.
		assert(p.address.country=="Important Country");
		assert(p.name=="John");
		assert(p.surname=="Smith");
   }
   --- 
  * The mechanism is more useful in get requests, when you have good default values for unspecified parameters.
  * Params:
  *		req  = The HttpServerRequest that contains the form data. (req.query or req.form will be used depending on HttpMethod)
  *		load_to = The struct you wan to be filled.
  *		name = The name of the struct, it is used to find data in the form.	(form is queried for name_fieldName).
  */
FormDataLoadResult loadFormData(T)(HttpServerRequest req, ref T load_to, string name="") if(is(T == struct) || isDynamicArray!T) {
	string[string] form = req.method == HttpMethod.GET ? req.query : req.form;
	if(form.length==0)
		return FormDataLoadResult(0, 0);
	Error error;
	int count=loadFormDataRecursive(form, load_to, name, error, No.strict);
	if(error.message) { // Only serious errors are reported, so let's throw.
		throw new Exception(error.message);
	}
	return FormDataLoadResult(cast(int)form.length, count);
}

/// private
private int loadFormDataRecursive(StructType)(string[string] form, ref StructType load_to, string name, ref Error error, Flag!"strict" strict) if(is(StructType == struct)) {
	int count=0;
	int try_count=0;
	foreach(elem; __traits(allMembers, typeof(load_to))) {
		static if(is(typeof(elem)) && __traits(compiles, mixin("load_to."~elem~"=load_to."~elem))) {
			try_count++;
			string fname=name.length ? name~"_"~elem : elem;
			count+=loadFormDataRecursiveSingle(form, mixin("load_to."~elem), fname, error, strict);
		}
	}
	if(!try_count) {
		error.message~="struct parameter found, with no assignable fields (make sure fields are accessible (public) and assignable): "~name~"\n";
	}
	return count;
}

/// private
private int loadFormDataRecursive(ArrayType)(string[string] form, ref ArrayType load_to, string name, ref Error error, Flag!"strict" strict) if(isDynamicArray!ArrayType && !is(ArrayType == string)) {
	int count=0;
	int i=0;
	immutable arr_length=load_to.length;
	for(i=0; i<arr_length; i++) {
		int c=applyArrayElement(form, load_to, name, i, error, strict);
		if(!c)
			break;
		count+=c;
	}
	if(i<arr_length) {
		load_to.length=i+1;
		load_to.assumeSafeAppend(); /// TODO: This has to be documented!
	}
	else {
		for(; ; i++) {
			load_to.length=load_to.length+1;
			int c=applyArrayElement(form, load_to, name, i, error, strict);
			if(!c)
				break;
			count+=c;
		}
	}
	load_to.length=i; // Last item is invalid
	load_to.assumeSafeAppend(); /// TODO: This has to be documented!
	return count;
}

private int loadFormDataRecursive(T)(string[string] form, ref T load_to, string name, ref Error error, Flag!"strict" strict) if(!is(T == struct) && (!isDynamicArray!T || is(T == string))) {
	static if( __traits(compiles, load_to=to!T("some_string"))) {
		if(strict)
			error.missing_parameters~=name;
	}
	else {
		error.message~=name~" can not be parsed from string or is not assignable!\n";
	}
	return 0;
}
/// private
private int applyArrayElement(ArrayType)(string[string] form, ref ArrayType load_to, string name, int index, ref Error error, Flag!"strict" strict) if(isDynamicArray!ArrayType) {
	string[] backup=error.missing_parameters;
	int count=loadFormDataRecursiveSingle(form, load_to[index], name~to!string(index), error, strict);
	if(!count) { // Nothing found, index does not exist.
		error.missing_parameters=backup; // Not interested in missing parameters. But we are interested in other errors.
	}
	return count;
}

/// private
private int loadFormDataRecursiveSingle(T)(string[string] form, ref T elem, string fname, ref Error error, Flag!"strict" strict) {
	static if( (!isDynamicArray!T || __traits(compiles, {char b=elem[0];})) && __traits(compiles, elem=to!T("some_string"))) {
		auto found_item=fname in form;
		if(found_item) {
			try {
				elem = to!T(*found_item);
				return 1;
			}
			catch(ConvException e) {
				error.message~="Conversion of '"~fname~"' failed, reason: "~e.msg~"\n";
				return 0;
			}
		}
	}
	return loadFormDataRecursive(form, elem, fname, error, strict);
}

unittest {
	struct Test1 {
		int a;
		float b;
	}
	struct Test {
		int a;
		int b;
		int[] c;
		Test1[] d;
		Test1 e;
	}
	Test t;
	t.b=8;
	t.e.a=9;
	string[string] form=[ "t_a" : "1", "t_b" : "2", "t_c0" : "3", "t_c1" : "4", "t_c2" : "5",
	   "t_d0_a" : "6", "t_d0_b" : "7", "t_d1_a" : "9"	];
	Error e;
	assert(loadFormDataRecursive(form, t, "t", e, No.strict)==form.length);
	assert(t.b==2);
	assert(t.e.a==9);
	assert(t.c.length==3);
	assert(t.c[1]==4);
	assert(t.d.length==2);
	assert(t.d[0].a==6);
	assert(t.d[0].b==7);
	assert(t.d[1].a==9);
}
/**
  * struct that contains result from loadFormData.
  *
  * It is convertible to bool and will result to true if all form data has been applied.
  */
struct FormDataLoadResult {
	/// The number of fields in the form
	int formLength;
	/// The number of actually applied fields.
	int appliedCount;
	alias fullApplied this;
	/// Were all fields applied?
	bool fullApplied() const {
		return formLength==appliedCount;
	}
}

struct Error {
	string message;
	string[] missing_parameters;
}
