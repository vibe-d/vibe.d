/**
	Helpers for working with user-defined attributes that can be attached to
	function or method to modify its behavior. In some sense those are similar to
	Python decorator. D does not support this feature natively but
	it can be emulated within certain code generation framework.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Михаил Страшун
 */

module vibe.internal.meta.funcattr;

import std.traits : isInstanceOf, ReturnType;
import vibe.internal.meta.traits : RecursiveFunctionAttributes;

/// example
unittest
{
	struct Context
	{
		int increment;
		string token;
		bool updated = false;
	}

	static int genID(Context* context)
	{
		static int id = 0;
		return (id += context.increment);
	}

	static string update(string result, Context* context)
	{
		context.updated = true;
		return result ~ context.token;
	}

	class API
	{
		@before!genID("id") @after!update()
		string handler(int id, string name, string text)
		{
			import std.string : format;

			return format("[%s] %s : %s", id, name, text);
		}
	}

	auto api = new API();
	auto context = new Context(5, " | token");
	auto funcattr = createAttributedFunction!(API.handler)(context);
	auto result = funcattr(&api.handler, "Developer", "Hello, World!");

	assert (result == "[5] Developer : Hello, World! | token");
	assert (context.updated);
}

/**
	Marks function/method for usage with `AttributedFunction`.

	Former will call a Hook before calling attributed function/method and
	provide its return value as input parameter.

	Params:
		Hook = function/method symbol to run before attributed function/method
		parameter_name = name in attributed function/method parameter list to bind result to

	Returns:
		internal attribute struct that embeds supplied information
*/
auto before(alias Hook)(string parameter_name)
{
	return InputAttribute!Hook(parameter_name);
}

///
unittest
{
	int genID() { return 42; }

	@before!genID("id")
	void foo(int id, double something) {}
}

/**
	Marks function/method for usage with `AttributedFunction`.

	Former will call a Hook after calling attributed function/method and provide
	its return value as a single input parameter for a Hook.

	There can be only one "after"-attribute attached to a single symbol.

	Params:
		Hook = function/method symbol to run after attributed function/method

	Returns:
		internal attribute struct that embeds supplied information
*/
@property auto after(alias Hook)()
{
	return OutputAttribute!Hook();
}

///
unittest
{
	auto filter(int result)
	{
		return result;
	}

	@after!filter()
	int foo() { return 42; }
}
/**
	Checks if parameter is calculated by one of attached
	functions.

	Params:
		Function = function symbol to query for attributes
		name = parameter name to check

	Returns:
		`true` if it is calculated
*/
template IsAttributedParameter(alias Function, string name)
{
	import std.traits : FunctionTypeOf;

	static assert (is(FunctionTypeOf!Function));

	private {
		alias Data = AttributedParameterMetadata!Function;

		template Impl(T...)
		{
			static if (T.length == 0) {
				enum Impl = false;
			}
			else {
				static if (T[0].name == name) {
					enum Impl = true;
				}
				else {
					enum Impl = Impl!(T[1..$]);
				}
			}
		}
	}

	enum IsAttributedParameter = Impl!Data;
}

template HasFuncAttributes(alias Func)
{
	import std.typetuple;
	enum HasFuncAttributes = (anySatisfy!(isOutputAttribute, __traits(getAttributes, Func))
							  || anySatisfy!(isInputAttribute, __traits(getAttributes, Func)));
}

unittest {
	string foo() { return "Hello"; }
	string bar(int) { return foo(); }

	@before!foo("b") void baz1(string b) {}
	@after!bar() string baz2() { return "Hi"; }
	@before!foo("b") @after!bar() string baz3(string b) { return "Hi"; }

	static assert (HasFuncAttributes!baz1);
	static assert (HasFuncAttributes!baz2);
	static assert (HasFuncAttributes!baz3);

	string foobar1(string b) { return b; }
	@("Irrelevant", 42) string foobar2(string b) { return b; }

	static assert (!HasFuncAttributes!foobar1);
	static assert (!HasFuncAttributes!foobar2);
}

