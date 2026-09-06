# Android 源码安全审查（2026-09-06）

## 结论和范围

在检查的 Android Flutter 主线、Dart 会话/传输/更新逻辑、原生音频/BLE/Wi-Fi 插件、C++ 核心和构建配置中，**未发现明确的恶意后门证据**（例如隐蔽上传录音、命令执行、动态下载执行代码、固定远程控制端）。这不是“已证明没有后门”：未取得你手机上的 APK，未做 APK 与源码一致性验证、全依赖源码/二进制逆向、动态抓包和模糊测试，也未全面审计其他平台。旧根目录 app/ 仅做相关构建、安全和蓝牙路径抽查。

当前应用不能按“默认端到端加密、安全匿名通话”理解。核心风险主要是协议缺少完整身份认证、加密没有接入实际创建/加入路径，以及若干实现错误。

以下路径均相对于原 sunsetripple 仓库；可对照同路径的 DawnMesh 修复。

## 发现

| 风险 | 证据与影响 | DawnMesh 状态 |
| --- | --- | --- |
| 高：默认应用层明文 | `lib/core/session/room_session.dart::secureCodec` 默认为 null；首页没有握手或赋值；`LanTransport` 直接 Frame.encode；BLE 用 `listenUsingInsecureL2capChannel/createInsecureL2capChannel`。局域网可监听语音/聊天/控制数据；BLE 不能假定有认证加密。 | **尚未完成默认加密**，界面和文档如实说明，不沿用 README 的安全保证。 |
| 高：加密失败继续发明文 | `sendFrame` catch 只写“已放弃发送”，实际继续调用 onSendFrame(outFrame)，outFrame 仍是原始帧。超大载荷等异常可触发。 | 已修复：失败立即 return；新增回归测试。 |
| 高：加密会话接受明文 | `handleIncomingFrame` 对 sealed 以外的帧直接 dispatch，即使 secureCodec 已配置仍处理明文。 | 已修复：启用 codec 时拒绝所有未密封入站帧；解密后走独立 dispatcher，拒绝嵌套信封/伪握手。 |
| 高：客户端注入房主命令 | LAN `_onClientConnected`、BLE `readLoop` 无角色检查就转发和交给会话；`_handleRoster` 可重写名单，hostHandover 可触发迁移。 | 已拦截客户端链路发来的 roster / hostHandover / hostAnnounce / chatSync；**普通成员 senderId 仍未与链路做完整认证绑定**。 |
| 高：UDP 信任边界不足 | 原 UDP 收包不限定帧类型；客户端仅核对房主 IP，房主通过自报 senderId + 首包学习端点。可注入控制帧/抢占成员身份。 | 已限定为 audio/heartbeat，客户端核对来源端口。**首包抢占、同网伪造及合法成员冒名风险仍存在**，IP 白名单不是密码学认证。 |
| 高：开放入房、缺少可信身份验证 | joinReq 自动分配成员号，无房主批准/口令；现有 ECDH hello 自签名只验证对方掌握其声明密钥，没有预先信任绑定或用户核对。房主会同步已有文字历史给新成员。 | 保留开放房行为并明确提示；尚需设计房间认证、用户验证、安全密钥分发与退出换钥。 |
| 中：资源耗尽/阻塞 | BLE `sendL2capData` 在 MethodChannel 主线程同步写 socket；单个慢链路可能阻塞 UI。已接入但不完成应用入房的连接可占连接名额；缺少全链路速率/读写超时。 | 加了建链和广播启动超时，保留连接数/帧长上限；**发送队列、握手期限和压力测试尚未完成**。 |
| 中：发布签名和更新混淆 | Flutter `android/app/build.gradle.kts` 缺密钥时 release 回退 debug 签名；更新 URL 指向上游，版本常量 alpha.10 与 pubspec alpha.11 不一致。 | 独立 applicationId，发布必须配置自己签名；移除上游更新联网，统一开发版本号。 |
| 中：供应链与复现性 | 本地优先第三方 Maven 镜像；pub lock 指向镜像；Flutter compile/target/NDK 随 SDK 漂移，wrapper 有两个 distributionUrl；旧根 gradle.properties 硬编码 Windows JDK。 | 默认官方源、镜像显式 opt-in；固定 Android/NDK/CMake，去掉重复 URL；未复制旧 Windows 配置。未完成所有 Maven 构件校验/CVE 扫描。 |
| 中：日志和备份 | Dart AppLog print、Kotlin Log 可能包含 MAC/IP/昵称。诊断导出虽过滤地址和长 token，昵称和其他上下文不一定消失；Manifest 未明确关闭备份。 | 禁用应用备份；完整 logcat 分享前仍需人工脱敏。 |
| 中：本机 C++ 边界/对象生命周期 | `sunset_frame_encode` 在非零长度且 payload=null 时返回成功，输出缓冲载荷未初始化；超长载荷静默截断。ring buffer 用 malloc 分配含 std::atomic 的 C++ 对象。 | 拒绝非法输入/超长帧，改为构造/析构 C++ 对象；新增 ASan/UBSan 回归测试。未发现当前 Dart 调用把空指针远程暴露的证据。 |

## 联网、权限与数据路径

- 主线外网 HTTP 入口是用户在关于页面触发的 GitHub Releases 更新检查；本次未发现偷偷向分析/广告服务器上报的主线代码。DawnMesh 移除此入口的联网逻辑。
- `INTERNET` 同时用于本地 TCP/UDP，不能因应用“离线”就移除此权限，也不能仅凭该权限认定有后门。
- 录音由进房后的音频初始化开启，PTT 松手时 Dart 阻止语音帧发送；麦克风采集本身可仍保持打开。前台服务显示通知，START_NOT_STICKY，不见开机自启动/隐藏录音上传逻辑。后台/快速进退房仍需真机验证。
- Manifest 对外导出的主入口是 Launcher Activity；通话 Service 不导出。Flutter 主线不申请联系人、短信、通话记录、无障碍或安装 APK 的权限。
- 语音和聊天主要在内存处理，没有发现主线主动保存录音文件；日志、系统备份、进程内存及参与者自行录音意味着不能承诺绝对“无痕”。
- 旧 Kotlin `app/` 有 Google Nearby 依赖及另一套更新实现，不能把它的依赖/安全行为套到当前 Flutter APK；DawnMesh 不包含这套工程。

## 后续优先级

1. 默认认证加密：为每个物理连接建立经用户确认/预共享秘密认证的会话，防降级，入房成功前不传语音/历史。多人转发需明确房主是否可信，不能把“共享一把组密钥”误称可防组内冒名。
2. 绑定 socket/成员号、握手期限、重连令牌保护、UDP AEAD 与端点绑定；接收认证通过后才转发，防止密封帧成为绕过角色检查的通道。
3. 有界异步发送队列、背压、慢消费者断开、连接与帧速率限制。
4. 依赖清单/漏洞扫描、签名证书指纹、最终 APK 抓包、两品牌真机和多成员压力测试。

本次改进没有把上述未解决风险改写为“已安全”。对于敏感语音，不应在完成认证加密与验证前依赖当前开发版。
