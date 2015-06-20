/**
 * Implements REST server private functions and types.
 *
 * This module is private and should not be imported from outside of Vibe.d
 *
 * Copyright: © 2015 RejectedSoftware e.K.
 * License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
 * Authors: Mathias Lang
 */
module vibe.web.internal.rest_server;

import vibe.web.common;
import vibe.http.server;
import vibe.web.rest : RestInterfaceSettings;
import vibe.web.internal.rest;
import vibe.web.internal.routes;
import vibe.core.log;
import vibe.internal.meta.uda;
import vibe.data.json;
import std.traits;
import std.typetuple;

static if (__VERSION__ >= 2067)
	mixin("package (vibe.web):");

/**
 * Generate an handler that will wrap the server's method
 *
 * This function returns an handler, generated at compile time, that
 * will deserialize the parameters, pass them to the function implemented
 * by the user, and return what it needs to return, be it header parameters
 * or body, which is at the moment either a pure string or a Json object.
 *
 * One thing that makes this method more complex that it needs be is the
 * inability for D to attach UDA to parameters. This means we have to roll
 * our own implementation, which tries to be as easy to use as possible.
 * We'll require the user to give the name of the parameter as a string to
 * our UDA. Hopefully, we're also able to detect at compile time if the user
 * made a typo of any kind (see $(D genInterfaceValidationError)).
 *
 * Note:
 * Lots of abbreviations are used to ease the code, such as
 * PTT (ParameterTypeTuple), WPAT (WebParamAttributeTuple)
 * and PWPAT (ParameterWebParamAttributeTuple).
 *
 * Params:
 *	T = type of the object which represent the REST server (user implemented).
 *	Func = An alias to the function of $(D T) to wrap.
 *
 *	inst = REST server on which to call our $(D Func).
 *	settings = REST server configuration.
 *
 * Returns:
 *	A delegate suitable to use as an handler for an HTTP request.
 */
