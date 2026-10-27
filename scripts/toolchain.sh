#!/usr/bin/env bash
# Reuse the bundled local tools, or the tools installed by CI.
dawnmesh_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -d "$dawnmesh_root/.tools/jdk/Contents/Home" ]]; then
  export JAVA_HOME="$dawnmesh_root/.tools/jdk/Contents/Home"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
if [[ -d "$dawnmesh_root/.tools/android-sdk" ]]; then
  export ANDROID_HOME="$dawnmesh_root/.tools/android-sdk"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$dawnmesh_root/.tools/gradle-cache}"
  export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
  if ! command -v cmake >/dev/null && [[ -d "$ANDROID_HOME/cmake/4.1.2/bin" ]]; then
    export PATH="$ANDROID_HOME/cmake/4.1.2/bin:$PATH"
  fi
fi
