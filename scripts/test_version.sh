#!/bin/bash

set -xueo pipefail

# test version strings
ver_git=$(git describe)
ver_vibe=$(sed -n 's|.*vibeVersionString\s*= "\(.*\)";$|\1|p' core/vibe/core/core.d)
ver_meson=$(sed -n 's|project_version\s*= '"'"'\(.*\)'"'"'$|\1|p' meson.build)
ver_name_meson=$(sed -n 's|project_version_name\s*= '"'"'\(.*\)'"'"'$|\1|p' meson.build)
if [ "${ver_git%%-*}" != v"$ver_vibe" -o "${ver_git%%-*}" != v"$ver_meson" -o "${ver_git%%-*}" != v"$ver_name_meson" ]; then
    echo "Mismatch between versions."
    echo "	git: '$ver_git'"
    echo "	vibeVersionString: '$ver_vibe'"
    echo "	meson.build project_version: '$ver_meson'"
    echo "	meson project_version_name: '$ver_name_meson'"
    exit 1
fi
