vibe.d
======

vibe.d is an asynchronous I/O and web application framework written in D.
It already contains many supplemental features such as database support
to be able to offer a complete development toolbox. Extensions are
supported in the form of [VPM modules](http://registry.vibed.org/).

Visit the website at <http://vibed.org/> for more information.


Installation on Windows
-----------------------

 - Install DMD using the installer on <http://dlang.org/download.html>
 - Unzip the vibe archive (or git clone) and add the bin/ subfolder to your PATH variable
 - Run any vibe apps using "vibe" from the application's root directory


Installation on Mac using brew
------------------------------

If you don't have brew installed, install it according to their [install
instructions](<https://github.com/mxcl/homebrew/wiki/installation>) and
install libevent.

    /usr/bin/ruby -e "$(curl -fsSL https://raw.github.com/gist/323731)"
    brew install libevent

(Note: Install brew only if you do not have macports, as they will conflict)

Install DMD using the installer on <http://dlang.org/download.html>.
 
Unzip the vibe archive (or git clone) and use the "vibe" script to run applications.
 
Optionally, it's recommended to create a symlink in /usr/bin so you don't
have to specify the path everytime:
 
    sudo ln -s /path/to/vibe/bin/vibe /usr/bin/vibe


Installation on Linux (Debian/Ubuntu)
-------------------------------------

Install vibe dependencies

    sudo apt-get install libevent-dev libssl-dev


On 32-bit linux: Install DMD-i386

    sudo apt-get install g++ gcc-multilib xdg-util
    wget "http://ftp.digitalmars.com/dmd_2.058-0_i386.deb"
    sudo dpkg -i dmd_2.058-0_i386.deb


On 64-bit linux: Install DMD-amd64

    sudo apt-get install g++ gcc-multilib xdg-util
    wget "http://ftp.digitalmars.com/dmd_2.058-0_amd64.deb"
    sudo dpkg -i dmd_2.058-0_amd64.deb


Unzip the vibe archive (or git clone) and use the "vibe" script to run applications

Optionally, it's recommended to create a symlink in /usr/bin so you don't
have to specify the path everytime:
 
    sudo ln -s /path/to/vibe/bin/vibe /usr/bin/vibe
