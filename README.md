# 曙光之声 · DawnMesh（Android 独立开发版）

从 SunsetRipple 当前 Flutter 主线复制的 Android 工程，包含 Kotlin 宿主、Dart 界面与会话逻辑、C++ 核心及测试。原作者 Apache-2.0 许可和版权保留，来源提交见 [UPSTREAM.md](docs/UPSTREAM.md)。原目录不作修改。

**所有应用建房/入房入口默认启用邀请码加密（AES-256-GCM）。** 每次建房生成随机 **6 位数字邀请码**（可包含前导零），当面口述即可。短码通过 PAKE 验证后下发独立随机房间密钥，语音、聊天与成员控制消息使用 AES-GCM 加密。邀请码代表可信小组的访问权，不能防范持码成员冒名；仍需你完成真机验证。

- 安装包 ID：`dev.dawnmesh.intercom`，可以与原版并存。
- 版本：`0.1.0-dev.8+8`。
- Kotlin namespace、Dart 包、平台通道、原生库和日志 tag 已统一为 DawnMesh 标识。
- 中文名：曙光之声；英文名：DawnMesh。原作者许可与来源说明保留。
- 不包含旧版根目录 `app/`（纯 Kotlin alpha.7）及 iOS、桌面、Web、HarmonyOS。
- 更新检查不再访问原作者 GitHub；仅通过自己签名的 APK 更新。

## 本机直接构建与使用

本次已在项目 `.tools/` 安装 Flutter、JDK 17、Android SDK/NDK/CMake；无需再次配置全局 PATH：

```sh
cd /Users/judoon/workspace/DawnMesh
./scripts/check.sh
./scripts/gradle.sh :app:testDebugUnitTest :app:lintDebug
./scripts/flutter.sh build apk --release
```

工具链约占 7.6 GB，不提交 Git。当前电脑的发布签名位于 `android/keystore/dawnmesh.jks`，口令保存在 `android/key.properties`，两者均设为仅本人可读写并忽略提交。**请自行安全备份这两个文件；后续覆盖升级必须保留同一签名。** 本次生成的是 DawnMesh 独立签名，与原版无关。

两台手机安装同一个 DawnMesh APK。在应用内创建房间后，聊天室信息下方直接显示 6 位数字，10 秒后自动隐藏。点击小眼睛可随时显示或隐藏，每次显示 10 秒后再次隐藏；切到后台立即隐藏。将数字口述给另一台手机；对方搜索房间、点“加入房间”并输入数字，无需联网或发送文本。错误邀请码不能进入房间。邀请码只在当前会话内存中保存；请仅分享给信任的人。加入者默认隐藏邀请码，可点击眼睛查看。

当前加密 Wi-Fi 房的语音与控制都走 TCP，不使用旧版未认证的 UDP 语音端点登记。弱网丢包可能增加语音延迟。**本版房主退出后房间结束，不支持房主自动迁移**。单条加密聊天限制为 320 UTF-8 字节，保证多人昵称和历史同步的信封不超过传输帧上限。**dev.8 已统一发现标识、平台通道和加密上下文，不能与 dev.7 及更早版本互通；参与房间的手机必须全部更新到 dev.8。**

昵称保存在 Android 应用私有设置中，关闭并重新打开应用后自动恢复；清除应用数据或卸载会删除。Wi-Fi 和蓝牙房现在都可在“按住对讲”与“自动通话”之间切换。Android 10 及以上的 Wi-Fi Direct 使用邀请码派生的临时 SSID/口令连接，避免房主侧旧式 WPS 确认；部分厂商若额外强制系统确认，应用没有权限代替用户操作。普通同一局域网房仍直接通过 TCP 加入。

## 发言模式与锁屏使用

创建入口为“创建 Wi-Fi 房间”/“创建蓝牙房间”。进入任一房间后，都可随时切换本机的发言模式，不必退房重连：

- **按住对讲**：按住发送，松开收听。切换模式、静音或应用失去前台焦点时释放按住状态。
- **自动通话**：无需按键，检测到声音后发送，静音环境暂停发送。保留约 100 ms 前置音频和 400 ms 尾音。它是本地响度/噪声门限检测，不是语义识别人声；环境噪声也可能触发。Wi-Fi 自动通话使用相同声音触发逻辑。

每台手机独立选择自己的发言方式，两种方式均可接收其他人的声音。dev.6 将模式选择改为带图标、状态说明和滑动高亮的胶囊控件，自动适配矮屏与大字号。蓝牙保持 16 kbps 音频码率；dev.5 增加 120 ms 初始缓冲、断流重新预缓冲、可靠链路音频序列处理和旧机编码降载，实际延迟和音质仍需在目标设备复测。

**先在应用前台进入房间，允许麦克风、附近设备和通知，再锁屏。** 自动模式继续收发。按住模式下唤醒屏幕后，点击常驻的“曙光之声 · 房间通话”通知进入锁屏通话面板，使用中央圆形按钮按住说话、松手停止。面板采用深色渐变、图标化胶囊模式切换和独立静音卡片，选中项带色彩、缩放与轻震反馈；滑出圆环即停止发送，滑回不会重新开麦。面板不会解锁手机，不显示邀请码或聊天记录。再次熄屏或切走会释放对讲按钮。

通话期间运行 microphone 前台服务并持有 CPU 部分唤醒锁，Wi-Fi 房另持有 Wi-Fi 锁；退房释放。Xiaomi/OnePlus 的锁屏通知隐藏或电池冻结设置仍可能影响使用：请允许锁屏显示该通话通知，并按系统提供的选项允许应用在后台运行。**已完成代码和构建检查，没有把未执行的两品牌锁屏实测描述为通过。**

