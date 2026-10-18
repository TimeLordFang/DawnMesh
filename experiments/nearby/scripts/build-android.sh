#!/usr/bin/env bash
set -euo pipefail
dawnmesh_root="$(cd "$(dirname "$0")/../../.." && pwd)"
dawnmesh_tools="${DAWNMESH_TOOLS_ROOT:-$dawnmesh_root/.tools}"
if [[ ! -d "$dawnmesh_tools" && -d "$dawnmesh_root/../DawnMesh/.tools" ]]; then
  dawnmesh_tools="$dawnmesh_root/../DawnMesh/.tools"
fi
if [[ -z "${JAVA_HOME:-}" && -d "$dawnmesh_tools/jdk/Contents/Home" ]]; then
  export JAVA_HOME="$dawnmesh_tools/jdk/Contents/Home"
fi
if [[ -z "${ANDROID_HOME:-}" && -d "$dawnmesh_tools/android-sdk" ]]; then
  export ANDROID_HOME="$dawnmesh_tools/android-sdk"
fi
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$dawnmesh_tools/gradle-cache}"
[[ -n "${JAVA_HOME:-}" ]] && export PATH="$JAVA_HOME/bin:$PATH"
"$dawnmesh_root/experiments/nearby/android/gradlew" -p "$dawnmesh_root/experiments/nearby/android" :app:assembleDebug :app:lintDebug
mkdir -p "$dawnmesh_root/artifacts/nearby"
cp "$dawnmesh_root/experiments/nearby/android/app/build/outputs/apk/debug/app-debug.apk" "$dawnmesh_root/artifacts/nearby/DawnMesh-NearbyProbe-0.1.0-debug.apk"
echo "APK: $dawnmesh_root/artifacts/nearby/DawnMesh-NearbyProbe-0.1.0-debug.apk"
