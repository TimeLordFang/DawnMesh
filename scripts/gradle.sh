#!/usr/bin/env bash
set -euo pipefail
dawnmesh_root="$(cd "$(dirname "$0")/.." && pwd)"
export JAVA_HOME="$dawnmesh_root/.tools/jdk/Contents/Home"
export ANDROID_HOME="$dawnmesh_root/.tools/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export GRADLE_USER_HOME="$dawnmesh_root/.tools/gradle-cache"
export PATH="$JAVA_HOME/bin:$PATH"
exec "$dawnmesh_root/android/gradlew" -p "$dawnmesh_root/android" "$@"
