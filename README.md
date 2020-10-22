[![vibe.d](http://vibed.org/images/logo-and-title.png)](http://vibed.org)

vibe.d is a high-performance asynchronous I/O, concurrency and web application
toolkit written in D. It already contains many supplemental features such as
database support to be able to offer a complete development environment. For
more specialized needs, there are also many compatible
[DUB packages](https://code.dlang.org/?sort=updated&category=library.vibed)
available.

Visit the website at <https://vibed.org/> for more information and
[documentation](https://vibed.org/docs).

[![DUB Package](https://img.shields.io/dub/v/vibe-d.svg)](https://code.dlang.org/packages/vibe-d)
[![Posix Build Status](https://travis-ci.com/vibe-d/vibe.d.svg?branch=master)](https://travis-ci.com/vibe-d/vibe.d)
[![Windows Build Status](https://ci.appveyor.com/api/projects/status/cp2kxg70h54pga9d/branch/master?svg=true)](https://ci.appveyor.com/project/s-ludwig/vibe-d/branch/master)

Hello Vibe.d
------------

```d
#!/usr/bin/env dub
/+ dub.sdl:
   name "hello_vibed"
   dependency "vibe-d" version="~>0.8.0"
+/
import vibe.vibe;

void main()
{
    listenHTTP("127.0.0.1:8080", (req, res) {
        res.writeBody("Hello Vibe.d: " ~ req.path);
    });

    runApplication();
}
```

Download this file as `hello.d` and run it with [DUB](https://github.com/dlang/dub):

```
> dub hello.d
```

(or `chmod +x` and execute it: `./hello.d`)

Alternatively, you can quickstart with examples directly on [![Open on run.dlang.io](https://img.shields.io/badge/run.dlang.io-open-blue.svg)](https://run.dlang.io/is/qTsfv6).

Support
-------

Vibe.d supports the 10 latest minor releases of DMD.
For example, if the current version is v2.090.1,
then v2.089.x, v2.088.x, ... v2.080.x are supported.
Note that support for patch release is desireable,
but only support for the last patch in a minor is guaranteed.

Additionally, Vibe.d supports all LDC versions that implement
the version of a supported frontend (e.g. by the previous rule
[LDC v1.20.0](https://github.com/ldc-developers/ldc/releases/tag/v1.20.0)
implements v2.090.1 and would be supported).


Installation
------------

Instead of explicitly installing vibe.d, it is recommended to use
[DUB](https://github.com/dlang/dub) for building vibe.d based
applications. Once DUB is installed, you can create and run a new project
using the following shell commands:

    dub init <name> -t vibe.d
    cd <name>
    dub

Similarly, you can run an example by invoking `dub` from any of the
example project directories.

Note that on non-Windows operating systems, you also need to have
libevent and OpenSSL installed - and of course a D compiler. See below
for instructions.


Additional setup on Windows
---------------------------

 - Just install DMD using the installer on <https://dlang.org/download.html>
 - And get the latest [DUB release](https://code.dlang.org/download)

### Note for building on Win64

There are currently no 64-bit Windows binaries of libevent included, so you'll either need to build those yourself, or you can switch to the "win32" event driver by inserting `"subConfigurations": {"vibe-d": "win32"}` into the dub.json file of your project.


Additional setup on Mac using brew
----------------------------------

If you don't have brew installed, install it according to their [install
instructions](<https://www.brew.sh>) and
install libevent.

    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    brew install libevent

You can then also install DUB using brew:

    brew install dub

(Note: Install brew only if you do not have macports, as they will conflict)

Install DMD using the installer on <https://dlang.org/download.html>.

Optionally, run `./setup-mac.sh` to create a user/group pair for privilege lowering.


Additional setup on Linux (Debian/Ubuntu/Mint)
----------------------------------------------

Install vibe.d's dependencies (*)

    sudo apt-get install libevent-dev libssl-dev


On 32-bit linux: Install DMD-i386

    sudo apt-get install g++ gcc-multilib xdg-utils
    wget "http://downloads.dlang.org/releases/2.x/2.087.1/dmd_2.087.1-0_i386.deb"
    sudo dpkg -i dmd_2.087.1-0_i386.deb


On 64-bit linux: Install DMD-amd64

    sudo apt-get install g++ gcc-multilib xdg-utils
    wget "http://downloads.dlang.org/releases/2.x/2.087.1/dmd_2.087.1-0_amd64.deb"
    sudo dpkg -i dmd_2.087.1-0_amd64.deb


Optionally, run `./setup-linux.sh` to create a user/group pair for privilege lowering.

(*) Note that Debian 6 (Squeeze) and older requires manual installation (see below).


Additional setup on Linux (generic)
-----------------------------------

You need to have the following dependencies installed:

 - [DMD 2.077.1 or greater](http://dlang.org/download)
 - [libssl](http://www.openssl.org/source/)

If using the (now deprecated) "libevent" configuration, libevent is also required:
 - [libevent 2.0.x](http://libevent.org/) (*)

Optionally, run `./setup-linux.sh` to create a user/group pair for privilege lowering.

(*) Note that some Linux distributions such as Debian Squeeze or CentOS 6 may only ship libevent 1.4, in this case you will have to manually compile the latest 2.0.x version:

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


Switching between OpenSSL versions
----------------------------------

By default, vibe.d is built against OpenSSL 1.0.x. On systems that use the newer
1.1.x branch, this can be overridden on the DUB command line using
`--override-config vibe-d:tls/openssl-1.1`. Alternatively, the same can be done
using a sub configuration directive in the package recipe:

SDL syntax:
```
dependency "vibe-d:tls" version="~>0.8.2"
subConfiguration "vibe-d:tls" "openssl-1.1"
```

JSON syntax:
```
{
    ...
    "dependencies": {
        ...
        "vibe-d:tls": "*"
    },
    "subConfigurations": {
        ...
        "vibe-d:tls": "openssl-1.1"
    }
}
```

For older systems there is also an "openssl-0.9" configuration that can be
used in analogy to the above to build against the OpenSSL 0.9.8 branch.

Finally, there is a "botan" configuration for using the D port of the Botan
library.
