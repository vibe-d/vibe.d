Contents
========

1. About
2. Installation
	1. Windows
	2. Mac using Brew
	3. Mac using the install script
	4. Linux on Ubuntu
	5. Linux using the install script

1 About
=======

vibe.d is an asynchronouse I/O and web framework written in D. Visit
the website at http://vibed.org/ for more information.

2-1 Installation on Windows
===========================

 - Install DMD using the installer on http://dlang.org/download.html
 - Unzip the vibe archive
 - Run any vibe apps using "vibe"



2-2 Installation on Mac using brew
==================================

If you don't have brew installed, install it according to their [install
instructions](https://github.com/mxcl/homebrew/wiki/installation). 

    /usr/bin/ruby -e "$(curl -fsSL https://raw.github.com/gist/323731)"

(Note: Install brew only if you do not have macports, as they will conflict)


 - Install dependencies:

    brew install libevent

 - Install DMD using the installer on <http://dlang.org/download.html>
 - Unzip the vibe archive
 - Run any vibe apps using "vibe"


2-3 Installation on Mac using the install script
================================================

 - Install DMD using the installer on <http://dlang.org/download.html>
 - Unzip the vibe archive
 - Run the `./install.sh` script
 - Run any vibe apps using "vibe"



2-4 Installation on Linux on Ubuntu
===================================


Install vibe dependencies

    sudo apt-get install libevent-dev libssl-dev


On 32-bit linux: Install DMD-i386

    sudo apt-get install g++ xdg-util
    wget "http://ftp.digitalmars.com/dmd_2.058-0_i386.deb"
    sudo dpkg -i dmd_2.058-0_i386.deb


On 64-bit linux: Install DMD-amd64

    sudo apt-get install g++ xdg-util
    wget "http://ftp.digitalmars.com/dmd_2.058-0_amd64.deb"
    sudo dpkg -i dmd_2.058-0_amd64.deb


Unzip the vibe archive and use the `'vibe` script to run applications


2-5 Installation on Linux using the install script
==================================================

 - Install DMD from <http://dlang.org/download.html>
 - Extract the vibe archive
 - Run the `./install.sh` script
 - Use `vibe`
