import vibe.inet.url;
import vibe.http.client;
import vibe.stream.operations;
import std.stdio;

void main()
{
	URL url = URL("http+unix://%2Ftmp%2Fvibe.sock/hello");
	writeln(url);
	requestHTTP(url,(scope req){},(scope res){
		writeln(res.bodyReader.readAllUTF8);
		});
}
