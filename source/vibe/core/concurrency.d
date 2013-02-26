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
import std.typecons;
import std.variant;
import vibe.core.task;

private extern (C) pure void _d_monitorenter(Object h);
private extern (C) pure void _d_monitorexit(Object h);

/**
	Locks the given shared object and returns a ScopedLock for accessing any unshared members.

	Using this function will ensure that there are no data races. For this reason, the class
	type T is required to contain no unshared or unisolated aliasing.

	Examples:

	---
	import vibe.core.typecons;

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
pure {
	return ScopedLock!T(object);
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
	//static assert(isWeaklyIsolated!(FieldTypeTuple!T), T.stringof~" contains non-immutable, non-shared references. Accessing it in a multi-threaded environment is not safe.");

	private Rebindable!T m_ref;

	@disable this(this);

	this(shared(T) obj)
		pure {
			assert(obj !is null, "Attempting to lock null object.");
			m_ref = cast(T)obj;
			_d_monitorenter(getObject());
		}

	pure ~this()
	{
		_d_monitorexit(getObject());
	}

	/**
		Returns an unshared reference to the locked object.

		Note that using this function breaks type safety. Be sure to not escape the reference beyond
		the life time of the lock.
	*/
	@property inout(T) unsafeGet() inout { return m_ref; }

	alias unsafeGet this;
	//pragma(msg, "In ScopedLock!("~T.stringof~")");
	//pragma(msg, isolatedRefMethods!T());
	#line 1 "isolatedAggreateMethodsString"
	//mixin(isolatedAggregateMethodsString!T());
	#line 138 "source/vibe/core/concurrency.d"

	private Object getObject()
		pure {
			static if( is(Rebindable!T == struct) ) return cast()m_ref.get();
			else return cast()m_ref;
		}
}


/******************************************************************************/
/* std.concurrency compatible interface for message passing                   */
/******************************************************************************/

alias Task Tid;

void send(T...)(Tid tid, T args)
{
	static assert(args.length > 0, "Need to send at least one value.");
	static if( args.length == 1 ) tid.messageQueue.send(Variant(args[0]));
	else tid.messageQueue.send(Variant(tuple(args)));
}

void prioritySend(T...)(Tid tid, T args)
{
	static assert(args.length > 0, "Need to send at least one value.");
	static if( args.length == 1 ) tid.messageQueue.prioritySend(Variant(args[0]));
	else tid.messageQueue.prioritySend(Variant(tuple(args)));
}

// TODO: handle special exception types

void receive(T...)(T ops)
{
	auto tid = Task.getThis();
	tid.messageQueue.receive(ops, (Throwable th) { throw th; });
}

auto receiveOnly(T...)()
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
	tid.messageQueue.receiveTimeout(ops);
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

