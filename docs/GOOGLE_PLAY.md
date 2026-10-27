# Google Play 发布与 AAB 构建

核对日期：2026-10-27。项目包名 `dev.dawnmesh.intercom`，当前版本 `1.2.2+63`。

## 本机打包

项目已在 `android/app/build.gradle.kts` 配置 release 签名，并对 `bundleRelease` 强制检查签名配置。使用现有的 `android/key.properties` 或 `DAWNMESH_*` 签名环境变量即可；不要把密钥或口令提交到 Git。

在项目根目录执行：

```sh
./scripts/flutter.sh pub get --enforce-lockfile
./scripts/flutter.sh build appbundle --release --no-pub
```

本仓库的脚本会使用 `.tools/` 内的 Flutter、JDK 和 Android SDK。使用自行安装且版本匹配的工具链时，可改用 `flutter build appbundle --release`。

产物通常为 `build/app/outputs/bundle/release/app-release.aab`，以构建末尾打印的路径为准。AAB 是上传给 Play 的发布包，不可像 APK 一样直接安装；通过 Play 内部测试或 bundletool 生成设备 APK 进行安装验证。

后续更新必须使用大于 Play 已上传版本的 `versionCode`。在 `pubspec.yaml` 中修改 `version: 版本名+构建号`，例如后续 `1.2.3+64`；若 Play 已使用对应构建号，则继续递增。仅重新上传设计候选不需要改应用版本；将选定图标接入应用后需重新打包。

签名检查：

```sh
.tools/jdk/Contents/Home/bin/jarsigner -verify \
  build/app/outputs/bundle/release/app-release.aab
```

AAB 使用 JAR 签名校验；`apksigner` 用于 APK。自签名证书的信任链提示不等于签名数据校验失败。

## 首次配置签名

本项目已向 GitHub 分发签名 APK。若需要 GitHub 安装用户直接升级到 Play 分发版本，首次配置 Play App Signing 时选择导入现有应用签名密钥，按照控制台的 PEPK 流程导入。不能仅因为 AAB 使用旧密钥签名，就认为 Play 最终分发的 APK 也会使用同一个密钥。

应用签名密钥用于给用户安装的 APK 签名；上传密钥用于证明 AAB 上传者身份。可另外注册上传密钥，然后将本地 Play 打包签名配置改为该上传密钥。保留 GitHub APK 使用原应用签名密钥的构建方式。

如果不需要与已有 APK 兼容升级，可以使用 Google 生成的应用签名密钥，但应先明确分发策略。永久备份现有 keystore 和口令。

## 控制台操作

1. 在 Google Play Console 创建应用，确定名称、默认语言、应用类型和收费方式。
2. 配置 Play App Signing，进入“测试和发布 → 测试 → 内部测试”，创建版本并上传 AAB。
3. 完成商店资料：介绍、512×512 应用图标、1024×500 宣传图、真实应用截图、联系邮箱和隐私政策链接。
4. 完成“应用内容”中的数据安全、内容分级、目标受众、广告、应用访问权限及控制台要求的权限声明。数据安全应依据实际语音、聊天、图片、服务器和第三方 SDK 行为填写，不能仅凭“没有账号、没有遥测”认定不涉及数据处理。
5. 本应用使用 microphone、connectedDevice、mediaPlayback 前台服务。按实际用途完成前台服务声明，并准备演示建房、授权麦克风、后台通话及结束通话的视频。若审核需要公网房，提供可用测试服务器和可复现的操作说明；同时说明如何用两台设备测试近场通信。
6. 在内部测试中验证安装、冷启动、入房、录音权限、后台/锁屏通话、蓝牙耳机及升级。检查预发布报告与 App Bundle Explorer 的兼容性信息。
7. 若属于 2023-11-13 之后创建的个人开发者账号，需要至少 12 名测试人员连续加入封闭测试 14 天，达到条件后申请正式发布权限；内部测试不能替代这项封闭测试。

截至核对日期，新应用和更新要求 target API 至少 36，本项目设置为 37。本项目含 Flutter、WebRTC、RNNoise 等原生库，仍需检查最终产物的全部 64 位库 16 KB 对齐、打包对齐及 16 KB 设备运行情况；高版本 NDK 本身不能证明第三方库全部兼容。

GitHub Actions 的发布工作流现同时构建签名 APK 与 AAB，并发布校验文件；不会自动上传 Google Play。商店图标使用 `assets/branding/google-play-icon.png`。离线转交为新增可选持久化能力，填写隐私与数据安全时应一并说明其密文托管和元数据边界。

## 1.2.2 本地构建记录（2026-10-27）

