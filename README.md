<p align="center">
  <img src="assets/branding/google-play-icon.png" width="144" height="144" alt="DawnMesh 应用 Logo">
</p>

# 曙光之声 · DawnMesh Android

**越过地平线，让声音相遇。**

[Android](https://github.com/TimeLordFang/DawnMesh) · [iOS](https://github.com/TimeLordFang/DawnMeshIOS) · [服务端与网页](https://github.com/TimeLordFang/DawnMeshServer)

DawnMesh（曙光之声）是一款面向附近同伴与远程小组的语音对讲应用。没有互联网时，可以通过 Wi-Fi、热点或蓝牙进行本地通话和聊天；需要跨网络交流时，连接自己部署的服务端即可使用公网房或融合中继。

支持按住对讲、自动发言、文字与图片、降噪、房主管理和有界断线恢复。语音留言与离线密封转交默认关闭；Wi-Fi Aware 是需要设备、系统、配对和签名能力的可选加速。近场参与者应使用兼容的同一代客户端。

## 项目与仓库

| 仓库 | 用途 |
| --- | --- |
| [DawnMesh · Android](https://github.com/TimeLordFang/DawnMesh) | Android 手机客户端，支持附近通信和自部署远程房间。 |
| [DawnMesh · iOS](https://github.com/TimeLordFang/DawnMeshIOS) | iPhone 客户端，与 Android 使用兼容的房间和加密协议。 |
| [DawnMesh Server · 服务端与网页](https://github.com/TimeLordFang/DawnMeshServer) | 公网房控制服务、融合房目录与加密中继，包含网页客户端和管理后台。 |

## 通信方式与部署依赖

| 使用方式 | 是否需要部署服务端 | 说明 |
| --- | --- | --- |
| 附近 Wi-Fi / 蓝牙房 | 不需要 | 手机间通过本地链路通信，不依赖互联网。Wi-Fi 协议上限 16 人，蓝牙房 6 人。 |
| 融合房：本地离线通信 | 不需要 | 处于同一 Wi-Fi、热点或支持的本地链路时，可以离线建房、加入和通话。 |
| 融合房：跨网络发现与远程中继 | 需要 DawnMesh Server | 已入房且联网的成员连接同一服务端，发布签名目录并中继密文；房主可不直接联网，远程参与仍需可用网关。 |
| 公网房 | 需要 DawnMesh Server 与 LiveKit | 控制服务处理房间与入房权限，LiveKit 承载实时语音；手机和网页需能访问相应服务与媒体端口。 |

应用不内置公共服务器。要使用公网房，或让融合房跨网络互通，请先按 [服务端部署说明](https://github.com/TimeLordFang/DawnMeshServer#使用容器镜像部署) 部署实例，再在客户端 **设置 → 服务器** 中填写 HTTPS 地址，并按实例配置提供访问凭证，让参与者选择同一实例。

公网部署需配置 HTTPS/WSS、反向代理与媒体端口。融合远程中继转发已加密的近场帧，不走公网房的 LiveKit 媒体通道；服务端的默认 Compose 同时部署控制服务与 LiveKit，以支持两种房型。已有本地融合连接不会因公网中断而结束。

Android Wi-Fi Direct 与苹果点对点 Wi-Fi 是不同无线协议，不能直接互联；跨平台本地通信可使用共同 Wi-Fi/热点或支持的蓝牙路径。设备无线容量、耳机共存和锁屏表现需真机验收，协议人数上限不代表硬件保证。

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

本项目保留 [Apache-2.0](LICENSE) 与原作者版权；Opus、RNNoise 等第三方许可保留在各自源码中。服务端与网页的部署、备份及升级见 [DawnMesh Server](https://github.com/TimeLordFang/DawnMeshServer)。
