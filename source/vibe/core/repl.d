/**
	Provides facility to easily set up a $(LINK2 http://en.wikipedia.org/wiki/Read%E2%80%93eval%E2%80%93print_loop, REPL) with an event loop.

	The following code demonstrate the possibility of this module:

	----
	module myrepl;
	import vibe.core.repl;

	class MyPrompt
 	{
		enum Prompts = ["!>", "@>", "#>", "$>", "%>"];
		private int off = 0;
		@property string currentPrompt() { return Prompts[off++ % Prompts.length]; }
	}

 	shared static this()
	{
 		Drone drone = new Drone();
 		auto dynamicPrompt = new MyPrompt();
 		// Argument can be either a function or a delegate
 		createRepl((s) => myReplImpl(drone, s), dynamicPrompt.currentPrompt);
 	}
 
 	string myReplImpl(Drone dthis, string cmd)
 	{
 		switch (cmd) {
 		case "takeoff":
 			dthis.takeoff();
 			break;
 		case "land":
 			dthis.land();
 			break;
 		// Gets catched and printed to stderr.
 		// Second argument is the default.
 		default:
 			throw new ReplException(cmd~": Command not found");
 		}
 		// If the repl returns a string which isn't null nor empty, it gets printed.
 		return "Command "~cmd~" executed successfully";
 	}
 	----
 
 	Copyright: © 2014 RejectedSoftware e.K.
 	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
 	Authors: Mathias Lang
 */
module vibe.core.repl;


/**
	A class for exceptions related to the REPL.

	By default, the repl loop will catch all $(D Exception)s $(LPAREN)but not $(D Error)s$(RPAREN).
	Exceptions which are $(LPAREN)or derive from$(RPAREN) $(D ReplException) will have their message printed,
	while the others would be printed in full (including stack trace).
	This can be used to throw exceptions related to the usage $(LPAREN)most common use case$(RPAREN),
	or when an operation might fail but you don't want its full stack trace.
*/
class ReplException : Exception {
	/// Construct an exception based on the given $(D message).
	this(string message, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		super(message, file, line, next);
	}
}

/**
	Create an REPL in the current thread, using $(D cb) as the callback function and optionally a $(D prompt).

	They're two command that are implemented by default: 'quit' and 'exit', with the effect you can expect.
	In addition, on compatible terminals, Ctrl+D will close stdin, and thus end the REPL as well.
	Once the REPL terminate, the event loop is exited if $(D exitAtEnd) is specified.

	Note: It has to be called from the main thread.

	Params:
	exitAtEnd:	Call $(D vibe.core.core.exitEventLoop) when the REPL returns.
	buffSize:	The size of the maximum command line that would be read.
			If a command greater than this size is issued, it will be discarded.
	cb:		A $(D function) or a $(D delegate) that will be called each type a command is received.
			The parameter will be the typed line (with the last '\n' removed).
			If it returns a non-null, non-empty string, it will be printed to the standard output.
	prompt:		An optional value that represent the prompt. It can also be a property, if the prompt needs to change.
*/
void createRepl(bool exitAtEnd = true, size_t buffSize = (2048 - (void*).sizeof))
	(string delegate(string) cb, lazy string prompt = "$> ")
{
	import vibe.core.core : setTimer;
	import core.time : msecs;
	setTimer(1.msecs, { createReplImpl!(exitAtEnd, buffSize)(cb, prompt); });
}

/// Ditto
void createRepl(bool exitAtEnd = true, size_t buffSize = (2048 - (void*).sizeof))
	(string function(string) cb, lazy string prompt = "$> ")
{
	import vibe.core.core : setTimer;
	import core.time : msecs;
	setTimer(1.msecs, { createReplImpl!(exitAtEnd, buffSize)(toDelegate(&cb), prompt); });
}

private:
///
void createReplImpl(bool exitAtEnd, size_t buffSize)(string delegate(string) cb, string prompt)
{
	import vibe.stream.stdio;
	import vibe.core.core : exitEventLoop;
	import std.stdio : write, stdin, stdout, stderr, writeln;
	import core.time : weeks;

	ubyte[buffSize] buffer;
	size_t least;
	auto sstdin = new StdinStream();

promptAndWait:
	while (true) {
		buffer[0..least] = 0;
		write(prompt);
		stdout.flush();
		while (sstdin.waitForData(42.weeks)) {
			least = sstdin.leastSize;
			assert(least > 0, "Error: Nothing to read ?");
			// If the command line is too big (unlikely), we read all the data and just discard it.
			if (least >= buffSize) {
				stderr.writeln("The command size limit is ", buffSize,
				               ", your current command is ", least, " chars.");
				stderr.writeln("Increase the buffSize template parameter for",
				               " createRepl if you wish to process such input.");
				while (sstdin.dataAvailableForRead) {
					least = sstdin.leastSize;
					least = (least >= buffSize) ? (buffSize) : (least);
					sstdin.read(buffer[0..least]);
				}
				continue promptAndWait;
			}
			// Our read is *NOT* complete, wait for all data.
			if (sstdin.peek[$-1] != '\n') {
				vibe.core.core.yield();
				continue;
			}
			sstdin.read(buffer[0..least]);
			// Strip last '\n'
			if (buffer[least-1] == '\n') buffer[--least] = 0;
			// User just hit enter.
			if (!least) continue promptAndWait;
			// Check for exit and quit.
			if (buffer[0..least] == "exit" || buffer[0..least] == "quit")
				break promptAndWait;
			// If the user just hit enter, do nothing.
			try {
				auto ret = cb(cast(string)(buffer[0..least]));
				if (ret && ret.length)
					writeln(ret);
			} catch (ReplException e) {
				stderr.writefln(e.msg);
			} catch (Exception e) {
				stderr.writeln(e);
			}
			continue promptAndWait;
		}
		// We get a \0, probably because the user pressed Ctrl + D
		writeln();
		break;
	}
	static if (exitAtEnd)
		exitEventLoop(true);
}
