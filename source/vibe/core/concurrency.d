/**
	Functions and structures for dealing with threads and concurrent access.

	This module is modeled after std.concurrency, but provides a fiber-aware alternative
	to it. All blocking operations will yield the calling fiber instead of blocking it.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.concurrency;

public import std.concurrency : MessageMismatch, OwnerTerminated, LinkTerminated, PriorityMessageException, MailboxFull, OnCrowding;

import core.time;
import std.traits;
import std.typecons;
import std.variant;
import vibe.core.task;

private extern (C) pure nothrow void _d_monitorenter(Object h);
private extern (C) pure nothrow void _d_monitorexit(Object h);

/**
	Locks the given shared object and returns a ScopedLock for accessing any unshared members.

	Using this function will ensure that there are no data races. For this reason, the class
	type T is required to contain no unshared or unisolated aliasing.

	Examples:

	---
	import vibe.core.concurrency;

	class Item {
		private double m_value;

		this(double value) { m_value = value; }

		@property double value() const { return m_value; }
	}

	class Manager {
		private {
			string m_name;
			Isolated!(Item) m_ownedItem;
			Isolated!(shared(Item)[]) m_items;
		}

		this(string name)
		{
			m_name = name;
			auto itm = makeIsolated!Item(3.5);
			m_ownedItem = itm;
		}

		void addItem(shared(Item) item) { m_items ~= item; }

		double getTotalValue()
		const {
			double sum = 0;

			// lock() is required to access shared objects
			foreach( itm; m_items ) sum += itm.lock().value;

			// owned objects can be accessed without locking
			sum += m_ownedItem.value;

			return sum;
		}
	}

	void main()
	{
		import std.stdio;

		auto man = new shared(Manager)("My manager");
		{
			auto l = man.lock();
			l.addItem(new shared(Item)(1.5));
			l.addItem(new shared(Item)(0.5));
		}

		writefln("Total value: %s", man.lock().getTotalValue());
	}
	---

	See_Also: core.concurrency.isWeaklyIsolated
*/
ScopedLock!T lock(T)(shared(T) object)
pure nothrow {
	return ScopedLock!T(object);
}
/// ditto
void lock(T)(shared(T) object, scope void delegate(scope T) accessor)
nothrow {
	auto l = lock(object);
	accessor(l.unsafeGet());
}


/**
	Proxy structure that keeps the monitor of the given object locked until it
	goes out of scope.

	Any unshared members of the object are safely accessible during this time. The usual
	way to use it is by calling lock.

	See_Also: lock
*/
struct ScopedLock(T)
{
	static assert(is(T == class), "ScopedLock is only usable with classes.");
//	static assert(isWeaklyIsolated!(FieldTypeTuple!T), T.stringof~" contains non-immutable, non-shared references. Accessing it in a multi-threaded environment is not safe.");

	private Rebindable!T m_ref;

	@disable this(this);

	this(shared(T) obj)
		pure nothrow {
			assert(obj !is null, "Attempting to lock null object.");
			m_ref = cast(T)obj;
			_d_monitorenter(getObject());
		}

	pure nothrow ~this()
	{
		_d_monitorexit(getObject());
	}

	/**
		Returns an unshared reference to the locked object.

		Note that using this function breaks type safety. Be sure to not escape the reference beyond
		the life time of the lock.
	*/
	@property inout(T) unsafeGet() inout nothrow { return m_ref; }

	alias unsafeGet this;
	//pragma(msg, "In ScopedLock!("~T.stringof~")");
	//pragma(msg, isolatedRefMethods!T());
	#line 1 "isolatedAggreateMethodsString"
//	mixin(isolatedAggregateMethodsString!T());
	#line 140 "source/vibe/core/concurrency.d"

	private Object getObject()
		pure nothrow {
			static if( is(Rebindable!T == struct) ) return cast()m_ref.get();
			else return cast()m_ref;
		}
}


/**
	Creates a new isolated object.

	Isolated objects contain no mutable aliasing outside of their own reference tree. They can thus
	be safely converted to immutable and they can be safely passed between threads.

	The function returns an instance of Isolated that will allow proxied access to the members of
	the object, as well as providing means to convert the object to immutable or to an ordinary
	mutable object.

	Examples:

	---
	import vibe.core.concurrency;

	class Item {
		double value;
		string name;
	}

	void modifyItem(Isolated!Item itm)
	{
		itm.value = 1.3;
		// TODO: send back to initiating thread
	}

	void main()
	{
		immutable(Item)[] items;

		// create immutable item procedurally
		auto itm = makeIsolated!Item();
		itm.value = 2.4;
		itm.name = "Test";
		items ~= itm.freeze();

		// send isolated item to other thread
		auto itm2 = makeIsolated!Item();
		spawn(&modifyItem, itm2.move());
		// ...
	}
	---
*/
pure Isolated!T makeIsolated(T, ARGS...)(ARGS args)
{
	return Isolated!T(new T(args));
}


