vibe.d
======

vibe.d is an asynchronous I/O and web application framework written in D.
It already contains many supplemental features such as database support
to be able to offer a complete development toolbox. Extensions are
supported in the form of [DUB modules](http://registry.vibed.org/).

Visit the website at <http://vibed.org/> for more information.


Installation
------------

Instead of explicitly installing vibe.d, it is now recommended to use 
[DUB](https://github.com/rejectedsoftware/dub) for building vibe.d based
applications. Once DUB is installed, you can create a new project by running
`dub init <name>` and enable the use of vibe.d by adding the following
dependency to the `package.json` file in your project's directory:

    {
        "name": "your-project-identifier",
        "dependencies": {
            "vibe-d": ">=0.7.16"
        }
    }

Invoking `dub` will then automatically download the latest vibe.d and compile
and run the project.

Similarly, you can run an example by invoking `dub` from any of the
example project directories.


Additional setup on Windows
---------------------------

 - Just install DMD using the installer on <http://dlang.org/download.html>


Additional setup on Mac using brew
----------------------------------

If you don't have brew installed, install it according to their [install
instructions](<https://github.com/mxcl/homebrew/wiki/installation>) and
install libevent.

    ruby -e "$(curl -fsSkL raw.github.com/mxcl/homebrew/go)"
    brew install libevent

(Note: Install brew only if you do not have macports, as they will conflict)

Install DMD using the installer on <http://dlang.org/download.html>.
 
Optionally, run `./setup-mac.sh` to create a user/group pair for privilege lowering.


Additional setup on Linux (Debian/Ubuntu/Mint, using apt)
---------------------------------------------------------

Go to <https://code.google.com/p/d-apt/wiki/APT_Repository> and follow the
instructions. This will setup the APT repository of Jordi Sayol, who maintains
a number of D packages for Debian based systems (*).

Installing is then done using

    sudo apt-get install vibe

(*) Note that Debian 6 (Squeeze) and older requires manual installation (see below).


Additional setup on Linux (Debian/Ubuntu/Mint, manually)
---------------------------------------------------

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


Optionally, run `./setup-linux.sh` to create a user/group pair for privilege lowering.


Additional setup on Linux (generic)
-----------------------------------

You need to have the following dependencies installed:

 - [DMD 2.062 or greater](http://dlang.org/download)
 - [libssl](http://www.openssl.org/source/)
 - [libevent 2.0.x](http://libevent.org/) (*)

Optionally, run `./setup-linux.sh` to create a user/group pair for privilege lowering.

(*) Note that some current linux distributions such as Debian squeeze or CentOS 6 may only ship libevent 1.4, in this case you will have to manually compile the latest 2.0.x version:

```
wget https://github.com/downloads/libevent/libevent/libevent-2.0.21-stable.tar.gz
tar -xf libevent-2.0.21-stable.tar.gz
cd libevent-2.0.21-stable
./configure
make
make install
ldconfig
```


Additional setup on FreeBSD
---------------------------

Install the DMD compiler and vibe.d's dependencies using portupgrade or a similar mechanism:

    sudo portupgrade -PN devel/libevent2 devel/pkgconf

Optionally, run `./setup-freebsd.sh` to create a user/group pair for privilege lowering.
