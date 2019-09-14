

// Author: Pablo De Nápoli <pdenapo@gmail.com>
// License: MIT

// Adaptation an example from https://github.com/mdn/learning-area/tree/master/html/forms to D language
// which permited since this example is licenced under Creative Commons Zero v1.0 Universal license

import vibe.vibe;

class WebInterface
{
  // GET /
  void index()
	{
	render!("form.dt");
  }
   
  // POST /hello (say and to are automatically read as form fields)
  @path("/hello") 
  void postHello(string say, string to)
   {
	logInfo("postHello method called with parameters: say=" ~ say ~ ",to=" ~ to );
	render!("greeting.dt",say,to);
  }
}


void main()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["127.0.0.1"];
	
	
	auto router = new URLRouter;
    router.registerWebInterface(new WebInterface);

	
	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8080/ in your browser.");
	runApplication();
}

