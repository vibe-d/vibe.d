
/** Web based, bi-directional, concurrent RPC implementation.

	This module implements a generic RPC mechanism that allows transparently
	calling remote functions over an HTTP based network connection. The current
	implementation is based on a WebSocket based protocol, serializing method
	arguments and return types as BSON.

	The RPC API is defined using interfaces, very similar to the system in
	`vibe.web.rest`. It supports methods with or without a return value, normal,
	`ref` and `out` parameters, exceptions, properties returning interfaces,
	and properties returning `vibe.web.rest.Collection!I`.

	Authorization and authentication is supported via the `vibe.web.auth`
	framework. When using it, the `authenticate` method should be defined as
	`@noRoute T authenticate(ref const WebRPCPerrInfo)`, where `T` is the type
	passed to the `@requiresAuth` UDA.

	Any remote function calls can execute concurrently, so that the connection
	never gets blocked by an unfinished function call.

	Note that this system will establish a bi-directional communication
	facility, allowing both, the client and the server, to initiate calls. This
	effectively forms a peer-to-peer connection instead of a client-server
	connection. The advantage of using HTTP as the basis is that this makes it
	easy to establish P2P connections where one of the peers is behind a
	firewall or NAT layer, but the other peer can be reached through a public
	port or through a (reverse) proxy server.


	Defining_a_simple_RPC_interface:

	The API for the interface is defined as a normal D interface:

	---
	interface ExampleAPI {
		void performSomeAction();
		int getSomeInformation();
	}
	---

	An implementation of this interface is required on both, the server and the
	client side:

	---
	class ExampleAPIImplementation : ExampleAPI {
		void performSomeAction() { ... }
		int getSomeInformation() { return ...; }
	}
	---

	With this defined, this is the basic code needed to set up the server side:

	---
	void handleIncomingPeer(WebRPCPeer!ExampleAPI peer)
	@safe nothrow {
		// this gets executed for any client that connects to the server
		try {
			peer.performSomeAction();
		} catch (Exception e) {
			logException(e, "Failed to perform peer action");
		}
	}

	auto r = new URLRouter;
	r.registerWebRPC!ExampleAPI(r, "/rpc", new ExampleAPIImplementation, &handlePeer);
	// could register other routes here, such as for a web or REST interface

	auto l = listenHTTP("127.0.0.1:1234", r);
	---

	A client can now connect to the server and access the API as well:

	---
	auto peer = connectWebRPC(URL("http://127.0.0.1:1234/rpc"),
		new ExampleAPIImplementation);

	peer.performSomeAction();
	---


	Copyright: © 2024 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.web.rpc;

import vibe.core.log;
import vibe.core.core : Task, runTask, yield;
import vibe.core.path : InetPath;
import vibe.core.stream : isInputStream;
import vibe.data.bson;
import vibe.inet.url : URL;
import vibe.http.router;
import vibe.http.server;
import vibe.http.websockets;
import vibe.stream.tls : TLSCertificateInformation;
import vibe.web.internal.rest.common : RestInterface, SubInterfaceType;
import vibe.web.auth;
import vibe.web.common;
import vibe.web.rest : Collection;

import std.meta;
import std.traits;


alias WebRPCPeerCallback(I) = void delegate(WebRPCPeer!I peer) @safe nothrow;


/** Registers a route for handling incoming WebRPC requests.

	The endpoint defined by `path` will attempt to establish a WebSocket
	connection with the client and subsequently enables bi-directional
	communication by listening for calls made by the client, as well as invoking
	the `peer_callback` to allow the server to make calls, too.

	Params:
		router = The `URLRouter` on which to register the endpoint
		path = Path of the registered endpoint
		implementation = The API implementation to invoke for incoming method
			calls
		peer_callback = Callback invoked for each incoming connection
*/
void registerWebRPC(I)(URLRouter router, string path, I implementation,
	WebRPCPeerCallback!I peer_callback)
	if (is(I == interface))
{
	router.get(path, (scope HTTPServerRequest req, scope HTTPServerResponse res) => handleWebRPC!I(implementation, peer_callback, req, res));
}


