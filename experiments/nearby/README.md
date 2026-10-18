# Google Nearby 真机原型

这是独立于正式 DawnMesh 的传输实验，应用名称为 **DawnMesh Nearby Probe**，版本 0.1.1，应用 ID 为 `dev.dawnmesh.nearbyprobe`。不会覆盖正式应用，也尚未接入融合房、邀请码、语音或服务器。目标是先验证你手中的 iPhone / Android 能否在没有共同 Wi-Fi 时发现、配对并可靠传输，再决定阶段 B/C 的具体适配。

## 已完成的验证

- 0.1.1 Android Debug APK 构建通过，5 项 JVM 回归测试通过，Android Lint 为 0。
- 0.1.1 iOS Release 真机架构未签名构建及 Swift 传输回归检查通过；需要在 Xcode 用自己的 Team 签名安装。
- 用户已用 iPhone 17 Pro、小米 15、一加 15T 实测 0.1.0：iOS 发布 → Android 发现、配对、双向传输通过；Android 发布 → iOS 发现失败。跨平台 32 KiB 往返 7502 ms，最大 RTT 405 ms，有效率 8.5 KiB/s。
- Android ↔ Android 首次传输约 120+ KiB/s，但重复传输和重建连接出现失败；0.1.1 为此增加回调隔离与完整状态清理，**尚待真机复测**。
- 上述 iPhone 使用默认 Debug，断开共同 Wi-Fi，蜂窝开启。iOS 未启用 WebRTC 或服务器中继；该结果证明传输可行，不证明已完成跨平台 Wi-Fi 升级。

## Android 安装

从仓库根目录运行：

```sh
experiments/nearby/scripts/build-android.sh
```

输出 `artifacts/nearby/DawnMesh-NearbyProbe-0.1.1-debug.apk`，安装到两台有 Google Play services 的安卓手机。也可使用 `adb install -r` 安装。脚本优先使用环境中的 `JAVA_HOME` / `ANDROID_HOME`，否则寻找本仓库或相邻 DawnMesh 的 `.tools`；独立环境可通过 `DAWNMESH_TOOLS_ROOT` 指定工具目录。

开启蓝牙和 Wi-Fi，授予“附近设备”等系统提示的权限。Android 12 及以下还需位置权限及系统位置服务。原型会检查 Play services 是否可用，安装了 Play 商店仍可能需要先更新 Play services。

## iPhone 安装（普通免费 Apple 账号）

1. 用 Xcode 打开 `experiments/nearby/ios/NearbyProbe.xcodeproj`。
2. 选择 NearbyProbe target，在 Signing & Capabilities 中启用自动签名，选择自己的 Personal Team。如 bundle ID 冲突，可修改为自己唯一的 ID。
3. 选择实际 iPhone，使用默认 **Debug** 配置，运行 ⌘R。信任开发者、开启开发者模式的操作与正式应用相同；免费签名通常需要每 7 天重新安装。
4. 授予蓝牙、本地网络权限。保持两端应用在前台。

默认 Debug / Release **没有 Hotspot Configuration entitlement**，先验证 BLE、同网 Wi-Fi 和 Apple 点对点路径。这条安装路径不需要为热点能力更换账号。

可选的 **HotspotDebug / HotspotRelease** 配置才加入 Hotspot Configuration、Access Wi-Fi Information 及 `DAWNMESH_NEARBY_HOTSPOT` 编译条件。只有签名 profile 支持这些能力时才使用，并在应用中打开“允许为高速连接切换 Wi-Fi”，授予位置权限。不要给普通 Debug 手工添加这些 capability 来修复签名错误；免费 Personal Team 不保证支持它们。没有该能力仍可手动连接相同 Wi-Fi/热点做基线测试。

命令行编译检查：

```sh
experiments/nearby/scripts/build-ios.sh
# 仅验证带热点能力的源码能编译，不代表已获签名能力：
experiments/nearby/scripts/build-ios.sh --hotspot
```

上述命令只生成未签名 `.app`，不能直接安装到 iPhone。项目已生成并纳入源文件；生成脚本默认保留现有项目和 Team 设置，只有明确传入 `--force` 才重建项目。

## 两台设备如何测试

1. 先在共同 Wi-Fi 下跑通基线。一端点击“发布此设备”，另一端点击“发现附近设备”，选择发现的设备。
2. **双方核对显示的配对码**，一致才确认。配对不是 DawnMesh 邀请码认证。
3. 任一端点击“测试 32 KiB 双向完整性与往返速率”，等待通过，再由另一端发起一次。
4. 双方点击停止；交换发布/发现角色后重试。
5. 在系统设置中断开共同 Wi-Fi、关闭个人热点及蜂窝数据，保留 Wi-Fi 和蓝牙开关开启，再重复上述步骤。不要用控制中心按钮“关闭 Wi-Fi”来代替断开共同 AP。
6. Android 0.1.1 默认勾选“仅用 BLE 发布”，用来对照 iPhone 的反向发现；取消勾选并重新发布可对比 SDK 默认广播。该选项仅约束发布，不能据此证明实际数据承载。是否解决反向发现仍需实测。
7. 在同一连接上连续测试至少 5 次，再停止、重新发布/发现/配对至少 3 轮。最后连续快速点击发布/发现/停止，检查是否有迟到回调恢复旧连接。
8. Android 的“允许为高速连接切换 Wi-Fi”默认关闭。测试时可明确打开重试，记录是否出现切网。iOS 对应选项只出现在上述 Hotspot 配置中。

