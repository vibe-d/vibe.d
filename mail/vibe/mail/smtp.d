/**
	SMTP client implementation

	Copyright: © 2012-2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.mail.smtp;

import vibe.core.log;
import vibe.core.net;
import vibe.inet.message;
import vibe.stream.operations;
import vibe.stream.tls;
import vibe.internal.interfaceproxy;

import std.algorithm : map, splitter;
import std.base64;
import std.conv;
import std.exception;
import std.string;

@safe:


/**
	Determines the (encryption) type of an SMTP connection.
*/
enum SMTPConnectionType {
	plain,
	tls,
	startTLS,
}


/** Represents the different status codes for SMTP replies.
*/
enum SMTPStatus {
	_success = 200,
	systemStatus = 211,
	helpMessage = 214,
	serviceReady = 220,
	serviceClosing = 221,
	success = 250,
	forwarding = 251,
	serverAuthReady = 334,
	startMailInput = 354,
	serviceUnavailable = 421,
	mailboxTemporarilyUnavailable = 450,
	processingError = 451,
	outOfDiskSpace = 452,
	commandUnrecognized = 500,
	invalidParameters = 501,
	commandNotImplemented = 502,
	badCommandSequence = 503,
	commandParameterNotImplemented = 504,
	domainAcceptsNoMail = 521,
	accessDenied = 530,
	mailboxUnavailable = 550,
	userNotLocal = 551,
	exceededStorageAllocation = 552,
	mailboxNameNotAllowed = 553,
	transactionFailed = 554
}


/**
	Represents the authentication mechanism used by the SMTP client.
*/
enum SMTPAuthType {
	none,
	plain,
	login,
	cramMd5
}


/**
	Configuration options for the SMTP client.
*/
final class SMTPClientSettings {
	/// SMTP host to connect to
	string host = "127.0.0.1";
	/// Port on which to connect
	ushort port = 25;
	/// Own network name to report to the SMTP server
	string localname = "localhost";
	/// Type of encryption protocol to use
	SMTPConnectionType connectionType = SMTPConnectionType.plain;
	/// Authentication type to use
	SMTPAuthType authType = SMTPAuthType.none;

	/// Determines how the server certificate gets validated.
	TLSPeerValidationMode tlsValidationMode = TLSPeerValidationMode.trustedCert;
	/// Version(s) of the TLS/SSL protocol to use
	TLSVersion tlsVersion = TLSVersion.any;
	/// Callback to invoke to enable additional setup of the TLS context.
	void delegate(scope TLSContext) tlsContextSetup;

	/// User name to use for authentication
	string username;
	/// Password to use for authentication
	string password;

	this() {}
	this(string host, ushort port) { this.host = host; this.port = port; }
}


/**
	Represents an email message, including its headers.
*/
final class Mail {
	InetHeaderMap headers;
	string bodyText;
}

