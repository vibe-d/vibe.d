import vibe.data.json;

import std.algorithm;
import std.array;
import std.file;
import std.stdio;
import std.string;


int main()
{
	auto text = readText("docs.json");
	auto json = parseJson(text);
	Json*[] filtered;
	
	foreach( ref mod; json ){
		if( mod.name.get!string.startsWith("vibe.") )
			filtered ~= &mod;
	}
	
	sort!q{a.name < b.name}(filtered);
	
	Json[] ret;
	foreach( j; filtered ) ret ~= *j;
	
	auto dst = appender!string();
	toPrettyJson(dst, Json(ret));
	std.file.write("docs.json", dst.data);
	return 0;
}