/**
	Creates a new isolated array.

	Examples:

	---
	import vibe.core.concurrency;

	void compute(Tid tid, Isolated!(double[]) array, size_t start_index)
	{
		foreach( i; 0 .. array.length )
			array[i] = (start_index + i) * 0.5;

		send(tid, array.move());
	}

	void main()
	{
		import std.stdio;

		// compute contents of an array using multiple threads
		auto arr = makeIsolatedArray!double(256);

		// partition the array (no copying takes place)
		size_t[] indices = [64, 128, 192, 256];
		Isolated!(double[])[] subarrays = arr.splice(indices);

		// start processing in threads
		Tid[] tids;
		foreach( i, idx; indices )
			tids ~= spawn(&compute, thisTid, subarrays[i].move(), idx);

		// collect results
		auto resultarrays = new Isolated!(double[])[tids.length];
		foreach( i, tid; tids )
			resultarrays[i] = receiveOnly!(Isolated!(double[])).move();
		
		// BUG: the arrays must be sorted here, but since there is no way to tell
		// from where something was received, this is difficult here.

		// merge results (no copying takes place again)
		foreach( i; 1 .. resultarrays.length )
			resultarrays[0].merge(resultarrays[i]);

		// convert the final result to immutable
		auto result = resultarrays[0].freeze();

		writefln("Result: %s", result);
	}
	---
*/
pure Isolated!(T[]) makeIsolatedArray(T)(size_t size)
{
	Isolated!(T[]) ret;
	ret.length = size;
	return ret.move();
}


/**
	Unsafe facility to assume that an existing reference is unique.
*/
Isolated!T assumeIsolated(T)(T object)
{
	return Isolated!T(object);
}

/**
	Encapsulates the given type in a way that guarantees memory isolation.

	See_Also: makeIsolated, makeIsolatedArray
*/
template Isolated(T)
{
	static if( isWeaklyIsolated!T ){
		alias T Isolated;
	} else static if( is(T == class) ){
		alias IsolatedRef!T Isolated;
	} else static if( isPointer!T ){
		alias IsolatedRef!(PointerTarget!T) Isolated;
	} else static if( isDynamicArray!T ){
		alias IsolatedArray!(typeof(T.init[0])) Isolated;
	} else static if( isAssociativeArray!T ){
		alias IsolatedAssociativeArray!(KeyType!T, ValueType!T) Isolated;
	} else static assert(false, T.stringof~": Unsupported type for unique - must be class, pointer, array or associative array.");
}


version(unittest)
{
	private class CE {}
	private struct SE {}
}

unittest
{
	static assert(is(Isolated!CE == IsolatedRef!CE));
	static assert(is(Isolated!(SE*) == IsolatedRef!SE));
	static assert(is(Isolated!(SE[]) == IsolatedArray!SE));
	version(EnablePhobosFails){
		// AAs don't work because they are impure
		static assert(is(Isolated!(SE[string]) == IsolatedAssociativeArray!(string, SE)));
	}
}


/// private
private struct IsolatedRef(T)
{
	pure:
	static assert(isWeaklyIsolated!(FieldTypeTuple!T), T.stringof ~ " contains non-immutable/non-shared references. Isolation cannot be guaranteed.");
	enum __isWeakIsolatedType = true;
	static if( isStronglyIsolated!(FieldTypeTuple!T) )
		enum __isIsolatedType = true;

	alias T BaseType;

	static if( is(T == class) ){
		alias T Tref;
		alias immutable(T) Tiref;
	} else {
		alias T* Tref;
		alias immutable(T)* Tiref;
	}

	private Tref m_ref;

	//mixin isolatedAggregateMethods!T;
	#line 1 "isolatedAggregateMethodsString"
	mixin(isolatedAggregateMethodsString!T());
	#line 322 "source/vibe/concurrency.d"

	@disable this(this);

	private this(Tref obj)
	{
		m_ref = obj;
	}

	this(ref IsolatedRef src)
	{
		m_ref = src.m_ref;
		src.m_ref = null;
	}

	void opAssign(ref IsolatedRef src)
	{
		m_ref = src.m_ref;
		src.m_ref = null;
	}

	/**
		Returns the raw reference.

		Note that using this function breaks type safety. Be sure to not escape the reference.
	*/
	inout(Tref) unsafeGet() inout { return m_ref; }

	/**
		Move the contained reference to a new IsolatedRef.

		Since IsolatedRef is not copyable, using this function may be necessary when
		passing a reference to a function or when returning it. The reference in
		this instance will be set to null after the call returns.
	*/
	IsolatedRef move() { auto r = m_ref; m_ref = null; return IsolatedRef(r); }

