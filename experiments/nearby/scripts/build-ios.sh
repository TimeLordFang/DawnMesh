#!/usr/bin/env bash
set -euo pipefail
dawnmesh_root="$(cd "$(dirname "$0")/../../.." && pwd)"
dawnmesh_config=Release
if [[ "${1:-}" == "--hotspot" ]]; then
  dawnmesh_config=HotspotRelease
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--hotspot]" >&2
  exit 2
fi
python3 "$dawnmesh_root/experiments/nearby/scripts/generate-ios-project.py"
mkdir -p "$dawnmesh_root/artifacts/nearby"
swiftc -DPROBE_REGRESSION -module-cache-path "$dawnmesh_root/artifacts/nearby/swift-regression-cache" \
  "$dawnmesh_root/experiments/nearby/ios/NearbyProbeApp.swift" \
  "$dawnmesh_root/experiments/nearby/tests/swift/main.swift" \
  -o "$dawnmesh_root/artifacts/nearby/swift-regression"
"$dawnmesh_root/artifacts/nearby/swift-regression"
xcodebuild -project "$dawnmesh_root/experiments/nearby/ios/NearbyProbe.xcodeproj" \
  -scheme NearbyProbe -configuration "$dawnmesh_config" -destination 'generic/platform=iOS' \
  -derivedDataPath "$dawnmesh_root/artifacts/nearby/ios-derived" \
  CODE_SIGNING_ALLOWED=NO build
echo "Unsigned app: $dawnmesh_root/artifacts/nearby/ios-derived/Build/Products/${dawnmesh_config}-iphoneos/NearbyProbe.app"
echo "For an iPhone installation, open NearbyProbe.xcodeproj in Xcode, select your Team and device, then Run."
