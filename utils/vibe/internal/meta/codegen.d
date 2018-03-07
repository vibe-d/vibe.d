/**
	Templates and CTFE-functions useful for type introspection during  code generation.

	Some of those are very similar to `traits` utilities but instead of general type
	information focus on properties that are most important during such code generation.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Михаил Страшун
*/

module vibe.internal.meta.codegen;

import std.traits : FunctionTypeOf, isSomeFunction;

/*
	As user types defined inside unittest blocks don't have proper parent
	module, those need to be defined outside for tests that require module
	inspection for some reasons. All such tests use single declaration
	compiled in this module in unittest version.
*/
version(unittest)
{
	private:
		interface TestInterface
		{
			static struct Inner
			{
			}

			const(Inner[]) func1(ref string name);
			ref int func1();
			shared(Inner[4]) func2(...) const;
			immutable(int[string]) func3(in Inner anotherName) @safe;
		}
}

/**
	For a given type T finds all user-defined symbols it embeds.

	Important property of such symbols is that they are likely to
	need an explicit import if used in some other scope / module.

	Implementation is incomplete and tuned for REST interface generation needs.

	Params:
		T = type to introspect for qualified symbols

	Returns:
		tuple of "interesting" symbols, no duplicates
*/
template getSymbols(T)
{
	import std.typetuple : TypeTuple, NoDuplicates, staticMap;
	import std.traits;

	private template Implementation(T)
	{
		static if (is(T == U!V, alias U, V)) { // single-argument template support
			alias Implementation = TypeTuple!(U, Implementation!V);
		}
		else static if (isAggregateType!T || is(T == enum)) {
			alias Implementation = T;
		}
		else static if (isStaticArray!T || isArray!T) {
			alias Implementation = Implementation!(typeof(T.init[0]));
		}
		else static if (isAssociativeArray!T) {
			alias Implementation = TypeTuple!(
				Implementation!(ValueType!T),
				Implementation!(KeyType!T)
			);
		}
		else static if (isPointer!T) {
			alias Implementation = Implementation!(PointerTarget!T);
		}
		else
			alias Implementation = TypeTuple!();
	}

	alias getSymbols = NoDuplicates!(Implementation!T);
}

///
unittest
{
	import std.typetuple : TypeTuple;

	struct A {}
	interface B {}
	alias Type = A[const(B[A*])];
	struct C(T) {}

	// can't directly compare tuples thus comparing their string representation
	static assert (getSymbols!Type.stringof == TypeTuple!(A, B).stringof);
	static assert (getSymbols!int.stringof == TypeTuple!().stringof);
	static assert (getSymbols!(C!A).stringof == TypeTuple!(C, A).stringof);
}

/**
	For a given interface I finds all modules that types in its methods
	come from.

	These modules need to be imported in the scope code generated from I
	is used to avoid errors with unresolved symbols for user types.

	Params:
		I = interface to inspect

	Returns:
		list of module name strings, no duplicates
*/
string[] getRequiredImports(I)()
	if (is(I == interface))
{
	import std.traits : MemberFunctionsTuple, moduleName,
		ParameterTypeTuple, ReturnType;

	if( !__ctfe )
		assert(false);

	bool[string] visited;
	string[] ret;

	void addModule(string name)
	{
		if (name !in visited) {
			ret ~= name;
			visited[name] = true;
		}
	}

	foreach (method; __traits(allMembers, I)) {
		// WORKAROUND #1045 / @@BUG14375@@
		static if (method.length != 0)
		foreach (overload; MemberFunctionsTuple!(I, method)) {
			alias FuncType = FunctionTypeOf!overload;

			foreach (symbol; getSymbols!(ReturnType!FuncType)) {
				static if (__traits(compiles, moduleName!symbol)) {
					addModule(moduleName!symbol);
				}
			}

			foreach (P; ParameterTypeTuple!FuncType) {
				foreach (symbol; getSymbols!P) {
					static if (__traits(compiles, moduleName!symbol)) {
						addModule(moduleName!symbol);
					}
				}
			}
		}
	}

	return ret;
}

///
unittest
{
	// `Test` is an interface using single user type
	enum imports = getRequiredImports!TestInterface;
	static assert (imports.length == 1);
	static assert (imports[0] == "vibe.internal.meta.codegen");
}

/**
 * Returns a Tuple of the parameters.
 * It can be used to declare function.
 */
template ParameterTuple(alias Func)
{
	static if (is(FunctionTypeOf!Func Params == __parameters)) {
		alias ParameterTuple = Params;
	} else static assert(0, "Argument to ParameterTuple must be a function");
}

