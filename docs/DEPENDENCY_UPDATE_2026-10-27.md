# 2026-10-27 稳定依赖核对与更新

应用版本保持 **1.2.2+63**；本次只更新源码和锁文件，不新增正式标签或覆盖历史发布包。Android、iOS 与服务器分别执行本地验证。

| 范围 | 更新后的版本 |
| --- | --- |
| Flutter / Dart | 3.47.8 / 3.13.7 |
| Gradle / AGP / Kotlin | 9.8.2 / 9.4.1 / 2.4.21 |
| 本地 Gradle JDK | Temurin 27.0.1.0.2+1；Android 字节码仍为 Java 17 |
| Android SDK / Build Tools / NDK | compile 37.2、target 37 / 37.0.0 / 30.0.16248370 |
| Android SDK CMake / 独立 CMake | 4.1.2 / 4.4.4（各自渠道最新稳定版） |
| Flutter WebRTC / 原生 WebRTC SDK | 1.6.3 / 150.7871.04 |
| Flutter LiveKit / crypto | 2.13.2 / 3.0.8 |
| CocoaPods | 1.17.0 |
| Node / npm | 26.12.1 / 12.2.1 |
| Web LiveKit / Vite / Playwright | 2.23.0 / 8.3.5 / 1.64.1 |
| TypeScript / @types/node | 7.0.2 / 26.6.5 |
| Go 工具链 / LiveKit protocol / SQLite | 1.27.3 / 1.53.1 / 1.61.0 |
| 容器基础镜像 / BuildKit | Alpine 3.24.3 / 0.34.1；Buildx 0.38.1 |
| CI action 更新 | setup-java 6.1.0、docker/login-action 4.7.0；保持提交 SHA 固定 |

其余直接 Flutter 依赖（cryptography、pointycastle、http、connectivity_plus、flutter_secure_storage、image_picker、gal、flutter_lints、fake_async）、AGP、Kotlin、AndroidX Core、Concentus、RNNoise 0.2、iOS Opus 1.6.1 等已核对稳定发布，无需改动。Dart 锁文件同时升级 asn1lib、image_picker_ios、jni、vector_math、web 等可解析间接依赖；服务器升级实际使用的 Go 间接依赖并重新整理 go.sum。

## 兼容约束

- 不引入 beta、RC 或 nightly 工具链。依赖管理器不会把不兼容的上游约束强行覆盖。
- `cross_file 0.3.5+5`、`sdp_transform 0.3.2` 受最新插件的上游约束；`material_color_utilities 0.13.0`、`test_api 0.7.12` 受最新稳定 Flutter SDK 固定。不能为消除 outdated 提示添加 overrides 或改写插件约束。
- 部分 Go 上游模块没有稳定标签，继续采用其最新兼容 pseudo-version；不替换为不兼容的大版本路径。
- WebRTC-SDK 150.7871.04 的官方 podspec 最低 iOS 13；项目最低 **iOS 15 不变**。新插件和原生 SDK 必须一起更新锁文件，DawnMeshDSP 保持精确依赖 1.6.3，避免音频处理器 ABI 错配。
- 当前电脑安装 Xcode 27.0；Apple 当前稳定版为 **27.1（Swift 6.4）**，27.2 RC 不采用。CI 使用 `latest-stable`。本机 Xcode 的 App Store 安装/账号交互需由使用者完成，不能把当前机器上的验证写成 Xcode 27.1 验证。

## 官方核对来源

- [Flutter 3.47.8](https://github.com/flutter/flutter/releases/tag/3.47.8)、[Gradle 发布](https://gradle.org/releases/)、[Kotlin 发布](https://kotlinlang.org/docs/releases.html)
- [pub.dev](https://pub.dev/)、[Google Maven](https://maven.google.com/)、[Maven Central](https://repo.maven.apache.org/maven2/)、[CocoaPods Specs](https://github.com/CocoaPods/Specs)
- [Temurin 27](https://github.com/adoptium/temurin27-binaries/releases)、[CMake](https://github.com/Kitware/CMake/releases)、[Opus 稳定下载](https://opus-codec.org/downloads/)
- [Go 稳定下载](https://go.dev/dl/)、[Node 发行](https://nodejs.org/en/download/releases)、[npm registry](https://registry.npmjs.org/)、[Alpine 发行](https://alpinelinux.org/releases/)
- [Xcode App Store](https://apps.apple.com/app/xcode/id497799835)、[Apple 开发者发行](https://developer.apple.com/news/releases/)

## 本地验证记录

- Android：363 项 Flutter 回归（含真实 Go 中继）、2 项原生 sanitizer 测试、JVM 与 Lint、签名 APK/AAB、签名和 16KB 页对齐检查通过；最后的主题切换、房间布局和进出动画专项也通过。
- iOS：382 项 Flutter 回归与独立建房用例通过，原生、Swift、插件补丁和 512 KiB Apple TCP 代理回归通过；普通和可选 Aware 构建分别验证。构建机仍为 Xcode 27.0。
- 服务器：网页构建、5 项前端单测、协议密码学向量、21 项真实浏览器回归、Go race/vet、Linux amd64/arm64 编译通过；npm audit 为 0，govulncheck 未发现可达漏洞。扫描还记录 1 项未被导入/调用模块中的漏洞，不代表模块级扫描完全为零。
- 当前机器只有 Docker CLI，无可运行的本地容器引擎，镜像构建交给 CI 验证；未把原生 Linux 构建通过记为容器已验证。
- 厂商桌面动画、无线通信与锁屏效果仍按真机清单手动验证。