/** Connects to a WebRPC endpoint.

	This will perform a HTTP GET request to the supplied `url` and attempts
	to establish a WebSocket connection for bi-directional communication.
	Incoming method calls will be forwarded to `implementation`.

	Params:
		url = URL of the endpoint to connect to
		implementation = The API implementation to invoke for incoming method
			calls

	Returns:
		A `WebRPCPeer` instance is returned, which exposes the API interface `I`
		for making outgoing method calls.
*/
WebRPCPeer!I connectWebRPC(I)(URL url, I implementation)
	if (is(I == interface))
{
	WebRPCPeerInfo info;
	auto ws = connectWebSocketEx(url, (scope req) {
		info.address = req.remoteAddress;
		info.certificate = req.peerCertificate;
	});
	auto h = new WebSocketHandler!I(ws, implementation, info);
	runTask(&h.runReadLoop);

	return WebRPCPeer!I(new WebRPCPeerImpl!(I, I, "")(h));
}


/** Provides information about a peer;
*/
struct WebRPCPeerInfo {
	// (Remote) address of the peer
	NetworkAddress address;

	// Information about the peer's TLS certificate, if any
	TLSCertificateInformation certificate;
}


/** Reference counted type used to access a peer's API.

	This struct defines an `alias this` to its `implementation` property in
	order to provide an interface implementation of `I`. Any calls on the
	methods of this implementation will be forwarded to the remote peer.

	Note that the WebRPC connection will be closed as soon as the last instance
	of a connected `WebRPCPeer` gets destroyed.
*/
struct WebRPCPeer(I) {
	private {
		WebRPCPeerImpl!(I, I, "") m_impl;
	}

@safe:

	private this(WebRPCPeerImpl!(I, I, "") impl)
	{
		m_impl = impl;
	}

	this(this)
	{
		if (m_impl && m_impl.m_handler)
			m_impl.m_handler.addRef();
	}

	~this()
	{
		if (m_impl && m_impl.m_handler)
			m_impl.m_handler.releaseRef();
	}

	/** Provides information about the remote peer.
	*/
	@property ref const(WebRPCPeerInfo) peerInformation() const { return m_impl.m_handler.m_peerInfo; }

	/** Accesses the remote peer's API interface.

		Note that this does not need to be called explicitly, as an `alias this`
		will make all methods of `I` available on `WebRPCPeer` directly.
	*/
	@property inout(I) implementation() inout { return m_impl; }

	///
	alias implementation this;
}


final class WebRPCPeerImpl(I, RootI, string method_prefix) : I
	if (is(I == interface) && is(RootI == interface))
{
	private alias Info = RestInterface!(I, false);

	mixin(generateModuleImports!I());

	private alias SubPeerImpl(alias method) = WebRPCPeerImpl!(SubInterfaceType!method, RootI, method_prefix ~ __traits(identifier, method) ~ ".");

	private {
		WebSocketHandler!RootI m_handler;
		staticMap!(SubPeerImpl, Info.SubInterfaceFunctions) m_subInterfaces;
	}

@safe:

	private this(WebSocketHandler!RootI handler)
	{
		m_handler = handler;
		foreach (i, SI; Info.SubInterfaceTypes)
			m_subInterfaces[i] = new WebRPCPeerImpl!(SI, RootI, method_prefix ~ __traits(identifier, Info.SubInterfaceFunctions[i]) ~ ".")(handler);
	}

	mixin(generateWebRPCPeerMethods!I());

	private ReturnType!method performCall(alias method, PARAMS...)(auto ref PARAMS params)
	{
		alias outparams = refOutParameterIndices!method;
		alias paramnames = ParameterIdentifierTuple!method;

		Bson args = Bson.emptyObject;
		foreach (i, pname; ParameterIdentifierTuple!method)
			static if (!is(ParameterTypeTuple!method[i] == AuthInfo!I) && !(ParameterStorageClassTuple!method[i] & ParameterStorageClass.out_))
				args[pname] = serializeToBson(params[i]);
		auto seq = m_handler.sendCall(method_prefix ~ __traits(identifier, method), args);
		auto ret = m_handler.waitForResponse(seq);
		static if (outparams.length > 0) {
			foreach (pi; outparams)
				params[pi] = ret[paramnames[pi]].deserializeBson!(PARAMS[pi]);
			static if (!is(ReturnType!method == void))
				return ret["return"].deserializeBson!(ReturnType!method);
		} else static if (isInputStream!(ReturnType!method)) {
			throw new Exception("Stream type results are not yet supported");
		} else static if (!is(ReturnType!method == void)) {
			return ret.deserializeBson!(ReturnType!method);
		}
	}
}