///
unittest
{
	void foo(string val = "Test", int = 10);
	void bar(ParameterTuple!foo) { assert(val == "Test"); }
	// Variadic functions require special handling:
	import core.vararg;
	void foo2(string val, ...);
	void bar2(ParameterTuple!foo2, ...) { assert(val == "42"); }

	bar();
	bar2("42");

	// Note: outside of a parameter list, it's value is the type of the param.
	import std.traits : ParameterDefaultValueTuple;
	ParameterTuple!(foo)[0] test = ParameterDefaultValueTuple!(foo)[0];
	assert(test == "Test");
}

/// Returns a Tuple containing a 1-element parameter list, with an optional default value.
/// Can be used to concatenate a parameter to a parameter list, or to create one.
template ParameterTuple(T, string identifier, DefVal : void = void)
{
	import std.string : format;
	mixin(q{private void __func(T %s);}.format(identifier));
	alias ParameterTuple = ParameterTuple!__func;
}


/// Ditto
template ParameterTuple(T, string identifier, alias DefVal)
{
	import std.string : format;
	mixin(q{private void __func(T %s = DefVal);}.format(identifier));
	alias ParameterTuple = ParameterTuple!__func;
}

///
unittest
{
	void foo(ParameterTuple!(int, "arg2")) { assert(arg2 == 42); }
	foo(42);

	void bar(string arg);
	void bar2(ParameterTuple!bar, ParameterTuple!(string, "val")) { assert(val == arg); }
	bar2("isokay", "isokay");

	// For convenience, you can directly pass the result of std.traits.ParameterDefaultValueTuple
	// without checking for void.
	import std.traits : PDVT = ParameterDefaultValueTuple;
	import std.traits : arity;
	void baz(string test, int = 10);

	static assert(is(PDVT!(baz)[0] == void));
	// void baz2(string test2, string test);
	void baz2(ParameterTuple!(string, "test2", PDVT!(baz)[0]), ParameterTuple!(baz)[0..$-1]) { assert(test == test2); }
	static assert(arity!baz2 == 2);
	baz2("Try", "Try");

	// void baz3(string test, int = 10, int ident = 10);
	void baz3(ParameterTuple!baz, ParameterTuple!(int, "ident", PDVT!(baz)[1])) { assert(ident == 10); }
	baz3("string");

	import std.datetime;
	void baz4(ParameterTuple!(SysTime, "epoch", Clock.currTime)) { assert((Clock.currTime - epoch) < 30.seconds); }
	baz4();

	// Convertion are possible for default parameters...
	alias baz5PT = ParameterTuple!(SysTime, "epoch", uint.min);

	// However this blows up because of @@bug 14369@@
	// alias baz6PT = ParameterTuple!(SysTime, "epoch", PDVT!(baz4)[0]));

	alias baz7PT = ParameterTuple!(SysTime, "epoch", uint.max);
	// Non existing convertion are detected.
	static assert(!__traits(compiles, { alias baz7PT = ParameterTuple!(SysTime, "epoch", Object.init); }));
	// And types are refused
	static assert(!__traits(compiles, { alias baz7PT = ParameterTuple!(SysTime, "epoch", uint); }));
}

/// Returns a string of the functions attributes, suitable to be mixed
/// on the LHS of the function declaration.
///
/// Unfortunately there is no "nice" syntax for declaring a function,
/// so we have to resort on string for functions attributes.
template FuncAttributes(alias Func)
{
	import std.array : join;
	enum FuncAttributes = [__traits(getFunctionAttributes, Func)].join(" ");
}