- AAB：90,018,317 字节；SHA-256 `bb648964c06c5a0628d25587d1bcd61c0a697f21f5f0e6ebc43f462b0b11f758`。
- APK：108,991,479 字节；SHA-256 `7ff330546e1a9742b9bc3cdd1599c172d54fe8780326946779340a94b6177666`。
- 包内版本为 1.2.2 / 63；签名、16 KiB ZIP/ELF 对齐、官方 bundletool 结构及 115 个 JAR 签名载荷验证通过。
- 本地统一产物位于 `artifacts/releases/1.2.2/`；下载 GitHub Release 时使用该次重构建的随包校验文件。
- 尚未上传 Google Play、没有执行手机安装；按控制台步骤和 [五机验收](MANUAL_ACCEPTANCE.md) 操作。

## 1.2.1 本地构建记录（2026-10-27）

- AAB：90,006,481 字节；SHA-256 `5feeec657d9451171f2434e42cd682730cd718197a24c9c12244c550c769f9fb`。
- APK：108,991,479 字节；SHA-256 `e6154a8723b32aaa8c1bde07e37177c2e4e95073f209bc86f074ab8cd837b8ba`。
- 当前包内版本为 1.2.1 / 62，签名、16 KiB ZIP/ELF 对齐、官方 bundletool 结构及 JAR 115 个签名载荷验证通过。
- 本地文件位于 `artifacts/releases/1.2.1/`；GitHub 会从标签重构建，下载 Release 时采用随包校验文件。
- 尚未上传 Google Play，也未进行手机安装；按上方控制台步骤和 [五机验收](MANUAL_ACCEPTANCE.md) 操作。

## 1.2.0 本地构建记录（2026-10-27）

- AAB：89,977,165 字节；SHA-256 `058afcf6c6e627c36d41df2b28ff180339714076092211181bcbf6982d43b0d8`。
- APK：108,958,711 字节；SHA-256 `4b7541f73dfa98c9e8f41bfdefe89ce80abab2aa19cdb80659aadc6e4c7aa255`。
- APK 包信息确认为 `dev.dawnmesh.intercom`、1.2.0 / 61、min API 26、target API 37；APK v2 签名与 ZIP/ELF 16 KiB 检查通过。
- AAB 经官方 bundletool 1.18.3 验证；JarFile 逐项验证 115 个签名载荷，ZIP CRC 和 64 位 ELF 对齐通过。jarsigner 的自签名、时间戳和流式读取告警保留说明于 [验证记录](VALIDATION.md)。
- 本地统一产物位于 `artifacts/releases/1.2.0/`。GitHub Actions 会从标签重新构建，Release 下载应采用该次发布随包的 SHA-256；不把本地哈希当作所有重构建产物的固定值。
- 尚未上传 Play 或执行真机安装，按 [五机验收](MANUAL_ACCEPTANCE.md) 操作。

## 历史构建记录（1.1.9，2026-10-26）

- 构建命令：`./scripts/flutter.sh build appbundle --release --no-pub`，使用现有依赖缓存及现有 release 签名配置。
- 产物：`build/app/outputs/bundle/release/app-release.aab`，87,044,430 字节。
- SHA-256：`1fcb37367298036aecdbf534c3025b1b5c16dd217d94ca3a62b75600ef0ed03a`。
- `jarsigner -verify` 返回成功；同时提示自签名证书、无时间戳，以及 ZIP 中签名清单位置导致的 JarInputStream 流式读取提示。不要将其描述为无警告的校验。
- 另外使用 Java `JarFile` 验证全部载荷内容：117 个载荷条目均有签名，未签名载荷为 0。
- ZIP CRC 检查通过；包内 12 个 64 位 `.so` 的所有 PT_LOAD 段对齐均至少 16,384 字节。
- 尚未上传 Play，未执行 Play 生成 APK 的 ZIP 对齐验证或 16 KB 设备运行测试；本次未修改应用逻辑，未重跑完整功能测试。
- 上述旧产物使用原图标；1.2.0 已选用第一个“曙光声波”方案，新产物记录见 [1.2.0 发布说明](RELEASE_1.2.0.md)。

## 官方资料

- [Flutter Android 发布](https://docs.flutter.dev/deployment/android)
- [应用签名与 Play App Signing](https://developer.android.com/studio/publish/app-signing)
- [Target API 要求](https://support.google.com/googleplay/android-developer/answer/11926878)
- [16 KB 页面兼容性](https://developer.android.com/guide/practices/page-sizes)
- [商店图片要求](https://support.google.com/googleplay/android-developer/answer/9866151)
- [前台服务声明](https://support.google.com/googleplay/android-developer/answer/13392821)
- [新个人开发者账号测试要求](https://support.google.com/googleplay/android-developer/answer/14151465)