/**
	Sends an e-mail using the given settings.

	The mail parameter must point to a valid $(D Mail) object and should define
	at least the headers "To", "From", Sender" and "Subject".

	Valid headers can be found at http://tools.ietf.org/html/rfc4021
*/
void sendMail(in SMTPClientSettings settings, Mail mail)
{
	TCPConnection raw_conn;
	try {
		raw_conn = connectTCP(settings.host, settings.port);
	} catch(Exception e){
		throw new Exception("Failed to connect to SMTP server at "~settings.host~" port "
			~to!string(settings.port), e);
	}
	scope(exit) raw_conn.close();

	InterfaceProxy!Stream conn = raw_conn;

	if( settings.connectionType == SMTPConnectionType.tls ){
		auto ctx = createTLSContext(TLSContextKind.client, settings.tlsVersion);
		ctx.peerValidationMode = settings.tlsValidationMode;
		if (settings.tlsContextSetup) settings.tlsContextSetup(ctx);
		conn = createTLSStream(raw_conn, ctx, TLSStreamState.connecting, settings.host, raw_conn.remoteAddress);
	}

	expectStatus(conn, SMTPStatus.serviceReady, "connection establishment");

	void greet() @safe {
		conn.write("EHLO "~settings.localname~"\r\n");
		while(true){ // simple skipping of
			auto ln = () @trusted { return cast(string)conn.readLine(); } ();
			logDebug("EHLO response: %s", ln);
			auto sidx = ln.indexOf(' ');
			auto didx = ln.indexOf('-');
			if( sidx > 0 && (didx < 0 || didx > sidx) ){
				enforce(ln[0 .. sidx] == "250", "Server not ready (response "~ln[0 .. sidx]~")");
				break;
			}
		}
	}

	greet();

	if (settings.connectionType == SMTPConnectionType.startTLS) {
		conn.write("STARTTLS\r\n");
		expectStatus(conn, SMTPStatus.serviceReady, "STARTTLS");
		auto ctx = createTLSContext(TLSContextKind.client, settings.tlsVersion);
		ctx.peerValidationMode = settings.tlsValidationMode;
		if (settings.tlsContextSetup) settings.tlsContextSetup(ctx);
		conn = createTLSStream(raw_conn, ctx, TLSStreamState.connecting, settings.host, raw_conn.remoteAddress);
		greet();
	}

	final switch (settings.authType) {
		case SMTPAuthType.none: break;
		case SMTPAuthType.plain:
			logDebug("seding auth");
			conn.write("AUTH PLAIN\r\n");
			expectStatus(conn, SMTPStatus.serverAuthReady, "AUTH PLAIN");
			logDebug("seding auth info");
			conn.write(Base64.encode(cast(const(ubyte)[])("\0"~settings.username~"\0"~settings.password)));
			conn.write("\r\n");
			expectStatus(conn, 235, "plain auth info");
			logDebug("authed");
			break;
		case SMTPAuthType.login:
			conn.write("AUTH LOGIN\r\n");
			expectStatus(conn, SMTPStatus.serverAuthReady, "AUTH LOGIN");
			conn.write(Base64.encode(cast(const(ubyte)[])settings.username) ~ "\r\n");
			expectStatus(conn, SMTPStatus.serverAuthReady, "login user name");
			conn.write(Base64.encode(cast(const(ubyte)[])settings.password) ~ "\r\n");
			expectStatus(conn, 235, "login password");
			break;
		case SMTPAuthType.cramMd5: assert(false, "TODO!");
	}

	conn.write("MAIL FROM:"~addressMailPart(mail.headers["From"])~"\r\n");
	expectStatus(conn, SMTPStatus.success, "MAIL FROM");

	static immutable rcpt_headers = ["To", "Cc", "Bcc"];
	foreach (h; rcpt_headers) {
		mail.headers.getAll(h, (v) @safe {
			foreach (a; v.splitter(',').map!(a => a.strip)) {
				conn.write("RCPT TO:"~addressMailPart(a)~"\r\n");
				expectStatus(conn, SMTPStatus.success, "RCPT TO");
			}
		});
	}

	mail.headers.removeAll("Bcc");

	conn.write("DATA\r\n");
	expectStatus(conn, SMTPStatus.startMailInput, "DATA");
	foreach (name, value; mail.headers) {
		conn.write(name~": "~value~"\r\n");
	}
	conn.write("\r\n");
	conn.write(mail.bodyText);
	conn.write("\r\n.\r\n");
	expectStatus(conn, SMTPStatus.success, "message body");

	conn.write("QUIT\r\n");
	expectStatus(conn, SMTPStatus.serviceClosing, "QUIT");
}

/**
	The following example demonstrates the complete construction of a valid
	e-mail object with UTF-8 encoding. The Date header, as demonstrated, must
	be converted with the local timezone using the $(D toRFC822DateTimeString)
	function.
*/
unittest {
	import vibe.inet.message;
	import std.datetime;
	void testSmtp(string host, ushort port){
		Mail email = new Mail;
		email.headers["Date"] = Clock.currTime(PosixTimeZone.getTimeZone("America/New_York")).toRFC822DateTimeString(); // uses UFCS
		email.headers["Sender"] = "Domain.com Contact Form <no-reply@domain.com>";
		email.headers["From"] = "John Doe <joe@doe.com>";
		email.headers["To"] = "Customer Support <support@domain.com>";
		email.headers["Subject"] = "My subject";
		email.headers["Content-Type"] = "text/plain;charset=utf-8";
		email.bodyText = "This message can contain utf-8 [κόσμε], and\nwill be displayed properly in mail clients with \\n line endings.";

		auto smtpSettings = new SMTPClientSettings(host, port);
		sendMail(smtpSettings, email);
	}
	// testSmtp("localhost", 25);
}

private void expectStatus(InputStream)(InputStream conn, int expected_status, string in_response_to)
	if (isInputStream!InputStream)
{
	// TODO: make the full status message available in the exception
	//       message or for general use (e.g. determine server features)
	string ln;
	sizediff_t sp, dsh;
	do {
		ln = () @trusted { return cast(string)conn.readLine(); } ();
		sp = ln.indexOf(' ');
		if (sp < 0) sp = ln.length;
		dsh = ln.indexOf('-');
	} while (dsh >= 0 && dsh < sp);

	auto status = to!int(ln[0 .. sp]);
	enforce(status == expected_status, "Expected status "~to!string(expected_status)~" in response to "~in_response_to~", got "~to!string(status)~": "~ln[sp .. $]);
}

private int recvStatus(InputStream conn)
{
	string ln = () @trusted { return cast(string)conn.readLine(); } ();
	auto sp = ln.indexOf(' ');
	if( sp < 0 ) sp = ln.length;
	return to!int(ln[0 .. sp]);
}

private string addressMailPart(string str)
{
	auto idx = str.indexOf('<');
	if( idx < 0 ) return "<"~ str ~">";
	str = str[idx .. $];
	enforce(str[$-1] == '>', "Malformed email address field: '"~str~"'.");
	return str;
}
