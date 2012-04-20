import vibe.d;

import vibe.mail.smtp;

static this()
{
	auto settings = new SmtpClientSettings("outerproduct.org", 25);
	auto mail = new Mail;
	mail.headers["From"] = "<sludwig@outerproduct.org>";
	mail.headers["To"] = "<sdas@outerproduct.org>";
	mail.headers["Subject"] = "Testmail";
	mail.bodyText = "Hello, World!";
	sendMail(settings, mail);
}