	/**
		Convert the isolated reference to a normal mutable reference.

		The reference in this instance will be set to null after the call returns.
	*/
	Tref extract()
	{
		auto ret = m_ref;
		m_ref = null;
		return ret;
	}

	/**
		Converts the isolated reference to immutable.

		The reference in this instance will be set to null after the call returns.
		Note that this method is only available for strongly isolated references,
		which means references that do not contain shared aliasing.
	*/
	Tiref freeze()()
	{
		static assert(isStronglyIsolated!(FieldTypeTuple!T), "freeze() can only be called on strongly isolated values, but "~T.stringof~" contains shared references.");
		auto ret = m_ref;
		m_ref = null;
		return cast(immutable)ret;
	}
}


/// private
private struct IsolatedArray(T)
{
	static assert(isWeaklyIsolated!T, T.stringof ~ " contains non-immutable references. Isolation cannot be guaranteed.");
	enum __isWeakIsolatedType = true;
	static if( isStronglyIsolated!T )
		enum __isIsolatedType = true;

	alias T[] BaseType;

	private T[] m_array;

	mixin isolatedArrayMethods!T;

	@disable this(this);

	/**
		Returns the raw reference.

		Note that using this function breaks type safety. Be sure to not escape the reference.
	*/
	inout(T[]) unsafeGet() inout { return m_array; }

	IsolatedArray!T move() pure { auto r = m_array; m_array = null; return IsolatedArray(r); }

	T[] extract()
	pure {
		auto arr = m_array;
		m_array = null;
		return arr;
	}

	immutable(T)[] freeze()() pure
	{
		static assert(isStronglyIsolated!T, "Freeze can only be called on strongly isolated values, but "~T.stringof~" contains shared references.");
		auto arr = m_array;
		m_array = null;
		return cast(immutable)arr;
	}


	/**
		Splits the array into individual slices at the given incides.

		The indices must be in ascending order. Any items that are larger than
		the last given index will remain in this IsolatedArray.
	*/
	IsolatedArray!T[] splice(in size_t[] indices...) pure
		in {
			//import std.algorithm : isSorted;
			assert(indices.length > 0, "At least one splice index must be given.");
			//assert(isSorted(indices), "Indices must be in ascending order.");
			assert(indices[$-1] <= m_array.length, "Splice index out of bounds.");
		}
		body {
			auto ret = new IsolatedArray!T[indices.length];
			size_t lidx = 0;
			foreach( i, sidx; indices ){
				ret[i].m_array = m_array[lidx .. sidx];
				lidx = sidx;
			}
			m_array = m_array[lidx .. $];
			return ret;
		}

	void merge(ref IsolatedArray!T array) pure
		in {
			assert(array.m_array.ptr == m_array.ptr+m_array.length || array.m_array.ptr+array.length == m_array.ptr,
				"Argument to merge() must be a neighbouring array partition.");
		}
		body {
			if( array.m_array.ptr == m_array.ptr + m_array.length ){
				m_array = m_array.ptr[0 .. m_array.length + array.length];
			} else {
				m_array = array.m_array.ptr[0 .. m_array.length + array.length];
			}
			array.m_array.length = 0;
		}
}


/// private
private struct IsolatedAssociativeArray(K, V)
{
	pure:
	static assert(isWeaklyIsolated!K, "Key type has aliasing. Memory isolation cannot be guaranteed.");
	static assert(isWeaklyIsolated!V, "Value type has aliasing. Memory isolation cannot be guaranteed.");

	enum __isWeakIsolatedType = true;
	static if( isStronglyIsolated!K && isStronglyIsolated!V )
		enum __isIsolatedType = true;

	alias V[K] BaseType;

	private {
		V[K] m_aa;
	}

	mixin isolatedAssociativeArrayMethods!(K, V);

	/**
		Returns the raw reference.

		Note that using this function breaks type safety. Be sure to not escape the reference.
	*/
	inout(V[K]) unsafeGet() inout { return m_aa; }

	IsolatedAssociativeArray move() { auto r = m_aa; m_aa = null; return IsolatedAssociativeArray(r); }

	V[K] extract()
	{
		auto arr = m_aa;
		m_aa = null;
		return arr;
	}

	static if( is(typeof(IsolatedAssociativeArray.__isIsolatedType)) ){
		immutable(V)[K] freeze()
		{
			auto arr = m_aa;
			m_aa = null;
			return cast(immutable(V)[K])(arr);
		}

		immutable(V[K]) freeze2()
		{
			auto arr = m_aa;
			m_aa = null;
			return cast(immutable(V[K]))(arr);
		}
	}
}


