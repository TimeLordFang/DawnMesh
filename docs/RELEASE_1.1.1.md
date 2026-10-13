# DawnMesh 1.1.1（versionCode 52）

在 1.1.0 功能基础上更新稳定版依赖和构建工具。

- Flutter 3.47.7，LiveKit 2.13.1，flutter_webrtc 1.6.2+hotfix.4 / WebRTC 150.7871.01；更新连接、Keychain/存储和图片插件。
- RNNoise 0.2 内置模型及上游 ARM 编译修复；适配新版 WebRTC 的 Wi-Fi Direct 网络信息参数。
- JDK 27、Gradle 9.8.1、AGP 9.4.1、Kotlin 2.4.21、SDK 37.2、NDK 30 和最新稳定构建工具；最低 Android API 26。
- Actions 更新并固定官方 release commit，使用 Ubuntu 26.04 GA；保留 16 KB 原生库和安装包对齐检查。

已验证 Android 构建、签名、Flutter/Kotlin 回归、lint、原生内存安全、Android ↔ iOS 双向 Opus、浏览器加密向量及真实 Go 融合中继。
与 iOS 1.0.0 和 Server/Web 0.3.1 配套；协议保持兼容原 Android 1.1.0 / Server 0.3.0。真机音质和后台行为仍需设备验收。

依赖明细与上游版本约束见 [依赖更新记录](DEPENDENCY_UPDATE_2026-10-13.md)。
