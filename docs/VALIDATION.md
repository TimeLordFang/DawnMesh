# 当前验证基线与设备验收

更新日期：2026-10-28。当前候选为 **1.2.4+65**，最近正式版本为 **1.2.3+64**。本页保留本轮候选与最近正式版的验证结果和复核入口；历史测试数字、临时排查记录及旧环境结论通过对应 Git 标签和正式版发布说明追溯。

## 1.2.4-rc.2 / 构建 65

候选包含统一弹窗按钮、邀请码滚动和文档合并，未修改传输或加密协议。前置 UI 专项 Android 42 项、iOS 47 项通过，两端静态检查通过；包括 iOS 键盘出现后的三类建房流程。

本轮完整本地预检通过：Android 383 项、iOS 402 项 Flutter 回归，均包含真实本机 Go 中继；iOS 独立建房 3 项也通过。两端静态与原生检查、Android JVM/Lint 和签名 APK/AAB、iOS 普通与 Wi-Fi Aware 变体构建通过。包内版本核对为 `1.2.4 / 65`。

候选云端结果以 [Android 标签任务](https://github.com/TimeLordFang/DawnMesh/actions?query=branch%3Av1.2.4-rc.2)、[iOS 标签任务](https://github.com/TimeLordFang/DawnMeshIOS/actions?query=branch%3Av1.2.4-rc.2) 和各自 Release 附件为准，不沿用下方 1.2.3 的成功结果。

## 最近正式发布：1.2.3

| 平台 | 发布提交 | 正式任务 | 附件 |
| --- | --- | --- | --- |
| Android | `edae629` | [Actions 成功](https://github.com/TimeLordFang/DawnMesh/actions/runs/40641000790) | [签名 APK、AAB 与 SHA-256](https://github.com/TimeLordFang/DawnMesh/releases/tag/v1.2.3) |
| iOS | `01bdb84` | [Actions 成功](https://github.com/TimeLordFang/DawnMeshIOS/actions/runs/40641006240) | [普通版、Wi-Fi Aware 版未签名 App ZIP 与 SHA-256](https://github.com/TimeLordFang/DawnMeshIOS/releases/tag/v1.2.3) |

两端 main 和 `v1.2.3-rc.3` 共四个校验任务成功后，提升相同提交为正式 `v1.2.3`；正式标签任务也已成功。下载后的四个正式包均核对为版本 `1.2.3`、构建号 `64`，SHA-256 与随包文件一致，ZIP CRC 通过。

- Android APK 签名与本地发布证书一致；AAB 的 117 个载荷逐项签名校验通过。APK ZIP 16 KiB 对齐及 APK/AAB 的 64 位 ELF 对齐检查通过。
- iOS 两种包的 Wi-Fi Aware 开关分别为 `NO` 和 `YES`，无内嵌签名描述文件。未签名 App ZIP 需要适当签名后才能安装。
- 本地只保留一份对应平台的正式包及校验文件，位于 `artifacts/releases/1.2.3/`。不同构建的二进制哈希可能不同，应使用同一 Release 随包提供的校验文件。

## 自动化覆盖

- 本地 Android 383 项、iOS 402 项 Flutter 全量回归通过，均配置真实本机 Go 中继且无跳过；iOS 独立建房专项 3 项通过，两端静态检查通过。
- Android 原生 ASan/UBSan、JVM 与 Lint、签名 APK/AAB 发布预检通过；iOS 原生 C++、Swift、插件补丁及苹果点对点 TCP 回归通过，普通版与 Wi-Fi Aware 版设备目标构建通过。
- 融合回归覆盖确认丢失后的有界入房重试、16 人完整名单与密钥收敛、成员签名、语音可达性与去重，以及第 17 人拒绝。
- 16 人容量夹具显式驱动已入房会话的同步，避免把 16 台设备的周期维护集中到一个测试事件循环；连接重试仍使用真实计时器，心跳和重连由独立用例覆盖。该夹具不代表完成了 16 台真机同时通话验收。

未配置 `DAWNMESH_FUSION_TEST_URL` 时，真实 Go 中继集成项按测试条件跳过；不能把该情况下的测试成功记作中继验收。多个移动仓库的网络回归应串行执行，避免固定端口冲突。

## 本地复核入口

在对应仓库根目录执行；真实中继测试需先启动测试服务并设置上述环境变量。

```sh
./scripts/preflight-release.sh
```

Android 签名与打包见 [发布流程](RELEASING.md) 和 [Google Play 准备](GOOGLE_PLAY.md)。

## 尚需真机验收

继续使用 [五机手动验收清单](MANUAL_ACCEPTANCE.md)，记录实际系统版本和安装方式，覆盖同网发现、跨平台 GATT 文字备用、Wi-Fi Aware 配对、耳机与音频中断、房主离线与重连、锁屏后台、多人容量及功耗。

共同 Wi-Fi/热点下发现成功不能证明无共同网络时可以自动直连；编译、模拟通道和回环测试也不能替代厂商桌面动画、射频互通或道路声学验收。历史构建日志不作为当前版本已通过的证明。
