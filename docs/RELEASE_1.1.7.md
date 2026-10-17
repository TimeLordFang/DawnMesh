# DawnMesh Android 1.1.7

版本：1.1.7+58；配套 iOS 1.0.6。Server/Web 0.3.3 无需升级，语音、聊天和邀请码协议不变。

修复 iOS 建 Wi-Fi 房时安卓无法自动发现的协议缺口，为双方补齐同网 Bonjour/NSD 双向发现。保留之前侧滑动画、蓝牙房名及异步 UDP 错误处理。

## 发现协议与范围

- Android 通过系统 `NsdManager` 浏览并发布 `_dawnmesh._tcp`、`_dawnfusion._tcp`，与 iOS 的 Bonjour 使用相同 TXT 字段。Android 14+ 跟踪服务地址/人数更新，旧系统串行解析，避免同时解析冲突。
- Android 使用服务解析所得的地址与 SRV 端口；iOS 苹果点对点监听是 TCP 转接，其发布端口可能与 TXT 内的 Dart 控制端口不同。保留完整房名、房主、人数及既有邀请码认证，元数据不授予入房权限。
- 保留现有 UDP 发现和 iOS 单播/手动地址备用路径；普通 Apple 账号无需新增 multicast entitlement。Android 17 声明并申请 `ACCESS_LOCAL_NETWORK`，首次授予后重试 NSD。
- 发现列表有容量及字段边界校验；服务消失及时移除，退出/刷新取消旧订阅，每次启动使用独立 ID，迟到结果不再关闭新扫描。
- **本次不包含无共同网络的 iOS ↔ Android 自动直连。** 现有苹果点对点链路与 Android Wi-Fi Direct 协议不同；共同 Wi-Fi 或任一手机开启热点并由另一台连接后，可走上述同网发现。真正的跨平台无路由器发现需另行实现 Wi-Fi Aware、系统配对及能力检测，不能仅靠修改广播名称。

## 验证

Android Flutter 304 项、iOS Flutter 323 项通过（两端各 1 项既有中继测试按配置跳过）；新增回归覆盖实际端口、双语/emoji 名称、无 UDP 路由、普通/融合房隔离、服务移除、边界/容量、缺失插件备用路径，以及快速重启时旧启动迟到的竞争。Android JVM 45 项及 Lint 通过，两端静态分析与 Release 构建通过。

尚未完成本次版本两台真机同网射频验收，不能用通道模拟、编译或回环测试代替。测试时双方升级并保持前台，iOS 允许本地网络，Android 17 允许本地网络；分别以双方作为房主检查发现、邀请码、双向语音、消息和退房。路由器的访客隔离/mDNS 过滤仍可能阻止发现。

参考：[Apple 本地网络与广播权限](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)、[Android NSD](https://developer.android.com/develop/connectivity/wifi/use-nsd)、[Android 本地网络权限](https://developer.android.com/privacy-and-security/local-network-permission)、[Apple Wi-Fi Aware](https://developer.apple.com/documentation/WiFiAware)、[Android Wi-Fi Aware](https://developer.android.com/develop/connectivity/wifi/wifi-aware)。