/**
	Computes the given attributed parameter using the corresponding @before modifier.
*/
auto computeAttributedParameter(alias FUNCTION, string NAME, ARGS...)(ARGS args)
{
	import std.meta : Filter;
	static assert(IsAttributedParameter!(FUNCTION, NAME), "Missing @before attribute for parameter "~NAME);
	alias input_attributes = Filter!(isInputAttribute, RecursiveFunctionAttributes!FUNCTION);
	foreach (att; input_attributes)
		static if (att.parameter == NAME) {
			return att.evaluator(args);
		}
	assert(false);
}


/**
	Computes the given attributed parameter using the corresponding @before modifier.

	This overload tries to invoke the given function as a member of the $(D ctx)
	parameter. It also supports accessing private member functions using the
	$(D PrivateAccessProxy) mixin.
*/
auto computeAttributedParameterCtx(alias FUNCTION, string NAME, T, ARGS...)(T ctx, ARGS args)
{
	import std.meta : AliasSeq, Filter;
	static assert(IsAttributedParameter!(FUNCTION, NAME), "Missing @before attribute for parameter "~NAME);
	alias input_attributes = Filter!(isInputAttribute, RecursiveFunctionAttributes!FUNCTION);
	foreach (att; input_attributes)
		static if (att.parameter == NAME) {
			static if (!__traits(isStaticFunction, att.evaluator)) {
				static if (is(typeof(ctx.invokeProxy__!(att.evaluator)(args))))
					return ctx.invokeProxy__!(att.evaluator)(args);
				else return __traits(getMember, ctx, __traits(identifier, att.evaluator))(args);
			} else {
				return att.evaluator(args);
			}
		}
	assert(false);
}


/**
	Helper mixin to support private member functions for $(D @before) attributes.
*/
mixin template PrivateAccessProxy() {
	auto invokeProxy__(alias MEMBER, ARGS...)(ARGS args) { return MEMBER(args); }
}
///
unittest {
	class MyClass {
		@before!computeParam("param")
		void method(bool param)
		{
			assert(param == true);
		}

		private bool computeParam()
		{
			return true;
		}
	}
}


/**
	Processes the function return value using all @after modifiers.
*/
ReturnType!FUNCTION evaluateOutputModifiers(alias FUNCTION, ARGS...)(ReturnType!FUNCTION result, ARGS args)
{
	import std.string : format;
	import std.traits : ParameterTypeTuple, ReturnType, fullyQualifiedName;
	import std.typetuple : Filter;
	import vibe.internal.meta.typetuple : Compare, Group;

	alias output_attributes = Filter!(isOutputAttribute, RecursiveFunctionAttributes!FUNCTION);
	foreach (OA; output_attributes) {
		import std.typetuple : TypeTuple;

		static assert (
			Compare!(
				Group!(ParameterTypeTuple!(OA.modificator)),
				Group!(ReturnType!FUNCTION, ARGS)
			),
			format(
				"Output attribute function '%s%s' argument list " ~
				"does not match provided argument list %s",
				fullyQualifiedName!(OA.modificator),
				ParameterTypeTuple!(OA.modificator).stringof,
				TypeTuple!(ReturnType!FUNCTION, ARGS).stringof
			)
		);

		result = OA.modificator(result, args);
	}
	return result;
}

///
unittest
{
	int foo()
	{
		return 42;
	}

	@before!foo("name1")
	void bar(int name1, double name2)
	{
	}

	static assert (IsAttributedParameter!(bar, "name1"));
	static assert (!IsAttributedParameter!(bar, "name2"));
	static assert (!IsAttributedParameter!(bar, "oops"));
}

