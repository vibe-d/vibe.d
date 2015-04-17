#!/bin/bash

set -e -o pipefail

dub build -b release --compiler=$DC --config=${VIBED_DRIVER=libevent}
dub test --compiler=$DC --config=${VIBED_DRIVER=libevent}
dub test :base --compiler=$DC --config=${VIBED_DRIVER}
dub test :utils --compiler=$DC --config=${VIBED_DRIVER}
dub test :data --compiler=$DC --config=${VIBED_DRIVER}
dub test :mail --compiler=$DC --config=${VIBED_DRIVER}
dub test :http --compiler=$DC --config=${VIBED_DRIVER}
dub test :diet --compiler=$DC --config=${VIBED_DRIVER}
dub test :web --compiler=$DC --config=${VIBED_DRIVER}
dub test :mongodb --compiler=$DC --config=${VIBED_DRIVER}
dub test :redis --compiler=$DC --config=${VIBED_DRIVER}

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
