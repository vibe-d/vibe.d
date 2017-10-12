import vibe.inet.url;
import vibe.http.client;
import vibe.stream.operations;
import std.stdio;

void main()
{
	URL url = URL("http+unix://%2Fvar%2Frun%2Fdocker.sock/containers/json");
	writeln(url);
	requestHTTP(url,(scope req){},(scope res){
		writeln(res.bodyReader.readAllUTF8);
		});
}
