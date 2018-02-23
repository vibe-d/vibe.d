#!/bin/bash

set -e -x -o pipefail

DUB_ARGS="--build-mode=${DUB_BUILD_MODE:-separate} ${DUB_ARGS:-}"
# default to run all parts
: ${PARTS:=lint,builds,unittests,examples,tests,meson}
# default to vibe-core driver
: ${VIBED_DRIVER:=vibe-core}

if [[ $PARTS =~ (^|,)lint(,|$) ]]; then
    ./scripts/test_version.sh
    # Check for trailing whitespace"
    grep -nrI --include=*.d '\s$'  && (echo "Trailing whitespace found"; exit 1)
fi

if [[ $PARTS =~ (^|,)builds(,|$) ]]; then
    # test for successful release build
    dub build --combined -b release --compiler=$DC --config=${VIBED_DRIVER=libevent}
    dub clean --all-packages

    # test for successful 32-bit build
    if [ "$DC" == "dmd" ]; then
        dub build --combined --arch=x86 --config=${VIBED_DRIVER=libevent}
        dub clean --all-packages
    fi
fi

if [[ $PARTS =~ (^|,)unittests(,|$) ]]; then
    dub test :data --compiler=$DC $DUB_ARGS
    dub test :core --compiler=$DC --config=$VIBED_DRIVER $DUB_ARGS
    dub test :mongodb --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS
    dub test :redis --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS
    dub test :web --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS
    dub test :utils --compiler=$DC $DUB_ARGS
    dub test :http --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS
    dub test :mail --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS
    dub test :stream --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS
    dub test :crypto --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS
    dub test :tls --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS
    dub test :textfilter --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS
    dub test :inet --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS
    dub clean --all-packages
fi

if [[ $PARTS =~ (^|,)examples(,|$) ]]; then
    for ex in $(\ls -1 examples/); do
        echo "[INFO] Building example $ex"
        (cd examples/$ex && dub build --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS && dub clean)
    done
fi

if [[ $PARTS =~ (^|,)tests(,|$) ]]; then
    for ex in `\ls -1 tests/`; do
        if [ -r tests/$ex/dub.json ] || [ -r tests/$ex/dub.sdl ]; then
            if [ $ex == "vibe.http.client.2080" ]; then
                echo "[WARNING] Skipping test $ex due to TravisCI incompatibility".
            else
                echo "[INFO] Running test $ex"
                (cd tests/$ex && dub --compiler=$DC --override-config=vibe-d:core/$VIBED_DRIVER $DUB_ARGS && dub clean)
            fi
        fi
    done
fi

# test building with Meson
if [[ $PARTS =~ (^|,)meson(,|$) ]]; then
    mkdir build && cd build
    meson ..

    allow_meson_test="yes"
    if [[ ${DC=dmd} = ldc2 ]]; then
        # we can not run tests when compiling with LDC+Meson on Travis at the moment,
        # due to an LDC bug: https://github.com/ldc-developers/ldc/issues/2280
        # as soon as the bug is fixed, we can run tests again for the fixed LDC versions.
        allow_meson_test="no"
    fi
    if [[ ${DC=dmd} = dmd ]]; then
        dc_version=$("$DC" --version | perl -pe '($_)=/([0-9]+([.][0-9]+)+)/')
        if [[ ${dc_version} = "2.072.2" ]]; then
            # The stream test fails with DMD 2.072.2 due to a missing symbol. This is a DMD bug,
            # so we skip tests here.
            # This check can be removed when support for that compiler version is dropped.
            allow_meson_test="no"
        fi
    fi

    # we limit the number of Ninja jobs to 4, so Travis doesn't kill us
    ninja -j4

    if [[ ${allow_meson_test} = "yes" ]]; then
        ninja test -v
    fi
    DESTDIR=/tmp/vibe-install ninja install

    cd ..
fi
