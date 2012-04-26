/**
	File handling.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.file;

public import vibe.core.driver;

import vibe.core.core;

FileStream openFile(string path, FileMode mode = FileMode.Read)
{
	return getEventDriver().openFile(path, mode);
}

