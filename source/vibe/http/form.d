/**
	Routines for automated implementation of HTML form based interfaces.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.form;

public import vibe.inet.webform;
public import std.typecons : Yes, No;

import vibe.core.log;
import vibe.http.client : HTTPClientRequest; // for writeFormBody
import vibe.http.rest;
import vibe.http.router;
import vibe.http.server;
import vibe.inet.url;

import std.array;
import std.conv;
import std.exception;
import std.range;
import std.string;
import std.traits;
import std.typecons;


/**
	Encodes the given dictionary as URL encoded form data.
*/
void writeFormData(R)(R dst, in string[string] data)
	if (isOutputRange!(R, char))
{
	import vibe.textfilter.urlencode;

	bool first = true;
	foreach (k, v; data) {
		if (first) first = false;
		else dst.put("&");
		filterURLEncode(dst, k);
		dst.put("=");
		filterURLEncode(dst, v);
	}
}

///
unittest {
	import std.array;
	import vibe.core.log;
	import vibe.http.form;

	void test()
	{
		auto dst = appender!string();
		dst.writeFormData(["field1": "value1", "field2": "value2"]);
		logInfo("Form data: %s", dst.data);
	}
}

/**
	Encodes the given ranges of `Tuple!(string, string)` as URL encoded form data
*/
void writeFormData(R, PairRange)(R dst, PairRange pr)
	if (isOutputRange!(R, char) && isTuple!(ElementType!PairRange) && ElementType!PairRange.length == 2)
{
	import vibe.textfilter.urlencode;

   if(pr.empty) return;

   auto fst = pr.front;
   pr.popFront();

   filterURLEncode(dst, fst[0]);
   dst.put("=");
   filterURLEncode(dst, fst[1]);

	foreach (pair; pr) {
		dst.put("&");
		filterURLEncode(dst, pair[0]);
		dst.put("=");
		filterURLEncode(dst, pair[1]);
	}
}

/**
	Writes a `vibe.http.client.HTTPClientRequest` body as URL encoded form data.
*/
void writeFormBody(HTTPClientRequest req, in string[string] form)
{
	import vibe.http.form;
	import vibe.stream.wrapper;

	StringLengthCountingRange len;
	writeFormData(&len, form);
	req.contentType = "application/x-www-form-urlencoded";
	req.contentLength = len.count;
	auto rng = StreamOutputRange(req.bodyWriter);
	writeFormData(&rng, form);
}

///
unittest {
	import vibe.core.log;
	import vibe.http.client;
	import vibe.http.form;
	import vibe.stream.operations;

	void sendForm()
	{
		requestHTTP("http://example.com/form",
			(scope req) {
				req.method = HTTPMethod.POST;
				req.writeFormBody(["field1": "value1", "field2": "value2"]);
			},
			(scope res) {
				logInfo("Response: %s", res.bodyReader.readAllUTF8());
			});
	}
}

/**
	Writes a `vibe.http.client.HTTPClientRequest` body as URL encoded form data.

	Params:
      form = range of `t = Tuple!(string, string)`,
             where `t[0]` is the name and `t[1]` the
             value of a form entry.
*/
void writeFormBody(PairRange)(HTTPClientRequest req, PairRange form)
   if(isTuple!(ElementType!PairRange) && ElementType!PairRange.length == 2)
{
	import vibe.http.form;
	import vibe.stream.wrapper;

	StringLengthCountingRange len;
	writeFormData(&len, form.save);
	req.contentType = "application/x-www-form-urlencoded";
	req.contentLength = len.count;
	auto rng = StreamOutputRange(req.bodyWriter);
	writeFormData(&rng, form);
}

///
unittest {
	import vibe.core.log;
	import vibe.http.client;
	import vibe.http.form;
	import vibe.stream.operations;
	import std.range;

	void sendForm()
	{
		string[] names = ["foo", "bar", "baz"];
		string[] values = ["1", "2", "3"];
		auto form = zip(names, values);
		requestHTTP("http://example.com/form",
			(scope req) {
				req.method = HTTPMethod.POST;
				req.writeFormBody(form);
			},
			(scope res) {
				logInfo("Response: %s", res.bodyReader.readAllUTF8());
			});
	}
}


/// private
struct StringLengthCountingRange {
	import std.utf;
	size_t count = 0;
	void put(string str) { count += str.length; }
	void put(dchar ch) { count += codeLength!char(ch); }
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
   void postPerson(HTTPServerRequest req, HTTPServerResponse res) {
		Person p;
		// We have a default value for country if not provided, so we don't care that it is not:
		p.address.country="Important Country";
		p.name="Jane";
		enforceBadRequest(loadFormData(req, p, "customer"), "More data than needed provided!");
		// p will now contain the provided form data, non provided data stays untouched.
		assert(p.address.country=="Important Country");
		assert(p.name=="John");
		assert(p.surname=="Smith");
   }
   ---
  * The mechanism is more useful in get requests, when you have good default values for unspecified parameters.
  * Params:
  *		req  = The HTTPServerRequest that contains the form data. (req.query or req.form will be used depending on HTTPMethod)
  *		load_to = The struct you wan to be filled.
  *		name = The name of the struct, it is used to find data in the form.	(form is queried for name_fieldName).
  */
deprecated FormDataLoadResult loadFormData(T)(HTTPServerRequest req, ref T load_to, string name="") if(is(T == struct) || isDynamicArray!T)
{
	FormFields form = req.method == HTTPMethod.GET ? req.query : req.form;
	if (form.length == 0)
		return FormDataLoadResult(0, 0);
	Error error;
	int count = loadFormDataRecursive(form, load_to, name, error, No.strict);
	if (error.message) { // Only serious errors are reported, so let's throw.
		throw new Exception(error.message);
	}
	return FormDataLoadResult(cast(int)form.length, count);
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

/// private
private int loadFormDataRecursive(StructType)(FormFields form, ref StructType load_to, string name, ref Error error, Flag!"strict" strict) if(is(StructType == struct)) {
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
private int loadFormDataRecursive(ArrayType)(FormFields form, ref ArrayType load_to, string name, ref Error error, Flag!"strict" strict) if(isDynamicArray!ArrayType && !is(ArrayType == string)) {
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

private int loadFormDataRecursive(T)(FormFields form, ref T load_to, string name, ref Error error, Flag!"strict" strict) if(!is(T == struct) && (!isDynamicArray!T || is(T == string))) {
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
private int applyArrayElement(ArrayType)(FormFields form, ref ArrayType load_to, string name, int index, ref Error error, Flag!"strict" strict) if(isDynamicArray!ArrayType) {
	string[] backup=error.missing_parameters;
	int count=loadFormDataRecursiveSingle(form, load_to[index], name~to!string(index), error, strict);
	if(!count) { // Nothing found, index does not exist.
		error.missing_parameters=backup; // Not interested in missing parameters. But we are interested in other errors.
	}
	return count;
}

/// private
private int loadFormDataRecursiveSingle(T)(FormFields form, ref T elem, string fname, ref Error error, Flag!"strict" strict) {
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
	enum E {
		someValue,
		someOtherValue
	}
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
		E f;
	}

	Test t;
	t.b=8;
	t.e.a=9;

	FormFields form;
	form["t_a"] = "1";
	form["t_b"] = "2";
	form["t_c0"] = "3";
	form["t_c1"] = "4";
	form["t_c2"] = "5";
	form["t_d0_a"] = "6";
	form["t_d0_b"] = "7";
	form["t_d1_a"] = "9";
	form["t_f"] = "someOtherValue";

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
	assert(t.f == E.someOtherValue);
}
