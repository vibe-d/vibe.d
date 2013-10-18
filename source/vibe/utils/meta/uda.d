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

/**
    Determines index of UDA.

    Params:
        UDA = attribute to search
        Symbol = symbol to query

    Returns: index of attribute or -1 if attribute is not found
*/
template indexOfUda(alias UDA, alias Symbol) {
    import std.typetuple : staticIndexOf;
    enum indexOfUda = staticIndexOf!(UDA, __traits(getAttributes, Symbol));
}

/**
    Determines whether Symbol has given UDA

    Params:
        UDA = attribute to search
        Symbol = symbol to query

    Returns: true if symbol has given UDA
*/
template hasUda(alias UDA, alias Symbol) {
    enum bool hasUda = indexOfUda!(UDA, Symbol) != -1;
}

///
unittest
{
    struct Attribute { int x; }
    @("something", Attribute(42), Attribute(41)) void symbol();
    static assert (extractUda!(string, symbol) == "something");
    static assert (extractUda!(Attribute, symbol) == Attribute(42));
    static assert (extractUda!(int, symbol) == null);
    static assert(indexOfUda!("something", symbol) == 0);
    static assert(indexOfUda!(Attribute(41), symbol) == 2);
    static assert(indexOfUda!(43, symbol) == -1);
    static assert(hasUda!("something", symbol));
    static assert(hasUda!(Attribute(42), symbol));
    static assert(!hasUda!(Attribute(44), symbol));
}
