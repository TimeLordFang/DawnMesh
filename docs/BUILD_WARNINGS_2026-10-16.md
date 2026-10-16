# 三端构建检查 · 2026-10-16

版本：Android 1.1.3+54 / iOS 1.0.2+3 / Server/Web 0.3.3。

| 范围 | 本次处理 | 验证与剩余提示 |
| --- | --- | --- |
| 共用原生代码 | RNNoise 标准 C 原型、文件长度与资源所有权检查 | 两端相同源码，新增边界回归；默认模型与线协议不变 |
| Android | 备份规则、API 判断、无障碍、资源限定符、图标、KTX 与 Gradle 写法 | 应用 Lint 零问题，37 JVM 测试、295 Dart 测试及原生 sanitizer 通过；上游 Flutter/插件迁移提示保留 |
| iOS | HFP API、C/C++ 声明/初始化/转换、依赖回调与内存计算、可复现 Pods 补丁 | 298 Dart 测试、原生/Swift 与完整 Release 编译通过；保留两条归档/AppIntents 工具提示 |
| Web/Server | 媒体 SDK 按需加载、默认体积检查、npm 脚本策略与官方 registry | 21 浏览器用例、5 Node 测试、加密向量、Go race/vet、两个 Linux 架构通过；保留约 523 kB SDK 体积提示 |

没有全局关闭编译、Lint 或包体积告警。Android 两处同步持久化必须向 Dart 返回
commit() 的 Boolean 结果，而 KTX edit(commit=true) 返回 Unit，因此仅对这两处注明
局部 UseKtx 例外。npm 的 fsevents 是可选 macOS 文件监听扩展，显式禁用其安装脚本，
不影响浏览器构建；其余依赖继续使用 npm 12 默认脚本审查。

移动端 pubspec.lock 一致；无法被当前 Flutter/上游约束解析的四个间接新版本未强制 override。
两个移动端均通过同一本机真实 Go 中继集成，不代表已完成真实手机射频或声学验收。

安卓发布使用独立检出，原工作区的未提交删除和草稿未纳入版本。
iOS 的 Apple Team 和本机 Launch scheme 偏好未纳入提交；Server 的本地 systemd 草稿未纳入版本。

依据：[AndroidX Core 稳定版](https://developer.android.google.cn/jetpack/androidx/releases/core?hl=en)、
[Android 12 备份与迁移规则](https://developer.android.com/about/versions/12/behavior-changes-12)、
[Vite 生产构建拆包](https://vite.dev/guide/build.html)。
