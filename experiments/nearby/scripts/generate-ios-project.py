#!/usr/bin/env python3
"""Generate the standalone probe project; never edits the production Runner."""
import hashlib
import plistlib
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "ios"
project = root / "NearbyProbe.xcodeproj"
if (project / "project.pbxproj").exists() and "--force" not in sys.argv:
    print(project)
    sys.exit(0)
project.mkdir(exist_ok=True)
revision = "1c1bcbe8e7c5d40597014789414a6a48c40294a2"
service = "dev.dawnmesh.nearby.probe.v1"
info = {
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)",
    "CFBundleName": "DawnMesh Nearby Probe", "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "0.1.2", "CFBundleVersion": "3",
    "UILaunchScreen": {}, "LSRequiresIPhoneOS": True,
    "NSBluetoothAlwaysUsageDescription": "验证与附近安卓和 iPhone 的连接。",
    "NSLocalNetworkUsageDescription": "验证附近连接的 Wi-Fi 数据路径。",
    "NSLocationWhenInUseUsageDescription": "仅在启用热点升级试验时用于连接附近设备的 Wi-Fi。",
    "NSBonjourServices": ["_" + hashlib.sha256(service.encode()).hexdigest()[:12].upper() + "._tcp"],
}
(root / "Info.plist").write_bytes(plistlib.dumps(info))
entitlements = {"com.apple.developer.networking.HotspotConfiguration": True,
                "com.apple.developer.networking.wifi-info": True}
(root / "Hotspot.entitlements").write_bytes(plistlib.dumps(entitlements))
settings = 'SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 15.0; SWIFT_VERSION = 5.0; INFOPLIST_FILE = Info.plist; PRODUCT_BUNDLE_IDENTIFIER = dev.dawnmesh.nearbyprobe; PRODUCT_NAME = NearbyProbe; CODE_SIGN_STYLE = Automatic; TARGETED_DEVICE_FAMILY = "1,2";'
ids = {name: f"A{index:023X}" for index, name in enumerate([
    "project", "group", "products", "target", "sources", "frameworks", "source", "sourceBuild", "product", "package", "packageProduct", "packageBuild", "projectConfigs", "targetConfigs", "projectDebug", "projectRelease", "targetDebug", "targetRelease", "projectHotspotDebug", "projectHotspotRelease", "targetHotspotDebug", "targetHotspotRelease"], 1)}
def i(name): return ids[name]
objects = [
 f'{i("project")} = {{isa = PBXProject; attributes = {{LastUpgradeCheck = 2700; }}; buildConfigurationList = {i("projectConfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = {i("group")}; productRefGroup = {i("products")}; projectDirPath = ""; packageReferences = ({i("package")}); targets = ({i("target")}); }};',
 f'{i("group")} = {{isa = PBXGroup; children = ({i("source")}, {i("products")}); sourceTree = "<group>"; }};',
 f'{i("products")} = {{isa = PBXGroup; name = Products; children = ({i("product")}); sourceTree = "<group>"; }};',
 f'{i("target")} = {{isa = PBXNativeTarget; name = NearbyProbe; productName = NearbyProbe; productType = "com.apple.product-type.application"; buildConfigurationList = {i("targetConfigs")}; buildPhases = ({i("sources")}, {i("frameworks")}); buildRules = (); dependencies = (); packageProductDependencies = ({i("packageProduct")}); productReference = {i("product")}; }};',
 f'{i("source")} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NearbyProbeApp.swift; sourceTree = "<group>"; }};',
 f'{i("product")} = {{isa = PBXFileReference; explicitFileType = wrapper.application; path = NearbyProbe.app; sourceTree = BUILT_PRODUCTS_DIR; }};',
 f'{i("sourceBuild")} = {{isa = PBXBuildFile; fileRef = {i("source")}; }};',
 f'{i("packageBuild")} = {{isa = PBXBuildFile; productRef = {i("packageProduct")}; }};',
 f'{i("sources")} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({i("sourceBuild")}); runOnlyForDeploymentPostprocessing = 0; }};',
 f'{i("frameworks")} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({i("packageBuild")}); runOnlyForDeploymentPostprocessing = 0; }};',
 f'{i("package")} = {{isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/google/nearby.git"; requirement = {{kind = revision; revision = {revision}; }}; }};',
 f'{i("packageProduct")} = {{isa = XCSwiftPackageProductDependency; package = {i("package")}; productName = NearbyConnections; }};',
]
configs = ("Debug", "Release", "HotspotDebug", "HotspotRelease")
for scope in ("project", "target"):
 objects.append(f'{i(scope+"Configs")} = {{isa = XCConfigurationList; buildConfigurations = ({", ".join(i(scope+c) for c in configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};')
 for config in configs:
  extra = ' CODE_SIGN_ENTITLEMENTS = Hotspot.entitlements; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DAWNMESH_NEARBY_HOTSPOT;' if config.startswith("Hotspot") and scope == "target" else ""
  objects.append(f'{i(scope+config)} = {{isa = XCBuildConfiguration; name = {config}; buildSettings = {{{settings if scope == "target" else "CLANG_ENABLE_MODULES = YES;"}{extra}}}; }};')
(project / "project.pbxproj").write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {i("project")}; }}\n')
print(project)
