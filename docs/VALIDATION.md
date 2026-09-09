# 验证记录（2026-09-09）

## 本次交付

- 发布 APK：`artifacts/DawnMesh-0.1.0-dev.13-release.apk`，**53,900,004 字节**。
- 包 ID `dev.dawnmesh.intercom`，版本 `0.1.0-dev.13` / versionCode **13**，minSdk **26**、targetSdk **35**。BLE L2CAP 对讲需要 Android **10 / API 29** 以上。
- APK SHA-256：`9b42b21f70f553a2f875b003c1692f03591d8cdd1c73ef434e4e928f2b45555c`。
- 独立 RSA 3072 位签名证书 SHA-256：`58807a8354fe95537c7b818a29cc694d7f43c9480f1a60bd3fba7320bd285446`。
- APK Signature Scheme v2 校验通过；没有使用原作者或 Android debug 签名。release Manifest 未开启 debuggable，allowBackup=false。
- 优先将上述 release 安装到所有测试手机，避免混用调试签名。

## 已执行

工具链位于本项目 `.tools/`：Flutter **3.29.3 / Dart 3.7.2**、Temurin **JDK 17.0.20.1**、Android SDK Platform **35**、Build-Tools **35.0.0 / 34.0.0**、NDK **27.0.12077973**、CMake **3.22.1**、Gradle **8.12**。Apple Silicon 主机补装 Rosetta 后，Flutter Intel AOT 编译器可正常执行。

| 检查 | 结果 |
| --- | --- |
| `./scripts/check.sh` | 退出码 0，包含以下 Dart/Flutter 与 C++ 检查 |
| Flutter analyze | **No issues found** |
| Flutter 全量测试（串行） | **168 项通过，0 失败** |
| C++ ASan / UBSan | 帧边界、环形缓冲测试通过，无 sanitizer 报错 |
| `:app:testDebugUnitTest` | Kotlin **22 项通过，0 失败** |
| `:app:lintDebug` | 成功；**0 errors、10 warnings**（旧版 API 冗余判断、备份配置建议、图标资源、锁屏属性版本提示等），没有关闭 Lint 或加入忽略基线 |
| Flutter release APK | 构建成功，使用独立本地密钥 |
| `apksigner verify --verbose --print-certs` | 通过，1 个签名者 |
| `zipalign -c -P 16 -v 4` | Verification successful |
| ELF PT_LOAD 对齐 | 全部 **6 个 arm64-v8a / x86_64** 库均 ≥ 16384；包括 Flutter 引擎、Dart AOT、本项目 C++ |
| 32 位 ABI | armeabi-v7a 的本项目 C++ 为 4096 对齐，单独记录；不是 Android 64 位 16 KB 对齐失败 |
| 原 sunsetripple 目录 | `git status --short` 为空，未修改原工程 |

