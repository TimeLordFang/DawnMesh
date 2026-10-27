#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
exec "$dawnmesh_root/android/gradlew" -p "$dawnmesh_root/android" "$@"
