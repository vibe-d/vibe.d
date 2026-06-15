import vibe.d;

interface API
{
    @safe:

    public void postPing(@viaStatus out HTTPStatus status);
    public void postPong();
}

class Service : API
{
    int pinged, ponged;

    public override void postPing(out HTTPStatus status) @safe
    {
        this.pinged++;
        status = HTTPStatus.created;
    }

    public override void postPong() @safe
    {
        this.ponged++;
    }
}

void main()
@safe
{
    auto settings = new HTTPServerSettings;
    settings.port = 0;
    settings.bindAddresses = ["127.0.0.1"];

    scope router = new URLRouter;
    scope svc = new Service();
    router.registerRestInterface(svc);

    auto listener = listenHTTP(settings, router);
    scope (exit) listener.stopListening();

    auto address = listener.bindAddresses[0];

    assert(svc.pinged + svc.ponged == 0);
    requestHTTP("http://" ~ address.toString() ~ "/ping",
        (scope HTTPClientRequest req) {
            req.method = HTTPMethod.POST;
        },
        (scope HTTPClientResponse res) {
            assert(svc.pinged == 1);
            assert(svc.ponged == 0);
            assert(res.statusCode == HTTPStatus.created,
                "Expected 201 Created, got " ~ res.statusCode.to!string);
            assert(("Content-Type" in res.headers) is null,
                "Unexpected Content-Type: " ~ res.headers.get("Content-Type", ""));
            assert(("Content-Length" in res.headers) is null,
                "Unexpected Content-Length: " ~ res.headers.get("Content-Length", ""));
            res.dropBody();
        }
    );

    requestHTTP("http://" ~ address.toString() ~ "/pong",
        (scope HTTPClientRequest req) {
            req.method = HTTPMethod.POST;
        },
        (scope HTTPClientResponse res) {
            assert(svc.pinged == 1);
            assert(svc.ponged == 1);
            assert(res.statusCode == HTTPStatus.noContent,
                "Expected 204 No Content, got " ~ res.statusCode.to!string);
            assert(("Content-Type" in res.headers) is null,
                "Unexpected Content-Type: " ~ res.headers.get("Content-Type", ""));
            assert(("Content-Length" in res.headers) is null,
                "Unexpected Content-Length: " ~ res.headers.get("Content-Length", ""));
            res.dropBody();
        }
    );
}
