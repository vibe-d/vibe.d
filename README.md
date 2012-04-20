Contents
========

1 Installation
1-1 Windows
1-2 Mac using Brew
1-3 Mac using the install script
1-4 Linux on Ubuntu
1-5 Linux using the install script


1-1 Installation on Windows
===========================

 - Install DMD using the installer on http://dlang.org/download.html
 - Unzip the vibe archive
 - Run any vibe apps using "vibe app.d"



1-2 Installation on Mac using brew
==================================
 - If you don't have brew installed, install it according to their install
	instructions at <https://github.com/mxcl/homebrew/wiki/installation>
	(only install, if you do not have MacPorts installed as they will conflict)
		/usr/bin/ruby -e "$(curl -fsSL https://raw.github.com/gist/323731)"
		
 - Install dependencies:
		brew install libevent
 - Install DMD using the installer on <http://dlang.org/download.html>
 - Unzip the vibe archive
 - Run any vibe apps using "vibe app.d"

1-2 Installation on Mac using the install script
================================================

 - Install DMD using the installer on <http://dlang.org/download.html>
 - Unzip the vibe archive
 - Run the `./install.sh` script
 - Run any vibe apps using "vibe app.d"



1-2 Installation on Linux on Ubuntu
===================================

 - On 32-bit linux: Install DMD-i386
		sudo apt-get install g++ xdg-util
		wget "http://ftp.digitalmars.com/dmd_2.058-0_i386.deb"
		sudo dpkg -i dmd_2.058-0_i386.deb
		
 - On 64-bit linux: Install DMD-amd64
		sudo apt-get install g++ xdg-util
		wget "http://ftp.digitalmars.com/dmd_2.058-0_amd64.deb"
		sudo dpkg -i dmd_2.058-0_amd64.deb
		
 - Install vibe dependencies
		sudo apt-get install libevent-dev libssl-dev"
		
 - Unzip the vibe archive and use the 'vibe' script to run applications


1-2 Installation on Linux using the install script
==================================================

 - Install DMD from <http://dlang.org/download.html>
 - Extract the vibe archive
 - Run the `./install.sh` script
 - Use `vibe`