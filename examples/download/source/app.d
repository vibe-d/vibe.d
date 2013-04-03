import vibe.core.log;
import vibe.inet.urltransfer;
import vibe.stream.operations;

void main()
{
	download("http://google.com/", (scope res){
		logInfo("Response: %s", cast(string)res.readAll());
	});
}
