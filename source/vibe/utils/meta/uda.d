/**
	Utility templates that help working with User Defined Attributes

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Михаил Страшун
*/

module vibe.utils.meta.uda;

/**
	Small convenience wrapper to find and extract certain UDA from given type.
	Will stop on first element which is of required type.

	Params:
		UDA = type to search for in UDA list
		Symbol = symbol to query for UDA's

	Returns: null if UDA is not found, UDA value otherwise
*/
template extractUda(UDA, alias Symbol)
{
	import std.typetuple : TypeTuple;

    private alias TypeTuple!(__traits(getAttributes, Symbol)) udaTuple;

    private template extract(list...)
    {
        static if (!list.length)
            enum extract = null;
        else {
			static assert (!is(list[0] == UDA), "extractUda is designed to look up values, not types");

			static if (is(typeof(list[0]) == UDA))
            	enum extract = list[0];
	        else
    	        enum extract = extract!(list[1..$]);
		}
    }

    enum extractUda = extract!udaTuple;
}

///
unittest
{
    struct Attribute { int x; }
    @("something", Attribute(42), Attribute(41)) void symbol();
    static assert (extractUda!(string, symbol) == "something");
    static assert (extractUda!(Attribute, symbol) == Attribute(42));
    static assert (extractUda!(int, symbol) == null);
}