传输测试使用 32 个 1 KiB 数据块，逐块回显，带独立随机测试标识及完整性校验，单块超时 10 秒。显示的速率为收发合计 64 KiB 除以总时间，包含逐块往返等待，**不是单向链路带宽测试，也不能仅据此判定实际使用了 Wi-Fi**。SDK 自动选择介质，原型界面不声称已经完成 Wi-Fi 升级。

下表为 0.1.1 复测清单，0.1.0 的已知结果保留在上文。

| 组合 | 共同 Wi-Fi 基线 | 无共同 Wi-Fi，BLE/Wi-Fi 开启 | 双方各发布一次 | 双方各发起传输一次 |
| --- | --- | --- | --- | --- |
| iPhone 17 Pro ↔ iPhone XR | 待真机 | 待真机 | 待真机 | 待真机 |
| iPhone 17 Pro ↔ 小米 15 | 待真机 | 待真机 | 待真机 | 待真机 |
| iPhone XR ↔ 任一 Android | 待真机 | 待真机 | 待真机 | 待真机 |
| 小米 15 ↔ 一加 15T | 待真机 | 待真机 | 待真机 | 待真机 |
| iPhone 17 Pro ↔ 一加 15T | 待真机 | 待真机 | 待真机 | 待真机 |

记录手机/系统版本、应用构建配置、BLE 发布选项、网络条件、发现耗时、是否弹配对码、测试结果/耗时/最大 RTT、切网和断线情况即可。0.1.1 的诊断区保留最近 12 条事件，API 失败会显示具体数值状态码和符号名；请一起记录。Android 的 SDK bandwidth quality 只是质量分级，仍不是实际介质名称。再检查拒绝权限、拒绝配对、断开重连、关闭蓝牙、锁屏后的恢复；不要把配对码、Wi-Fi 口令或其他敏感信息上传。

## 依赖与下一步

- Android：官方 `com.google.android.gms:play-services-nearby:19.5.1`，AGP 9.4.1 / Gradle 9.8.1 / Kotlin 2.4.21。显式对齐 Kotlin 版本，避免 SDK 元数据版本不兼容。
- Swift：官方 `google/nearby` 固定 revision `1c1bcbe8e7c5d40597014789414a6a48c40294a2`。这是实验性源码固定点，**不是声明为最新稳定发行版**。传递依赖也由 `Package.resolved` 固定。
- Swift SDK 自身存在编译告警，未通过全局关闭诊断掩盖。实验没有向正式 Runner 增加 SDK、权限或 entitlement。
- 采用 `.pointToPoint` / `P2P_POINT_TO_POINT`，只验证一对设备，不能据此承诺多人语音容量。
- 不记录房间密钥，不交换正式网络口令，不处理用户文件。后续即使采用 Nearby，仍需保留 DawnMesh 房间身份、邀请码 PAKE、加密帧、重放防护和媒体去重。

通过真实设备的发现、配对、传输、切网/重连测试后，再把可行路径接入统一目录和 FusionLink，并完成三人以上、语音、后台、无 GMS 和服务器兜底验收。原型不会自行改变正式融合房的链路选择。

官方资料：[Android 接入](https://developers.google.com/nearby/connections/android/get-started)、[Swift 接入及热点权限](https://developers.google.com/nearby/connections/swift/get-started)、[Swift 连接管理](https://developers.google.com/nearby/connections/swift/manage-connections)、[SDK 源码](https://github.com/google/nearby)、[BLE 发布参数](https://developers.google.com/android/reference/com/google/android/gms/nearby/connection/AdvertisingOptions.Builder)、[连接类型及切网语义](https://developers.google.com/android/reference/com/google/android/gms/nearby/connection/ConnectionType)。


## 0.1.1 修复范围

- Android 回调绑定会话代次，停止/重发使旧回调失效；停止发现、广播和全部端点后等待 500 ms 再开始。Android 公共停止 API 没有完成回调，这段等待不能代替真机确认。
- iOS 串行等待停止发现和广播完成，再调用 SDK 的完整端点清理接口，随后才开始新会话。保留原 Xcode Team / capability 设置。
- 两端配对成功后停止发现和广播；重复测试按 payload ID、测试随机标识和数据块序号隔离失败。已回显确认、上轮测试、回显发送和其他 payload 的迟到失败，不再取消当前请求。实际本轮请求失败仍报告错误。
- Android 显式使用 `ConnectionType.BALANCED / DISRUPTIVE` 替代已弃用的 setter；BLE 发布对照选项不是已确认的反向发现修复。
- Android 构建脚本运行 5 项 JVM 回归测试；iOS 构建脚本先运行 Swift 传输状态回归检查。回归覆盖旧会话、旧测试、已确认数据块、无关 payload 与重复失败回调。
- 正式 DawnMesh 的 Android Wi-Fi Direct、iOS ApplePeer 和公网路径均未被实验替换。Nearby 仍是可选候选，暂不作为正式融合房的唯一发现或承载方式。
