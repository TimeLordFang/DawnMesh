#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/flutter.sh pub get
./scripts/flutter.sh analyze
./scripts/flutter.sh test --concurrency=1
if command -v clang++ >/dev/null; then
  if ! command -v cmake >/dev/null && [[ -d .tools/android-sdk/cmake/4.1.2/bin ]]; then
    export PATH="$PWD/.tools/android-sdk/cmake/4.1.2/bin:$PATH"
  fi
  dawnmesh_check_dir="$(mktemp -d)"
  trap 'rm -rf "$dawnmesh_check_dir"' EXIT
  cmake -S native -B "$dawnmesh_check_dir" -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
    -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer"
  cmake --build "$dawnmesh_check_dir" --parallel 2
  ctest --test-dir "$dawnmesh_check_dir" --output-on-failure
fi