## 手机内调试日志

主页和房间页右上角的终端图标可打开“调试日志”。记录默认关闭；打开后会记住开关状态，并同时收集 Dart 会话、Flutter 未捕获异常及 Android 原生音频、BLE、Wi-Fi Direct 日志。日志在一块连续的等宽控制台中按时间从上到下紧凑显示，支持按级别筛选、关键字搜索、复制、清空和刷新系统快照，最多保留最近 400 条。

系统快照包含设备型号、Android/API/安全补丁、ABI、CPU/内存、低内存状态、电池优化、音频采样参数与路由设备、当前网络、Wi-Fi/BLE 硬件能力和关键权限。Android 不允许普通应用读取完整系统 Logcat，因此其他应用、内核和受保护系统服务的日志无法展示。日志内容只保存在当前进程内存中，关闭记录会立即清空，重启应用也不会恢复旧内容；复制时会自动隐藏 IP、MAC 和长令牌。旧红米语音断续复测时，可重点查看 `DawnAudio` 的编码超时、音频缓冲和 `trackUnderruns`，以及 `DawnBle` 的链路异常。

## 在其他电脑安装构建依赖

首次复现建议使用以下固定组合，避免直接装最新版后混入工具链迁移问题：

| 依赖 | 版本 / 用途 |
| --- | --- |
| Flutter | **3.29.3**（随带 Dart 3.7.2），与原仓库 CI 的 3.29.x 对齐 |
| JDK | **17**，运行 Gradle；只安装 JRE 不够 |
| Android SDK Platform | **35**，本项目固定 compileSdk/targetSdk 35；可在 Android 16 运行 |
| Android SDK Build-Tools | **35.0.0**，另保留 AGP 自动要求的 **34.0.0** |
| Command-line Tools | SDK Manager 安装与许可证管理 |
| Platform-Tools | 包含 adb，用于安装、日志和连接真机 |
| NDK Side by side | **27.0.12077973**，构建 native/ 下 C++ |
| CMake | **3.22.1** |
| Git | 获取 Flutter 和管理源码 |

Gradle 8.12、AGP 8.7.0、Kotlin 1.8.22 由项目/Flutter 构建工具解析，不需要全局安装 Gradle、Kotlin。无需 Node.js、Python 或 iOS 的完整 Xcode 来构建 APK；macOS 获取 Git/本机 C++ 检查可安装 Xcode Command Line Tools。Android Studio 可用于安装和管理 SDK，但不是强制依赖。Apple Silicon Mac 使用此 Flutter 版本编译 release 还需要 Rosetta（`softwareupdate --install-rosetta --agree-to-license`），因为其 Android AOT 编译器为 Intel 架构。

安装 Flutter 后将 `flutter/bin` 加入 PATH。Android Studio 中打开 SDK Manager，安装表中的组件；或配置好 `sdkmanager` 后执行：

```sh
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "build-tools;34.0.0" "ndk;27.0.12077973" "cmake;3.22.1"
flutter doctor --android-licenses
flutter doctor -v
```

如果 Android Studio 自带 Java 版本与 JDK 17 不同，可用 `flutter config --jdk-dir=/你的/JDK17/Contents/Home` 指定。`android/local.properties` 由 Flutter 本机生成，不应提交。

在 **DawnMesh 根目录**执行（不是 android/ 下，也不是原仓库旧 `app/` 下）：

```sh
flutter pub get
flutter analyze
# 回环网络测试共享端口 8988/8989，串行避免争用
flutter test --concurrency=1
flutter build apk --debug
```

调试 APK：`build/app/outputs/flutter-apk/app-debug.apk`。两台手机都安装同一种构建 APK，再在应用内选择蓝牙对讲、扫描/创建并使用邀请码；不用先在系统蓝牙设置里配对。

```sh
adb devices
adb -s 手机序列号 install -r build/app/outputs/flutter-apk/app-debug.apk
```

发布包必须使用自己的密钥。可交互生成（口令不写在命令行中）：

```sh
mkdir -p android/keystore
keytool -genkeypair -v -keystore android/keystore/dawnmesh.jks -alias dawnmesh -keyalg RSA -keysize 3072 -validity 10000
cp android/key.properties.example android/key.properties
# 编辑 key.properties 的口令；妥善备份 keystore，后续升级必须使用同一签名
flutter build apk --release
```

发布 APK：`build/app/outputs/flutter-apk/app-release.apk`。开发版与发布版签名不同，直接覆盖可能失败；可先卸载调试版，再装自己的发布版。缺少签名配置会阻止 release 打包，不会再自动退回 debug 签名。

默认使用官方 Maven / pub.dev。若网络无法连接，可自行选择镜像：`DAWNMESH_USE_MIRROR=1 flutter build apk --debug` 为 Gradle 启用原有阿里云镜像；Dart 的源由 `PUB_HOSTED_URL` 控制。镜像是另一条供应链，不能代替构件校验；仓库未完成完整依赖锁定、SBOM 或 CVE 审计。

NDK r27 已开启 `ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES`。最终 APK 的 ELF 段与 ZIP 对齐检查结果见验证记录；对齐检查不能替代 Android 16 真机运行测试。

## 修复与验证

见 [安全审查](docs/SECURITY_REVIEW.md)、[蓝牙复测步骤](docs/ANDROID16_BLUETOOTH.md)、[验证记录](docs/VALIDATION.md)。

官方资料：[Flutter Android 环境](https://docs.flutter.dev/platform-integration/android/setup)、[AGP 8.7 兼容表](https://developer.android.com/build/releases/agp-8-7-0-release-notes)、[Android 蓝牙权限](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)、[16 KB 页面](https://developer.android.com/guide/practices/page-sizes)。