// internal attribute definitions
private {

	struct InputAttribute(alias Function)
	{
		alias evaluator = Function;
		string parameter;
	}

	struct OutputAttribute(alias Function)
	{
		alias modificator = Function;
	}

	template isInputAttribute(T...)
	{
		enum isInputAttribute = (T.length == 1) && isInstanceOf!(InputAttribute, typeof(T[0]));
	}

	unittest
	{
		void foo() {}

		enum correct = InputAttribute!foo("name");
		enum wrong = OutputAttribute!foo();

		static assert (isInputAttribute!correct);
		static assert (!isInputAttribute!wrong);
	}

	template isOutputAttribute(T...)
	{
		enum isOutputAttribute = (T.length == 1) && isInstanceOf!(OutputAttribute, typeof(T[0]));
	}

	unittest
	{
		void foo() {}

		enum correct = OutputAttribute!foo();
		enum wrong = InputAttribute!foo("name");

		static assert (isOutputAttribute!correct);
		static assert (!isOutputAttribute!wrong);
	}
}

//  tools to operate on InputAttribute tuple
private {

	// stores metadata for single InputAttribute "effect"
	struct Parameter
	{
		// evaluated parameter name
		string name;
		// that parameter index in attributed function parameter list
		int index;
		// fully qualified return type of attached function
		string type;
		// for non-basic types - module to import
		string origin;
	}

	/**
		Used to accumulate various parameter-related metadata in one
		tuple in one go.

		Params:
			Function = attributed functon / method symbol

		Returns:
			TypeTuple of Parameter instances, one for every Function
			parameter that will be evaluated from attributes.
	*/
	template AttributedParameterMetadata(alias Function)
	{
		import std.array : join;
		import std.typetuple : Filter, staticMap, staticIndexOf;
		import std.traits : ParameterIdentifierTuple, ReturnType,
			fullyQualifiedName, moduleName;

		private alias attributes = Filter!(
			isInputAttribute,
			RecursiveFunctionAttributes!Function
		);

		private	alias parameter_names = ParameterIdentifierTuple!Function;

		/*
			Creates single Parameter instance. Used in pair with
			staticMap.
		*/
		template BuildParameter(alias attribute)
		{
			enum name = attribute.parameter;

			static assert (
				is (ReturnType!(attribute.evaluator)) && !(is(ReturnType!(attribute.evaluator) == void)),
				"hook functions attached for usage with `AttributedFunction` " ~
				"must have a return type"
			);

			static if (is(typeof(moduleName!(ReturnType!(attribute.evaluator))))) {
				enum origin = moduleName!(ReturnType!(attribute.evaluator));
			}
			else {
				enum origin = "";
			}

			enum BuildParameter = Parameter(
				name,
				staticIndexOf!(name, parameter_names),
				fullyQualifiedName!(ReturnType!(attribute.evaluator)),
				origin
			);

			import std.string : format;

			static assert (
				BuildParameter.index >= 0,
				format(
					"You are trying to attach function result to parameter '%s' " ~
					"but there is no such parameter for '%s(%s)'",
					name,
					fullyQualifiedName!Function,
					join([ parameter_names ], ", ")
				)
			);
		}

		alias AttributedParameterMetadata = staticMap!(BuildParameter, attributes);
	}

	// no false attribute detection
	unittest
	{
		@(42) void foo() {}
		static assert (AttributedParameterMetadata!foo.length == 0);
	}

	// does not compile for wrong attribute data
	unittest
	{
		int attached1() { return int.init; }
		void attached2() {}

		@before!attached1("doesnotexist")
		void bar(int param) {}

		@before!attached2("param")
		void baz(int param) {}

		// wrong name
		static assert (!__traits(compiles, AttributedParameterMetadata!bar));
		// no return type
		static assert (!__traits(compiles, AttributedParameterMetadata!baz));
	}

	// generates expected tuple for valid input
	unittest
	{
		int attached1() { return int.init; }
		double attached2() { return double.init; }

		@before!attached1("two") @before!attached2("three")
		void foo(string one, int two, double three) {}

		alias result = AttributedParameterMetadata!foo;
		static assert (result.length == 2);
		static assert (result[0] == Parameter("two", 1, "int"));
		static assert (result[1] == Parameter("three", 2, "double"));
	}

	/**
		Combines types from arguments of initial `AttributedFunction` call
		with parameters (types) injected by attributes for that call.

		Used to verify that resulting argument list can be passed to underlying
		attributed function.

		Params:
			ParameterMeta = Group of Parameter instances for extra data to add into argument list
			ParameterList = Group of types from initial argument list

		Returns:
			type tuple of expected combined function argument list
	*/
	template MergeParameterTypes(alias ParameterMeta, alias ParameterList)
	{
		import vibe.internal.meta.typetuple : isGroup, Group;

		static assert (isGroup!ParameterMeta);
		static assert (isGroup!ParameterList);

		static if (ParameterMeta.expand.length) {
			enum Parameter meta = ParameterMeta.expand[0];

			static assert (meta.index <= ParameterList.expand.length);
			static if (meta.origin != "") {
				mixin("static import " ~ meta.origin ~ ";");
			}
			mixin("alias type = " ~ meta.type ~ ";");

			alias PartialResult = Group!(
				ParameterList.expand[0..meta.index],
				type,
				ParameterList.expand[meta.index..$]
			);

			alias MergeParameterTypes = MergeParameterTypes!(
				Group!(ParameterMeta.expand[1..$]),
				PartialResult
			);
		}
		else {
			alias MergeParameterTypes = ParameterList.expand;
		}
	}

	// normal
	unittest
	{
		import vibe.internal.meta.typetuple : Group, Compare;

		alias meta = Group!(
			Parameter("one", 2, "int"),
			Parameter("two", 3, "string")
		);

		alias initial = Group!( double, double, double );

		alias merged = Group!(MergeParameterTypes!(meta, initial));

		static assert (
			Compare!(merged, Group!(double, double, int, string, double))
		);
	}

	// edge
	unittest
	{
		import vibe.internal.meta.typetuple : Group, Compare;

		alias meta = Group!(
			Parameter("one", 3, "int"),
			Parameter("two", 4, "string")
		);

		alias initial = Group!( double, double, double );

		alias merged = Group!(MergeParameterTypes!(meta, initial));

		static assert (
			Compare!(merged, Group!(double, double, double, int, string))
		);
	}

	// out-of-index
	unittest
	{
		import vibe.internal.meta.typetuple : Group;

		alias meta = Group!(
			Parameter("one", 20, "int"),
		);

		alias initial = Group!( double );

		static assert (
			!__traits(compiles,  MergeParameterTypes!(meta, initial))
		);
	}

}

