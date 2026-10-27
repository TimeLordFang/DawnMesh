#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
if [[ -d "$dawnmesh_root/.tools/flutter" ]]; then
  export XDG_CONFIG_HOME="$dawnmesh_root/.tools/config"
fi
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true
if [[ -n "${FLUTTER_ROOT:-}" ]]; then
  exec "$FLUTTER_ROOT/bin/flutter" "$@"
elif [[ -x "$dawnmesh_root/.tools/flutter-3.47.8/bin/flutter" ]]; then
  exec "$dawnmesh_root/.tools/flutter-3.47.8/bin/flutter" "$@"
fi
exec flutter "$@"
