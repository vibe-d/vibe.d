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

sed -i 's|vibeVersionString\(\s*\)= "\(.*\)";|vibeVersionString\1= "'${VER:1}'";|' core/vibe/core/core.d
sed -i 's|project_version\(\s*\)= '"'"'\(.*\)'"'"'$|project_version\1= '"'"${VER:1}"'"'|' meson.build
sed -i 's|project_version_name\(\s*\)= '"'"'\(.*\)'"'"'$|project_version_name\1= '"'"${VER:1}"'"'|' meson.build

set -x
git --no-pager diff
git add core/vibe/core/core.d meson.build
git commit --message "bump version to $VER"
git tag --sign --message "$VER" "$VER"
