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
		MethodStyle style = MethodStyle.Unaltered)
{
	foreach( method; __traits(allMembers, I) ){
		//pragma(msg, "What: "~"&instance."~method);
		//pragma(msg, "Compiles: "~to!string(__traits(compiles, {mixin("auto dg=&instance."~method);}))); 
		//pragma(msg, "Is function: "~to!string(is(typeof(mixin("I."~method)) == function )));
		//pragma(msg, "Is delegate: "~to!string(is(typeof(mixin("I."~method)) == delegate )));
		static if( is(typeof(mixin("I."~method)) == function) && !__traits(isStaticFunction, mixin("I."~method)) && (method.startsWith("get") || method.startsWith("query") || method.startsWith("add") 
					|| method.startsWith("create") || method.startsWith("post") || method == "index" ))  {
			registerFormMethod!method(router, instance, url_prefix, style);
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
void registerFormMethod(string method, I)(UrlRouter router, I instance, string url_prefix, MethodStyle style = MethodStyle.Unaltered) 
{
	string url(string name) {
		return url_prefix ~ adjustMethodStyle(name, style);
	}
	
	auto handler=formMethodHandler!(I, method)(instance);
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
HttpServerRequestDelegate formMethodHandler(DelegateType)(DelegateType func) if(isCallable!DelegateType) 
{
	void handler(HttpServerRequest req, HttpServerResponse res)
	{
		string error;
		enforce(applyParametersFromAssociativeArray(req, res, func, error), error);
	}
	return &handler;
}

/*
	Create a delegate handling form data for any matching overload of T.method.

	T is some class or struct. Method some probably overloaded method of T. The returned delegate will try all overloads
	of the passed method and will only raise an error if no conforming overload is found.
*/
/// private
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

	Returns: true if successful, false otherwise.
*/
/// private
private bool applyParametersFromAssociativeArray(Func)(HttpServerRequest req, HttpServerResponse res, Func func, out string error) {
	return applyParametersFromAssociativeArray!(Func, Func)(req, res, func, error);
}

// Overload which takes additional parameter for handling overloads of func.
/// private
private bool applyParametersFromAssociativeArray(alias Overload, Func)(HttpServerRequest req, HttpServerResponse res, Func func, out string error) {
			alias ParameterTypeTuple!Overload ParameterTypes;
			ParameterTypes args;
			string[string] form = req.method == HttpMethod.GET ? req.query : req.form;
			int count=0;
			string[] missing_parameters;
			foreach(i, item; ParameterIdentifierTuple!Overload) {
				static if(is(ParameterTypes[i] : HttpServerRequest)) {
					args[i] = req;
				}
				else static if(is(ParameterTypes[i] : HttpServerResponse)) {
					args[i] = res;
				}
				else {
					auto found_item=item in form;
					if(found_item) {
						try {
							args[i] = to!(typeof(args[i]))(*found_item);
							count++;
						}
						catch(ConvException e) {
							error~="Conversion of '"~item~"' failed, reason: "~e.msg~"\n";
						}
					}
					else {
						int old_count=count;
						static if(is(typeof(args[i]) == struct)) {
							foreach(elem; __traits(allMembers, typeof(args[i]))) {
								//static if(__traits(compiles, {__traits(getMember, args[i], elem)=__traits(getMember, args[i], elem);}))   // Does not compile: _args_field_4 Internal error: e2ir.c 720
								//pragma(msg, "Compiles '__traits(compiles, {args[i]."~elem~"=args[i]."~elem~";})': "~to!string(mixin("__traits(compiles, {args[i]."~elem~"=args[i]."~elem~";})")));
								static if(mixin("__traits(compiles, {args[i]."~elem~"=args[i]."~elem~";})")) {
									string fname=item~"_"~elem;
									auto found=fname in form;
									if(found) {
										try {
											mixin("args[i]."~elem~"=to!(typeof(args[i]."~elem~"))(*found);");
											count++;
											//__traits(getMember, args[i], elem)=to!(typeof(__traits(getMember, args[i], elem)))(*found); // Does not compile: _args_field_4 Internal error: e2ir.c 720
										}
										catch(ConvException e) {
											error~="Conversion of '"~fname~"' failed, reason: "~e.msg~"\n";
										}
									}
									else
										missing_parameters~=fname;
								}
							}
							if(old_count==count) {
								error~="struct parameter found, with no assignable or readable fields (make sure fields are accessible (public), assignable and readable): "~item~"\n";
							}
						}
						else {
							missing_parameters~=item;
						}
					}
				}
			}
			if(missing_parameters.length) {
				error~="The following parameters have not been found in the form data: "~to!string(missing_parameters)~"\n";
				error~="Provied form data was: "~to!string(form.keys)~"\n";
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
  * Load form data into fields of a given struct.
  *
  * In comparison to registerFormInterface this method can be used in the case
  * you have many, many optional form fields. It is not an error if not all
  * fields of the struct are filled, but if it is present it must be
  * convertible to the type of the corresponding struct field. It is also not
  * an error if the form contains more data than applied, the method simply
  * returns the form length and the number of applied elements, so you can
  * decide what todo.
  *
  * The keys in the form must be named like "name_field", where name is the one
  * passed to this function. If you pass "" for name then the form is queried
  * for "field" where field is the identifier of a field in the struct, as
  * before.
  *
  * If the struct contains other structs whose identifier can not be found in the form, its fields will be filled recursively.
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
FormDataLoadResult loadFormData(StructType)(HttpServerRequest req, ref StructType load_to, string name) if(is(StructType == struct)) {
	string[string] form = req.method == HttpMethod.GET ? req.query : req.form;
	int count=loadFormDataRecursive(form, load_to, prefix);
	return FormDataLoadResult(form.length, count);
}

/// private
private int loadFormDataRecursive(StructType)(string[string] form, ref StructType load_to, string name) if(is(StructType == struct)) {
	int count=0;
	foreach(elem; __traits(allMembers, typeof(load_to))) {
		string fname=name.length ? name~"_"~elem : elem;
		bool found=false;
		static if(mixin("__traits(compiles, {load_to."~elem~"=load_to."~elem~";})")) {
			found=fname in form;
			if(found) {
				mixin("args[i]."~elem~"=to!(typeof(args[i]."~elem~"))(*found);");
				count++;
			}
		}
		static if(mixin("is(typeof(load_to."~elem~") == struct)")) {
			if(!found) {
				count+=loadFormDataRecursive(form, mixin("load_to."~elem), fname, count);
			}
		}
	}
	return count;
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
