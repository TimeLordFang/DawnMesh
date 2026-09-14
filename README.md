# 曙光之声 · DawnMesh

[![Android release](https://github.com/TimeLordFang/DawnMesh/actions/workflows/release.yml/badge.svg)](https://github.com/TimeLordFang/DawnMesh/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/TimeLordFang/DawnMesh?include_prereleases)](https://github.com/TimeLordFang/DawnMesh/releases)
[![License](https://img.shields.io/github/license/TimeLordFang/DawnMesh)](LICENSE)
[![Android](https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white)](#兼容性)

一款支持近场离线通信和自部署公网房的语音对讲应用。手机可以通过 Wi-Fi 局域网、Wi-Fi Direct 或蓝牙直接通信；需要远距离通话时，也可以连接用户自己部署的 DawnMesh Server。

> 当前开发版本：`0.1.0-dev.21`。安装包请从 [GitHub Releases](https://github.com/TimeLordFang/DawnMesh/releases) 获取。

## 功能

- **三种近场链路**：同一局域网、Wi-Fi Direct、BLE 发现 + L2CAP 数据通道。
- **自部署公网房**：可保存并切换多个 HTTPS 服务器，默认 25 人；公网语音使用 LiveKit/WebRTC，语音与聊天均端到端加密。
- **公网房主管理**：支持修改房间名、关闭成员麦克风、移交房主，以及建房时设置 1–60 分钟的房主断线保留时间。
- **两种发言方式**：按住对讲，或检测到语音后自动发送；Wi-Fi 房和蓝牙房均支持。
- **邀请码加密**：建房生成随机 6 位数字，使用 PAKE 验证后分发独立随机房间密钥；语音、消息和控制帧使用 AES-256-GCM。
- **断线恢复**：链路意外中断后最多自动重试 10 分钟，蓝牙房主重新开启蓝牙后会重建广播、监听端口和动态 PSM。
- **蓝牙耳机共存**：可选择耳机或手机麦克风；蓝牙互联和耳机同时工作时自动降低 Opus 码率并调整发送与播放缓冲。
- **锁屏通话**：前台服务、常驻通知和锁屏对讲面板支持后台收发。
- **本机调试与调参**：可开关、筛选、搜索、复制全链路时延日志，并在运行中调整蓝牙码率、写入策略、抖动缓冲和播放缓冲。
- **中英文界面**：中文名为“曙光之声”，英文名为 DawnMesh。

## 安全与隐私

房间邀请码仅保存在当前会话内存中，文字聊天退出后从本机内存清除。应用没有账号、预置公网服务或遥测上传。使用公网房时，App 只连接用户选定的自部署服务器；主动检查更新时会连接 GitHub。

6 位邀请码适合当面口述和临时小组访问控制。它不能抵御持码成员冒名，也不等同于长期高强度密码。请只把邀请码告诉可信成员。

详细设计和已知边界见 [安全审查](docs/SECURITY_REVIEW.md)。发现安全问题时，请避免在公开 Issue 中附带邀请码、设备地址、签名材料或完整原始日志。

## 下载与更新

打开 [GitHub Releases](https://github.com/TimeLordFang/DawnMesh/releases)，下载名称类似 `DawnMesh-0.1.0-dev.21-release.apk` 的文件。每个 Release 同时提供 SHA-256 校验文件。

应用内“关于曙光之声 → 看看有没有更新”会读取本仓库最近的公开 Releases，包括 prerelease。发现更高版本后，可直接打开对应 GitHub Release 页面。应用不会静默下载或安装 APK。

## 从源码构建

项目只提交源码和 Gradle Wrapper。以下组合已用于当前 Android 构建：

| 工具 | 版本 |
| --- | --- |
| Flutter / Dart | Flutter **3.47.2** / Dart **3.13.2** |
| JDK | Temurin **25 LTS**，用于运行 Gradle |
| Gradle / Android Gradle Plugin | **9.7.1** / **9.4.0** |
| Kotlin | **2.4.10** |
| Android SDK | compileSdk / targetSdk **36** |
| Android Build-Tools | **36.1.0** |
| Android NDK | **28.2.13676358** |
| CMake | **3.22.1** |

Gradle 使用 JDK 25 运行，但 Android Java/Kotlin 字节码目标保持为 Java 17，JDK 版本不会提高应用的 Android 系统要求。

安装 Android SDK 组件：

```sh
sdkmanager \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;36.1.0" \
  "ndk;28.2.13676358" \
  "cmake;3.22.1"
flutter doctor --android-licenses
```

在项目根目录执行：

```sh
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter build apk --debug
```

仓库中的 `scripts/flutter.sh`、`scripts/gradle.sh` 和 `scripts/check.sh` 会自动使用 `.tools/` 下的本地工具链：

```sh
./scripts/check.sh
./scripts/gradle.sh :app:testDebugUnitTest :app:lintDebug
./scripts/flutter.sh build apk --debug
```

调试 APK 位于 `build/app/outputs/flutter-apk/app-debug.apk`。

## 发布签名

发布构建必须提供自己的 JKS，缺少完整配置时构建会失败，不会回退为 debug 签名：

```sh
mkdir -p android/keystore
keytool -genkeypair -v \
  -keystore android/keystore/dawnmesh.jks \
  -alias dawnmesh \
  -keyalg RSA \
  -keysize 3072 \
  -validity 10000
cp android/key.properties.example android/key.properties
# 编辑 android/key.properties 后执行：
flutter build apk --release
```

签名发生在 Android Gradle 的 `packageRelease` 任务内。配置位于 [`android/app/build.gradle.kts`](android/app/build.gradle.kts)：它从未提交的 `android/key.properties` 读取本地密钥信息，或从 `DAWNMESH_KEYSTORE_PATH`、`DAWNMESH_STORE_PASSWORD`、`DAWNMESH_KEY_ALIAS`、`DAWNMESH_KEY_PASSWORD` 环境变量读取 CI 配置。Gradle 完成资源打包、zipalign 和 APK Signature Scheme 签名后，才写出 `build/app/outputs/flutter-apk/app-release.apk`。

GitHub Actions 在 [`.github/workflows/release.yml`](.github/workflows/release.yml) 中把 JKS Secret 临时还原到 Runner，调用 `flutter build apk --release`，随后用 `apksigner verify` 做只读校验，再复制并重命名到 `dist/` 上传 Release。复制和重命名不会再次签名。配置方法见 [GitHub 自动发布](docs/GITHUB_RELEASES.md)。

请永久备份 keystore 和密码。Android 要求后续升级包继续使用同一签名；密钥丢失后，现有安装通常无法直接覆盖升级。

## 项目结构

```text
android/   Android 宿主、BLE/L2CAP、Wi-Fi Direct、音频与前台服务
lib/       Flutter 界面、近场/公网会话、发现、传输、加密和调试日志
native/    C++ 帧协议、环形缓冲和 PCM 处理
test/      Dart/Flutter 回归测试
docs/      安全审查、兼容性、验证记录和发布说明
scripts/   本机工具链与校验脚本
```

公网控制服务和 LiveKit Compose 部署文件位于独立的同级项目 `DawnMeshServer`，其 README 包含 Nginx、媒体端口、备份和升级说明。

## 兼容性

- minSdk 26（Android 8.0）；BLE L2CAP 房需要 Android 10 / API 29 或更高版本。
- Android 14 及以上声明麦克风与连接设备前台服务类型。
- Xiaomi、OnePlus 等系统可能需要手动允许后台运行、锁屏通知和电池优化豁免。
- 蓝牙互联与蓝牙耳机共用同一控制器时，实际延迟和稳定性仍受手机射频、厂商蓝牙栈及现场 2.4 GHz 干扰影响。

蓝牙复测建议见 [Android 蓝牙测试](docs/ANDROID16_BLUETOOTH.md)，已执行的自动化和 APK 校验见 [验证记录](docs/VALIDATION.md)。

## 参与开发

欢迎提交 Issue 和 Pull Request。改动前请先运行：

```sh
./scripts/check.sh
./scripts/gradle.sh :app:testDebugUnitTest :app:lintDebug
```

涉及传输协议、邀请码或加密格式的修改，请同时补充互操作和失败路径测试，并在 PR 中说明是否与旧版兼容。

## 许可与来源

DawnMesh 使用 [Apache License 2.0](LICENSE)。项目基于 SunsetRipple 的 Flutter 主线独立开发，保留原作者版权和许可信息；来源提交与差异说明见 [UPSTREAM.md](docs/UPSTREAM.md)。
