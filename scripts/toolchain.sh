#!/usr/bin/env bash
# Reuse the bundled local tools, or the tools installed by CI.
dawnmesh_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -d "$dawnmesh_root/.tools/jdk-27.0.1/jdk-27.0.1.0.2+1/Contents/Home" ]]; then
  export JAVA_HOME="$dawnmesh_root/.tools/jdk-27.0.1/jdk-27.0.1.0.2+1/Contents/Home"
  export PATH="$JAVA_HOME/bin:$PATH"
elif [[ -d "$dawnmesh_root/.tools/jdk/Contents/Home" ]]; then
  export JAVA_HOME="$dawnmesh_root/.tools/jdk/Contents/Home"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
if [[ -d "$dawnmesh_root/.tools/android-sdk" ]]; then
  export ANDROID_HOME="$dawnmesh_root/.tools/android-sdk"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$dawnmesh_root/.tools/gradle-cache}"
  export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

fi

if ! command -v cmake >/dev/null; then
  if [[ -x "$dawnmesh_root/.tools/cmake-4.4.4/CMake.app/Contents/bin/cmake" ]]; then
    export PATH="$dawnmesh_root/.tools/cmake-4.4.4/CMake.app/Contents/bin:$PATH"
  elif [[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME/cmake/4.1.2/bin" ]]; then
    export PATH="$ANDROID_HOME/cmake/4.1.2/bin:$PATH"
  fi
fi