/**
	Entry point for `funcattr` API.

	Helper struct that takes care of calling given Function in a such
	way that part of its arguments are evalutated by attached input attributes
	(see `before`) and output gets post-processed by output attribute
	(see `after`).

	One such structure embeds single attributed function to call and
	specific argument type list that can be passed to attached functions.

	Params:
		Function = attributed function
		StoredArgTypes = Group of argument types for attached functions

*/
struct AttributedFunction(alias Function, alias StoredArgTypes)
{
	import std.traits : isSomeFunction, ReturnType, FunctionTypeOf,
		ParameterTypeTuple, ParameterIdentifierTuple;
	import vibe.internal.meta.typetuple : Group, isGroup, Compare;
	import std.functional : toDelegate;
	import std.typetuple : Filter;

	static assert (isGroup!StoredArgTypes);
	static assert (is(FunctionTypeOf!Function));

	/**
		Stores argument tuple for attached function calls

		Params:
			args = tuple of actual argument values
	*/
	void storeArgs(StoredArgTypes.expand args)
	{
		m_storedArgs = args;
	}

	/**
		Used to invoke configured function/method with
		all attached attribute functions.

		As aliased method symbols can't be called without
		the context, explicit providing of delegate to call
		is required

		Params:
			dg = delegated created from function / method to call
			args = list of arguments to dg not provided by attached attribute function

		Return:
			proxies return value of dg
	*/
	ReturnType!Function opCall(T...)(FunctionDg dg, T args)
	{
				import std.traits : fullyQualifiedName;
				import std.string : format;

		enum hasReturnType = is(ReturnType!Function) && !is(ReturnType!Function == void);

		static if (hasReturnType) {
			ReturnType!Function result;
		}

		// check that all attached functions have conforming argument lists
		foreach (uda; input_attributes) {
			static assert (
				Compare!(
					Group!(ParameterTypeTuple!(uda.evaluator)),
					StoredArgTypes
				),
				format(
					"Input attribute function '%s%s' argument list " ~
					"does not match provided argument list %s",
					fullyQualifiedName!(uda.evaluator),
					ParameterTypeTuple!(uda.evaluator).stringof,
					StoredArgTypes.expand.stringof
				)
			);
		}

		static if (hasReturnType) {
			result = prepareInputAndCall(dg, args);
		}
		else {
			prepareInputAndCall(dg, args);
		}

		static assert (
			output_attributes.length <= 1,
			"Only one output attribute (@after) is currently allowed"
		);

		static if (output_attributes.length) {
			import std.typetuple : TypeTuple;

			static assert (
				Compare!(
					Group!(ParameterTypeTuple!(output_attributes[0].modificator)),
					Group!(ReturnType!Function, StoredArgTypes.expand)
				),
				format(
					"Output attribute function '%s%s' argument list " ~
					"does not match provided argument list %s",
					fullyQualifiedName!(output_attributes[0].modificator),
					ParameterTypeTuple!(output_attributes[0].modificator).stringof,
					TypeTuple!(ReturnType!Function, StoredArgTypes.expand).stringof
				)
			);

			static if (hasReturnType) {
				result = output_attributes[0].modificator(result, m_storedArgs);
			}
			else {
				output_attributes[0].modificator(m_storedArgs);
			}
		}

		static if (hasReturnType) {
			return result;
		}
	}

