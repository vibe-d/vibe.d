/**
	Helper module for vibe.http.rest that contains various utility templates and functions
	that use D static introspection capabilities. Separated to keep main module concentrated
	on HTTP/API related functionality. Is not intended for direct usage but some utilities here
	are pretty general.

	Some of the templates/functions may someday make their way into wider use.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Михаил Страшун
*/

module vibe.http.restutil;

import vibe.http.common;

import std.traits, std.string, std.algorithm, std.range, std.array;

public import std.typetuple, std.typecons;

///	Distinguishes getters from setters by their function signatures.
template isPropertyGetter(T)
{
	enum isPropertyGetter = (functionAttributes!(T) & FunctionAttribute.property) != 0
		&& !is(ReturnType!T == void);
}

/// Close relative of isPropertyGetter
template isPropertySetter(T)
{
	enum isPropertySetter = (functionAttributes!(T) & FunctionAttribute.property) != 0
		&& is(ReturnType!T == void);
}

unittest
{
	interface Sample
	{
		@property int getter();
		@property void setter(int);
		int simple();
	}

	static assert(isPropertyGetter!(typeof(&Sample.getter)));
	static assert(!isPropertyGetter!(typeof(&Sample.simple)));
	static assert(isPropertySetter!(typeof(&Sample.setter)));
}

/**
	Clones function signature including its name so that resulting string
	can be mixed into descendant class to override it. All symbols in
	resulting string are fully qualified.
 */
