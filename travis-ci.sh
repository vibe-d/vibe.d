#!/bin/bash

set -e -x -o pipefail

DUB_ARGS=${DUB_ARGS:-}

./scripts/test_version.sh

# Check for trailing whitespace"
grep -nrI --include=*.d '\s$'  && (echo "Trailing whitespace found"; exit 1)

if [ "${VIBED_SSL:-openssl}" == "botan" ]; then
    grep -qF "Have_botan" stream/dub.sdl || echo 'versions "Have_botan"' >> stream/dub.sdl
    # Make botan mandatory (i.e. non-optional)
    sed -E 's/(dependency "botan".*) optional=true/\1/' -i stream/dub.sdl
fi

# test for successful release build
dub build --combined -b release --compiler=$DC --config=${VIBED_DRIVER=libevent}
dub clean --all-packages

DUB_ARGS="--build-mode=${DUB_BUILD_MODE:-separate} ${DUB_ARGS:-}"

# test for successful 32-bit build
if [ "$DC" == "dmd" ]; then
	dub build --combined --arch=x86 --config=${VIBED_DRIVER=libevent}
	dub clean --all-packages
fi

dub test :data --compiler=$DC $DUB_ARGS
dub test :core --compiler=$DC --config=${VIBED_DRIVER=libevent} $DUB_ARGS
dub test :mongodb --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent} $DUB_ARGS
dub test :redis --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent} $DUB_ARGS
dub test :web --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent} $DUB_ARGS
dub test :utils --compiler=$DC $DUB_ARGS
dub test :http --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent} $DUB_ARGS
dub test :mail --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent} $DUB_ARGS
dub test :stream --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent} $DUB_ARGS
dub test :crypto --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent} $DUB_ARGS
dub test :tls --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent} $DUB_ARGS
dub test :textfilter --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent} $DUB_ARGS
dub test :inet --compiler=$DC --override-config=vibe-d:core/${VIBED_DRIVER=libevent} $DUB_ARGS
dub clean --all-packages

if [ ${BUILD_EXAMPLE=1} -eq 1 ]; then
    for ex in $(\ls -1 examples/); do
        echo "[INFO] Building example $ex"
        (cd examples/$ex && dub build --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS && dub clean)
    done
fi
if [ ${RUN_TEST=1} -eq 1 ]; then
    for ex in `\ls -1 tests/`; do
        if [ -r test/$ex/dub.json ] || [ -r test/$ex/dub.sdl ]; then
            echo "[INFO] Running test $ex"
            (cd tests/$ex && dub --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS && dub clean)
        fi
    done
fi
