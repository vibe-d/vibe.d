/**
	Utility templates that help working with User Defined Attributes

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Михаил Страшун
*/

module vibe.internal.meta.uda;

//import vibe.internal.meta.traits;


/**
	Small convenience wrapper to find and extract certain UDA from given type.
	Will stop on first element which is of required type.

	Params:
		UDA = type or template to search for in UDA list
		Symbol = symbol to query for UDA's
		allow_types = if set to `false` considers attached `UDA` types an error
			(only accepts instances/values)

	Returns: aggregated search result struct with 3 field. `value` aliases found UDA.
		`found` is boolean flag for having a valid find. `index` is integer index in
		attribute list this UDA was found at.
*/
template findFirstUDA(alias UDA, alias Symbol, bool allow_types = false)
{
	import std.typetuple : TypeTuple;
	import std.traits : isInstanceOf;

    private alias TypeTuple!(__traits(getAttributes, Symbol)) udaTuple;

	private struct UdaSearchResult(alias UDA)
	{
		alias value = UDA;
		bool found = false;
		long index = -1;
	}

    private template extract(size_t index, list...)
    {
        static if (!list.length) enum extract = UdaSearchResult!(null)(false, -1);
        else {
        	static if (is(list[0])) {
				static if (is(UDA) && is(list[0] == UDA) || !is(UDA) && isInstanceOf!(UDA, list[0])) {
					static assert (allow_types, "findFirstUDA is designed to look up values, not types");
					enum extract = UdaSearchResult!(list[0])(true, index);
				} else enum extract = extract!(index + 1, list[1..$]);
        	} else {
				static if (is(UDA) && is(typeof(list[0]) == UDA) || !is(UDA) && isInstanceOf!(UDA, typeof(list[0]))) {
					import vibe.internal.meta.traits : isPropertyGetter;
					static if (isPropertyGetter!(list[0])) {
						enum value = list[0];
						enum extract = UdaSearchResult!(value)(true, index);
					} else enum extract = UdaSearchResult!(list[0])(true, index);
				} else enum extract = extract!(index + 1, list[1..$]);
			}
		}
    }

    enum findFirstUDA = extract!(0, udaTuple);
}
/// ditto
template findFirstUDA(UDA, alias Symbol, bool allow_types = false)
{
	import std.typetuple : TypeTuple;
	import std.traits : isInstanceOf;

    private alias TypeTuple!(__traits(getAttributes, Symbol)) udaTuple;

	private struct UdaSearchResult(alias UDA)
	{
		alias value = UDA;
		bool found = false;
		long index = -1;
	}

    private template extract(size_t index, list...)
    {
        static if (!list.length) enum extract = UdaSearchResult!(null)(false, -1);
        else {
        	static if (is(list[0])) {
				static if (is(list[0] == UDA)) {
					static assert (allow_types, "findFirstUDA is designed to look up values, not types");
					enum extract = UdaSearchResult!(list[0])(true, index);
				} else enum extract = extract!(index + 1, list[1..$]);
        	} else {
				static if (is(typeof(list[0]) == UDA)) {
					import vibe.internal.meta.traits : isPropertyGetter;
					static if (isPropertyGetter!(list[0])) {
						enum value = list[0];
						enum extract = UdaSearchResult!(value)(true, index);
					} else enum extract = UdaSearchResult!(list[0])(true, index);
				} else enum extract = extract!(index + 1, list[1..$]);
			}
		}
    }

    enum findFirstUDA = extract!(0, udaTuple);
}


///
unittest
{
    struct Attribute { int x; }

    @("something", Attribute(42), Attribute(41))
	void symbol();

    enum result0 = findFirstUDA!(string, symbol);
	static assert (result0.found);
	static assert (result0.index == 0);
	static assert (result0.value == "something");

	enum result1 = findFirstUDA!(Attribute, symbol);
	static assert (result1.found);
	static assert (result1.index == 1);
	static assert (result1.value == Attribute(42));

	enum result2 = findFirstUDA!(int, symbol);
    static assert (!result2.found);
}

unittest
{
    struct Attribute { int x; }

	@(Attribute) void symbol();

	static assert (!__traits(compiles, findFirstUDA!(Attribute, symbol)));

	enum result0 = findFirstUDA!(Attribute, symbol, true);
	static assert (result0.found);
	static assert (result0.index == 0);
	static assert (is(result0.value == Attribute));
}

unittest
{
    struct Attribute { int x; }
    enum Dummy;

	@property static Attribute getter()
	{
		return Attribute(42);
	}

	@Dummy @getter void symbol();

	enum result0 = findFirstUDA!(Attribute, symbol);
	static assert (result0.found);
	static assert (result0.index == 1);
	static assert (result0.value == Attribute(42));
}