version (unittest) {
	private interface TestSubI {
	@safe:
		int test();
	}

	private interface TestCollI {
	@safe:
		struct CollectionIndices {
			int index;
		}

		@property int count();
		int get(int index);
	}

	@requiresAuth!TestAuthInfo
	private interface TestAuthI {
	@safe:
		@noAuth void login();
		@noAuth int testUnauthenticated();
		@auth(Role.authenticatedPeer) int testAuthenticated();
		@noRoute TestAuthInfo authenticate(ref const WebRPCPeerInfo peer);
	}

	struct TestAuthInfo {
		bool authenticated;

		bool isAuthenticatedPeer() @safe nothrow { return authenticated; }
	}

	private interface TestI {
	@safe:
		@property TestSubI sub();
		@property Collection!TestCollI items();
		@property TestAuthI auth();
		int add(int a, int b);
		void add2(int a, int b, out int c);
		int addmul(ref int a, int b, int c);
		void except();
	}

	private class TestSubC : TestSubI {
		int test() { return 42; }
	}

	private class TestCollC : TestCollI {
		@property int count() { return 4; }
		int get(int index) { return index * 2; }
	}

	private class TestAuthC : TestAuthI {
		private bool m_authenticated;

		void login() { m_authenticated = true; }
		@noAuth int testUnauthenticated() { return 1; }
		@auth(Role.authenticatedPeer) int testAuthenticated() { return 2; }

		@noRoute
		TestAuthInfo authenticate(ref const WebRPCPeerInfo peer)
		{
			return TestAuthInfo(m_authenticated);
		}
	}

	private class TestC : TestI {
		TestSubC m_sub;
		TestCollC m_items;
		TestAuthC m_auth;
		this() {
			m_sub = new TestSubC;
			m_items = new TestCollC;
			m_auth = new TestAuthC;
		}
		@property TestSubC sub() { return m_sub; }
		@property Collection!TestCollI items() { return Collection!TestCollI(m_items); }
		@property TestAuthI auth() { return m_auth; }
		int add(int a, int b) { return a + b; }
		void add2(int a, int b, out int c) { c = a + b; }
		int addmul(ref int a, int b, int c) { a += b; return a * c; }
		void except() { throw new Exception("Error!"); }
	}
}

unittest {
	import core.time : seconds;
	import std.exception : assertThrown;
	import vibe.core.core : setTimer;

	auto tm = setTimer(1.seconds, { assert(false, "Test timeout"); });
	scope (exit) tm.stop();

	auto r = new URLRouter;
	bool got_client = false;
	registerWebRPC!TestI(r, "/rpc", new TestC, (WebRPCPeer!TestI peer) @safe nothrow {
		// test the reverse direction (server calls client)
		try assert(peer.add(2, 3) == 5);
		catch (Exception e) assert(false, e.msg);
		got_client = true;
	});

	auto l = listenHTTP("127.0.0.1:0", r);
	auto url = URL("http", "127.0.0.1", l.bindAddresses[0].port, InetPath("/rpc"));
	auto cli = connectWebRPC!TestI(url, new TestC);

	// simple method call with return value
	assert(cli.add(3, 4) == 7);

	// sub interface method call
	assert(cli.sub.test() == 42);

	{ // call with out parameter
		int c;
		cli.add2(2, 3, c);
		assert(c == 5);
	}

	{ // call with ref parameter
		int a;
		a = 4;
		assert(cli.addmul(a, 2, 3) == 18);
		assert(a == 6);
	}

	try { // call with exception
		cli.except();
		assert(false);
	} catch (Exception e) {
		assert(e.msg == "Error!");
	}

	// Collection!I syntax
	assert(cli.items.count == 4);
	foreach (i; 0 .. 4)
		assert(cli.items[i].get() == i * 2);

	// "auth" framework tests
	assert(cli.auth.testUnauthenticated() == 1);
	assertThrown(cli.auth.testAuthenticated());
	cli.auth.login();
	assert(cli.auth.testAuthenticated() == 2);

	// make sure the reverse direction got established and tested
	while (!got_client) yield();
}