/** Encapsulates a reference in a way that disallows escaping it or any contained references.
*/
template ScopedRef(T)
{
	static if( isAggregateType!T ) alias ScopedRefAggregate!T ScopedRef;
	else static if( isAssociativeArray!T ) alias ScopedRefAssociativeArray!T ScopedRef;
	else static if( isArray!T ) alias ScopedRefArray!T ScopedRef;
	else static if( isBasicType!T ) alias ScopedRefBasic!T ScopedRef;
	else static assert(false, "Unsupported type for ScopedRef: "~T.stringof);
}

/// private
private struct ScopedRefBasic(T)
{
	private T* m_ref;

	@disable this(this);

	this(ref T tref) pure { m_ref = &tref; }

	//void opAssign(T value) { *m_ref = value; }

	ref T unsafeGet() pure { return *m_ref; }

	alias unsafeGet this;
}

/// private
private struct ScopedRefAggregate(T)
{
	private T* m_ref;

	@disable this(this);

	this(ref T tref) pure { m_ref = &tref; }

	//void opAssign(T value) { *m_ref = value; }

	ref T unsafeGet() pure { return *m_ref; }

	static if( is(T == shared) ){
		auto lock() pure { return .lock(unsafeGet()); }
	} else {
		#line 1 "isolatedAggregateMethodsString"
		mixin(isolatedAggregateMethodsString!T());
		#line 567 "source/vibe/concurrency.d"
		//mixin isolatedAggregateMethods!T;
	}
}

/// private
private struct ScopedRefArray(T)
{
	alias typeof(T.init[0]) V;
	private T* m_ref;
	
	private @property ref T m_array() pure { return *m_ref; }
	private @property ref const(T) m_array() const pure { return *m_ref; }

	mixin isolatedArrayMethods!(V, !is(T == const) && !is(T == immutable));

	@disable this(this);

	this(ref T tref) pure { m_ref = &tref; }

	//void opAssign(T value) { *m_ref = value; }

	ref T unsafeGet() pure { return *m_ref; }
}

/// private
private struct ScopedRefAssociativeArray(K, V)
{
	alias KeyType!T K;
	alias ValueType!T V;
	private T* m_ref;

	private @property ref T m_array() pure { return *m_ref; }
	private @property ref const(T) m_array() const pure { return *m_ref; }

	mixin isolatedAssociativeArrayMethods!(K, V);

	@disable this(this);

	this(ref T tref) pure { m_ref = &tref; }

	//void opAssign(T value) { *m_ref = value; }

	ref T unsafeGet() pure { return *m_ref; }

}

/******************************************************************************/
/* COMMON MIXINS FOR NON-REF-ESCAPING WRAPPER STRUCTS                         */
/******************************************************************************/

/// private
/*private mixin template(T) isolatedAggregateMethods
{
#line 1 "isolatedAggregateMethodsString"
	mixin(isolatedAggregateMethodsString!T());
#line 623 "source/vibe/concurrency.d"
}*/

/// private
private string isolatedAggregateMethodsString(T)()
{
	string ret = generateModuleImports!T();
	//pragma(msg, "Type '"~T.stringof~"'");
	foreach( mname; __traits(allMembers, T) ){
		static if( !is(FunctionTypeOf!(__traits(getMember, T, mname)) == function) ){
			static if( isMemberPublic!(T, mname) ){
				alias typeof(__traits(getMember, T, mname)) mtype;
				auto mtypename = fullyQualifiedName!mtype;
				//pragma(msg, "  field " ~ mname ~ " : " ~ mtype.stringof);
				ret ~= "@property ScopedRef!(const("~mtypename~")) "~mname~"() const pure { return ScopedRef!(const("~mtypename~"))(m_ref."~mname~"); }\n";
				ret ~= "@property ScopedRef!("~mtypename~") "~mname~"() pure { return ScopedRef!("~mtypename~")(m_ref."~mname~"); }\n";
				static if( !is(mtype == const) && !is(mtype == immutable) ){
					static if( isWeaklyIsolated!mtype ){
						ret ~= "@property void "~mname~"("~mtypename~" value) pure { m_ref."~mname~" = value; }\n";
					} else {
						ret ~= "@property void "~mname~"(AT)(AT value) pure { static assert(isWeaklyIsolated!AT); m_ref."~mname~" = value.unsafeGet(); }\n";
					}
				}
			} //else pragma(msg, "  non-public field " ~ mname);
		} else {
			foreach( method; __traits(getOverloads, T, mname) ){
				alias FunctionTypeOf!method ftype;

				// only pure functions are allowed (or they could escape references to global variables)
				// don't allow non-isolated references to be escaped
				if( functionAttributes!ftype & FunctionAttribute.pure_ &&
					isWeaklyIsolated!(ReturnType!ftype) )
				{
					static if( __traits(isStaticFunction, method) ){
						//pragma(msg, "  static method " ~ mname ~ " : " ~ ftype.stringof);
						ret ~= "static "~fullyQualifiedName!(ReturnType!ftype)~" "~mname~"(";
						foreach( i, P; ParameterTypeTuple!ftype ){
							if( i > 0 ) ret ~= ", ";
							ret ~= fullyQualifiedName!P ~ " p"~i.stringof;
						}
						ret ~= "){ return "~fullyQualifiedName!T~"."~mname~"(";
						foreach( i, P; ParameterTypeTuple!ftype ){
							if( i > 0 ) ret ~= ", ";
							ret ~= "p"~i.stringof;
						}
						ret ~= "); }\n";
					} else {
						//pragma(msg, "  normal method " ~ mname ~ " : " ~ ftype.stringof);
						if( is(ftype == const) ) ret ~= "const ";
						if( is(ftype == shared) ) ret ~= "shared ";
						if( is(ftype == immutable) ) ret ~= "immutable ";
						if( functionAttributes!ftype & FunctionAttribute.pure_ ) ret ~= "pure ";
						if( functionAttributes!ftype & FunctionAttribute.property ) ret ~= "@property ";
						ret ~= fullyQualifiedName!(ReturnType!ftype)~" "~mname~"(";
						foreach( i, P; ParameterTypeTuple!ftype ){
							if( i > 0 ) ret ~= ", ";
							ret ~= fullyQualifiedName!P ~ " p"~i.stringof;
						}
						ret ~= "){ return m_ref."~mname~"(";
						foreach( i, P; ParameterTypeTuple!ftype ){
							if( i > 0 ) ret ~= ", ";
							ret ~= "p"~i.stringof;
						}
						ret ~= "); }\n";
					}
				}
			}
		}
	}
	return ret;
}


