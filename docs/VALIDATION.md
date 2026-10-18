# 验证基线与设备验收

整理日期：2026-10-18。以下数字来自对应正式版已有验证记录，本次文档整理没有重新运行产品测试或构建。旧开发版的逐次流水、构建日志和临时工作区说明不再作为当前验收依据。

## 正式版验证摘要

| Android 版本 | 已记录的验证 | 对应说明 |
| --- | --- | --- |
| 1.1.7 | Android Flutter 304 项，JVM 45 项、Lint、静态分析与 Release 构建通过；iOS Flutter 323 项。两端各 1 项真实中继测试按配置跳过 | [同网双向发现](RELEASE_1.1.7.md) |
| 1.1.6 | Android Flutter 298 项、iOS 317 项；JVM 41 项/Swift 190 项沿用未改动原生部分的前版结果；两端各 1 项中继测试跳过 | [异步 UDP 错误](RELEASE_1.1.6.md) |
| 1.1.5 | Android Flutter 297 项、JVM 41 项、Lint；iOS Flutter 316 项、Swift 190 项；两端各 1 项中继测试跳过；Release 构建通过 | [蓝牙完整房名](RELEASE_1.1.5.md) |
| 1.1.4 | Android Flutter 295 项、JVM 39 项、Lint；iOS Flutter 302 项含真实 Go 中继、Swift 186 项和 TCP 回环；两端 Release 构建通过 | [移动端互通](RELEASE_1.1.4.md) |
| 1.1.3 | Android Flutter 295 项、JVM 37 项、应用 Lint 零问题、原生 sanitizer、Debug APK 与 ELF 对齐 | [构建与资源治理](RELEASE_1.1.3.md) |
| 1.1.2 | Android 295 项 Dart（含真实 Go 中继）、JVM 37 项、Lint、原生 sanitizer 与 Debug 构建 | [重连安全与生命周期](RELEASE_1.1.2.md) |
| 1.1.1 | Flutter 295 项（默认跳过 1 项真实中继）、JVM 35 项、Lint、原生 sanitizer、跨端 Opus 与 Debug 构建 | [依赖与工具链明细](RELEASE_1.1.1.md) |

各行属于各版本的历史结果，不能相加或当成当前代码刚刚通过的测试数。1.0.x 的验证与升级条件保留在相应 [正式版说明](README.md#正式版发布说明)。

## 1.1.0 / Server 0.3.0 基线（2026-10-08）

- Wi-Fi/融合房原 6 人限制来自应用的成员号、连接数、名单及签名校验；现统一支持 16 人（含房主）。蓝牙房保持 6 人。通过真实回环套接字验证 16 人加密入房、长昵称完整名单、语音转发/去重、满房身份恢复和 17 人拒绝。
- 296 项 Flutter 全量回归通过，无跳过，包含与本机 Go 服务端的实际跨端用例。全量 Dart 静态分析通过；原生协议/环形缓冲 ASan/UBSan 检查通过。
- Android 35 项单元测试及 Release Lint 通过。签名 APK 版本 1.1.0 / 51，签名、ZIP 16 KB 和全部 64 位 ELF 16 KB 对齐通过。SHA-256：`eea05193a4fd7979ca221f6bec0dd26bf7498d945fdd24bb03ebfbd0ae365bfa`。
- Server 0.3.0：全量 Go 竞态测试、vet、go mod tidy 一致性检查通过；TypeScript/Vite 构建、4 项网页单测、加密向量及 17 项 Chrome 浏览器回归通过，Linux amd64/arm64 编译通过。
- 新增分片乱序组装、重复/冲突/过期/非法消息拒绝、16 人交接长载荷及成员环路单点失联连通性测试。服务端验证 16 人最大签名状态、17 人拒绝及 16 条真实中继连接。
- 审阅并统一容量常量、UTF-8 编码和房主命令检查，拒绝半份名单；减少全互连重复转发，调整限流和去重预算。没有提高单帧 512 字节上限，也未改动蓝牙驱动容量。
- 实际 Wi-Fi Direct 群组容量受系统/驱动限制；未进行 16 台不同品牌手机的射频、同时讲话、系统休眠及道路测试。更新全体客户端和服务端后，仍需真机验收这些设备能力。
- 保留 SDK/Gradle/npm/Go 依赖缓存；发布仅推送 GitHub 主分支与正式标签，不追踪 Actions、不自动部署服务器。


## 本地复核入口

在仓库根目录执行：

```sh
./scripts/check.sh
./scripts/gradle.sh :app:testDebugUnitTest :app:lintDebug
```

`check.sh` 执行依赖解析、Dart 静态检查、串行 Flutter 测试及可用时的原生 sanitizer。真实 Go 中继集成需要按测试配置提供 `DAWNMESH_FUSION_TEST_URL`；未提供时会跳过，不能记为已验收。多个移动端仓库的网络回归应串行运行，避免固定端口冲突。

签名、ZIP/ELF 16 KiB 对齐与产物版本按 [发布工作流](../.github/workflows/release.yml) 检查；历史通过的 APK 不替代新产物校验。

## 尚需设备或部署验收

| 场景 | 检查内容 |
| --- | --- |
| Android / iOS 同网发现 | 两端前台并授权本地网络，互换房主，检查中文/emoji 房名、邀请码、双向语音、消息和退出；覆盖访客隔离/mDNS 过滤 |
| 蓝牙与耳机 | 互换房主，长房名/GATT、路由切换、距离断连、重新扫描与 PSM 更新、锁屏恢复；详见 [蓝牙排查](ANDROID16_BLUETOOTH.md) |
| PTT 恢复 | 成员按下再松开，房主断网、恢复、退出再加入；未按键成员始终不发声，再次按下与自动通话正常 |
| 音频生命周期 | 来电/导航失焦、后台限制、服务失败、TalkBack 操作、退房取消采集；恢复不绕过静音或禁麦 |
| 融合与容量 | 多网关、房主不可达、30 分钟恢复、16 台不同品牌手机、P2P/蜂窝并发、无线群组消失后的备用链路 |
| 声学与部署 | 真实头盔风噪、多人讲话、端到端延迟；实际 nginx/Docker 来源地址、反向代理与媒体连通性 |

共同 Wi-Fi/热点下的跨平台发现不等于无共同网络的 iOS ↔ Android 自动直连。回环、模拟通道和编译成功不能替代射频、道路声学或真实部署结果。
