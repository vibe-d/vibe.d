import std.algorithm.iteration : map;
import std.array;
import std.datetime;
import std.range;
import vibe.core.core;
import vibe.core.stream;
import vibe.data.bson;
import vibe.data.json;
import vibe.data.serialization;
import vibe.http.client;
import vibe.http.router;
import vibe.http.server;
import vibe.stream.memory;
import vibe.stream.operations;
import vibe.web.rest;

void main()
@safe {
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	auto router = new URLRouter;
	router.registerRestInterface(new Llama);
	auto listener = listenHTTP(settings, router);
	scope (exit) listener.stopListening();
	immutable addr = listener.bindAddresses[0];

	auto api = new RestInterfaceClient!ILlama("http://"~addr.toString);
	assert(api.getDataStream().readAll() == testdata);
	assert(api.getDataStream2().readAll() == testdata);
	assert(api.getData() == testdata);
	assert(api.getData2() == testdata);

	// the first three routes should yield raw bytes
	foreach (endpoint; ["data_stream", "data_stream2", "data"]) {
		requestHTTP("http://"~addr.toString()~"/"~endpoint,
			(scope req) {},
			(scope res) {
				assert(res.statusCode == 200);
				assert(res.headers["Content-Type"] == "application/octet-stream");
				assert(res.bodyReader.readAll() == testdata);
			}
		);
	}

	// getData2 should yield BSON by default and JSON on request
	requestHTTP("http://"~addr.toString()~"/data2",
		(scope req) {
			req.headers["Accept"] = "application/json";
		},
		(scope res) {
			assert(res.statusCode == 200);
			assert(res.headers["Content-Type"] == "application/json; charset=UTF-8");
			assert(res.bodyReader.readAllUTF8().deserializeJson!(ubyte[]) == testdata);
		}
	);

	requestHTTP("http://"~addr.toString()~"/data2",
		(scope req) {},
		(scope res) {
			assert(res.statusCode == 200);
			assert(res.headers["Content-Type"] == "application/bson");
			auto data = cast(immutable)res.bodyReader.readAll();
			assert(fromBsonData!(Bson.Type)(data) == Bson.Type.binData);
			assert(Bson(Bson.Type.binData, data[1 .. $]).deserializeBson!(ubyte[]) == testdata);
		}
	);
}

interface ILlama {
@safe:
	InputStream getDataStream();
	InputStreamProxy getDataStream2();

	@serializeAsRawBytes
	immutable(ubyte)[] getData();

	@serializeAsBson @serializeAsJson
	immutable(ubyte)[] getData2();
}

class Llama : ILlama {
	InputStream getDataStream()
	{
		import vibe.internal.interfaceproxy : asInterface;
		auto str = createMemoryStream(testdata.dup);
		return str.asInterface!InputStream;
	}

	InputStreamProxy getDataStream2()
	{
		auto str = createMemoryStream(testdata.dup);
		return InputStreamProxy(str);
	}

	immutable(ubyte)[] getData()
	{
		return testdata;
	}

	immutable(ubyte)[] getData2()
	{
		return testdata;
	}
}

static immutable(ubyte)[] testdata = iota(2000).map!(i => cast(ubyte)i).array;

enum serializeAsJson = resultSerializer!(jsonSerialize, jsonDeserialize, "application/json; charset=UTF-8")();
enum serializeAsBson = resultSerializer!(bsonSerialize, bsonDeserialize, "application/bson")();
enum serializeAsRawBytes = resultSerializer!(rawSerialize, rawDeserialize, "application/octet-stream")();

void jsonSerialize (alias P, T, RT) (ref RT output_range, const scope ref T value)
@safe {
	static struct R {
		typeof(output_range) underlying;
		void put(char ch) { underlying.put(ch); }
		void put(const(char)[] ch) { underlying.put(cast(const(ubyte)[])ch); }
	}
	auto dst = R(output_range);
	value.serializeWithPolicy!(JsonStringSerializer!R, P) (dst);
}

T jsonDeserialize (alias P, T, R) (R input_range)
@safe {
	import std.string : assumeUTF;
	return deserializeWithPolicy!(JsonStringSerializer!(typeof(assumeUTF(input_range))), P, T)
		(assumeUTF(input_range));
}

void bsonSerialize (alias P, T, RT) (ref RT output_range, const scope ref T value)
@safe {
	auto bson = value.serializeWithPolicy!(BsonSerializer, P)(null);
	output_range.put(bson.type.toBsonData);
	output_range.put(bson.data);
}

T bsonDeserialize (alias P, T, R) (R input_range)
@safe {
	import std.array : array;
	auto data = () @trusted { return cast(immutable(ubyte)[])input_range.array; } ();
	if (!data.length) throw new Exception("Malformed BSON data");
	auto type = fromBsonData!(Bson.Type)(data);
	return deserializeWithPolicy!(BsonSerializer, P, T)(Bson(type, data[1 .. $]));
}

void rawSerialize (alias P, T, RT) (ref RT output_range, const scope ref T value)
@safe {
	output_range.put(value);
}

T rawDeserialize (alias P, T, R) (R input_range)
@trusted {
	return cast(T)input_range.array;
}

