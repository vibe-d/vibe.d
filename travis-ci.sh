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

# test building with Meson
if [[ ${VIBED_DRIVER=libevent} = libevent ]]; then
    mkdir build && cd build
    meson ..

    # looks like Meson doesn't work well when building shared libraries with DMD at time, so we limit the
    # actual build to LDC.
    if [[ ${DC=dmd} = ldc2 ]]; then
        dc_version=$("$DC" --version | sed -n '1,${s/[^0-9.]*\([0-9.]*\).*/\1/; p; q;}')

        # we can not compile with LDC 1.0 on Travis since the version there has static Phobos/DRuntime built
        # without PIC, which makes the linker fail. All other LDC builds do not have this issue.
        if [[ ${dc_version} != "1.0.0" ]]; then
            # we limit the number of Ninja jobs to 3, so Travis doesn't kill us
            ninja -j3
            ninja test -v
            DESTDIR=/tmp/vibe-install ninja install
        fi
    fi
    cd ..
fi
