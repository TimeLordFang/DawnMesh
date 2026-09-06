# 小米 / 一加 Android 16 蓝牙搜房排查

## 从源码确认的首要原因

本结论针对当前 Flutter 主线。若手机装的是旧 Kotlin alpha.7 APK，蓝牙是 RFCOMM 而非 BLE L2CAP，不能假定与新版本互通。先记录 APK 版本、来源及两端是否同版本。

1. 原 `lib/ui/pages/home_page.dart::_startScan` 只调用 LAN discovery 和 Wi-Fi Direct，没有调用 `BleL2capTransport.startScan`。列表也是 `DiscoveredRoom` 与 Wi-Fi P2P 设备，没有 BLE 房间列表和 connectToHost 入口。这足以解释两种品牌均无法搜房，无需假设 Android 16 本身不支持。
2. 创建 BLE 房忽略 `startHost()` 返回值，广播失败时仍 `createRoom` 并切入房内，形成“房主已建房”的假象。原 Wi-Fi 路径也有同样问题。
3. 原 `supportError` 先读取 `adapter.isEnabled` 再检查 BLUETOOTH_CONNECT，权限被拒绝时可能抛 SecurityException。Android 10/11 的扫描也未检查精确位置/位置开关。
4. 原广播只有 UUID 在主包，PSM/人数/房名全部在扫描响应。若 ROM 未提供扫描响应，解析器直接丢弃。DawnMesh 把 PSM/人数也放入主包：flags 3 + UUID 18 + 厂商数据 7 = 28 字节，低于 31 字节预算；名字仍在扫描响应。
5. 广播人数更新复用最初的 MethodChannel.Result，回调会再次回复已完成调用；现改为仅回复一次，后续失败走事件诊断。启动广播 8 秒、建立连接 12 秒超时并关闭相应 socket；过期回调不能复活已关闭的房间。

## 仍属待验证的可能因素

- Android 12+ 需要运行时“附近设备”权限；Manifest 声明不等于已授权。新版有按操作申请/重新尝试的入口。
- 官方文档明确 `BLUETOOTH_SCAN` 的 `neverForLocation` 可能过滤部分 BLE beacon。本项目保留该声明，避免为尚未证实的问题扩大定位权限。没有证据证明本应用的 UUID/0xFFFF 广播一定被过滤；若补齐 UI 后仍收不到，才做受控 A/B 测试。
- 电池限制、屏幕熄灭、后台冻结、其他应用占用扫描/广播资源可能影响 Xiaomi / OnePlus；没有两台手机的型号、ROM 构建号和日志，不能断定具体厂商 bug。
- Android 的扫描注册有频率限制，不应连续快速停启扫描。当前页面在前台持续扫描，刷新复用扫描注册，不做后台循环。
- BLE 搜房发生在应用内部。系统“配对新设备”的经典蓝牙列表不是该应用房间列表。
- 硬件需支持 BLE peripheral 广播和 Android 10+ L2CAP CoC API；并非只看营销上的“蓝牙 5.x”。

## 两台手机复测

两台都装同一 DawnMesh debug APK，打开蓝牙、允许附近设备与麦克风。先亮屏、应用保持前台、相距 1–2 米。

| 场景 | 应检查的结果 |
| --- | --- |
| 小米创建，一加选择“蓝牙对讲”并扫描 | 10 秒内看到房间，点击加入；双方名单出现第二人 |
| 一加创建，小米扫描 | 反向同样成功 |
| 两端分别按住说话并松开 | 对端能听到；松开后不再发送本机语音 |
| 建房前关闭蓝牙 / 拒绝权限 | 明确错误，不能进入一个虚假的房间；恢复后可重试 |
| 房主离开再创建 | 旧房消失，重新扫描拿到新 PSM；可再次加入 |
| 快速点击建房/加入 | 只启动一次操作，不产生多个连接/重复房间 |
| 加入/离开人数变化 | 房间人数更新，广播回调不出现 Reply already submitted |
| 入房后切后台 30 秒、熄屏 1 分钟 | 记录声音/连接变化；若仅后台失败再检查厂商电池策略 |
| 3–6 台、远距离/干扰、连续 10 次进退房 | 记录断连、卡顿、资源泄漏；这是后续压力测试 |

对每台手机分别保存只读诊断（不要把完整日志公开，可能含设备地址/昵称）：

```sh
adb devices -l
adb -s SERIAL shell getprop ro.product.model
adb -s SERIAL shell getprop ro.build.version.release
adb -s SERIAL shell getprop ro.build.display.id
adb -s SERIAL shell dumpsys package dev.dawnmesh.intercom
adb -s SERIAL logcat -v time SunsetBle:I SunsetMain:I SunsetAudio:I flutter:I '*:S'
```

顺序判断：没出现“开始扫描蓝牙房” → 扫描/权限入口；房主没“BLE 广播已开启” → 广播/权限/硬件；双方都有但列表为空 → 扫描结果/广播解析；列表有而连接失败 → PSM、L2CAP、超时；连接成功没声音 → 麦克风、PTT、音频路由，与搜房分开定位。

资料：[蓝牙权限](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)、[Android 16 面向 target 36 的行为变化](https://developer.android.com/about/versions/16/behavior-changes-16)。DawnMesh 当前 target 35；“运行在 Android 16”与“targetSdk 36”不是同一条件。
