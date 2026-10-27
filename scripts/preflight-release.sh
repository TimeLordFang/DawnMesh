#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
command -v clang++ >/dev/null
command -v cmake >/dev/null
./scripts/check.sh
./scripts/gradle.sh :app:testDebugUnitTest :app:lintDebug
./scripts/flutter.sh build apk --release --no-pub
./scripts/flutter.sh build appbundle --release --no-pub
sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
[[ -n "$sdk_root" ]]
apk=build/app/outputs/flutter-apk/app-release.apk
aab=build/app/outputs/bundle/release/app-release.aab
"$sdk_root/build-tools/37.0.0/apksigner" verify --verbose "$apk"
"$sdk_root/build-tools/37.0.0/zipalign" -c -P 16 4 "$apk"
jarsigner -verify "$aab"
python3 scripts/check_apk_elf_alignment.py "$apk"
python3 scripts/check_apk_elf_alignment.py "$aab"
