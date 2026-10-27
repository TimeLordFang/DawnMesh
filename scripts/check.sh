#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
python3 -m unittest discover -s test -p release_policy_test.py
./scripts/flutter.sh pub get --enforce-lockfile
./scripts/flutter.sh analyze --no-pub
./scripts/flutter.sh test --concurrency=1 --no-pub
if command -v clang++ >/dev/null; then
  dawnmesh_check_dir="$(mktemp -d)"
  trap 'rm -rf "$dawnmesh_check_dir"' EXIT
  cmake -S native -B "$dawnmesh_check_dir" -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
    -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer"
  cmake --build "$dawnmesh_check_dir" --parallel 2
  ctest --test-dir "$dawnmesh_check_dir" --output-on-failure
fi
