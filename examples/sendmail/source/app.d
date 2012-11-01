import vibe.vibe;

import vibe.mail.smtp;

void main()
{
	auto settings = new SmtpClientSettings("smtp.example.com", 25);
	settings.connectionType = SmtpConnectionType.StartTLS;
	settings.authType = SmtpAuthType.Plain;
	settings.username = "username";
	settings.password = "secret";

	auto mail = new Mail;
	mail.headers["From"] = "<user@isp.com>";
	mail.headers["To"] = "<recipient@domain.com>";
	mail.headers["Subject"] = "Testmail";
	mail.bodyText = "Hello, World!";
	
	logInfo("Sending mail...");
	sendMail(settings, mail);
	logInfo("done.");
}