template cloneFunction(alias Symbol)
	if (isSomeFunction!(Symbol))
{
	private:
		alias FunctionTypeOf!(Symbol) T;

		static if (is(T F == delegate) || isFunctionPointer!T)
			static assert(0, "Plain function or method symbol are expected");

	    // Phobos has fullyQualifiedName implementation for types only since 2.062
		import std.compiler;
		static if ((D_major == 2) && (D_minor >= 62U))
			alias std.traits.fulllyQualifiedName fqn;
		else
			alias vibe.http.restutil.legacyfullyQualifiedName fqn;

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
			if (qualifiers[_shared])
			{
				result = format("shared(%s)", result);
			}
			if (qualifiers[_const] || qualifiers[_immutable] || qualifiers[_inout])
			{
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
			
			final switch (variadicFunctionStyle!T)
			{
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
			
			static if (parameters.length)
			{
				string result = join(
					map!(a => format("%s%s %s", a[0], a[1], a[2]))(
						zip([staticMap!(storageClassesString, parameterStC)],
				            [staticMap!(fqn, parameters)],
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
			static if (functionLinkage!T != "D")
				enum string linkageString = format("extern(%s) ", functionLinkage!T);
			else
				enum string linkageString = "";
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

	public:

		enum string cloneFunction = addTypeQualifiers(
			format(
				"%s%s%s %s(%s)",
				linkageString!T,
				functionAttributeString!T,
				fqn!(ReturnType!T),
				__traits(identifier, Symbol),
				parametersString!Symbol()				
			)
		);
}

unittest
{
	class Test : QualifiedNameTests
	{
		import core.vararg;

		override:
			//pragma(msg, generateAll!QualifiedNameTests);
			mixin(generateAll!QualifiedNameTests);
	}
}

// Will be removed upon Phobos 2.063 release
private template legacyfullyQualifiedName(T)
{
	enum legacyfullyQualifiedName = legacyfullyQualifiedNameImpl!(
		T,
		false,
		false,
		false,
		false
	);
}

// Same as legacyfullyQualifiedName, it simply copies latest phobos implementation for now
// Thus not tested separately only as part of cloneFunction
private template legacyfullyQualifiedNameImpl(T,
	bool alreadyConst, bool alreadyImmutable, bool alreadyShared, bool alreadyInout)
{   
	import std.string;
	
	// Convenience tags
	enum {
		_const = 0,
		_immutable = 1,
		_shared = 2,
		_inout = 3
	}
	
	alias TypeTuple!(is(T == const), is(T == immutable), is(T == shared), is(T == inout)) qualifiers;
	alias TypeTuple!(false, false, false, false) noQualifiers;
	
	string storageClassesString(uint psc)() @property
	{
		alias ParameterStorageClass PSC;
		
		return format("%s%s%s%s",
			psc & PSC.scope_ ? "scope " : "",
			psc & PSC.out_ ? "out " : "",
			psc & PSC.ref_ ? "ref " : "",
			psc & PSC.lazy_ ? "lazy " : ""
		);
	}
	
	string parametersTypeString(T)() @property
	{
		import std.array, std.algorithm, std.range;
		
		alias ParameterTypeTuple!(T) parameters;
		alias ParameterStorageClassTuple!(T) parameterStC;
		
		enum variadic = variadicFunctionStyle!T;
		static if (variadic == Variadic.no)
			enum variadicStr = "";
		else static if (variadic == Variadic.c)
			enum variadicStr = ", ...";
		else static if (variadic == Variadic.d)
			enum variadicStr = parameters.length ? ", ..." : "...";
		else static if (variadic == Variadic.typesafe)
			enum variadicStr = " ...";
		else
			static assert(0, "New variadic style has been added, please update fullyQualifiedName implementation");
		
		static if (parameters.length)
		{
			string result = join(
				map!(a => format("%s%s", a[0], a[1]))(
				zip([staticMap!(storageClassesString, parameterStC)],
			    [staticMap!(fullyQualifiedName, parameters)])
				),
				", "
				);
			
			return result ~= variadicStr;
		}
		else
			return variadicStr;
	}
	
	string linkageString(T)() @property
	{
		enum linkage = functionLinkage!T;
		
		if (linkage != "D")
			return format("extern(%s) ", linkage);
		else
			return "";
	}
	
	string functionAttributeString(T)() @property
	{
		alias FunctionAttribute FA;
		enum attrs = functionAttributes!T;
		
		static if (attrs == FA.none)
			return "";
		else
			return format("%s%s%s%s%s%s",
				attrs & FA.pure_ ? " pure" : "",
				attrs & FA.nothrow_ ? " nothrow" : "",
				attrs & FA.ref_ ? " ref" : "",
				attrs & FA.property ? " @property" : "",
				attrs & FA.trusted ? " @trusted" : "",
				attrs & FA.safe ? " @safe" : ""
			);
	}
	
	string addQualifiers(string typeString,
		bool addConst, bool addImmutable, bool addShared, bool addInout)
	{
		auto result = typeString;
		if (addShared)
		{
			result = format("shared(%s)", result);
		}
		if (addConst || addImmutable || addInout)
		{
			result = format("%s(%s)",
			                addConst ? "const" :
			                addImmutable ? "immutable" : "inout",
			                result
			                );
		}
		return result;
	}
	
	// Convenience template to avoid copy-paste
	template chain(string current)
	{
		enum chain = addQualifiers(current,
		                           qualifiers[_const]     && !alreadyConst,
		                           qualifiers[_immutable] && !alreadyImmutable,
		                           qualifiers[_shared]    && !alreadyShared,
		                           qualifiers[_inout]     && !alreadyInout);
	}
	
	static if (is(T == string))
	{
		enum legacyfullyQualifiedNameImpl = "string";
	}
	else static if (is(T == wstring))
	{
		enum legacyfullyQualifiedNameImpl = "wstring";
	}
	else static if (is(T == dstring))
	{
		enum legacyfullyQualifiedNameImpl = "dstring";
	}
	else static if (isBasicType!T || is(T == enum))
	{
		enum legacyfullyQualifiedNameImpl = chain!((Unqual!T).stringof);
	}
	else static if (isAggregateType!T)
	{
		enum legacyfullyQualifiedNameImpl = chain!(fullyQualifiedName!T);
	}
	else static if (isStaticArray!T)
	{
		import std.conv;
		
		enum legacyfullyQualifiedNameImpl = chain!(
			format("%s[%s]", legacyfullyQualifiedNameImpl!(typeof(T.init[0]), qualifiers), T.length)
			);
	}
	else static if (isArray!T)
	{
		enum legacyfullyQualifiedNameImpl = chain!(
			format("%s[]", legacyfullyQualifiedNameImpl!(typeof(T.init[0]), qualifiers))
			);
	}
	else static if (isAssociativeArray!T)
	{
		enum legacyfullyQualifiedNameImpl = chain!(
			format("%s[%s]", legacyfullyQualifiedNameImpl!(ValueType!T, qualifiers), legacyfullyQualifiedNameImpl!(KeyType!T, noQualifiers))
			);
	}
	else static if (isSomeFunction!T)
	{
		static if (is(T F == delegate))
		{
			enum qualifierString = format("%s%s",
				is(F == shared) ? " shared" : "",
				is(F == inout) ? " inout" :
				is(F == immutable) ? " immutable" :
				is(F == const) ? " const" : ""
			);
			enum formatStr = "%s%s delegate(%s)%s%s";
			enum legacyfullyQualifiedNameImpl = chain!(
				format(formatStr, linkageString!T, legacyfullyQualifiedNameImpl!(ReturnType!T, noQualifiers),
				parametersTypeString!(T), functionAttributeString!T, qualifierString)
				);
		}
		else
		{
			static if (isFunctionPointer!T)
				enum formatStr = "%s%s function(%s)%s";
			else
				enum formatStr = "%s%s(%s)%s";
			
			enum legacyfullyQualifiedNameImpl = chain!(
				format(formatStr, linkageString!T, legacyfullyQualifiedNameImpl!(ReturnType!T, noQualifiers),
				parametersTypeString!(T), functionAttributeString!T)
			);
		}
	}
	else static if (isPointer!T)
	{
		enum legacyfullyQualifiedNameImpl = chain!(
			format("%s*", legacyfullyQualifiedNameImpl!(PointerTarget!T, qualifiers))
			);
	}
	else
		// In case something is forgotten
		static assert(0, "Unrecognized type " ~ T.stringof ~ ", can't convert to fully qualified string");
}

/**
	Returns a tuple consisting of all symbols type T consists of
	that may need explicit qualification. Implementation is incomplete
	and tuned for REST interface generation needs.
 */
template getSymbols(T)
{
	import std.typetuple;

	static if (isAggregateType!T || is(T == enum))
	{
		alias TypeTuple!T getSymbols;
	}
	else static if (isStaticArray!T || isArray!T)
	{
		alias getSymbols!(typeof(T.init[0])) getSymbols;
	}
	else static if (isAssociativeArray!T)
	{
		alias TypeTuple!(getSymbols!(ValueType!T) , getSymbols!(KeyType!T)) getSymbols;
	}
	else static if (isPointer!T)
	{
		alias getSymbols!(PointerTarget!T) getSymbols;
	}
	else
		alias TypeTuple!() getSymbols;
}

unittest
{   
	alias QualifiedNameTests.Inner symbol;
	enum target1 = TypeTuple!(symbol).stringof;
	enum target2 = TypeTuple!(symbol, symbol).stringof;
	static assert(getSymbols!(symbol[10]).stringof == target1);
	static assert(getSymbols!(symbol[]).stringof == target1);
	static assert(getSymbols!(symbol).stringof == target1);
	static assert(getSymbols!(symbol[symbol]).stringof == target2);
	static assert(getSymbols!(int).stringof == TypeTuple!().stringof);
}

version(unittest)
{
	private:
		// data structure used in most unit tests
		interface QualifiedNameTests
		{
			static struct Inner
			{
			}

			const(Inner[]) func1(ref string name);
			ref int func1();
			shared(Inner[4]) func2(...) const;
			immutable(int[string]) func3(in Inner anotherName) @safe;
		}

		// helper for cloneFunction unit-tests that clones all method declarations of given interface,
		string generateAll(alias iface)()
		{
			if (!__ctfe)
				assert(false);

			string result;
			foreach (method; __traits(allMembers, iface))
			{
				foreach (overload; MemberFunctionsTuple!(iface, method))
				{
					result ~= cloneFunction!overload;
					result ~= "{ static typeof(return) ret; return ret; }";
					result ~= "\n";
				}
			}
			return result;
		}
}

template ReturnTypeString(alias F)
{   
	alias ReturnType!F T;
	static if (returnsRef!F)  
		enum ReturnTypeString = "ref " ~ fullyQualifiedTypeName!T;
	else
		enum ReturnTypeString = legacyfullyQualifiedName!T;
}

private template returnsRef(alias f)
{
	enum bool returnsRef = is(typeof(
	{
		ParameterTypeTuple!f param;
		auto ptr = &f(param);
	}));
}


template temporary_packageName(alias T)
{
    static if (is(typeof(__traits(parent, T))))
        enum parent = packageName!(__traits(parent, T));
    else
        enum string parent = null;

    static if (T.stringof.startsWith("package "))
        enum packageName = (parent ? parent ~ "." : "") ~ T.stringof[8 .. $];
    else static if (parent)
        enum packageName = parent;
    else
        static assert(false, T.stringof ~ " has no parent");
}

template temporary_moduleName(alias T)
{
    static assert(!T.stringof.startsWith("package "), "cannot get the module name for a package");

    static if (T.stringof.startsWith("module "))
    {
        static if (__traits(compiles, packageName!T))
            enum packagePrefix = packageName!T ~ '.';
        else
            enum packagePrefix = "";

        enum temporary_moduleName = packagePrefix ~ T.stringof[7..$];
    }
    else
        alias temporary_moduleName!(__traits(parent, T)) temporary_moduleName;
}
