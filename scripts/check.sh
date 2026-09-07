#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/flutter.sh pub get
./scripts/flutter.sh analyze
./scripts/flutter.sh test --concurrency=1
if command -v clang++ >/dev/null; then
  dawnmesh_check_dir="$(mktemp -d)"
  trap 'rm -rf "$dawnmesh_check_dir"' EXIT
  clang++ -std=c++17 -Wall -Wextra -fsanitize=address,undefined -I native/src \
    native/test/safety_test.cpp native/src/protocol_frame.cpp native/src/ring_buffer.cpp \
    -o "$dawnmesh_check_dir/native-test"
  "$dawnmesh_check_dir/native-test"
fi