	/**
		Convenience wrapper tha creates stub delegate for free functions.

		As those do not require context, passing delegate explicitly is not
		required.
	*/
	ReturnType!Function opCall(T...)(T args)
		if (!is(T[0] == delegate))
	{
		return this.opCall(toDelegate(&Function), args);
	}

	private {
		// used as an argument tuple when function attached
		// to InputAttribute is called
		StoredArgTypes.expand m_storedArgs;

		// used as input type for actual function pointer so
		// that both free functions and methods can be supplied
		alias FunctionDg = typeof(toDelegate(&Function));

		// information about attributed function arguments
		alias ParameterTypes = ParameterTypeTuple!Function;
		alias parameter_names = ParameterIdentifierTuple!Function;

		// filtered UDA lists
		alias input_attributes = Filter!(isInputAttribute, __traits(getAttributes, Function));
		alias output_attributes = Filter!(isOutputAttribute, __traits(getAttributes, Function));
	}

	private {

		/**
			Does all the magic necessary to prepare argument list for attributed
			function based on `input_attributes` and `opCall` argument list.

			Catches all name / type / size mismatch erros in that domain via
			static asserts.

			Params:
				dg = delegate for attributed function / method
				args = argument list from `opCall`

			Returns:
				proxies return value of dg
		*/
		ReturnType!Function prepareInputAndCall(T...)(FunctionDg dg, T args)
			if (!Compare!(Group!T, Group!(ParameterTypeTuple!Function)))
		{
			alias attributed_parameters = AttributedParameterMetadata!Function;
			// calculated combined input type list
			alias Input = MergeParameterTypes!(
				Group!attributed_parameters,
				Group!T
			);

			import std.traits : fullyQualifiedName;
			import std.string : format;

			static assert (
				Compare!(Group!Input, Group!ParameterTypes),
				format(
					"Calculated input parameter type tuple %s does not match " ~
					"%s%s",
					Input.stringof,
					fullyQualifiedName!Function,
					ParameterTypes.stringof
				)
			);

			// this value tuple will be used to assemble argument list
			Input input;

			foreach (i, uda; input_attributes) {
				// each iteration cycle is responsible for initialising `input`
				// tuple from previous spot to current attributed parameter index
				// (including)

				enum index = attributed_parameters[i].index;

				static if (i == 0) {
					enum lStart = 0;
					enum lEnd = index;
					enum rStart = 0;
					enum rEnd = index;
				}
				else {
					enum previousIndex = attributed_parameters[i - 1].index;
					enum lStart = previousIndex + 1;
					enum lEnd = index;
					enum rStart = previousIndex + 1 - i;
					enum rEnd = index - i;
				}

				static if (lStart != lEnd) {
					input[lStart..lEnd] = args[rStart..rEnd];
				}

				// during last iteration cycle remaining tail is initialised
				// too (if any)

				static if ((i == input_attributes.length - 1) && (index != input.length - 1)) {
					input[(index + 1)..$] = args[(index - i)..$];
				}

				input[index] = uda.evaluator(m_storedArgs);
			}

			// handle degraded case with no attributes separately
			static if (!input_attributes.length) {
				input[] = args[];
			}

			return dg(input);
		}

		/**
			`prepareInputAndCall` overload that operates on argument tuple that exactly
			matches attributed function argument list and thus gets updated by
			attached function instead of being merged with it
		*/
		ReturnType!Function prepareInputAndCall(T...)(FunctionDg dg, T args)
			if (Compare!(Group!T, Group!(ParameterTypeTuple!Function)))
		{
			alias attributed_parameters = AttributedParameterMetadata!Function;

			foreach (i, uda; input_attributes) {
				enum index = attributed_parameters[i].index;
				args[index] = uda.evaluator(m_storedArgs);
			}

			return dg(args);
		}
	}
}

