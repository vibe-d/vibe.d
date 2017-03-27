#!/bin/bash

set -e -x -o pipefail

# test for successful release build
dub build --combined -b release --compiler=$DC --config=${VIBED_DRIVER=libevent}

# test for successful 32-bit build
if [ "$DC" == "dmd" ]; then
	dub build --combined --arch=x86
fi

dub test :utils --compiler=$DC
dub test :data --compiler=$DC
dub test :core --compiler=$DC --config=${VIBED_DRIVER=libevent}
dub test :diet --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent}
dub test :http --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent}
dub test :mongodb --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent}
dub test :redis --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent}
dub test :web --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent}
dub test :mail --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent}
dub clean --all-packages

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
