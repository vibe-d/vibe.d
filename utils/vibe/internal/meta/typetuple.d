/**
	Additions to std.typetuple pending for inclusion into Phobos.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Михаил Страшун
*/

module vibe.internal.meta.typetuple;

import std.typetuple;
import std.traits;

/**
	TypeTuple which does not auto-expand.

	Useful when you need
	to multiple several type tuples as different template argument
	list parameters, without merging those.
*/
template Group(T...)
{
	alias expand = T;
}

///
unittest
{
	alias group = Group!(int, double, string);
	static assert (!is(typeof(group.length)));
	static assert (group.expand.length == 3);
	static assert (is(group.expand[1] == double));
}

/**
*/
template isGroup(T...)
{
	static if (T.length != 1) enum isGroup = false;
	else enum isGroup =
		!is(T[0]) && is(typeof(T[0]) == void)      // does not evaluate to something
		&& is(typeof(T[0].expand.length) : size_t) // expands to something with length
		&& !is(typeof(&(T[0].expand)));            // expands to not addressable
}

version (unittest) // NOTE: GDC complains about template definitions in unittest blocks
{
	alias group = Group!(int, double, string);
	alias group2 = Group!();

	template Fake(T...)
	{
		int[] expand;
	}
	alias fake = Fake!(int, double, string);

	alias fake2 = TypeTuple!(int, double, string);

	static assert (isGroup!group);
	static assert (isGroup!group2);
	static assert (!isGroup!fake);
	static assert (!isGroup!fake2);
}

/* Copied from Phobos as it is private there.
 */
private template isSame(ab...)
	if (ab.length == 2)
{
	static if (is(ab[0]) && is(ab[1]))
	{
		enum isSame = is(ab[0] == ab[1]);
	}
	else static if (!is(ab[0]) &&
					!is(ab[1]) &&
					is(typeof(ab[0] == ab[1]) == bool) &&
					(ab[0] == ab[1]))
	{
		static if (!__traits(compiles, &ab[0]) ||
				   !__traits(compiles, &ab[1]))
			enum isSame = (ab[0] == ab[1]);
		else
			enum isSame = __traits(isSame, ab[0], ab[1]);
	}
	else
	{
		enum isSame = __traits(isSame, ab[0], ab[1]);
	}
}

/**
	Compares two groups for element identity

	Params:
		Group1, Group2 = any instances of `Group`

	Returns:
		`true` if each element of Group1 is identical to
		the one of Group2 at the same index
*/
template Compare(alias Group1, alias Group2)
	if (isGroup!Group1 && isGroup!Group2)
{
	private template implementation(size_t index)
	{
		static if (Group1.expand.length != Group2.expand.length) enum implementation = false;
		else static if (index >= Group1.expand.length) enum implementation = true;
		else static if (!isSame!(Group1.expand[index], Group2.expand[index])) enum implementation = false;
		else enum implementation = implementation!(index+1);
	}

	enum Compare = implementation!0;
}

///
unittest
{
	alias one = Group!(int, double);
	alias two = Group!(int, double);
	alias three = Group!(double, int);
	static assert (Compare!(one, two));
	static assert (!Compare!(one, three));
}
