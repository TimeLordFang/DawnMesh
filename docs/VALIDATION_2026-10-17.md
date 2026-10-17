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


## iOS 侧滑动画与跨端蓝牙房名（iOS 1.0.4 / 安卓 1.1.5）

iOS 普通页面及公网房使用原生交互返回，支持跟手和取消回弹；本地房间的
侧滑进度驱动既有舞台转场。聊天、成员、设置、诊断和高级调优弹层补齐侧滑
移动及回弹动画。键盘优先返回仅收起键盘，房间最小化继续保留会话和聊天，
并释放按住说话状态。手势启用状态改变时始终保持组件结构，避免再次销毁
等待邀请码结果的首页。

安卓旧实现将 PSM/人数放在主广播中，房名放在最多 24 字节的扫描响应中；
iOS 原先在解析到主广播后不会继续读 GATT，因此部分发现结果只有占位房名。
安卓现提供与 iOS 相同的只读 GATT 元数据服务，支持完整 UTF-8 名称、ATT 长读、
人数更新、蓝牙重启恢复及退出清理。iOS 即使已读到主广播也补读 GATT，且完整
名称不会再被后续的主广播或较短扫描响应覆盖。

两端入房采用输入邀请码期间收到的最新名称。旧版安卓仍仅有占位名时，
入房后依据已认证的房主成员信息补全标题；切换 PSM 后不复用旧房名称。
发现信息仍仅用于展示，邀请码验证及加密帧协议保持兼容。

相关平台行为见 [Flutter PopScope](https://api.flutter.dev/flutter/widgets/PopScope-class.html)
和 [Android GATT 读取回调](https://developer.android.com/reference/android/bluetooth/BluetoothGattServerCallback#onCharacteristicReadRequest(android.bluetooth.BluetoothDevice,int,int,android.bluetooth.BluetoothGattCharacteristic))。

验证结果：

- iOS Flutter：316 项通过；安卓 Flutter：297 项通过。两端各 1 项真实 Go 中继测试
  因未设置测试服务器地址而按既有配置跳过。
- 两端 Flutter analyze 无问题；安卓 JVM 41 项通过，Android Lint 0 issues。
- Swift 元数据、完整名称优先级和换房缓存等共 190 项检查通过。
- iOS Release 完整未签名编译通过；安卓 Release APK 编译、签名及 16 KiB ZIP 对齐检查通过。

尚未执行本次修改后的真机蓝牙验收。复测时两端都安装本次构建，安卓房主保持前台，
先检查 iOS 附近房间的中文/emoji 长名称，再输入邀请码检查房内标题；反向建房
亦需回归。侧滑分别检查跟手、取消、完成、聊天键盘优先收起及返回后重新进入房间。

本轮版本：iOS 1.0.4+5、安卓 1.1.5+56；对应 GitHub main 上的 v1.0.4 / v1.1.5 tag。