按 [Android 官方 16 KB 检查范围](https://developer.android.com/guide/practices/page-sizes#elf-alignment)核对 64 位 ELF 与 ZIP 对齐。额外记录 GNU_RELRO：Flutter 引擎与本项目 C++ 具备该段；Flutter 3.29.3 生成的 `libapp.so` 没有该段。未对 Flutter 预编译运行时/AOT 生成器做进一步二进制加固审计。以上均为静态包检查，**没有据此声称已在 16 KB 手机运行通过**。

## 2026-09-09 依赖升级审计

- Flutter SDK 已升级到 **3.47.2**，随带 Dart **3.13.2**；`pubspec.lock` 已重解并移除已停止维护的 `js` 传递依赖。
- 直接 Dart 依赖已同步到当前稳定约束：`pointycastle 4.0.0`、`intl 0.20.3`、`ffi 2.2.0`、`flutter_lints 6.0.0`、`test 1.31.1`、`fake_async 1.3.3`。锁文件中的 7 项分析/测试传递依赖仍受 Flutter SDK 约束，不能独立升到其绝对最新版。
- Android 构建工具已升级到 **AGP 9.2.1 + Gradle 9.4.1 + AGP 内置 Kotlin 2.4.0 + compile/targetSdk 36 + NDK 28.2.13676358**。AGP 9.2 的官方默认 NDK 为 28.2；CMake 3.22.1 保留以兼容现有 native CMake 工程。
- 新增 `.github/dependabot.yml`，每周检查 pub、Gradle 和 GitHub Actions；Action 使用完整 commit pin，避免标签漂移。
- 3.47.2 下 `flutter analyze` 和 Flutter 全量测试 **168 项通过**；Android Kotlin 单元测试 **22 项通过**。新版 Lint 首次发现的 11 个 MissingPermission 错误已补上运行时权限检查和异常保护。
- 本轮最后一次 Android Lint/APK release 需要 Gradle 的本机进程锁；当前执行环境的提权审批额度在验证中耗尽，缓存构件已准备完成，需在本机终端重新执行 README 中的两条 Gradle/Flutter 命令完成最终 APK 产物更新。

日志：[静态分析](validation/flutter-analyze.txt)、[Flutter 测试](validation/flutter-tests.txt)、[完整代码检查](validation/final-checks.txt)、[Android 构建检查](validation/android-checks.txt)、[Android Lint](validation/android-lint.txt)、[发布构建](validation/release-build.txt)、[APK 校验](validation/apk-verification.txt)。测试日志中的地址、昵称和故意触发的认证失败均为测试样例。

## dev.13 本轮完成情况

- 蓝牙房接收缓冲由 300 ms 降到 **160 ms** 起播，发生欠载时仍会快速扩展，最高限制为 **400 ms**，最大队列限制为 640 ms。
- 修复自适应缓冲只增不减的问题。连续稳定播放约 5 秒后，每次静默解码并修剪一帧 20 ms 音频，逐步把已累积的播放延迟降回 160 ms；静默解码保持 Opus 预测状态连续。
- 蓝牙房与蓝牙耳机共用控制器时，Opus 由 12 kbps 进一步降为 **10 kbps**，降低空口载荷；保留 60 ms L2CAP 合并窗口，避免重新增加小包写入频率。没有蓝牙耳机时仍使用 16 kbps 与较短合并窗口。
- 缓冲诊断新增 `trimmed` 计数。真机日志可同时观察 `target=8..20`、`trimmed`、`rebuffer`、`coexistence=true`、`opus=10000bps` 与 `txFrames/txWrites`，区分抖动恢复、延迟回落和蓝牙控制器拥塞。
- 完整串行 Flutter 测试 **168 项**、Kotlin 测试 **22 项**、Android Lint（0 errors）、静态分析、release APK 构建、签名与 16 KB 对齐检查均通过。

## dev.12 已保留功能

- 根据真机日志确认房主关闭蓝牙会销毁 BLE 广播、L2CAP server socket 与旧动态 PSM；此前应用只记录 `adapter_disabled`/`accept 中断`，适配器恢复后没有重建房间。
- 原生插件现在监听 `BluetoothAdapter.ACTION_STATE_CHANGED`。房主蓝牙关闭时保留房间身份、房名、人数和成员会话；回到 `STATE_ON` 后按退避策略重新申请动态 PSM、启动 accept 线程并恢复 BLE 广播。旧恢复任务使用 generation 隔离，退房后不会误重建。
- Android 14+ 前台服务增加 `connectedDevice` 类型和对应权限，持续蓝牙连接、后台恢复广播与麦克风用途都向系统正确声明。
- 检测到蓝牙房与蓝牙耳机同时使用时，发送 Opus 自动由 16 kbps 调整为 12 kbps，L2CAP 合并窗口由 25 ms 增至 60 ms；无耳机时恢复原参数。诊断新增 `txWrites` 和 `coexistence`，可对照 `txFrames/txWrites` 判断实际合并比例。
- 蓝牙接收预缓冲从 200 ms 提高到 300 ms，连续欠载后最多自适应到 600 ms；最大缓存为 1 秒。音频路由日志把数字设备类型翻译为 `BT_SCO`、`BT_A2DP`、`BLE_HEADSET`、`BUILTIN_MIC` 等，并记录有效 Opus 码率。
- 完整串行 Flutter 测试 **168 项**、Kotlin 测试 **21 项**、Android Lint（0 errors）、静态分析与 release APK 构建均通过。

## dev.11 已保留功能

- BLE L2CAP 每条物理链路会在最多 25 ms 内合并相邻协议帧，一次 socket 写入可携带多个完整帧；接收端仍按原有 6 字节帧头逐帧解析，协议兼容。该改动降低 20 ms 音频小包与耳机实时音频竞争蓝牙控制器的调度频率。
- 蓝牙房接收缓冲从 120 ms 起步提高到 200 ms，发生欠载后最多自适应到 400 ms，最大缓存 800 ms。码率仍为 Opus 16 kbps，没有用进一步降低音质换取改善。
- Android 12 及以上使用 `setCommunicationDevice` 统一绑定耳机双向通信设备，清理可能冲突的单流偏好；日志每 10 秒记录 AudioRecord、AudioTrack 和通信设备的实际路由。
- 房间底部新增“耳机麦克风/手机麦克风”切换。手机麦克风模式继续把对讲声音送到蓝牙耳机，并优先使用 A2DP/BLE 媒体输出，以避开经典耳机 SCO 上行并改善同时播放音乐的兼容性。
- 新增 L2CAP 合并写入、400 ms 自适应缓冲和三种手机尺寸下麦克风切换回归。完整串行 Flutter 测试 **168 项**、Kotlin 测试 **20 项**、Android Lint、静态分析与 release APK 构建均通过。

## dev.10 已保留功能

- 修复客户端关闭再开启蓝牙后仍复用旧扫描结果的问题。每次恢复现在先重新扫描原房间，再使用广播中的最新设备地址和动态 PSM 建立 L2CAP。
- 修复重连时 Flutter `EventChannel` 的取消/重新订阅竞态。现在会等待旧订阅的原生 `onCancel` 完成后再建立新订阅，避免新链路的数据 sink 被旧取消操作清空。
- 恢复日志新增重新扫描、发现房主、地址/PSM 刷新、开始建立 L2CAP，以及系统错误码和失败阶段。断开时同时记录蓝牙适配器状态；本机关闭蓝牙产生的 EOF 会标记为 `adapter_disabled`，避免误报成远端主动关闭。关闭蓝牙时重试会快速返回，开启后下一轮扫描自动继续。
- 新增“地址和 PSM 改变后重新扫描并连接”的回归测试。该版完整串行 Flutter 测试 **168 项**、Kotlin 测试 **18 项**、Android Lint、静态分析与 release APK 构建均通过。

## dev.9 已保留功能

- BLE L2CAP 原生层不再吞掉 EOF 和 `IOException`；客户端会立即收到结构化断链原因。断开日志带收发帧/字节数、链路存活时间和收发空闲时间；连接期间每 10 秒输出同类快照。
- Wi-Fi TCP 与蓝牙客户端都会重建物理链路、重新执行邀请码 PAKE 和入房，退避重试总窗口为 10 分钟。恢复期间不关闭音频前台服务与锁屏控件，成功后自动回到通话状态。
- 房主为掉线成员保留 10 分钟的成员号、加入顺序和名额；Wi-Fi Direct 房主会轮询系统群组状态并在同一窗口内自动重建意外消失的群组。
- 客户端对房主的存活判定从 6 秒放宽到 12 秒，且任意已认证的房主帧都会续期，降低 Android 后台调度抖动引发的假断线。房间标题下方会显示恢复状态。
- Wi-Fi Direct 连接等待改为先订阅系统事件并主动回查当前状态，避免厂商系统在方法返回前已广播连接结果导致假超时。
- 诊断日志的脱敏不再把 `securityPatch`、`batteryOptimizationIgnored` 等长字段名和安全补丁日期误删，仍会隐藏 IP、MAC 和随机长令牌。
- 新增重连控制器、物理断链重入房、PAKE 重认证、10 分钟成员保留与 Wi-Fi Direct 事件竞态回归。完整串行 Flutter 测试 **167 项**、Kotlin 测试 **18 项**、Android Lint 与 release APK 构建均通过。

## dev.8 本轮完成情况

- 日志条目改为单一深色等宽控制台，按时间从上到下连续排列；毫秒时间、级别、模块和消息压缩到同一行，新日志自动滚动到底部。360×640 页面交互测试通过。
- 系统快照新增应用版本/进程、设备与 SoC、Android/API/安全补丁、ABI、CPU/堆/RAM、低内存状态、电池优化、音频参数及路由设备、Wi-Fi/当前网络、BLE 能力和关键权限。支持页面内手动刷新。
- Flutter 框架错误与根 isolate 未捕获异步错误进入日志总线。普通应用无法读取完整系统 Logcat，未声称能读取其他应用、内核或受保护系统服务的日志。
- Dart 包改为 `dawn_mesh`；Kotlin namespace、平台通道和启动 Activity 改为 `dev.dawnmesh.intercom`；日志 tag、后台线程、C++ 库、FFI 类型和导出符号均采用 Dawn 标识。源码目录的 `sunset` 文本扫描结果为空。
- 清除旧 CMake 增量缓存后重新构建，APK 只包含 `libdawn_mesh_native.so`，不包含旧原生库。发现 magic、PAKE 上下文与 HKDF 上下文也已更新，因此 dev.8 不能与 dev.7 及更早版本互通，所有手机必须一起升级。

## dev.7 本轮完成情况

- 主页和房间页新增调试日志入口；记录默认关闭，用户开启后把状态持久化到 Android 私有设置，关闭时立即停止记录并清空内存。
- 页面最多保留最近 400 条，支持 DEBUG/INFO/WARN/ERROR 筛选、关键字搜索、复制当前结果和手动清空；日志不写入文件，重启应用不恢复旧内容。
- Android 原生音频、BLE、Wi-Fi Direct 和前台服务日志通过 EventChannel 进入同一页面。旧红米复测时可直接观察 Opus 编码超时、抖动缓冲、AudioTrack underrun 和 L2CAP 链路异常。
- 复制日志会隐藏 IP、MAC 和长令牌；关闭记录后原生层也停止向 Logcat 和 Flutter 转发，减少常态性能及隐私开销。
- 新增开关、持久化、内存清空、页面筛选和交互回归测试。本轮未改变邀请码、加密、发现和语音传输协议，可与 dev.6 互通并使用同一签名覆盖升级。

## dev.6 本轮完成情况

- Wi-Fi 和蓝牙房共用新的胶囊式模式切换控件：选中块以 260 ms 曲线滑动，按住对讲与自动通话分别使用图标、渐变色和“按住发送 / 声音触发”说明。
- 矮屏自动使用 46 dp 紧凑布局并收窄顶部间距；窄屏或大字号隐藏辅助说明但保留两个完整操作目标，360×640 进出房转场与 2 倍字号均无溢出。
- 锁屏通话面板同步为图标化胶囊按钮，选中项使用模式色、缩放、透明度动画和触觉反馈，无需解锁即可切换。
- 本轮只改变界面与版本号，邀请码、加密、发现和语音传输协议均未改变，可与 dev.5 互通并使用同一签名覆盖升级。

## dev.5 已保留功能

- 昵称通过 Android 私有 `SharedPreferences` 持久化，进程或活动重建后恢复；邀请码、密钥和聊天不写入该设置文件。
- Wi-Fi 房与蓝牙房都可在自动通话和按住对讲之间切换，主界面和锁屏面板行为一致，每台设备独立选择发言方式。
- Android 10+ Wi-Fi Direct 房由邀请码派生已知 SSID/口令，创建和加入均使用 `WifiP2pConfig.Builder`，不再触发旧式 WPS 房主批准流程；Android 8/9 受系统 API 限制仍使用旧流程。厂商系统仍可能实施额外确认。
- 蓝牙广播按原始 AD 结构逐条解析，避免 Android 15/16 合并相同厂商 ID 后把第二份 PSM/人数元数据渲染成房名前乱码；严格验证 UTF-8，并按 Unicode 码点截断。
- 音频播放把 TCP/L2CAP 视为有序可靠流，不再把共享协议序号中的心跳/聊天空档误判为丢失音频。蓝牙预缓冲提高到 120 ms，欠载后自适应重新缓冲，最多缓存 480 ms；采集/播放/发送线程提高优先级，Opus 复杂度降为 5，并增加欠载与编码超时诊断。
- 与 dev.4 使用相同签名，支持覆盖升级。K50 Ultra 的实际改善、Wi-Fi Direct 厂商确认行为与三机语音仍由用户真机验收。

## dev.4 已保留功能

- 邀请码直接显示在聊天室信息下方，创建后默认显示 10 秒；眼睛按钮切换，每次显示重新计时。加入者默认隐藏，切后台立即隐藏；隐藏数字从文字与无障碍节点移除。
- 锁屏面板采用深色渐变、分段模式选择、中央圆形对讲区和静音卡片；加入按压缩放、发言光环、轻震反馈。短屏可滚动，宽屏限制面板宽度，适配系统栏。
- 圆环外按下不发送；按住后滑出停止，滑回不恢复；多指不会接管对讲，切模式、收起、失焦和暂停均取消按住状态。待机不运行持续动画。
- 与 dev.3 使用相同协议和签名，支持覆盖升级。本轮没有执行 Android 原生界面截图或两品牌真机验证，界面观感和厂商锁屏表现需安装后确认。

## dev.3 已保留功能

- 中文名改为 **曙光之声**，英文名 DawnMesh；覆盖启动器、主标题、关于、麦克风权限提示、通知与锁屏通话面板。包 ID 和独立签名保留，可覆盖升级。
- 邀请码改为 6 位数字，支持前导零；PAKE 入房验证后下发随机房间密钥，不直接将低熵短码作为 AES 密钥。新旧邀请码协议不互通，两台都需更新 dev.3。
- 建房按钮统一为创建 Wi-Fi/蓝牙房间。蓝牙房可在按住对讲与自动通话之间切换，每台设备独立选择；自动模式采用本地声音门限、100 ms 前置缓冲和 400 ms 尾音。
- microphone 前台服务持有 CPU 部分唤醒锁；Wi-Fi 房额外持有 Wi-Fi 锁。新增不导出的锁屏控制面板，不解锁手机，不展示房间秘密。
- 原生锁屏控件通过平台通道同步模式/静音/PTT。松手、取消触控、切走、再次熄屏均释放 PTT；退房停止采集和服务并释放锁。新增启动中退房防止重新开麦的检查。

## 新增回归覆盖

1. BLE 模式开始扫描、渲染发现的房间、按广播 PSM 建链，并在正确邀请码认证后进入；广播失败不进入虚假房间。
2. 加密封装失败不发送明文；加密会话拒绝明文 join 和嵌套信封/握手。
3. 邀请码随机性与严格格式、错误密钥、密文篡改、并发重复包、超出重放窗口的旧包。
4. 新客户端未收到匹配本次令牌的 admission 时，拒绝录制的旧名单。
5. **真实回环 TCP**：房主和两位成员的加密入房、双向聊天、迟到成员历史同步、320 字节消息边界与音频帧转发；错误邀请码客户端无法入房；验证后的会话数据均为 sealed；PAKE 握手点和密钥确认消息公开交换。
6. 旧底层协议路径拒绝 TCP 客户端注入房主控制命令和 UDP 控制帧。
7. Kotlin 有界发送队列的有序写入/flush、满队列断开、写阻塞超时。
8. C++ 编码拒绝空指针与超长载荷；截断帧拒绝解码；环形缓冲满/读写回绕。
9. RFC 9382 附录 B SPAKE2 标准向量、错误码/非曲线点拒绝、确认前不发组密钥、相同短码的不同房间密钥不同、在线猜码限速。
10. 语音门限与首尾音、模式切换不重启采集、静音/退房停止发送、小屏切换布局、锁屏控制平台通道同步、音频初始化过程中退房不再开麦。

11. 邀请码首次及重复显示超时、主动隐藏、后台隐藏、房间切换、销毁取消计时器、紧凑屏大字体，以及实际建房后的邀请码位置与显示切换。
12. Kotlin 对讲手势：滑出后不复活、多指隔离、重复取消只释放一次、禁用状态和圆环外按下不发送。
13. 昵称存取平台通道与 Wi-Fi Direct 凭据确定性/格式/差异性，Wi-Fi 模式切换与紧凑屏布局。
14. 原始 BLE 广播多厂商段解析、段顺序变化、仅主包、非法 UTF-8/元数据与 Unicode 截断。
15. 音频缓冲覆盖可靠流非音频序号间隔、欠载重缓冲、短句截止时间、蓝牙突发、上限丢旧及非可靠序号回绕。
16. 新模式切换器覆盖 Wi-Fi/蓝牙交互、360×640 矮屏进出房转场、常见直板屏与 2 倍字号布局。
17. 调试日志默认关闭、启停与关闭清空、私有设置持久化，以及页面显示、级别筛选和清空交互。

## 按约定由你执行

你已明确真机验证自行完成，本次不等待 USB 设备。未执行 Xiaomi 15 / OnePlus Android 16 与 Redmi K50 Ultra Android 15 的射频发现、Wi-Fi Direct 系统确认、实际语音/麦克风路由、后台冻结、6 人容量、重复进退房压力和 16 KB 设备运行验收。操作表见 [ANDROID16_BLUETOOTH.md](ANDROID16_BLUETOOTH.md)。

源码审查未发现明确恶意后门证据，不等于证明所有依赖无漏洞或手机原 APK 与源码完全一致。仍存在组密钥成员互信、未认证物理连接占位、TCP 背压与缺少前向保密等边界，见 [安全审查](SECURITY_REVIEW.md)。
