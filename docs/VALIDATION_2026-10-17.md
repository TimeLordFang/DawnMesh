# 移动端无线互通更新验证（2026-10-17）

版本：iOS 1.0.3+4、Android 1.1.4+55；现有 Server/Web 0.3.3 协议不变。

| 检查 | 结果 |
| --- | --- |
| iOS Flutter analyze | 无问题 |
| iOS 全量 Dart | 302 项通过，包含真实 Go 中继 |
| Android Flutter analyze | 无问题 |
| Android 全量 Dart | 295 项通过，包含真实 Go 中继 |
| Android JVM | 39 项通过，含 Swift/Kotlin 共用格式的 GATT 元数据向量和畸形输入 |
| Android 应用 Lint | 0 issues |
| iOS 原生 CTest | 3 项通过，Android Opus 样本双向兼容、PLC/畸形输入检查通过 |
| Swift | 186 个帧、缓存、队列、GATT 元数据及房主命令检查通过 |
| 苹果 TCP 转接 | 真实回环网络往返 512 KiB，检查顺序、完整性和断线清理通过 |
| Dart 点对点路径 | 帧往返、原服务重连、取消未完成连接和失效服务检查通过 |
| iOS 界面 | 蓝牙建房按钮可用并实际调用原生接口，失败不进入空房间 |
| Pods 补丁 | 可重复应用，原缓存不变，未知源文件拒绝检查通过 |
| iOS Release | Xcode 27 完整未签名构建通过，App 版本 1.0.3 / 4 |
| Android Release | APK 构建、签名验证、ZIP 对齐和 64 位 ELF 16 KiB 对齐检查通过，版本 1.1.4 / 55 |
| 发布工作流 | iOS YAML 与所有 shell 块语法检查通过；tag 产物发布为未签名 App ZIP 与 SHA-256 |

iOS 保留本机 Team 和 Run scheme 偏好；发布提交排除这些本机设置。Android 原有 debug/profile manifest 本地删除及硬件方案草稿不属于本次发布。

## 尚未完成的真机验收

- 两台 iPhone 不连接共同 AP、关闭蜂窝数据时的首次无线发现、双向语音和聊天。
- iOS 房主、iOS/Android 混合客户端的蓝牙连接、长时间语音和实际稳定多人容量。
- 两种无线模式在弱信号、系统蓝牙/Wi-Fi 开关、锁屏及后台调度中的恢复。

编译与回环测试不能证明实际射频链路稳定。首次蓝牙发现/入房应保持 iOS 房主前台；后台广播对安卓的可见性受系统限制。苹果点对点路径目前仅用于普通 Wi-Fi 房；融合房继续使用同网/热点与原公网路径。
