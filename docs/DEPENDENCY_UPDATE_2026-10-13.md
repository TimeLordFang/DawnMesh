# 2026-10-13 稳定版依赖更新

本次以官方稳定发行、pub.dev/npm/Maven/Go proxy 的版本记录为准。
直接依赖升级到最新稳定版，锁定文件同时刷新可兼容的传递依赖。
Actions 固定官方 release commit，便于审计和 Dependabot 后续升级。

## 移动端

| 依赖/工具 | 版本 |
| --- | --- |
| Flutter / Dart | 3.47.7 / 3.13.5 |
| livekit_client | 2.13.1 |
| flutter_webrtc / 原生 WebRTC SDK | 1.6.2+hotfix.4 / 150.7871.01 |
| connectivity_plus | 7.3.2 |
| flutter_secure_storage | 11.2.0 |
| image_picker | 1.2.4 |
| RNNoise | 0.2，包含上游 ARM 编译修复 372f7b4 |

cryptography、crypto、pointycastle、http、gal、flutter_lints、fake_async 和
Android Concentus 1.0.2、JUnit 4.13.2 已核对，当前稳定发行无需变更。

以下传递依赖的最新版仍受 Flutter SDK 或最新插件约束：cross_file 0.3.5+5、
material_color_utilities 0.13.0、sdp_transform 0.3.2、test_api 0.7.12。
`flutter pub outdated` 的 resolvable 与 current 一致；不强制覆盖上游约束。

RNNoise 0.2 使用发行源码中的内置模型，不运行时下载权重。
保留 iOS CELT/FFT 符号前缀，并统一两端源码文件名以避免 Opus 链接重名。
原生测试始终验证绝对噪声抑制，输出高于噪声底线时才比较强力/标准两档比值。

## 构建工具与 CI

Android：Temurin JDK 27、Gradle 9.8.1、AGP 9.4.1、Kotlin 2.4.21、
compileSdk 37.2、targetSdk 37、Build Tools 37.0.0、NDK 30.0.16248370、
Android SDK CMake 4.1.2、Command-line Tools 23.0、Platform Tools 37.0.1。Java/Kotlin 字节码仍为 17，最低 Android API 26。
主分支/PR 新增 unsigned debug APK 检查；签名发布仍由版本标签触发。

iOS：Opus 1.6.1、CocoaPods 1.17.0、macOS 26 GA runner，Xcode 选择镜像内
最新稳定版。最低 iOS 15.0。未采用公开预览 runner。

原生主机检查使用 CMake 4.4.4，官方下载与 SHA-256 校验见
`scripts/setup-cmake-ci.sh`。Linux runner 为 Ubuntu 26.04 GA。

## 来源

- Flutter: https://github.com/flutter/flutter/tree/stable
- Gradle: https://services.gradle.org/versions/current
- Android SDK: https://dl.google.com/android/repository/repository2-3.xml
- RNNoise: https://github.com/xiph/rnnoise/releases/tag/v0.2
- RNNoise ARM 修复: https://github.com/xiph/rnnoise/commit/372f7b4b76cde4ca1ec4605353dd17898a99de38
- Opus: https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz
- CMake: https://github.com/Kitware/CMake/releases/tag/v4.4.4
- Runner 状态: https://github.com/actions/runner-images

源码归档 SHA-256：
- rnnoise_src.tar.gz: `90fce4b00b9ff24c08dbfe31b82ffd43bae383d85c5535676d28b0a2b11c0d37`
- opus_src.tar.gz: `6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1`

## 本地验证结果

Flutter analyze 无问题；295 项 Flutter 测试通过（1 项需要真实融合服务的集成测试跳过）；
35 项 Kotlin/JVM 测试和 lint 通过；JDK 27 + NDK 30 已生成三 ABI debug APK。
64 位原生库的 ELF PT_LOAD 对齐均至少 16 KB。原生 RNNoise 地址/未定义行为
消毒检查通过。Android Concentus ↔ iOS Opus 1.6.1 的双向 raw Opus 包测试通过。
真机三端语音、后台行为与新版模型听感仍需设备验收。
