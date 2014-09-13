/**
    Extensions to `std.traits` module of Phobos. Some may eventually make it into Phobos,
    some are dirty hacks that work only for vibe.d

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Михаил Страшун
*/

module vibe.internal.meta.traits;

/**
	Checks if given type is a getter function type

	Returns: `true` if argument is a getter
 */
template isPropertyGetter(T...)
	if (T.length == 1)
{
	import std.traits : functionAttributes, FunctionAttribute, ReturnType,
		isSomeFunction;
	static if (isSomeFunction!(T[0])) {
		enum isPropertyGetter =
			(functionAttributes!(T[0]) & FunctionAttribute.property) != 0
			&& !is(ReturnType!T == void);
	}
	else
		enum isPropertyGetter = false;
}

///
unittest
{
	interface Test
	{
		@property int getter();
		@property void setter(int);
		int simple();
	}

	static assert(isPropertyGetter!(typeof(&Test.getter)));
	static assert(!isPropertyGetter!(typeof(&Test.setter)));
	static assert(!isPropertyGetter!(typeof(&Test.simple)));
	static assert(!isPropertyGetter!int);
}

/**
	Checks if given type is a setter function type

	Returns: `true` if argument is a setter
 */
template isPropertySetter(T...)
	if (T.length == 1)
{
	import std.traits : functionAttributes, FunctionAttribute, ReturnType,
		isSomeFunction;

	static if (isSomeFunction!(T[0])) {
		enum isPropertySetter =
			(functionAttributes!(T) & FunctionAttribute.property) != 0
			&& is(ReturnType!(T[0]) == void);
	}
	else
		enum isPropertySetter = false;
}

///
unittest
{
	interface Test
	{
		@property int getter();
		@property void setter(int);
		int simple();
	}

	static assert(isPropertySetter!(typeof(&Test.setter)));
	static assert(!isPropertySetter!(typeof(&Test.getter)));
	static assert(!isPropertySetter!(typeof(&Test.simple)));
	static assert(!isPropertySetter!int);
}

/**
	Deduces single base interface for a type. Multiple interfaces
	will result in compile-time error.

	Params:
		T = interface or class type

	Returns:
		T if it is an interface. If T is a class, interface it implements.
*/
template baseInterface(T)
	if (is(T == interface) || is(T == class))
{
	import std.traits : InterfacesTuple;

	static if (is(T == interface)) {
		alias baseInterface = T;
	}
	else
	{
		alias Ifaces = InterfacesTuple!T;
		static assert (
			Ifaces.length == 1,
			"Type must be either provided as an interface or implement only one interface"
		);
		alias baseInterface = Ifaces[0];
	}
}

///
unittest
{
	interface I1 { }
	class A : I1 { }
	interface I2 { }
	class B : I1, I2 { }

	static assert (is(baseInterface!I1 == I1));
	static assert (is(baseInterface!A == I1));
	static assert (!is(typeof(baseInterface!B)));
}


/**
	Determins if a member is a public, non-static data field.
*/
template isRWPlainField(T, string M)
{
	static if (!isRWField!(T, M)) enum isRWPlainField = false;
	else {
		//pragma(msg, T.stringof~"."~M~":"~typeof(__traits(getMember, T, M)).stringof);
		enum isRWPlainField = __traits(compiles, *(&__traits(getMember, Tgen!T(), M)) = *(&__traits(getMember, Tgen!T(), M)));
	}
}

/**
	Determines if a member is a public, non-static, de-facto data field.

	In addition to plain data fields, R/W properties are also accepted.
*/
template isRWField(T, string M)
{
	import std.traits;
	import std.typetuple;

	static void testAssign()() {
		T* pt;
		__traits(getMember, *pt, M) = __traits(getMember, *pt, M);
	}

	// reject type aliases
	static if (is(TypeTuple!(__traits(getMember, T, M)))) enum isRWField = false;
	// reject non-public members
	else static if (!isPublicMember!(T, M)) enum isRWField = false;
	// reject static members
	else static if (!isNonStaticMember!(T, M)) enum isRWField = false;
	// reject non-typed members
	else static if (!is(typeof(__traits(getMember, T, M)))) enum isRWField = false;
	// reject void typed members (includes templates)
	else static if (is(typeof(__traits(getMember, T, M)) == void)) enum isRWField = false;
	// reject non-assignable members
	else static if (!__traits(compiles, testAssign!()())) enum isRWField = false;
	else static if (anySatisfy!(isSomeFunction, __traits(getMember, T, M))) {
		// If M is a function, reject if not @property or returns by ref
		private enum FA = functionAttributes!(__traits(getMember, T, M));
		enum isRWField = (FA & FunctionAttribute.property) != 0;
	} else {
		enum isRWField = true;
	}
}

