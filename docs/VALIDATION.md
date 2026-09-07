# 验证记录（2026-09-07）

## 本次交付

- 发布 APK：`artifacts/DawnMesh-0.1.0-dev.2-release.apk`，**49,297,624 字节**。
- 包 ID `dev.dawnmesh.intercom`，版本 `0.1.0-dev.2` / versionCode **2**，minSdk **26**、targetSdk **35**。BLE L2CAP 对讲需要 Android **10 / API 29** 以上。
- APK SHA-256：`fdb35830f846e7eb77c99a6b8c33a277a4a9a32b4043e11ff3100288f95a2877`。
- 独立 RSA 3072 位签名证书 SHA-256：`58807a8354fe95537c7b818a29cc694d7f43c9480f1a60bd3fba7320bd285446`。
- APK Signature Scheme v2 校验通过；没有使用原作者或 Android debug 签名。release Manifest 未开启 debuggable，allowBackup=false。
- 调试 APK 也从最终代码重新构建：`build/app/outputs/flutter-apk/app-debug.apk`；优先将上述 release 安装到两台手机，避免混用签名。

## 已执行

工具链位于本项目 `.tools/`：Flutter **3.29.3 / Dart 3.7.2**、Temurin **JDK 17.0.20.1**、Android SDK Platform **35**、Build-Tools **35.0.0 / 34.0.0**、NDK **27.0.12077973**、CMake **3.22.1**、Gradle **8.12**。Apple Silicon 主机补装 Rosetta 后，Flutter Intel AOT 编译器可正常执行。

| 检查 | 结果 |
| --- | --- |
| `./scripts/check.sh` | 退出码 0，包含以下 Dart/Flutter 与 C++ 检查 |
| Flutter analyze | **No issues found** |
| Flutter 全量测试（串行） | **138 项通过，0 失败** |
| C++ ASan / UBSan | 帧边界、环形缓冲测试通过，无 sanitizer 报错 |
| `:app:testDebugUnitTest` | Kotlin **3 项通过，0 失败** |
| `:app:lintDebug` | 成功；**0 errors、12 warnings**（旧版 API 冗余判断、备份配置建议、图标资源等），没有关闭 Lint 或加入忽略基线 |
| Flutter debug / release APK | 两种构建均成功；release 使用独立本地密钥 |
| `apksigner verify --verbose --print-certs` | 通过，1 个签名者 |
| `zipalign -c -P 16 -v 4` | Verification successful |
| ELF PT_LOAD 对齐 | 全部 **6 个 arm64-v8a / x86_64** 库均 ≥ 16384；包括 Flutter 引擎、Dart AOT、本项目 C++ |
| 32 位 ABI | armeabi-v7a 的本项目 C++ 为 4096 对齐，单独记录；不是 Android 64 位 16 KB 对齐失败 |
| 原 sunsetripple 目录 | `git status --short` 为空，未修改原工程 |

按 [Android 官方 16 KB 检查范围](https://developer.android.com/guide/practices/page-sizes#elf-alignment)核对 64 位 ELF 与 ZIP 对齐。额外记录 GNU_RELRO：Flutter 引擎与本项目 C++ 具备该段；Flutter 3.29.3 生成的 `libapp.so` 没有该段。未对 Flutter 预编译运行时/AOT 生成器做进一步二进制加固审计。以上均为静态包检查，**没有据此声称已在 16 KB 手机运行通过**。

日志：[静态分析](validation/flutter-analyze.txt)、[Flutter 测试](validation/flutter-tests.txt)、[完整代码检查](validation/final-checks.txt)、[Android 构建检查](validation/android-checks.txt)、[Android Lint](validation/android-lint.txt)、[发布构建](validation/release-build.txt)、[APK 校验](validation/apk-verification.txt)。测试日志中的地址、昵称和故意触发的认证失败均为测试样例。

## 新增回归覆盖

1. BLE 模式开始扫描、渲染发现的房间、按广播 PSM 建链，并在正确邀请码认证后进入；广播失败不进入虚假房间。
2. 加密封装失败不发送明文；加密会话拒绝明文 join 和嵌套信封/握手。
3. 邀请码随机性与严格格式、错误密钥、密文篡改、并发重复包、超出重放窗口的旧包。
4. 新客户端未收到匹配本次令牌的 admission 时，拒绝录制的旧名单。
5. **真实回环 TCP**：房主和两位成员的加密入房、双向聊天、迟到成员历史同步、320 字节消息边界与音频帧转发；错误邀请码客户端无法入房；线上帧均为 sealed。
6. 旧底层协议路径拒绝 TCP 客户端注入房主控制命令和 UDP 控制帧。
7. Kotlin 有界发送队列的有序写入/flush、满队列断开、写阻塞超时。
8. C++ 编码拒绝空指针与超长载荷；截断帧拒绝解码；环形缓冲满/读写回绕。

## 按约定由你执行

你已明确真机验证自行完成，本次不等待 USB 设备。未执行 Xiaomi / OnePlus Android 16 的射频发现、实际语音/麦克风路由、后台冻结、6 人容量、重复进退房压力和 16 KB 设备运行验收。操作表见 [ANDROID16_BLUETOOTH.md](ANDROID16_BLUETOOTH.md)。

源码审查未发现明确恶意后门证据，不等于证明所有依赖无漏洞或手机原 APK 与源码完全一致。仍存在组密钥成员互信、未认证物理连接占位、TCP 背压与缺少前向保密等边界，见 [安全审查](SECURITY_REVIEW.md)。
