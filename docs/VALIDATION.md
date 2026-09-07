# 验证记录（2026-09-06）

## 已执行

- Flutter **3.29.3 / Dart 3.7.2**（临时工具路径 `/tmp/dawnmesh-flutter`，不是已长期配置的系统 SDK）。
- `flutter analyze --no-pub`：**No issues found**。
- `flutter test --no-pub --concurrency=1 --reporter expanded`：**133 项通过，0 失败**。
- C++ `clang++ -std=c++17 -Wall -Wextra -fsanitize=address,undefined ...`：测试退出码 0，无 sanitizer 报错。
- Android XML 全部可解析；Gradle wrapper 只有一个 distributionUrl，包含 Gradle 官方 SHA-256。
- 原 sunsetripple 的 `git status --short` 为空；原工程未修改。

日志：[静态分析](validation/flutter-analyze.txt)、[Flutter 测试](validation/flutter-tests.txt)。日志中的地址/昵称为回环测试和测试样例。

新增回归覆盖：

1. 选择蓝牙模式会扫描、渲染广播中的房间、使用广播给出的 PSM 连接。
2. BLE 广播失败不进入房间。
3. 超出安全信封上限的载荷不会回退明文发送。
4. 配置加密器后拒绝明文 join，接受有效密封 join。
5. TCP 客户端不能注入名单/迁移/快照/聊天历史；UDP 不接受控制帧。
6. C++ 编码拒绝空载荷指针和超长载荷；截断输入拒绝解码；环形缓冲满/读写回绕。

原进退房测试的等待方式改为等待可见状态，同时驱动 Flutter 模拟时钟和真实 socket/平台通道事件循环；保留原来的进退房、标题/按钮状态及逐帧无溢出断言。会话销毁释放传输资源，并防止退房期间重新打开麦克风。

## 尚未执行

- **未执行 Android Gradle/Kotlin 编译、Android Lint 或生成 APK**：本机没有 Android SDK/NDK/CMake 工具链和可用的 JDK 17 构建环境。测试准备只临时下载了 Flutter/Dart。检测到 DBeaver 自带 Java 25 runtime，但未拿它代替所需 JDK 17。
- 未对 Android 蓝牙/权限 API 真机执行：Flutter 的平台通道回归使用 mock，不等于验证 Android 广播回调、扫描响应和 L2CAP CoC。
- 未验证 Xiaomi / OnePlus 的 Android 16、背景冻结/省电策略、实际语音路由、6 人容量、重复进退房压力、16 KB 最终 APK 对齐。
- 未逆向现有 APK，也未证明用户已安装 APK 与审查提交相同。
- 未完成依赖漏洞库扫描、完整成员认证和默认加密。

因此当前交付是经 Dart/Flutter 自动化测试和部分本机 C++ 检查的 Android 开发工程，**不是已通过两品牌验收的 APK**。安装 README 中的 Android 构建依赖后，再按 [双机复测表](ANDROID16_BLUETOOTH.md) 验证。