/// private
private mixin template isolatedArrayMethods(T, bool mutableRef = true)
{
	@property size_t length() const pure { return m_array.length; }

	@property bool empty() const pure { return m_array.length == 0; }

	static if( mutableRef ){
		@property void length(size_t value) pure { m_array.length = value; }


		void opCatAssign(T item) pure
		{
			static if( isCopyable!T ) m_array ~= item;
			else {
				m_array.length++;
				m_array[$-1] = item;
			}
		}

		void opCatAssign(IsolatedArray!T array) pure
		{
			static if( isCopyable!T ) m_array ~= array.m_array;
			else {
				size_t start = m_array.length;
				m_array.length += array.length;
				foreach( i, ref itm; array.m_array )
					m_array[start+i] = itm;
			}
		}
	}

	ScopedRef!(const(T)) opIndex(size_t idx) const pure { return ScopedRef!(const(T))(m_array[idx]); }
	ScopedRef!T opIndex(size_t idx) pure { return ScopedRef!T(m_array[idx]); }

	static if( !is(T == const) && !is(T == immutable) )
		void opIndexAssign(T value, size_t idx) pure { m_array[idx] = value; }

	int opApply(int delegate(ref size_t, ref ScopedRef!T) del)
	pure {
		foreach( idx, ref v; m_array ){
			auto noref = ScopedRef!T(v);
			if( auto ret = (cast(int delegate(ref size_t, ref ScopedRef!T) pure)del)(idx, noref) )
				return ret;
		}
		return 0;
	}

	int opApply(int delegate(ref size_t, ref ScopedRef!(const(T))) del)
	const pure {
		foreach( idx, ref v; m_array ){
			auto noref = ScopedRef!(const(T))(v);
			if( auto ret = (cast(int delegate(ref size_t, ref ScopedRef!(const(T))) pure)del)(idx, noref) )
				return ret;
		}
		return 0;
	}

	int opApply(int delegate(ref ScopedRef!T) del)
	pure {
		foreach( v; m_array ){
			auto noref = ScopedRef!T(v);
			if( auto ret = (cast(int delegate(ref ScopedRef!T) pure)del)(noref) )
				return ret;
		}
		return 0;
	}

	int opApply(int delegate(ref ScopedRef!(const(T))) del)
	const pure {
		foreach( v; m_array ){
			auto noref = ScopedRef!(const(T))(v);
			if( auto ret = (cast(int delegate(ref ScopedRef!(const(T))) pure)del)(noref) )
				return ret;
		}
		return 0;
	}
}


