# DawnMesh 1.1.3（versionCode 54）

同步 iOS 检查中发现的共用音频库问题，并规范 Android 构建与平台资源。

- RNNoise 标准 C 原型与 iOS 同步；模型文件加载检查 seek/tell、分配失败、空文件及 INT_MAX 上限，保留调用方文件所有权。
- 备份规则明确排除身份、凭据与房间密钥的云备份和设备迁移；保留 Android 8 最低版本。
- 清理冗余 API 判断与资源限定符，蓝牙恢复入口显式检查 API 29；保留锁屏显示的低版本兼容处理。
- 补全自定义 View 构造与无障碍 click 入口、圆形/单色启动图标，绘图和异步偏好写入使用 KTX。
- 直接声明稳定 AndroidX Core KTX 1.19.1；同步 image_picker_ios 0.8.13+12、synchronized 3.5.0，两移动端 pubspec.lock 一致。
- 更新项目自身弃用的 Gradle 写法，发布依赖解析使用 --enforce-lockfile。

验证：应用 Lint 从 17 项告警降至零；37 项 JVM 单测、295 项 Dart 回归（294 项全套加真实 Go 中继用例）、原生 ASan/UBSan 两目标、Debug APK 和 64 位 ELF 对齐检查通过。
两处需要返回实际 commit 成功值的同步持久化表达式保留原 API，并只在对应局部变量说明 UseKtx 例外；没有全局屏蔽告警。

Flutter/插件仍使用 AGP 兼容 DSL 和旧插件 API，保留这些上游迁移提示，不能在上游支持前直接移除兼容层。
配套 iOS 1.0.2、Server/Web 0.3.3；线协议和媒体加密保持兼容。手机蓝牙、备份/迁移、锁屏和声学效果仍需真机复测。
