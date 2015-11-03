/// Defines the REST API
module api;

import vibe.web.rest;

interface ForumAPI {
	// base path /threads/
	Collection!ThreadAPI threads();
}

interface ThreadAPI {
	// define the index parameters used to identify the collection items
	struct CollectionIndices {
		string _thread_name;
	}

	// base path /threads/:thread_number/posts/
	Collection!PostAPI posts(string _thread_name);

	// POST /threads/
	// Posts a new thread
	void post(string name, string message);

	// GET /threads/
	// Returns a list of all thread names
	string[] get();
}

interface PostAPI {
	// define the index parameters used to identify the collection items
	struct CollectionIndices {
		string _thread_name;
		int _post_index;
	}

	// POST /threads/:thread_number/posts/
	// Posts a new thread reply
	void post(string _thread_name, string message);

	// GET /threads/:thread_name/
	// Returns the number of posts in a thread
	int getLength(string _thread_name);

	// GET /threads/:thread_number/posts/:post_id
	// Returns a specific message
	string getMessage(string _thread_name, int _post_index);

	// GET /threads/:thread_number/posts/
	// Returns all messages of a particular thread
	string[] get(string _thread_name);
}