/// private
private mixin template isolatedAssociativeArrayMethods(K, V, bool mutableRef = true)
{
	@property size_t length() const pure { return m_aa.length; }
	@property bool empty() const pure { return m_aa.length == 0; }

	static if( !is(V == const) && !is(V == immutable) )
		void opIndexAssign(V value, K key) pure { m_aa[key] = value; }

	inout(V) opIndex(K key) inout pure { return m_aa[key]; }

	int opApply(int delegate(ref ScopedRef!K, ref ScopedRef!V) del)
	pure {
		foreach( ref k, ref v; m_aa )
			if( auto ret = (cast(int delegate(ref ScopedRef!K, ref ScopedRef!V) pure)del)(k, v) )
				return ret;
		return 0;
	}

	int opApply(int delegate(ref ScopedRef!V) del)
	pure {
		foreach( ref v; m_aa )
			if( auto ret = (cast(int delegate(ref ScopedRef!V) pure)del)(v) )
				return ret;
		return 0;
	}

	int opApply(int delegate(ref ScopedRef!(const(K)), ref ScopedRef!(const(V))) del)
	const pure {
		foreach( ref k, ref v; m_aa )
			if( auto ret = (cast(int delegate(ref ScopedRef!(const(K)), ref ScopedRef!(const(V))) pure)del)(k, v) )
				return ret;
		return 0;
	}

	int opApply(int delegate(ref ScopedRef!(const(V))) del)
	const pure {
		foreach( v; m_aa )
			if( auto ret = (cast(int delegate(ref ScopedRef!(const(V))) pure)del)(v) )
				return ret;
		return 0;
	}
}


/******************************************************************************/
/* UTILITY FUNCTIONALITY                                                      */
/******************************************************************************/

// private
private @property string generateModuleImports(T)()
{
	bool[string] visited;
	//pragma(msg, "generateModuleImports "~T.stringof);
	return generateModuleImportsImpl!T(visited);
}

private @property string generateModuleImportsImpl(T, TYPES...)(ref bool[string] visited)
{
	string ret;

	//pragma(msg, T);
	//pragma(msg, TYPES);

	static if( !haveTypeAlready!(T, TYPES) ){
		void addModule(string mod){
			if( mod !in visited ){
				ret ~= "static import "~mod~";\n";
				visited[mod] = true;
			}
		}

		static if( isAggregateType!T && !is(typeof(T.__isWeakIsolatedType)) ){ // hack to avoid a recursive template instantiation when Isolated!T is passed to moduleName
			addModule(moduleName!T);

			foreach( member; __traits(allMembers, T) ){
				//static if( isMemberPublic!(T, member) ){
					static if( !is(typeof(__traits(getMember, T, member))) ){
						// ignore sub types
					} else static if( !is(FunctionTypeOf!(__traits(getMember, T, member)) == function) ){
						alias typeof(__traits(getMember, T, member)) mtype;
						ret ~= generateModuleImportsImpl!(mtype, T, TYPES)(visited);
					} else static if( is(T == class) || is(T == interface) ){
						foreach( overload; MemberFunctionsTuple!(T, member) ){
							ret ~= generateModuleImportsImpl!(ReturnType!overload, T, TYPES)(visited);
							foreach( P; ParameterTypeTuple!overload )
								ret ~= generateModuleImportsImpl!(P, T, TYPES)(visited);
						}
					} // TODO: handle structs!
				//}
			}
		}
		else static if( isPointer!T ) ret ~= generateModuleImportsImpl!(PointerTarget!T, T, TYPES)(visited);
		else static if( isArray!T ) ret ~= generateModuleImportsImpl!(typeof(T.init[0]), T, TYPES)(visited);
		else static if( isAssociativeArray!T ) ret ~= generateModuleImportsImpl!(KeyType!T, T, TYPES)(visited) ~ generateModuleImportsImpl!(ValueType!T, T, TYPES)(visited);
	}

	return ret;
}

template haveTypeAlready(T, TYPES...)
{
	static if( TYPES.length == 0 ) enum haveTypeAlready = false;
	else static if( is(T == TYPES[0]) ) enum haveTypeAlready = true;
	else alias haveTypeAlready!(T, TYPES[1 ..$]) haveTypeAlready;
}

template isMemberPublic(T, string member)
{
	static if( __traits(compiles, {tryAccess!(T, member)(); }()) ){
		enum isMemberPublic = true;
	} else enum isMemberPublic = false;
}

/// private
private void tryAccess(T, string member)()
{
	mixin(generateModuleImports!T());
	mixin(fullyQualifiedName!T~" inst;");
	mixin("auto p = &inst."~member~";");
}


/******************************************************************************/
/* Additional traits useful for handling isolated data                        */
/******************************************************************************/