/// A template mixin which allow you to clone a function, and specify the implementation.
///
/// Params:
/// Func       = An alias to the function to copy.
/// body_      = The implementation of the class which will be mixed in.
/// keepUDA    = Whether or not to copy UDAs. Since the primary use case for this template
///                is implementing classes from interface, this defaults to $(D false).
/// identifier = The identifier to give to the new function. Default to the identifier of
///                $(D Func).
///
/// See_Also: $(D CloneFunctionDecl) to clone a prototype.
mixin template CloneFunction(alias Func, string body_, bool keepUDA = false, string identifier = __traits(identifier, Func))
{
	// Template mixin: everything has to be self-contained.
	import std.format : format;
	import std.traits : ReturnType, variadicFunctionStyle, Variadic;
	import std.typetuple : TypeTuple;
	import vibe.internal.meta.codegen : ParameterTuple, FuncAttributes;
	// Sadly this is not possible:
	// class Test {
	//   int foo(string par) pure @safe nothrow { /* ... */ }
	//   typeof(foo) bar {
	//      return foo(par);
	//   }
	// }
	static if (keepUDA)
		private alias UDA = TypeTuple!(__traits(getAttributes, Func));
	else
		private alias UDA = TypeTuple!();
	static if (variadicFunctionStyle!Func == Variadic.no) {
		mixin(q{
				@(UDA) ReturnType!Func %s(ParameterTuple!Func) %s {
					%s
				}
			}.format(identifier, FuncAttributes!Func, body_));
	} else static if (variadicFunctionStyle!Func == Variadic.typesafe) {
		mixin(q{
				@(UDA) ReturnType!Func %s(ParameterTuple!Func...) %s {
					%s
				}
			}.format(identifier, FuncAttributes!Func, body_));
	} else
		static assert(0, "Variadic style " ~ variadicFunctionStyle!Func.stringof
					  ~ " not implemented.");
}

///
unittest
{
	import std.typetuple : TypeTuple;

	interface ITest
	{
		@("42") int foo(string par, int, string p = "foo", int = 10) pure @safe nothrow const;
		@property int foo2() pure @safe nothrow const;
		// Issue #1144
		void variadicFun(ref size_t bar, string[] args...);
		// Gives weird error message, not supported so far
		//bool variadicDFun(...);
	}

	class Test : ITest
	{
		mixin CloneFunction!(ITest.foo, q{return 84;}, false, "customname");
	override:
		mixin CloneFunction!(ITest.foo, q{return 42;}, true);
		mixin CloneFunction!(ITest.foo2, q{return 42;});
		mixin CloneFunction!(ITest.variadicFun, q{bar = args.length;});
		//mixin CloneFunction!(ITest.variadicDFun, q{return true;});
	}

	// UDA tests
	static assert(__traits(getAttributes, Test.customname).length == 0);
	static assert(__traits(getAttributes, Test.foo2).length == 0);
	static assert(__traits(getAttributes, Test.foo) == TypeTuple!("42"));

	assert(new Test().foo("", 21) == 42);
	assert(new Test().foo2 == 42);
	assert(new Test().customname("", 21) == 84);

	size_t l;
	new Test().variadicFun(l, "Hello", "variadic", "world");
	assert(l == 3);

	//assert(new Test().variadicDFun("Hello", "again", "variadic", "world"));
}

/// A template mixin which allow you to clone a function declaration
///
/// Params:
/// Func       = An alias to the function to copy.
/// keepUDA    = Whether or not to copy UDAs. Since the primary use case for this template
///                is copying a definition, this defaults to $(D true).
/// identifier = The identifier to give to the new function. Default to the identifier of
///                $(D Func).
///
/// See_Also : $(D CloneFunction) to implement a function.
mixin template CloneFunctionDecl(alias Func, bool keepUDA = true, string identifier = __traits(identifier, Func))
{
	// Template mixin: everything has to be self-contained.
	import std.format : format;
	import std.traits : ReturnType, variadicFunctionStyle, Variadic;
	import std.typetuple : TypeTuple;
	import vibe.internal.meta.codegen : ParameterTuple, FuncAttributes;

	static if (keepUDA)
		private enum UDA = q{@(TypeTuple!(__traits(getAttributes, Func)))};
	else
		private enum UDA = "";

	static if (variadicFunctionStyle!Func == Variadic.no) {
		mixin(q{
				%s ReturnType!Func %s(ParameterTuple!Func) %s;
			}.format(UDA, identifier, FuncAttributes!Func));
	} else static if (variadicFunctionStyle!Func == Variadic.typesafe) {
		mixin(q{
				%s ReturnType!Func %s(ParameterTuple!Func...) %s;
			}.format(UDA, identifier, FuncAttributes!Func));
	} else
		static assert(0, "Variadic style " ~ variadicFunctionStyle!Func.stringof
					  ~ " not implemented.");

}

///
unittest {
	import std.typetuple : TypeTuple;

	enum Foo;
	interface IUDATest {
		@(Foo, "forty-two", 42) const(Object) bar() @safe;
	}
	interface UDATest {
		mixin CloneFunctionDecl!(IUDATest.bar);
	}
	// Tuples don't like when you compare types using '=='.
	static assert(is(TypeTuple!(__traits(getAttributes, UDATest.bar))[0] == Foo));
	static assert(__traits(getAttributes, UDATest.bar)[1 .. $] == TypeTuple!("forty-two", 42));
}