HTTPServerRequestDelegate jsonMethodHandler(T, alias Func)(T inst, RestInterfaceSettings settings)
{
	import std.string : format;
	import std.algorithm : startsWith;

	import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
	import vibe.http.common : HTTPStatusException, HTTPStatus, enforceBadRequest;
	import vibe.utils.string : sanitizeUTF8;
	import vibe.internal.meta.funcattr : IsAttributedParameter;

	alias PT = ParameterTypeTuple!Func;
	alias RT = ReturnType!Func;
	alias ParamDefaults = ParameterDefaultValueTuple!Func;
	alias WPAT = UDATuple!(WebParamAttribute, Func);

	enum Method = __traits(identifier, Func);
	enum ParamNames = [ ParameterIdentifierTuple!Func ];
	enum FuncId = (fullyQualifiedName!T~ "." ~ Method);

	void handler(HTTPServerRequest req, HTTPServerResponse res)
	{
		PT params;

		foreach (i, P; PT) {
			// will be re-written by UDA function anyway
			static if (!IsAttributedParameter!(Func, ParamNames[i])) {
				// Comparison template for anySatisfy
				//template Cmp(WebParamAttribute attr) { enum Cmp = (attr.identifier == ParamNames[i]); }
				mixin(GenCmp!("Loop", i, ParamNames[i]).Decl);
				// Find origin of parameter
				static if (i == 0 && ParamNames[i] == "id") {
					// legacy special case for :id, backwards-compatibility
					logDebug("id %s", req.params["id"]);
					params[i] = fromRestString!P(req.params["id"]);
				} else static if (anySatisfy!(mixin(GenCmp!("Loop", i, ParamNames[i]).Name), WPAT)) {
					// User anotated the origin of this parameter.
					alias PWPAT = Filter!(mixin(GenCmp!("Loop", i, ParamNames[i]).Name), WPAT);
					// @headerParam.
					static if (PWPAT[0].origin == WebParamAttribute.Origin.Header) {
						// If it has no default value
						static if (is (ParamDefaults[i] == void)) {
							auto fld = enforceBadRequest(PWPAT[0].field in req.headers,
							format("Expected field '%s' in header", PWPAT[0].field));
						} else {
							auto fld = PWPAT[0].field in req.headers;
								if (fld is null) {
								params[i] = ParamDefaults[i];
								logDebug("No header param %s, using default value", PWPAT[0].identifier);
								continue;
							}
						}
						logDebug("Header param: %s <- %s", PWPAT[0].identifier, *fld);
						params[i] = fromRestString!P(*fld);
					} else static if (PWPAT[0].origin == WebParamAttribute.Origin.Query) {
						// Note: Doesn't work if HTTPServerOption.parseQueryString is disabled.
						static if (is (ParamDefaults[i] == void)) {
							auto fld = enforceBadRequest(PWPAT[0].field in req.query,
										     format("Expected form field '%s' in query", PWPAT[0].field));
						} else {
							auto fld = PWPAT[0].field in req.query;
							if (fld is null) {
								params[i] = ParamDefaults[i];
								logDebug("No query param %s, using default value", PWPAT[0].identifier);
								continue;
							}
						}
						logDebug("Query param: %s <- %s", PWPAT[0].identifier, *fld);
						params[i] = fromRestString!P(*fld);
					} else static if (PWPAT[0].origin == WebParamAttribute.Origin.Body) {
						enforceBadRequest(
								  req.contentType == "application/json",
								  "The Content-Type header needs to be set to application/json."
								  );
						enforceBadRequest(
								  req.json.type != Json.Type.Undefined,
								  "The request body does not contain a valid JSON value."
								  );
						enforceBadRequest(
								  req.json.type == Json.Type.Object,
								  "The request body must contain a JSON object with an entry for each parameter."
								  );

                        auto par = req.json[PWPAT[0].field];
						static if (is(ParamDefaults[i] == void)) {
							enforceBadRequest(par.type != Json.Type.Undefined,
									  format("Missing parameter %s", PWPAT[0].field)
									  );
						} else {
							if (par.type == Json.Type.Undefined) {
								logDebug("No body param %s, using default value", PWPAT[0].identifier);
								params[i] = ParamDefaults[i];
								continue;
							}
                        }
                        params[i] = deserializeJson!P(par);
                        logDebug("Body param: %s <- %s", PWPAT[0].identifier, par);
					} else static assert (false, "Internal error: Origin "~to!string(PWPAT[0].origin)~" is not implemented.");
				} else static if (ParamNames[i].startsWith("_")) {
					// URL parameter
					static if (ParamNames[i] != "_dummy") {
						enforceBadRequest(
							ParamNames[i][1 .. $] in req.params,
							format("req.param[%s] was not set!", ParamNames[i][1 .. $])
						);
						logDebug("param %s %s", ParamNames[i], req.params[ParamNames[i][1 .. $]]);
						params[i] = fromRestString!P(req.params[ParamNames[i][1 .. $]]);
					}
				} else {
					// normal parameter
					alias DefVal = ParamDefaults[i];
					auto pname = stripTUnderscore(ParamNames[i], settings);

					if (req.method == HTTPMethod.GET) {
						logDebug("query %s of %s", pname, req.query);

						static if (is (DefVal == void)) {
							enforceBadRequest(
								pname in req.query,
								format("Missing query parameter '%s'", pname)
							);
						} else {
							if (pname !in req.query) {
								params[i] = DefVal;
								continue;
							}
						}

						params[i] = fromRestString!P(req.query[pname]);
					} else {
						logDebug("%s %s", FuncId, pname);

						enforceBadRequest(
							req.contentType == "application/json",
							"The Content-Type header needs to be set to application/json."
						);
						enforceBadRequest(
							req.json.type != Json.Type.Undefined,
							"The request body does not contain a valid JSON value."
						);
						enforceBadRequest(
							req.json.type == Json.Type.Object,
							"The request body must contain a JSON object with an entry for each parameter."
						);

						static if (is(DefVal == void)) {
							auto par = req.json[pname];
							enforceBadRequest(par.type != Json.Type.Undefined,
									  format("Missing parameter %s", pname)
									  );
							params[i] = deserializeJson!P(par);
						} else {
							if (req.json[pname].type == Json.Type.Undefined) {
								params[i] = DefVal;
								continue;
							}
						}
					}
				}
			}
		}

		try {
			import vibe.internal.meta.funcattr;

			auto handler = createAttributedFunction!Func(req, res);

			static if (is(RT == void)) {
				handler(&__traits(getMember, inst, Method), params);
				res.writeJsonBody(Json.emptyObject);
			} else {
				auto ret = handler(&__traits(getMember, inst, Method), params);
				res.writeJsonBody(ret);
			}
		} catch (HTTPStatusException e) {
			if (res.headerWritten) logDebug("Response already started when a HTTPStatusException was thrown. Client will not receive the proper error code (%s)!", e.status);
			else res.writeJsonBody([ "statusMessage": e.msg ], e.status);
		} catch (Exception e) {
			// TODO: better error description!
			logDebug("REST handler exception: %s", e.toString());
			if (res.headerWritten) logDebug("Response already started. Client will not receive an error code!");
			else res.writeJsonBody(
				[ "statusMessage": e.msg, "statusDebugMessage": sanitizeUTF8(cast(ubyte[])e.toString()) ],
				HTTPStatus.internalServerError
			);
		}
	}

	return &handler;
}
