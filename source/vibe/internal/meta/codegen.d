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
	import std.typetuple : TypeTuple, NoDuplicates;
	import std.traits;

	private template Implementation(T)
	{
		static if (isAggregateType!T || is(T == enum)) {
			alias Implementation = TypeTuple!T;
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

	// can't directly compare tuples thus comparing their string representation
	static assert (getSymbols!Type.stringof == TypeTuple!(A, B).stringof);
	static assert (getSymbols!int.stringof == TypeTuple!().stringof);
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
	Clones function declaration.
	
	Acts similar to std.traits.fullyQualifiedName run on function typem
	but includes original name so that resulting string can be mixed into
	descendant class to override it. All symbols in resulting string are
	fully qualified.

	Probably it can be merged with fullyQualifiedName to form a more 
	generic method but no elegant solution was proposed so far.

	Params:
		Symbol = function declaration to clone

	Returns:
		string that can be mixed in to declare exact duplicate of Symbol
 */
template cloneFunction(alias Symbol)
	if (isSomeFunction!(Symbol))
{
	private:
		import std.traits, std.typetuple;

		alias FunctionTypeOf!(Symbol) T;

		static if (is(T F == delegate) || isFunctionPointer!T)
			static assert(0, "Plain function or method symbols are expected");

		static string addTypeQualifiers(string type)
		{
			enum {
				_const = 0,
				_immutable = 1,
				_shared = 2,
				_inout = 3
			}

			alias TypeTuple!(is(T == const), is(T == immutable), is(T == shared), is(T == inout)) qualifiers;
			
			auto result = type;

			if (qualifiers[_shared]) {
				result = format("shared(%s)", result);
			}

			if (qualifiers[_const] || qualifiers[_immutable] || qualifiers[_inout]) {
				result = format(
					"%s %s",
					result,
					qualifiers[_const] ? "const" : (qualifiers[_immutable] ? "immutable" : "inout")
                );
			}

			return result;
		}		

		template storageClassesString(uint psc)
		{
			alias ParameterStorageClass PSC;
			
			enum storageClassesString = format(
				"%s%s%s%s",
				psc & PSC.scope_ ? "scope " : "",
				psc & PSC.out_ ? "out " : "",
				psc & PSC.ref_ ? "ref " : "",
				psc & PSC.lazy_ ? "lazy " : ""
			);
		}
		
		string parametersString(alias T)()
		{
			if (!__ctfe)
				assert(false);
			
			alias ParameterTypeTuple!T parameters;
			alias ParameterStorageClassTuple!T parameterStC;
			alias ParameterIdentifierTuple!T parameterNames;
			
			string variadicStr;
			
			final switch (variadicFunctionStyle!T) {
				case Variadic.no:
					variadicStr = "";
					break;
				case Variadic.c:
					variadicStr = ", ...";
					break;
				case Variadic.d:
					variadicStr = parameters.length ? ", ..." : "...";
					break;
				case Variadic.typesafe:
					variadicStr = " ...";
					break;
			}
			
			static if (parameters.length) {
				import std.algorithm : map;
				import std.range : join, zip;

				string result = join(
					map!(a => format("%s%s %s", a[0], a[1], a[2]))(
						zip([staticMap!(storageClassesString, parameterStC)],
				            [staticMap!(fullyQualifiedName, parameters)],
			                [parameterNames])
					),
					", "
				);
				
				return result ~= variadicStr;
			}
			else
				return variadicStr;
		}
		
		template linkageString(T)
		{
			static if (functionLinkage!T != "D") {
				enum string linkageString = format("extern(%s) ", functionLinkage!T);
			}
			else {
				enum string linkageString = "";
			}
		}
		
		template functionAttributeString(T)
		{
			alias FunctionAttribute FA;
			enum attrs = functionAttributes!T;
			
			static if (attrs == FA.none)
				enum string functionAttributeString = "";
			else
				enum string functionAttributeString = format(
					"%s%s%s%s%s%s",
					attrs & FA.pure_ ? "pure " : "",
					attrs & FA.nothrow_ ? "nothrow " : "",
					attrs & FA.ref_ ? "ref " : "",
					attrs & FA.property ? "@property " : "",
					attrs & FA.trusted ? "@trusted " : "",
					attrs & FA.safe ? "@safe " : ""
				);
		}

	public {
		import std.string : format;

		enum string cloneFunction = addTypeQualifiers(
			format(
				"%s%s%s %s(%s)",
				linkageString!T,
				functionAttributeString!T,
				fullyQualifiedName!(ReturnType!T),
				__traits(identifier, Symbol),
				parametersString!Symbol()				
			)
		);
	}
}

///
unittest
{
	static int foo(double[] param);

	static assert(cloneFunction!foo == "int foo(double[] param)");
}

version(unittest)
{
	// helper for cloneFunction unit-tests that clones all method declarations of given interface,
	string generateStubMethods(alias iface)()
	{
		if (!__ctfe)
			assert(false);

		import std.traits : MemberFunctionsTuple;

		string result;
		foreach (method; __traits(allMembers, iface)) {
			foreach (overload; MemberFunctionsTuple!(iface, method)) {
				result ~= cloneFunction!overload;
				result ~= "{ static typeof(return) ret; return ret; }";
				result ~= "\n";
			}
		}
		return result;
	}
}

unittest
{
	class TestClass : TestInterface
	{
		import core.vararg;

		override:
			mixin(generateStubMethods!TestInterface);
	}

	// any mismatch in types between class and interface will be a compile-time
	// error, no extra asserts needed
}