private void handleWebRPC(I)(I implementation, WebRPCPeerCallback!I peer_callback,
	scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	void handleSocket(scope WebSocket ws)
	nothrow {
		import std.exception : assumeWontThrow;

		scope const(HTTPServerRequest) req;
		auto info = const(WebRPCPeerInfo)(
			ws.request.assumeWontThrow.clientAddress,
			ws.request.assumeWontThrow.clientCertificate);
		auto h = new WebSocketHandler!I(ws, implementation, info);
		h.addRef(); // WebRPCPeer expects to receive an already owned handler

		// start reverse communication asynchronously
		auto t = runTask((WebRPCPeerCallback!I cb, WebSocketHandler!I h) {
			cb(WebRPCPeer!I(new WebRPCPeerImpl!(I, I, "")(h)));
		}, peer_callback, h);

		// handle incoming messages
		h.runReadLoop();
		h.releaseRef();
		t.joinUninterruptible();

		try ws.close();
		catch (Exception e) logException(e, "Failed to close WebSocket after handling WebRPC connection");
		h.m_socket = WebSocket.init;
	}

	handleWebSocket(&handleSocket, req, res);
}


private string generateWebRPCPeerMethods(I)()
{
	import std.array : join;
	import std.string : format;
	import vibe.web.common : NoRouteAttribute;

	alias Info = RestInterface!(I, false);

	string ret = q{
		import vibe.internal.meta.codegen : CloneFunction;
	};

	// generate sub interface methods
	foreach (i, SI; Info.SubInterfaceTypes) {
		alias F = Info.SubInterfaceFunctions[i];
		alias RT = ReturnType!F;
		alias ParamNames = ParameterIdentifierTuple!F;
		static if (ParamNames.length == 0) enum pnames = "";
		else enum pnames = ", " ~ [ParamNames].join(", ");
		static if (isInstanceOf!(Collection, RT)) {
			ret ~= q{
					mixin CloneFunction!(Info.SubInterfaceFunctions[%1$s], q{
						return Collection!(%2$s)(m_subInterfaces[%1$s]%3$s);
					});
				}.format(i, fullyQualifiedName!SI, pnames);
		} else {
			ret ~= q{
					mixin CloneFunction!(Info.SubInterfaceFunctions[%1$s], q{
						return m_subInterfaces[%1$s];
					});
				}.format(i);
		}
	}

	// generate route methods
	foreach (i, F; Info.RouteFunctions) {
		alias ParamNames = ParameterIdentifierTuple!F;
		static if (ParamNames.length == 0) enum pnames = "";
		else enum pnames = [ParamNames].join(", ");

		ret ~= q{
				mixin CloneFunction!(Info.RouteFunctions[%2$s], q{
					return performCall!(Info.RouteFunctions[%2$s])(%3$s);
				});
			}.format(fullyQualifiedName!F, i, pnames);
	}

	// generate stubs for non-route functions
	static foreach (m; __traits(allMembers, I))
		foreach (i, fun; MemberFunctionsTuple!(I, m))
			static if (hasUDA!(fun, NoRouteAttribute))
				ret ~= q{
					mixin CloneFunction!(MemberFunctionsTuple!(I, "%s")[%s], q{
						assert(false);
					});
				}.format(m, i);

	return ret;
}


private string generateModuleImports(I)()
{
	if (!__ctfe)
		assert (false);

	import vibe.internal.meta.codegen : getRequiredImports;
	import std.algorithm : map;
	import std.array : join;

	auto modules = getRequiredImports!I();
	return join(map!(a => "static import " ~ a ~ ";")(modules), "\n");
}


private final class WebSocketHandler(I) {
	import vibe.core.sync : LocalManualEvent, TaskMutex, createManualEvent;

	private alias Info = RestInterface!(I, false);

	struct Res {
		Bson result;
		string error;
	}

	private {
		I m_impl;
		const WebRPCPeerInfo m_peerInfo;
		int m_refCount = 1;
		WebSocket m_socket;
		TaskMutex m_sendMutex;
		ulong m_sequence;
		Res[ulong] m_availableResponses;
		LocalManualEvent m_responseEvent;
	}

@safe:

	this(return WebSocket ws, I impl, ref const(WebRPCPeerInfo) peer_info)
	{
		m_impl = impl;
		m_peerInfo = peer_info;

		static if (__VERSION__ < 2106)
			() @trusted { m_socket = ws; } ();
		else m_socket = ws;
		m_sendMutex = new TaskMutex;
		m_responseEvent = createManualEvent();
	}

	void addRef()
	{
		m_refCount++;
	}

	void releaseRef()
	{
		if (!--m_refCount) {
			try m_socket.close();
			catch (Exception e) {
				logException(e, "Failed to close WebSocket");
			}
			m_socket = null;
			m_responseEvent.emit();
		}
	}

