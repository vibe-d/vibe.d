/**
	SMTP client implementation

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.mail.smtp;

import vibe.core.log;
import vibe.core.net;
import vibe.inet.message;
import vibe.stream.operations;
import vibe.stream.ssl;

import std.base64;
import std.conv;
import std.exception;
import std.string;


/**
	Determines the (encryption) type of an SMTP connection.
*/
enum SMTPConnectionType {
	plain,
	ssl,
	startTLS,

	/// deprecated
	Plain = plain,
	/// deprecated
	SSL = ssl,
	/// deprecated
	StartTLS = startTLS
}

/// Compatibility alias, will be deprecated soon.
alias SmtpConnectionType = SMTPConnectionType;


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
	transactionFailed = 554,

	/// deprecated
	_Success = _success,
	/// deprecated
	SystemStatus = systemStatus,
	/// deprecated
	HelpMessage = helpMessage,
	/// deprecated
	ServiceReady = serviceReady,
	/// deprecated
	ServiceClosing = serviceClosing,
	/// deprecated
	Success = success,
	/// deprecated
	Forwarding = forwarding,
	/// deprecated
	ServerAuthReady = serverAuthReady,
	/// deprecated
	StartMailInput = startMailInput,
	/// deprecated
	ServiceUnavailable = serviceUnavailable,
	/// deprecated
	MailboxTemporarilyUnavailable = mailboxTemporarilyUnavailable,
	/// deprecated
	ProcessingError = processingError,
	/// deprecated
	OutOfDiskSpace = outOfDiskSpace,
	/// deprecated
	CommandUnrecognized = commandUnrecognized,
	/// deprecated
	InvalidParameters = invalidParameters,
	/// deprecated
	CommandNotImplemented = commandNotImplemented,
	/// deprecated
	BadCommandSequence = badCommandSequence,
	/// deprecated
	CommandParameterNotImplemented = commandParameterNotImplemented,
	/// deprecated
	DomainAcceptsNoMail = domainAcceptsNoMail,
	/// deprecated
	AccessDenied = accessDenied,
	/// deprecated
	MailboxUnavailable = mailboxUnavailable,
	/// deprecated
	UserNotLocal = userNotLocal,
	/// deprecated
	ExceededStorageAllocation = exceededStorageAllocation,
	/// deprecated
	MailboxNameNotAllowed = mailboxNameNotAllowed,
	/// deprecated
	TransactionFailed = transactionFailed,
}

/// Compatibility alias, will be deprecated soon.
alias SmtpStatus = SMTPStatus;


/**
	Represents the authentication mechanism used by the SMTP client.
*/
enum SMTPAuthType {
	none,
	plain,
	login,
	cramMd5,

	/// deprecated
	None = none,
	/// deprecated
	Plain = plain,
	/// deprecated
	Login = login,
	/// deprecated
	CramMd5 = cramMd5
}

/// Compatibility alias, will be deprecated soon.
alias SmtpAuthType = SMTPAuthType;


/**
	Configuration options for the SMTP client.
*/
class SMTPClientSettings {
	string host = "127.0.0.1";
	ushort port = 25;
	string localname = "localhost";
	SMTPConnectionType connectionType = SMTPConnectionType.plain;
	SMTPAuthType authType = SMTPAuthType.none;
	string username;
	string password;

	this() {}
	this(string host, ushort port) { this.host = host; this.port = port; }
}

/// Compatibility alias, will be deprecated soon.
alias SmtpClientSettings = SMTPClientSettings;


/**
	Represents an email message, including its headers.
*/
class Mail {
	InetHeaderMap headers;
	string bodyText;
}

