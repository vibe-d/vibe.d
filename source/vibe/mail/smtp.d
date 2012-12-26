/**
	SMTP client implementation

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.mail.smtp;

import vibe.core.log;
import vibe.core.net;
import vibe.http.common : StrMapCI;
import vibe.stream.operations;
import vibe.stream.ssl;

import std.algorithm;
import std.base64;
import std.conv;
import std.exception;


/**
	Determines the (encryption) type of an SMTP connection.
*/
enum SmtpConnectionType {
	Plain,
	SSL,
	StartTLS
}


/** Represents the different status codes for SMTP replies.
*/
enum SmtpStatus {
	_Success = 200,
	SystemStatus = 211,
	HelpMessage = 214,
	ServiceReady = 220,
	ServiceClosing = 221,
	Success = 250,
	Forwarding = 251,
	ServerAuthReady = 334,
	StartMailInput = 354,
	ServiceUnavailable = 421,
	MailboxTemporarilyUnavailable = 450,
	ProcessingError = 451,
	OutOfDiskSpace = 452,
	CommandUnrecognized = 500,
	InvalidParameters = 501,
	CommandNotImplemented = 502,
	BadCommandSequence = 503,
	CommandParameterNotImplemented = 504,
	DomainAcceptsNoMail = 521,
	AccessDenied = 530,
	MailboxUnavailable = 550,
	UserNotLocal = 551,
	ExceededStorageAllocation = 552,
	MailboxNameNotAllowed = 553,
	TransactionFailed = 554,
}

/**
	Represents the authentication mechanism used by the SMTP client.
*/
enum SmtpAuthType {
	None,
	Plain,
	Login,
	CramMd5
}

/**
	Configuration options for the SMTP client.
*/
class SmtpClientSettings {
	string host = "127.0.0.1";
	ushort port = 25;
	string localname = "localhost";
	SmtpConnectionType connectionType = SmtpConnectionType.Plain;
	SmtpAuthType authType = SmtpAuthType.None;
	string username;
	string password;

	this() {}
	this(string host, ushort port) { this.host = host; this.port = port; }
}

/**
	Represents an email message, including its headers.
*/
class Mail {
	StrMapCI headers;
	string bodyText;
}

/**
	Sends am email using the given settings.
*/
void sendMail(SmtpClientSettings settings, Mail mail)
{
	TcpConnection raw_conn;
	try {
		raw_conn = connectTcp(settings.host, settings.port);
	} catch(Exception e){
		throw new Exception("Failed to connect to SMTP server at "~settings.host~" port "
			~to!string(settings.port), e);
	}
	scope(exit) raw_conn.close();

	Stream conn = raw_conn;

	expectStatus(conn, SmtpStatus.ServiceReady, "connection establishment");

	void greet(){
		conn.write("EHLO "~settings.localname~"\r\n");
		while(true){ // simple skipping of 
			auto ln = cast(string)conn.readLine();
			logDebug("EHLO response: %s", ln);
			auto sidx = ln.countUntil(' ');
			auto didx = ln.countUntil('-');
			if( sidx > 0 && (didx < 0 || didx > sidx) ){
				enforce(ln[0 .. sidx] == "250", "Server not ready (response "~ln[0 .. sidx]~")");
				break;
			}
		}
	}

	if( settings.connectionType == SmtpConnectionType.SSL ){
		auto ctx = new SslContext();
		conn = new SslStream(raw_conn, ctx, SslStreamState.Connecting);
	}

	greet();

	if( settings.connectionType == SmtpConnectionType.StartTLS ){
		conn.write("STARTTLS\r\n");
		expectStatus(conn, SmtpStatus.ServiceReady, "STARTTLS");
		auto ctx = new SslContext();
		conn = new SslStream(raw_conn, ctx, SslStreamState.Connecting);
		greet();
	}

	final switch(settings.authType){
		case SmtpAuthType.None: break;
		case SmtpAuthType.Plain:
			logDebug("seding auth");
			conn.write("AUTH PLAIN\r\n");
			expectStatus(conn, SmtpStatus.ServerAuthReady, "AUTH PLAIN");
			logDebug("seding auth info");
			conn.write(Base64.encode(cast(ubyte[])("\0"~settings.username~"\0"~settings.password)));
			conn.write("\r\n");
			expectStatus(conn, 235, "plain auth info");
			logDebug("authed");
			break;
		case SmtpAuthType.Login:
			conn.write("AUTH LOGIN\r\n");
			expectStatus(conn, SmtpStatus.ServerAuthReady, "AUTH LOGIN");
			conn.write(Base64.encode(cast(ubyte[])settings.username) ~ "\r\n");
			expectStatus(conn, SmtpStatus.ServerAuthReady, "login user name");
			conn.write(Base64.encode(cast(ubyte[])settings.password) ~ "\r\n");
			expectStatus(conn, 235, "login password");
			break;
		case SmtpAuthType.CramMd5: assert(false, "TODO!");
	}

	conn.write("MAIL FROM:"~addressMailPart(mail.headers["From"])~"\r\n");
	expectStatus(conn, SmtpStatus.Success, "MAIL FROM");

	conn.write("RCPT TO:"~addressMailPart(mail.headers["To"])~"\r\n"); // TODO: support multiple recipients
	expectStatus(conn, SmtpStatus.Success, "RCPT TO");

	conn.write("DATA\r\n");
	expectStatus(conn, SmtpStatus.StartMailInput, "DATA");
	foreach( name, value; mail.headers ){
		conn.write(name~": "~value~"\r\n");
	}
	conn.write("\r\n");
	conn.write(mail.bodyText);
	conn.write("\r\n.\r\n");
	expectStatus(conn, SmtpStatus.Success, "message body");

	conn.write("QUIT\r\n");
	expectStatus(conn, SmtpStatus.ServiceClosing, "QUIT");
}

private void expectStatus(InputStream conn, int expected_status, string in_response_to)
{
	string ln = cast(string)conn.readLine();
	auto sp = ln.countUntil(' ');
	if( sp < 0 ) sp = ln.length;
	auto status = to!int(ln[0 .. sp]);
	enforce(status == expected_status, "Expected status "~to!string(expected_status)~" in response to "~in_response_to~", got "~to!string(status)~": "~ln[sp .. $]);
}

private int recvStatus(InputStream conn)
{
	string ln = cast(string)conn.readLine();
	auto sp = ln.countUntil(' ');
	if( sp < 0 ) sp = ln.length;
	return to!int(ln[0 .. sp]);
}

private string addressMailPart(string str)
{
	auto idx = str.countUntil('<');
	if( idx < 0 ) return str;
	str = str[idx .. $];
	enforce(str[$-1] == '>', "Malformed email address field: '"~str~"'.");
	return str;
}
