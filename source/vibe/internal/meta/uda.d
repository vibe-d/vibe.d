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
	enum findFirstUDA = findNextUDA!(UDA, Symbol, 0, allow_types);
}

/// Ditto
template findFirstUDA(UDA, alias Symbol, bool allow_types = false)
{
	enum findFirstUDA = findNextUDA!(UDA, Symbol, 0, allow_types);
}

/**
	Small convenience wrapper to find and extract certain UDA from given type.
	Will start at the given index and stop on the next element which is of required type.

	Params:
		UDA = type or template to search for in UDA list
		Symbol = symbol to query for UDA's
		idx = 0-based index to start at. Should be positive, and under the total number of attributes.
		allow_types = if set to `false` considers attached `UDA` types an error
			(only accepts instances/values)

	Returns: aggregated search result struct with 3 field. `value` aliases found UDA.
		`found` is boolean flag for having a valid find. `index` is integer index in
		attribute list this UDA was found at.
 */
template findNextUDA(alias UDA, alias Symbol, long idx, bool allow_types = false)
{
	import std.typetuple : TypeTuple;
	import std.traits : isInstanceOf;

	private alias udaTuple = TypeTuple!(__traits(getAttributes, Symbol));

	static assert(idx >= 0, "Index givent to findNextUDA can't be negative");
	static assert(idx <= udaTuple.length, "Index given to findNextUDA is above the number of attribute");

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
					static assert (allow_types, "findNextUDA is designed to look up values, not types");
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

	enum findNextUDA = extract!(idx, udaTuple[idx .. $]);
}
/// ditto
template findNextUDA(UDA, alias Symbol, long idx, bool allow_types = false)
{
	import std.typetuple : TypeTuple;
	import std.traits : isInstanceOf;

	private alias udaTuple = TypeTuple!(__traits(getAttributes, Symbol));

	static assert(idx >= 0, "Index givent to findNextUDA can't be negative");
	static assert(idx <= udaTuple.length, "Index given to findNextUDA is above the number of attribute");

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
					static assert (allow_types, "findNextUDA is designed to look up values, not types");
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

	enum findNextUDA = extract!(idx, udaTuple[idx .. $]);
}


///
unittest
{
    struct Attribute { int x; }

    @("something", Attribute(42), Attribute(41))
	void symbol();

    enum result0 = findNextUDA!(string, symbol, 0);
	static assert (result0.found);
	static assert (result0.index == 0);
	static assert (result0.value == "something");

	enum result1 = findNextUDA!(Attribute, symbol, 0);
	static assert (result1.found);
	static assert (result1.index == 1);
	static assert (result1.value == Attribute(42));

	enum result2 = findNextUDA!(int, symbol, 0);
	static assert (!result2.found);

	enum result3 = findNextUDA!(Attribute, symbol, result1.index + 1);
	static assert (result3.found);
	static assert (result3.index == 2);
	static assert (result3.value == Attribute(41));
}

unittest
{
    struct Attribute { int x; }

	@(Attribute) void symbol();

	static assert (!__traits(compiles, findNextUDA!(Attribute, symbol, 0)));

	enum result0 = findNextUDA!(Attribute, symbol, 0, true);
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

	enum result0 = findNextUDA!(Attribute, symbol, 0);
	static assert (result0.found);
	static assert (result0.index == 1);
	static assert (result0.value == Attribute(42));
}