/// example
unittest
{
	import std.conv;

	static string evaluator(string left, string right)
	{
		return left ~ right;
	}

	// all attribute function must accept same stored parameters
	static int modificator(int result, string unused1, string unused2)
	{
		return result * 2;
	}

	@before!evaluator("a") @before!evaluator("c") @after!modificator()
	static int sum(string a, int b, string c, double d)
	{
		return to!int(a) + to!int(b) + to!int(c) + to!int(d);
	}

	// ("10", "20") - stored arguments for evaluator()
	auto funcattr = createAttributedFunction!sum("10", "20");

	// `b` and `d` are unattributed, thus `42` and `13.5` will be
	// used as their values
	int result = funcattr(42, 13.5);

	assert(result == (1020 + 42 + 1020 + to!int(13.5)) * 2);
}

// testing other prepareInputAndCall overload
unittest
{
	import std.conv;

	static string evaluator(string left, string right)
	{
		return left ~ right;
	}

	// all attribute function must accept same stored parameters
	static int modificator(int result, string unused1, string unused2)
	{
		return result * 2;
	}

	@before!evaluator("a") @before!evaluator("c") @after!modificator()
	static int sum(string a, int b, string c, double d)
	{
		return to!int(a) + to!int(b) + to!int(c) + to!int(d);
	}

	auto funcattr = createAttributedFunction!sum("10", "20");

	// `a` and `c` are expected to be simply overwritten
	int result = funcattr("1000", 42, "1000", 13.5);

	assert(result == (1020 + 42 + 1020 + to!int(13.5)) * 2);
}

/**
	Syntax sugar in top of AttributedFunction

	Creates AttributedFunction with stored argument types that
	match `T` and stores `args` there before returning.
*/
auto createAttributedFunction(alias Function, T...)(T args)
{
	import vibe.internal.meta.typetuple : Group;

	AttributedFunction!(Function, Group!T) result;
	result.storeArgs(args);
	return result;
}

///
unittest
{
	void foo() {}

	auto funcattr = createAttributedFunction!foo(1, "2", 3.0);

	import std.typecons : tuple;
	assert (tuple(funcattr.m_storedArgs) == tuple(1, "2", 3.0));
}
