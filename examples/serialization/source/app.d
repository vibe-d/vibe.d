import vibe.core.log;
import vibe.data.serialization;
import vibe.data.json;
import vibe.data.bson;
import std.array : Appender, appender;


void main()
{
	// set up some data to serialize
	Data data;
	data.number = 13;
	data.requiredNumber = 42;
	data.messages ~= "Hello";
	data.messages ~= "World";

	// serialize to a Json runtime value
	logInfo("Serialize to Json value:");
	auto json = serializeToJson(data);
	logInfo("  result: %s", json.toString());
	auto dedata = deserializeJson!Data(json);
	logInfo("  deserialized: %s %s %s %s", dedata.number, dedata.requiredNumber, dedata.messages, dedata.custom.counter);
	logInfo(" ");

	// serialize directly as a JSON string using an output range (Appender)
	logInfo("Serialize to JSON string:");
	auto app = appender!string();
	serializeToJson(app, data);
	logInfo("  result: %s", app.data);
	app = appender!string();
	serialize!(JsonStringSerializer!(Appender!string, true))(data, app);
	logInfo("  pretty result: %s", app.data);
	auto dedata2 = deserialize!(JsonStringSerializer!string, Data)(app.data);
	logInfo("  deserialized: %s %s %s %s", dedata2.number, dedata2.requiredNumber, dedata2.messages, dedata2.custom.counter);
	logInfo(" ");

	// serialize to a BSON value (binary in-memory representation)
	logInfo("Serialize to BSON:");
	auto bson = serializeToBson(data);
	logInfo("  result: %s", bson.toJson().toString());
	auto dedata3 = deserializeBson!Data(bson);
	logInfo("  deserialized: %s %s %s %s", dedata3.number, dedata3.requiredNumber, dedata3.messages, dedata3.custom.counter);
}


// The root data type used for serialization
struct Data {
	// this field can be left out or set to null in the deserialization input
	@optional int number = 12;

	// change how the field is represented in the serialized output
	@name("required-number") int requiredNumber;

	// the toJson/fromJson methods of this type allow custom serialization
	CustomJsonRep custom;

	string[] messages;
}


// A type with custom JSON serialization support
struct CustomJsonRep {
	ulong counter = 13371337;

	static CustomJsonRep fromJson(Json value)
	{
		CustomJsonRep ret;
		ret.counter = value["loword"].get!long | (value["hiword"].get!long << 16);
		return ret;
	}

	Json toJson()
	const {
		auto ret = Json.emptyObject;
		ret["loword"] = counter & 0xFFFF;
		ret["hiword"] = (counter >> 16) & 0xFFFF;
		return ret;
	}
}
