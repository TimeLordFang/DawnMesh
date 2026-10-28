# 更新记录

本轮候选：[1.2.4-rc.2](RELEASE_1.2.4.md)。最近正式版：[1.2.3](RELEASE_1.2.3.md)，统一晨光主题、设置入口、图标资源与默认 iOS 签名配置。

近场 v3 要求全体参与者使用 1.2.0 或更新客户端；公网 LiveKit 房沿用原通路。Wi-Fi/融合房协议上限 16 人，蓝牙房 6 人，不等于真机无线容量已验收。可选语音留言和离线转交默认关闭；Aware 需要设备、系统和签名能力。

## 历史摘要

完整旧版说明链接到当时的 Git 标签，避免把旧测试数字或环境结论当作当前结果。

| 版本 | 主要变化 |
| --- | --- |
| [1.2.2](https://github.com/TimeLordFang/DawnMesh/blob/v1.2.2/docs/RELEASE_1.2.2.md) | 认证报文丢失后的有界补发、旧握手重放及换钥缓存清理。 |
| [1.2.1](https://github.com/TimeLordFang/DawnMesh/blob/v1.2.1/docs/RELEASE_1.2.1.md) | 繁忙融合房握手、并发连接共享、超时取消和加密队列调度。 |
| [1.2.0](https://github.com/TimeLordFang/DawnMesh/blob/v1.2.0/docs/RELEASE_1.2.0.md) | 两端统一版本；独立成员身份、退出换钥、可靠文字、GATT 文字备用和可选离线能力。 |
| [1.1.9](https://github.com/TimeLordFang/DawnMesh/blob/v1.1.9/docs/RELEASE_1.1.9.md) | 融合房一次输入邀请码继续入房、备用入口恢复，移除 Nearby 实验。 |
| [1.1.7](https://github.com/TimeLordFang/DawnMesh/blob/v1.1.7/docs/RELEASE_1.1.7.md) | Android/iOS 同网 Bonjour/NSD 双向发现。 |
| [1.1.6](https://github.com/TimeLordFang/DawnMesh/blob/v1.1.6/docs/RELEASE_1.1.6.md) | 无广播路由时的异步 UDP 错误恢复。 |
| [1.1.5](https://github.com/TimeLordFang/DawnMesh/blob/v1.1.5/docs/RELEASE_1.1.5.md) | 完整蓝牙房名与换房缓存恢复。 |
| [1.1.4](https://github.com/TimeLordFang/DawnMesh/blob/v1.1.4/docs/RELEASE_1.1.4.md) | 跨平台 GATT 房间发现及统一图标。 |
| [1.1.3](https://github.com/TimeLordFang/DawnMesh/blob/v1.1.3/docs/RELEASE_1.1.3.md) | 原生模型边界、资源及构建告警治理。 |
| [1.1.2](https://github.com/TimeLordFang/DawnMesh/blob/v1.1.2/docs/RELEASE_1.1.2.md) | 重连防重放、前台服务与音频焦点生命周期。 |
| [1.1.1](https://github.com/TimeLordFang/DawnMesh/blob/v1.1.1/docs/RELEASE_1.1.1.md) | 稳定依赖和工具链更新。 |
| [1.1.0](https://github.com/TimeLordFang/DawnMesh/blob/v1.1.0/docs/RELEASE_1.1.0.md) | Wi-Fi/融合房 16 人、长名单分片、离线融合及 30 分钟恢复。 |
| [1.0.4](https://github.com/TimeLordFang/DawnMesh/blob/v1.0.4/docs/RELEASE_1.0.4.md) | 公网发言权限恢复、房主交接和持续窄频噪声抑制。 |
| [1.0.3](https://github.com/TimeLordFang/DawnMesh/blob/v1.0.3/docs/RELEASE_1.0.3.md) | 统一四位邀请码，公网服务端入房验证与密钥信封，媒体/管理在线状态分离。 |
| [1.0.2](https://github.com/TimeLordFang/DawnMesh/blob/v1.0.2/docs/RELEASE_1.0.2.md) | 共用邀请码输入、成员在线状态与掉线播报。 |
| [1.0.1](https://github.com/TimeLordFang/DawnMesh/blob/v1.0.1/docs/RELEASE_1.0.1.md) | 初期稳定性与音频改进。 |

当前自动化见 [验证基线](VALIDATION.md)，设备步骤见 [手动验收](MANUAL_ACCEPTANCE.md)，安全边界见 [安全模型](SECURITY_REVIEW.md)。
