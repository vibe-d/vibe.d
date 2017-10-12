#!/bin/bash

set -xueo pipefail

# test version strings
ver_git=$(git describe --abbrev=0 --tags)
ver_vibe=$(sed -n 's|.*vibeVersionString\s*= "\(.*\)";$|\1|p' core/vibe/core/core.d)
ver_meson_base=$(sed -n 's|\s*version\s*: '"'"'\(.*\)'"'"'$|\1|p' meson.build)
ver_meson_suffix=$(sed -n 's|project_version_suffix\s*= '"'"'~\([a-z]*\)\([0-9]*\)'"'"'$|-\1.\2|p' meson.build)

if [ "${ver_git}" != v"$ver_vibe" -o "${ver_git}" != "v$ver_meson_base$ver_meson_suffix" ]; then
    echo "Mismatch between versions."
    echo "	git: '$ver_git'"
    echo "	vibeVersionString: '$ver_vibe'"
    echo "	meson.build project_version: '$ver_meson_base'"
    echo "	meson project_version_suffix: '$ver_meson_suffix'"
    exit 1
fi
