import vibe.data.json;

import std.stdio;
import std.bigint;

void main()
{
	Json a = 1;
	Json b = 2;
	writefln("%s %s", a.type, b.type);
	auto c = a + b;
	c = c * 2;
	writefln("%d", cast(long)c);

	Json[string] obj;
	obj["item1"] = a;
	obj["item2"] = "Object";
	Json parent = obj;
	parent.remove("item1");
	foreach (i; obj) writeln(i);

	auto obj2 = parseJsonString(`{"serial":17559991181826658461}`);
	writeln("serial: ", obj2["serial"]);
	assert(obj2["serial"] == BigInt(17559991181826658461UL));
}
