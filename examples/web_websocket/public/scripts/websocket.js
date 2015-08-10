var socket

function connect()
{
	setText("connecting...");
	socket = new WebSocket(getBaseURL() + "/ws");
	socket.onopen = function() {
		setText("connected. waiting for timer...");
	}
	socket.onmessage = function(message) {	
		setText(message.data);
	}
	socket.onclose = function() {
		setText("connection closed.");
	}
	socket.onerror = function() {
		setText("Error!");
	}
}

function closeConnection()
{
	socket.close();
	setText("closed.");
}

function setText(text)
{
	document.getElementById("timer").innerHTML = text;
}

function getBaseURL()
{
	var href = window.location.href.substring(7); // strip "http://"
	var idx = href.indexOf("/");
	return "ws://" + href.substring(0, idx);
}
