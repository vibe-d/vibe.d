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

git tag --sign --message "$VER" "$VER"
