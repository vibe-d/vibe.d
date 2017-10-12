#!/bin/bash

set -ueo pipefail

if [ $# -ne 1 ]; then
    echo 'Example Usage: ./scripts/tag_version.sh v1.2.0-alpha.1' 1>&2
    exit 1
fi
VER="$1"

if ! [[ $VER =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]]; then
    echo "Invalid version format '$VER'" 1>&2
    exit 1
fi

BASE=`echo ${VER:1} | cut -d - -f 1`
SUFFIX=`echo $VER | cut -d - -f 2 -s`
MSUFFIX="$(echo $SUFFIX | sed 's/\([a-z]*\)\.\([0-9]*\)/~\1\2/')"

sed -i 's|vibeVersionString\(\s*\)= "\(.*\)";|vibeVersionString\1= "'${VER:1}'";|' core/vibe/core/core.d
sed -i 's|version:\(\s*\)'"'"'.*'"'"'$|version:\1'"'$BASE'|" meson.build
sed -i 's|project_version_suffix\(\s*\)= '"'"'.*'"'"'$|project_version_suffix\1= '"'$MSUFFIX'|" meson.build

set -x
git --no-pager diff
git add core/vibe/core/core.d meson.build
git commit --message "bump version to $VER"
git tag --sign --message "$VER" "$VER"