	ulong sendCall(string method, Bson arguments)
	{
		m_sendMutex.lock();
		scope (exit) m_sendMutex.unlock();

		if (!m_socket || !m_socket.connected)
			throw new Exception("Connection closed before sending WebRPC call");

		WebRPCCallPacket pack;
		pack.sequence = m_sequence++;
		pack.method = method;
		pack.arguments = arguments;
		auto bpack = serializeToBson(pack);
		m_socket.send(WebRPCMessageType.call ~ bpack.data);
		return pack.sequence;
	}

	void sendResponse(ulong sequence, Bson result)
	{
		m_sendMutex.lock();
		scope (exit) m_sendMutex.unlock();

		if (!m_socket || !m_socket.connected)
			throw new Exception("Connection closed before sending WebRPC response");

		WebRPCResponsePacket res;
		res.sequence = sequence;
		res.result = result;
		auto bpack = serializeToBson(res);
		m_socket.send(WebRPCMessageType.response ~ bpack.data);
	}

	void sendErrorResponse(ulong sequence, string error_message)
	{
		m_sendMutex.lock();
		scope (exit) m_sendMutex.unlock();

		if (!m_socket || !m_socket.connected)
			throw new Exception("Connection closed before sending WebRPC error response");

		WebRPCErrorResponsePacket res;
		res.sequence = sequence;
		res.message = error_message;
		auto bpack = serializeToBson(res);
		m_socket.send(WebRPCMessageType.errorResponse ~ bpack.data);
	}


	Bson waitForResponse(ulong sequence)
	{
		auto ec = m_responseEvent.emitCount;
		while (true) {
			if (!m_socket || !m_socket.connected)
				throw new Exception("Connection closed while waiting for WebRPC response");
			if (auto pr = sequence in m_availableResponses) {
				if (pr.error !is null)
					throw new Exception(pr.error);
				auto ret = *pr;
				m_availableResponses.remove(sequence);
				return ret.result;
			}
			ec = m_responseEvent.wait(ec);
		}
	}

	private void terminateConnection()
	nothrow {
		if (!m_socket) return;
		try m_socket.close(WebSocketCloseReason.internalError);
		catch (Exception e2) {
			logException(e2, "Failed to close WebSocket after failure");
		}
	}

	void runReadLoop()
	nothrow {
		try {
			while (m_socket && m_socket.waitForData) {
				if (!m_socket) break;
				auto msg = m_socket.receiveBinary();
				auto brep = Bson(Bson.Type.object, msg[1 .. $].idup);
				switch (msg[0]) {
					default:
						logWarn("Unknown message type received (%s) - terminating WebRPC connection", brep["type"].opt!int(-1));
						m_socket.close();
						return;
					case WebRPCMessageType.call:
						addRef();
						runTask((WebSocketHandler handler, Bson brep) nothrow {
							scope (exit) handler.releaseRef();
							WebRPCCallPacket cmsg;
							try cmsg = deserializeBson!WebRPCCallPacket(brep);
							catch (Exception e) {
								logException(e, "Invalid call packet");
								handler.terminateConnection();
								return;
							}
							Bson res;
							try res = handler.invokeMethod(cmsg.method, cmsg.arguments);
							catch (Exception e) {
								logDiagnostic("WebRPC method %s has thrown: %s", cmsg.method, e.msg);
								try handler.sendErrorResponse(cmsg.sequence, e.msg);
								catch (Exception e) {
									logException(e, "Failed to send error response");
									handler.terminateConnection();
								}
								return;
							}
							try handler.sendResponse(cmsg.sequence, res);
							catch (Exception e) {
								logException(e, "Failed to send response");
								handler.terminateConnection();
							}
						}, this, brep);
						break;
					case WebRPCMessageType.response:
						auto rmsg = deserializeBson!WebRPCResponsePacket(brep);
						m_availableResponses[rmsg.sequence] = Res(rmsg.result, null);
						m_responseEvent.emit();
						break;
					case WebRPCMessageType.errorResponse:
						auto rmsg = deserializeBson!WebRPCErrorResponsePacket(brep);
						m_availableResponses[rmsg.sequence] = Res(Bson.init, rmsg.message);
						m_responseEvent.emit();
						break;
				}
			}
		} catch (Exception e) {
			logException(e, "WebRPC read failed");
			terminateConnection();
		}
	}

	private Bson invokeMethod(string name, Bson arguments)
	{
		switch (name) {
			default: throw new Exception("Unknown method called: " ~ name);
			static foreach (FI; recursiveInterfaceFunctions!(I, "")) {
				case FI.expand[2]: return invokeMethodF!(FI.expand)(arguments);
			}
		}
	}

