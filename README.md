# DawnMesh（Android 独立开发版）

从 SunsetRipple 当前 Flutter 主线复制的 Android 工程，包含 Kotlin 宿主、Dart 界面与会话逻辑、C++ 核心及测试。原作者 Apache-2.0 许可和版权保留，来源提交见 [UPSTREAM.md](docs/UPSTREAM.md)。原目录不作修改。

**这是仍需真机验证的开发版本。房间目前没有默认启用应用层加密，也没有完整成员身份认证，只适合可信设备测试。** 已修复加密异常时发送明文等问题，不代表默认会话已经加密。

- 安装包 ID：`dev.dawnmesh.intercom`，可以与原版并存。
- 版本：`0.1.0-dev.1+1`。
- Kotlin namespace / Dart package / 平台通道名保留，避免无关迁移。
- 启动器名：DawnMesh；原界面美术与部分原品牌文案暂保留。
- 不包含旧版根目录 `app/`（纯 Kotlin alpha.7）及 iOS、桌面、Web、HarmonyOS。
- 更新检查不再访问原作者 GitHub；仅通过自己签名的 APK 更新。

## 构建依赖

首次复现建议使用以下固定组合，避免直接装最新版后混入工具链迁移问题：

| 依赖 | 版本 / 用途 |
| --- | --- |
| Flutter | **3.29.3**（随带 Dart 3.7.2），与原仓库 CI 的 3.29.x 对齐 |
| JDK | **17**，运行 Gradle；只安装 JRE 不够 |
| Android SDK Platform | **35**，本项目固定 compileSdk/targetSdk 35；可在 Android 16 运行 |
| Android SDK Build-Tools | **35.0.0**，另保留 AGP 自动要求的 **34.0.0** |
| Command-line Tools | SDK Manager 安装与许可证管理 |
| Platform-Tools | 包含 adb，用于安装、日志和连接真机 |
| NDK Side by side | **27.0.12077973**，构建 native/ 下 C++ |
| CMake | **3.22.1** |
| Git | 获取 Flutter 和管理源码 |

Gradle 8.12、AGP 8.7.0、Kotlin 1.8.22 由项目/Flutter 构建工具解析，不需要全局安装 Gradle、Kotlin。无需 Node.js、Python 或 iOS 的完整 Xcode 来构建 APK；macOS 获取 Git/本机 C++ 检查可安装 Xcode Command Line Tools。Android Studio 是安装和管理 SDK 最省事的方式，但不是强制依赖。

安装 Flutter 后将 `flutter/bin` 加入 PATH。Android Studio 中打开 SDK Manager，安装表中的组件；或配置好 `sdkmanager` 后执行：

```sh
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "build-tools;34.0.0" "ndk;27.0.12077973" "cmake;3.22.1"
flutter doctor --android-licenses
flutter doctor -v
```

如果 Android Studio 自带 Java 版本与 JDK 17 不同，可用 `flutter config --jdk-dir=/你的/JDK17/Contents/Home` 指定。`android/local.properties` 由 Flutter 本机生成，不应提交。

在 **DawnMesh 根目录**执行（不是 android/ 下，也不是原仓库旧 `app/` 下）：

```sh
flutter pub get
flutter analyze
# 回环网络测试共享端口 8988/8989，串行避免争用
flutter test --concurrency=1
flutter build apk --debug
```

调试 APK：`build/app/outputs/flutter-apk/app-debug.apk`。两台手机都安装此 APK，再在应用内选择蓝牙对讲、扫描/创建；不用先在系统蓝牙设置里配对。

```sh
adb devices
adb -s 手机序列号 install -r build/app/outputs/flutter-apk/app-debug.apk
```

发布包必须使用自己的密钥。可交互生成（口令不写在命令行中）：

```sh
mkdir -p android/keystore
keytool -genkeypair -v -keystore android/keystore/dawnmesh.jks -alias dawnmesh -keyalg RSA -keysize 3072 -validity 10000
cp android/key.properties.example android/key.properties
# 编辑 key.properties 的口令；妥善备份 keystore，后续升级必须使用同一签名
flutter build apk --release
```

发布 APK：`build/app/outputs/flutter-apk/app-release.apk`。开发版与发布版签名不同，直接覆盖可能失败；可先卸载调试版，再装自己的发布版。缺少签名配置会阻止 release 打包，不会再自动退回 debug 签名。

默认使用官方 Maven / pub.dev。若网络无法连接，可自行选择镜像：`DAWNMESH_USE_MIRROR=1 flutter build apk --debug` 为 Gradle 启用原有阿里云镜像；Dart 的源由 `PUB_HOSTED_URL` 控制。镜像是另一条供应链，不能代替构件校验；仓库未完成完整依赖锁定、SBOM 或 CVE 审计。

NDK r27 已开启 `ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES`。这只处理本项目 C++；最终 APK 的 Flutter 引擎等所有 .so 仍需按官方方法检查 16 KB 对齐，不应据此声称完成所有 Android 16 适配。

## 修复与验证

见 [安全审查](docs/SECURITY_REVIEW.md)、[蓝牙复测步骤](docs/ANDROID16_BLUETOOTH.md)、[验证记录](docs/VALIDATION.md)。

官方资料：[Flutter Android 环境](https://docs.flutter.dev/platform-integration/android/setup)、[AGP 8.7 兼容表](https://developer.android.com/build/releases/agp-8-7-0-release-notes)、[Android 蓝牙权限](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)、[16 KB 页面](https://developer.android.com/guide/practices/page-sizes)。
