#!/bin/sh
set -e
rm docs.json >/dev/null 2>&1 || true
rdmd --build-only --force -lib -version=VibeLibeventDriver -Dftemp.html -Xfdocs.json -I../source ../source/vibe/d.d
rm temp.html
rm d.a
../../ddox/ddox filter docs.json --min-protection=Public --ex deimos. --ex vibe.core.drivers. --ex etc. --ex std. --ex core.
cp docs.json ../../vibed.org/docs.json

../../ddox/ddox generate-html --navigation-type=ModuleTree docs.json .
cp -r ../../ddox/public/* .
