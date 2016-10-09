#!/bin/bash

set -e -x -o pipefail

# test for successful release build
dub build --combined -b release --compiler=$DC --config=${VIBED_DRIVER=libevent}

# test for successful 32-bit build
if [ "$DC" == "dmd" ]; then
	dub build --combined --arch=x86
fi

dub test --combined --compiler=$DC --config=${VIBED_DRIVER=libevent}

if [ ${BUILD_EXAMPLE=1} -eq 1 ]; then
    for ex in $(\ls -1 examples/); do
        echo "[INFO] Building example $ex"
        (cd examples/$ex && dub build --compiler=$DC && dub clean)
    done
fi
if [ ${RUN_TEST=1} -eq 1 ]; then
    for ex in `\ls -1 tests/`; do
        echo "[INFO] Running test $ex"
        (cd tests/$ex && dub --compiler=$DC && dub clean)
    done
fi

# Test the Meson build system
git clone --depth 4 https://github.com/mesonbuild/meson.git meson-src
cd meson-src
python3 setup.py build
cd ..

mkdir build && cd build
../meson-src/meson.py -Derrorlogs=true ..
ninja
ninja test
DESTDIR=/tmp/installtest ninja install
