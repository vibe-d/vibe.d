/**
	SMTP client implementation

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.mail.smtp;

import vibe.core.tcp;
import vibe.http.common : StrMapCI;

import std.algorithm;
import std.conv;
import std.exception;


enum SmtpConnectionType {
	Plain,
	SSL,
	StartTLS
}

enum SmtpStatus {
	_Success = 200,
	SystemStatus = 211,
	HelpMessage = 214,
	ServiceReady = 220,
	ServiceClosing = 221,
	Success = 250,
	Forwarding = 251,
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

class SmtpClientSettings {
	string host = "127.0.0.1";
	ushort port = 25;
	string localname = "localhost";
	SmtpConnectionType connectionType = SmtpConnectionType.Plain;

	this() {}
	this(string host, ushort port) { this.host = host; this.port = port; }
}

class Mail {
	StrMapCI headers;
	string bodyText;
}

void sendMail(SmtpClientSettings settings, Mail mail)
{
	TcpConnection conn;
	try {
		conn = connectTcp(settings.host, settings.port);
	} catch(Exception e){
		throw new Exception("Failed to connect to SMTP server at "~settings.host~" port "
			~to!string(settings.port), e);
	}
	scope(exit) conn.close();

	expectStatus(conn, SmtpStatus.ServiceReady);

	conn.write("HELO "~settings.localname~"\r\n");
	expectStatus(conn, SmtpStatus.Success);

	conn.write("MAIL FROM:"~addressMailPart(mail.headers["From"])~"\r\n");
	expectStatus(conn, SmtpStatus.Success);

	conn.write("RCPT TO:"~addressMailPart(mail.headers["To"])~"\r\n"); // TODO: support multiple recipients
	expectStatus(conn, SmtpStatus.Success);

	conn.write("DATA\r\n");
	expectStatus(conn, SmtpStatus.StartMailInput);
	foreach( name, value; mail.headers ){
		conn.write(name~": "~value~"\r\n");
	}
	conn.write("\r\n");
	conn.write(mail.bodyText);
	conn.write("\r\n.\r\n");
	expectStatus(conn, SmtpStatus.Success);

	conn.write("QUIT\r\n");
	expectStatus(conn, SmtpStatus.ServiceClosing);
}

private void expectStatus(TcpConnection conn, int expected_status)
{
	string ln = cast(string)conn.readLine();
	auto sp = ln.countUntil(' ');
	if( sp < 0 ) sp = ln.length;
	auto status = to!int(ln[0 .. sp]);
	enforce(status == expected_status, "Expected status "~to!string(expected_status)~" got "~to!string(status)~": "~ln[sp .. $]);
}

private int recvStatus(TcpConnection conn)
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