/**
	Sends am email using the given settings.
*/
void sendMail(SMTPClientSettings settings, Mail mail)
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

	expectStatus(conn, SMTPStatus.serviceReady, "connection establishment");

	void greet(){
		conn.write("EHLO "~settings.localname~"\r\n");
		while(true){ // simple skipping of 
			auto ln = cast(string)conn.readLine();
			logDebug("EHLO response: %s", ln);
			auto sidx = ln.indexOf(' ');
			auto didx = ln.indexOf('-');
			if( sidx > 0 && (didx < 0 || didx > sidx) ){
				enforce(ln[0 .. sidx] == "250", "Server not ready (response "~ln[0 .. sidx]~")");
				break;
			}
		}
	}

	if( settings.connectionType == SMTPConnectionType.ssl ){
		auto ctx = new SSLContext();
		conn = new SSLStream(raw_conn, ctx, SSLStreamState.connecting);
	}

	greet();

	if( settings.connectionType == SMTPConnectionType.startTLS ){
		conn.write("STARTTLS\r\n");
		expectStatus(conn, SMTPStatus.serviceReady, "STARTTLS");
		auto ctx = new SSLContext();
		conn = new SSLStream(raw_conn, ctx, SSLStreamState.connecting);
		greet();
	}

	final switch(settings.authType){
		case SMTPAuthType.none: break;
		case SMTPAuthType.plain:
			logDebug("seding auth");
			conn.write("AUTH PLAIN\r\n");
			expectStatus(conn, SMTPStatus.serverAuthReady, "AUTH PLAIN");
			logDebug("seding auth info");
			conn.write(Base64.encode(cast(ubyte[])("\0"~settings.username~"\0"~settings.password)));
			conn.write("\r\n");
			expectStatus(conn, 235, "plain auth info");
			logDebug("authed");
			break;
		case SMTPAuthType.login:
			conn.write("AUTH LOGIN\r\n");
			expectStatus(conn, SMTPStatus.serverAuthReady, "AUTH LOGIN");
			conn.write(Base64.encode(cast(ubyte[])settings.username) ~ "\r\n");
			expectStatus(conn, SMTPStatus.serverAuthReady, "login user name");
			conn.write(Base64.encode(cast(ubyte[])settings.password) ~ "\r\n");
			expectStatus(conn, 235, "login password");
			break;
		case SMTPAuthType.cramMd5: assert(false, "TODO!");
	}

	conn.write("MAIL FROM:"~addressMailPart(mail.headers["From"])~"\r\n");
	expectStatus(conn, SMTPStatus.success, "MAIL FROM");

	conn.write("RCPT TO:"~addressMailPart(mail.headers["To"])~"\r\n"); // TODO: support multiple recipients
	expectStatus(conn, SMTPStatus.success, "RCPT TO");

	conn.write("DATA\r\n");
	expectStatus(conn, SMTPStatus.startMailInput, "DATA");
	foreach( name, value; mail.headers ){
		conn.write(name~": "~value~"\r\n");
	}
	conn.write("\r\n");
	conn.write(mail.bodyText);
	conn.write("\r\n.\r\n");
	expectStatus(conn, SMTPStatus.success, "message body");

	conn.write("QUIT\r\n");
	expectStatus(conn, SMTPStatus.serviceClosing, "QUIT");
}

private void expectStatus(InputStream conn, int expected_status, string in_response_to)
{
	string ln = cast(string)conn.readLine();
	auto sp = ln.indexOf(' ');
	if( sp < 0 ) sp = ln.length;
	auto status = to!int(ln[0 .. sp]);
	enforce(status == expected_status, "Expected status "~to!string(expected_status)~" in response to "~in_response_to~", got "~to!string(status)~": "~ln[sp .. $]);
}

private int recvStatus(InputStream conn)
{
	string ln = cast(string)conn.readLine();
	auto sp = ln.indexOf(' ');
	if( sp < 0 ) sp = ln.length;
	return to!int(ln[0 .. sp]);
}

private string addressMailPart(string str)
{
	auto idx = str.indexOf('<');
	if( idx < 0 ) return str;
	str = str[idx .. $];
	enforce(str[$-1] == '>', "Malformed email address field: '"~str~"'.");
	return str;
}
