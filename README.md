# 曙光之声 · DawnMesh

近场离线通信与自部署公网语音对讲。当前源码 **1.2.4+65**，候选标签 **v1.2.4-rc.1**；本轮统一建房及其他弹窗按钮，并整理文档。详见 [候选说明](docs/RELEASE_1.2.4.md) 与 [更新记录](docs/CHANGELOG.md)。

## 通信方式

| 房型 | 能力与边界 |
| --- | --- |
| Wi-Fi | 同一 Wi-Fi/热点下跨平台通信，协议上限 16 人。Android 可用 Wi-Fi Direct，iOS 可用苹果点对点 Wi-Fi，两种原生无线协议不能直接互联。 |
| 蓝牙 | L2CAP 语音优先，必要时使用 GATT 仅文字备用；协议上限 6 人，首次发现保持房主前台。 |
| 融合 | 协议上限 16 人，可离线建房并经已入房成员连接；联网成员可桥接同一自部署服务器，公网断开时保留已有本地连接。 |
| 公网 | 使用所选 HTTPS 服务器及 LiveKit，默认 25 人并由服务器配置控制；支持 Android、iOS 和网页同房。 |

支持按住对讲/自动发言、文字与图片、降噪、房主管理和有界断线恢复。可靠文字、独立成员签名及退出换钥要求近场全体成员使用 1.2.0 或更新客户端。语音留言、离线密封转交默认关闭；Wi-Fi Aware 为需要设备、系统、系统配对和签名能力的可选加速，不能据编译成功宣称无线互通已验收。

## 下载与构建

[Android Releases](https://github.com/TimeLordFang/DawnMesh/releases) 提供签名 APK、Play AAB 与 SHA-256；稳定版见 [Latest](https://github.com/TimeLordFang/DawnMesh/releases/latest)，候选包在 Prerelease 中。AAB 供 Play 分发，不能直接点击安装。

```sh
./scripts/flutter.sh pub get --enforce-lockfile
./scripts/flutter.sh build apk --debug
```

Android 8.0+；BLE L2CAP 语音需要 Android 10+。构建依赖见 [开发指南](docs/DEVELOPMENT.md)，JKS/CI 签名见 [发布流程](docs/RELEASING.md)，上架见 [Google Play](docs/GOOGLE_PLAY.md)。缺少 release 签名时构建失败，不回退 debug 签名。

## 安全、数据与验收

无预置公网服务和遥测；公网使用用户所选服务器，主动检查更新会连接对应 GitHub 仓库。管理员收听默认关闭，仅建房时授权的房间允许托管相应密钥并显示监听状态。

四位邀请码适合临时可信小组，不等于高熵密码。近场 v3 验证独立成员签名并在成员变化时换钥；合法参与者仍能读取、录制或转发共享内容。普通聊天和可选语音留言在会话内存中；主动开启离线转交后会持久化密文与联系人。安全存储、元数据及密码学边界见 [安全模型](docs/SECURITY_REVIEW.md)。

自动化与发布证据见 [验证基线](docs/VALIDATION.md)。发现、真实无线容量、耳机共存、后台和锁屏需按 [手动清单](docs/MANUAL_ACCEPTANCE.md) 验收，不能由回环或未签名编译推断通过。

## 文档与来源

[完整文档入口](docs/README.md) · [发布与候选规则](docs/RELEASING.md) · [来源与第三方许可](docs/UPSTREAM.md)

本项目保留 [Apache-2.0](LICENSE) 与原作者版权；Opus、RNNoise 等第三方许可保留在各自源码中。服务端与网页位于独立的 DawnMeshServer 仓库，部署及升级以该仓库说明为准。
