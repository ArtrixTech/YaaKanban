#!/bin/sh
# Render the design-system specimen: ./build.sh [out-dir] (default /tmp/yaak-ds).
# OVERVIEW=path/to/overview.swift renders an archived overview version instead.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-/tmp/yaak-ds}
mkdir -p "$out"
swiftc -O -o "$out/specimen" "$here/DesignSystem.swift" "$here/main.swift" "${OVERVIEW:-$here/overview.swift}"
"$out/specimen" "$out"