/**
	Determines if the given list of types has any non-immutable aliasing outside of their object tree.

	The types in particular may only contain plain data, pointers or arrays to immutable data, or references
	encapsulated in stdx.typecons.Isolated.
*/
template isStronglyIsolated(T...)
{
	static if( T.length == 0 ) enum isStronglyIsolated = true;
	else {
		alias T[0] HEAD;
		alias T[1 .. $] TAIL;
		/*static if( is(typeof(HEAD.__isIsolatedType)) ){
			pragma(msg, "I " ~ HEAD.stringof);
		} else static if( is(HEAD.BaseType) ){
			pragma(msg, HEAD.stringof ~ " <" ~ HEAD.BaseType.stringof ~ "> ");// ~ Isolated!(HEAD.BaseType).stringof);
		} else static if( is(HEAD == struct) ){
			pragma(msg, "S " ~ HEAD.stringof ~ " <-> " ~ TAIL.stringof);
		} else static if( is(HEAD == class) ){
			pragma(msg, "C " ~ HEAD.stringof ~ " <-> " ~ TAIL.stringof);
		} else static if( is(HEAD == function) ){
			pragma(msg, "F " ~ HEAD.stringof ~ " <-> " ~ TAIL.stringof);
		} else static if( is(HEAD == delegate) ){
			pragma(msg, "D " ~ HEAD.stringof ~ " <-> " ~ TAIL.stringof);
		} else static if( isSomeFunction!HEAD ){
			pragma(msg, "SF " ~ HEAD.stringof ~ " <-> " ~ TAIL.stringof);
		} else {
			pragma(msg, HEAD.stringof ~ " <-> " ~ TAIL.stringof);
		}*/
		static if( is(HEAD == immutable) ) enum isStronglyIsolated = isStronglyIsolated!TAIL;
		else static if( is(typeof(HEAD.__isIsolatedType)) ) enum isStronglyIsolated = isStronglyIsolated!TAIL;
		else static if( is(HEAD == class) ) enum isStronglyIsolated = false;
		else static if( is(HEAD == delegate) ) enum isStronglyIsolated = false; // can't know to what a delegate points
		else static if( isDynamicArray!HEAD ) enum isStronglyIsolated = is(typeof(HEAD.init[0]) == immutable) && isStronglyIsolated!TAIL;
		else static if( isAssociativeArray!HEAD ) enum isStronglyIsolated = false; // TODO: be less strict here
		else static if( isSomeFunction!HEAD ) enum isStronglyIsolated = isStronglyIsolated!TAIL; // functions are immutable
		else static if( isPointer!HEAD ) enum isStronglyIsolated = is(typeof(*HEAD.init) == immutable) && isStronglyIsolated!TAIL;
		else static if( isAggregateType!HEAD ) enum isStronglyIsolated = isStronglyIsolated!(FieldTypeTuple!HEAD) && isStronglyIsolated!TAIL;
		else enum isStronglyIsolated = isStronglyIsolated!TAIL;
	}
}


/**
	Determines if the given list of types has any non-immutable and unshared aliasing outside of their object tree.

	The types in particular may only contain plain data, pointers or arrays to immutable or shared data, or references
	encapsulated in stdx.typecons.Isolated. Values that do not have unshared and unisolated aliasing are safe to be passed
	between threads.
*/
template isWeaklyIsolated(T...)
{
	static if( T.length == 0 ) enum isWeaklyIsolated = true;
	else {
		alias T[0] HEAD;
		alias T[1 .. $] TAIL;

		static if( is(HEAD == immutable) ) enum isWeaklyIsolated = isWeaklyIsolated!TAIL;
		else static if( is(HEAD == shared) ) enum isWeaklyIsolated = isWeaklyIsolated!TAIL;
		else static if( is(typeof(HEAD.__isIsolatedType)) ) enum isWeaklyIsolated = isWeaklyIsolated!TAIL;
		else static if( is(typeof(HEAD.__isWeakIsolatedType)) ) enum isWeaklyIsolated = isWeaklyIsolated!TAIL;
		else static if( is(HEAD == class) ) enum isWeaklyIsolated = false;
		else static if( is(HEAD == delegate) ) enum isWeaklyIsolated = false; // can't know to what a delegate points
		else static if( isDynamicArray!HEAD ) enum isWeaklyIsolated = is(typeof(HEAD.init[0]) == immutable) && isWeaklyIsolated!TAIL;
		else static if( isAssociativeArray!HEAD ) enum isWeaklyIsolated = false; // TODO: be less strict here
		else static if( isSomeFunction!HEAD ) enum isWeaklyIsolated = isWeaklyIsolated!TAIL; // functions are immutable
		else static if( isPointer!HEAD ) enum isWeaklyIsolated = is(typeof(*HEAD.init) == immutable) && isWeaklyIsolated!TAIL;
		else static if( isAggregateType!HEAD ) enum isWeaklyIsolated = isWeaklyIsolated!(FieldTypeTuple!HEAD) && isWeaklyIsolated!TAIL;
		else enum isWeaklyIsolated = isWeaklyIsolated!TAIL; //
	}
}