	private Bson invokeMethodF(SI, alias method, string qualified_name)(Bson arguments)
	{
		alias outparams = refOutParameterIndices!method;
		alias paramnames = ParameterIdentifierTuple!method;

		SI impl = resolveImpl!qualified_name(m_impl, arguments);

		ParameterTypeTuple!method args;
		resolveArguments!method(impl, arguments, args);

		alias RT = typeof(__traits(getMember, impl, __traits(identifier, method))(args));
		static if (!is(RT == void)) {
			auto ret = __traits(getMember, impl, __traits(identifier, method))(args);
		} else {
			__traits(getMember, impl, __traits(identifier, method))(args);
		}
		Bson bret;
		static if (outparams.length > 0) {
			bret = Bson.emptyObject;
			foreach (pi; outparams)
				bret[paramnames[pi]] = serializeToBson(args[pi]);
			static if (is(typeof(ret)) && !isInputStream!(typeof(ret)))
				bret["return"] = serializeToBson(ret);
		} else static if (is(typeof(ret)) && !isInputStream!(typeof(ret))) {
			bret = serializeToBson(ret);
		}
		return bret;
	}

	private auto resolveImpl(string qualified_name, RI)(RI base, Bson arguments)
		if (is(RI == interface))
	{
		import std.string : indexOf;
		enum idx = qualified_name.indexOf('.');
		static if (idx < 0) return base;
		else {
			enum mname = qualified_name[0 .. idx];
			alias method = __traits(getMember, base, mname);

			ParameterTypeTuple!method args;
			resolveArguments!method(base, arguments, args);

			static if (isInstanceOf!(Collection, ReturnType!(__traits(getMember, base, mname))))
				return resolveImpl!(qualified_name[idx+1 .. $])(__traits(getMember, base, mname)(args).m_interface, arguments);
			else
				return resolveImpl!(qualified_name[idx+1 .. $])(__traits(getMember, base, mname)(args), arguments);
		}
	}

	private void resolveArguments(alias method, SI)(SI impl, Bson arguments, out typeof(ParameterTypeTuple!method.init) args)
	{
		alias paramnames = ParameterIdentifierTuple!method;

		static if (isAuthenticated!(SI, method)) {
			typeof(handleAuthentication!method(impl, m_peerInfo)) auth_info;

			auth_info = handleAuthentication!method(impl, m_peerInfo);
		}

		foreach (i, name; paramnames) {
			static if (is(typeof(args[i]) == AuthInfo!SI))
				args[i] = auth_info;
			else static if (!(ParameterStorageClassTuple!method[i] & ParameterStorageClass.out_))
				args[i] = deserializeBson!(typeof(args[i]))(arguments[name]);
		}

		static if (isAuthenticated!(SI, method))
			handleAuthorization!(SI, method, args)(auth_info);
	}
}


private enum WebRPCMessageType : ubyte {
	call = 1,
	response = 2,
	errorResponse = 3
}

private struct WebRPCCallPacket {
	ulong sequence;
	string method;
	Bson arguments;
}

private struct WebRPCResponsePacket {
	ulong sequence;
	Bson result;
}

private struct WebRPCErrorResponsePacket {
	ulong sequence;
	string message;
}


private template refOutParameterIndices(alias fun)
{
	alias pcls = ParameterStorageClassTuple!fun;
	template impl(size_t i) {
		static if (i < pcls.length) {
			static if (pcls[i] & (ParameterStorageClass.out_|ParameterStorageClass.ref_))
				alias impl = AliasSeq!(i, impl!(i+1));
			else alias impl = impl!(i+1);
		} else alias impl = AliasSeq!();
	}
	alias refOutParameterIndices = impl!0;
}

private template recursiveInterfaceFunctions(I, string method_prefix)
{
	import vibe.internal.meta.typetuple : Group;

	alias Info = RestInterface!(I, false);

	alias MethodEntry(alias method) = Group!(I, method, method_prefix ~ __traits(identifier, method));

	alias SubInterfaceEntry(alias method) = recursiveInterfaceFunctions!(SubInterfaceType!method, method_prefix ~ __traits(identifier, method) ~ ".");

	alias recursiveInterfaceFunctions = AliasSeq!(
		staticMap!(MethodEntry, Info.RouteFunctions),
		staticMap!(SubInterfaceEntry, Info.SubInterfaceFunctions)
	);
}
