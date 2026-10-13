#!/usr/bin/env bash
set -euo pipefail
# Official CMake release assets, checked against published SHA-256 digests.
case "$(uname -s)" in
  Darwin)
    dawnmesh_cmake_archive=cmake-4.4.4-macos-universal.tar.gz
    dawnmesh_cmake_sha=4b7b73704b1db9b374e5c9ab8e17ac6148b817b6396ee75cd94a852cbac9d305
    dawnmesh_cmake_subdir=cmake-4.4.4-macos-universal/CMake.app/Contents/bin
    ;;
  Linux)
    [[ "$(uname -m)" == x86_64 ]]
    dawnmesh_cmake_archive=cmake-4.4.4-linux-x86_64.tar.gz
    dawnmesh_cmake_sha=e5bb807f7728cb60cd8b27ebc97a2edb469b68655f21e844a600c3575b76f5bb
    dawnmesh_cmake_subdir=cmake-4.4.4-linux-x86_64/bin
    ;;
  *) echo "Unsupported CI host" >&2; exit 1 ;;
esac
dawnmesh_cmake_dir="${RUNNER_TEMP:?}/dawnmesh-cmake"
mkdir -p "$dawnmesh_cmake_dir"
curl --fail --location --retry 3 "https://github.com/Kitware/CMake/releases/download/v4.4.4/$dawnmesh_cmake_archive" -o "$dawnmesh_cmake_dir/$dawnmesh_cmake_archive"
python3 - "$dawnmesh_cmake_dir/$dawnmesh_cmake_archive" "$dawnmesh_cmake_sha" <<'PYTHON'
import hashlib, pathlib, sys
assert hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest() == sys.argv[2], 'CMake checksum mismatch'
PYTHON
tar -xzf "$dawnmesh_cmake_dir/$dawnmesh_cmake_archive" -C "$dawnmesh_cmake_dir"
echo "$dawnmesh_cmake_dir/$dawnmesh_cmake_subdir" >> "${GITHUB_PATH:?}"
"$dawnmesh_cmake_dir/$dawnmesh_cmake_subdir/cmake" --version
