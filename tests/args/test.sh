#!/bin/bash

set -e
die() { echo "$@" 1>&2 ; exit 1; }

if [ "${OS}" == "win32" -o "${OS}" == "Windows_NT" ]; then
	VIBE='cmd /C vibe'
else
	VIBE=vibe
fi

( $VIBE | grep -q '^argtest=$' ) || die "Fail (no argument)"
( $VIBE -- --argtest=aoeu | grep -q '^argtest=aoeu$' ) || die "Fail (with argument)"
( ( ! $VIBE -- --inexisting 2>&1 ) | grep -qF 'Unrecognized command line option' ) || die "Fail (unknown argument)"

echo 'OK'