version(unittest)
{
	private class A { int x; string y; }

	private struct B {
		string a; // strongly isolated
		Isolated!A b; // strongly isolated
		version(EnablePhobosFails)
		Isolated!(Isolated!A[]) c; // strongly isolated
		version(EnablePhobosFails)
		Isolated!(Isolated!A[string]) c; // AA implementation does not like this
		version(EnablePhobosFails)
		Isolated!(int[string]) d; // strongly isolated
	}

	private struct C {
		string a; // strongly isolated
		shared(A) b; // weakly isolated
		Isolated!A c; // strongly isolated
		shared(A*) d; // weakly isolated
		shared(A[]) e; // weakly isolated
		shared(A[string]) f; // weakly isolated
	}

	private struct D { A a; } // not isolated
	private struct E { void delegate() a; } // not isolated
	private struct F { void function() a; } // strongly isolated (functions are immutable)
	private struct G { void test(); } // strongly isolated
	private struct H { A[] a; } // not isolated

	static assert(!isStronglyIsolated!A);
	static assert(isStronglyIsolated!(FieldTypeTuple!A));
	static assert(isStronglyIsolated!B);
	static assert(!isStronglyIsolated!C);
	static assert(!isStronglyIsolated!D);
	static assert(!isStronglyIsolated!E);
	static assert(isStronglyIsolated!F);
	static assert(isStronglyIsolated!G);
	static assert(!isStronglyIsolated!H);

	static assert(!isWeaklyIsolated!A);
	static assert(isWeaklyIsolated!(FieldTypeTuple!A));
	static assert(isWeaklyIsolated!B);
	static assert(isWeaklyIsolated!C);
	static assert(!isWeaklyIsolated!D);
	static assert(!isWeaklyIsolated!E);
	static assert(isWeaklyIsolated!F);
	static assert(isWeaklyIsolated!G);
	static assert(!isWeaklyIsolated!H);
}


template isCopyable(T)
{
	static if( __traits(compiles, {foreach( t; [T.init]){}}) ) enum isCopyable = true;
	else enum isCopyable = false;
}


/******************************************************************************/
/******************************************************************************/
/* std.concurrency compatible interface for message passing                   */
/******************************************************************************/
/******************************************************************************/

alias Task Tid;

void send(ARGS...)(Tid tid, ARGS args)
{
	assert (tid != Task(), "Invalid task handle");
	static assert(args.length > 0, "Need to send at least one value.");
	foreach(A; ARGS){
		static assert(isWeaklyIsolated!A, "Only objects with no unshared or unisolated aliasing may be sent, not "~A.stringof~".");
	}
	static if( args.length == 1 ) tid.messageQueue.send(Variant(args[0]));
	else tid.messageQueue.send(Variant(tuple(args)));
}

void prioritySend(ARGS...)(Tid tid, ARGS args)
{
	assert (tid != Task(), "Invalid task handle");
	static assert(args.length > 0, "Need to send at least one value.");
	foreach(A; ARGS){
		static assert(isWeaklyIsolated!A, "Only objects with no unshared or unisolated aliasing may be sent, not "~A.stringof~".");
	}
	static if( args.length == 1 ) tid.messageQueue.prioritySend(Variant(args[0]));
	else tid.messageQueue.prioritySend(Variant(tuple(args)));
}

// TODO: handle special exception types

void receive(OPS...)(OPS ops)
{
	auto tid = Task.getThis();
	tid.messageQueue.receive(ops, (Throwable th) { throw th; });
}

auto receiveOnly(ARGS...)()
{
	Tuple!T ret;

	receive(
		(T val) { ret = val; },
		(LinkTerminated e) { throw e; },
		(OwnerTerminated e) { throw e; },
		(Variant val) { throw new MessageMismatch(format("Unexpected message type %s, expected %s.", val.type, T.stringof)); }
	);

	return ret;
}

bool receiveTimeout(OPS...)(Duration timeout, OPS ops)
{
	auto tid = Task.getThis();
	return tid.messageQueue.receiveTimeout!OPS(timeout, ops);
}

void setMaxMailboxSize(Tid tid, size_t messages, OnCrowding on_crowding)
{
	final switch(on_crowding){
		case OnCrowding.block: setMaxMailboxSize(tid, messages, null); break;
		case OnCrowding.throwException: setMaxMailboxSize(tid, messages, &onCrowdingThrow); break;
		case OnCrowding.ignore: setMaxMailboxSize(tid, messages, &onCrowdingDrop); break;
	}
}

void setMaxMailboxSize(Tid tid, size_t messages, bool function(Tid) on_crowding)
{
	tid.messageQueue.setMaxSize(messages, on_crowding);
}

private bool onCrowdingThrow(Task tid){
	throw new MailboxFull(std.concurrency.Tid());
}

private bool onCrowdingDrop(Task tid){
	return false;
}