unittest {
	import std.algorithm;

	struct S {
		alias a = int; // alias
		int i; // plain RW field
		enum j = 42; // manifest constant
		static int k = 42; // static field
		private int privateJ; // private RW field

		this(Args...)(Args args) {}

		// read-write property (OK)
		@property int p1() { return privateJ; }
		@property void p1(int j) { privateJ = j; }
		// read-only property (NO)
		@property int p2() { return privateJ; }
		// write-only property (NO)
		@property void p3(int value) { privateJ = value; }
		// ref returning property (OK)
		@property ref int p4() { return i; }
		// parameter-less template property (OK)
		@property ref int p5()() { return i; }
		// not treated as a property by DMD, so not a field
		@property int p6()() { return privateJ; }
		@property void p6(int j)() { privateJ = j; }

		static @property int p7() { return k; }
		static @property void p7(int value) { k = value; }

		ref int f1() { return i; } // ref returning function (no field)

		int f2(Args...)(Args args) { return i; }

		ref int f3(Args...)(Args args) { return i; }

		void someMethod() {}

		ref int someTempl()() { return i; }
	}

	enum plainFields = ["i"];
	enum fields = ["i", "p1", "p4", "p5"];

	foreach (mem; __traits(allMembers, S)) {
		static if (isRWField!(S, mem)) static assert(fields.canFind(mem), mem~" detected as field.");
		else static assert(!fields.canFind(mem), mem~" not detected as field.");

		static if (isRWPlainField!(S, mem)) static assert(plainFields.canFind(mem), mem~" not detected as plain field.");
		else static assert(!plainFields.canFind(mem), mem~" not detected as plain field.");
	}
}

package T Tgen(T)(){ return T.init; }


/**
	Tests if the protection of a member is public.
*/
template isPublicMember(T, string M)
{
	import std.algorithm;

	static if (!__traits(compiles, TypeTuple!(__traits(getMember, T, M)))) enum isPublicMember = false;
	else {
		alias MEM = TypeTuple!(__traits(getMember, T, M));
		enum isPublicMember = __traits(getProtection, MEM).among("public", "export");
	}
}

unittest {
	class C {
		int a;
		export int b;
		protected int c;
		private int d;
		package int e;
		void f() {}
		static void g() {}
		private void h() {}
		private static void i() {}
	}

	static assert (isPublicMember!(C, "a"));
	static assert (isPublicMember!(C, "b"));
	static assert (!isPublicMember!(C, "c"));
	static assert (!isPublicMember!(C, "d"));
	static assert (!isPublicMember!(C, "e"));
	static assert (isPublicMember!(C, "f"));
	static assert (isPublicMember!(C, "g"));
	static assert (!isPublicMember!(C, "h"));
	static assert (!isPublicMember!(C, "i"));

	struct S {
		int a;
		export int b;
		private int d;
		package int e;
	}
	static assert (isPublicMember!(S, "a"));
	static assert (isPublicMember!(S, "b"));
	static assert (!isPublicMember!(S, "d"));
	static assert (!isPublicMember!(S, "e"));

	S s;
	s.a = 21;
	assert(s.a == 21);
}

/**
	Tests if a member requires $(D this) to be used.
*/
template isNonStaticMember(T, string M)
{
	import std.typetuple;
	import std.traits;

	alias MF = TypeTuple!(__traits(getMember, T, M));
	static if (M.length == 0) {
		enum isNonStaticMember = false;
	} else static if (anySatisfy!(isSomeFunction, MF)) {
		enum isNonStaticMember = !__traits(isStaticFunction, MF);
	} else {
		enum isNonStaticMember = !__traits(compiles, (){ auto x = __traits(getMember, T, M); }());
	}
}

unittest { // normal fields
	struct S {
		int a;
		static int b;
		enum c = 42;
		void f();
		static void g();
		ref int h() { return a; }
		static ref int i() { return b; }
	}
	static assert(isNonStaticMember!(S, "a"));
	static assert(!isNonStaticMember!(S, "b"));
	static assert(!isNonStaticMember!(S, "c"));
	static assert(isNonStaticMember!(S, "f"));
	static assert(!isNonStaticMember!(S, "g"));
	static assert(isNonStaticMember!(S, "h"));
	static assert(!isNonStaticMember!(S, "i"));
}

unittest { // tuple fields
	struct S(T...) {
		T a;
		static T b;
	}

	alias T = S!(int, float);
	auto p = T.b;
	static assert(isNonStaticMember!(T, "a"));
	static assert(!isNonStaticMember!(T, "b"));

	alias U = S!();
	static assert(!isNonStaticMember!(U, "a"));
	static assert(!isNonStaticMember!(U, "b"));
}
