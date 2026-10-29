# Google Play 发布与 AAB 构建

构建记录更新日期：2026-10-28。项目包名 `dev.dawnmesh.intercom`，当前目标版本 `1.2.4+65`。

正式上架版本先按 [本地预检与候选发布](RELEASING.md) 验证，再创建正式标签；不通过连续递增版本解决 CI 问题。

## 本机打包

项目已在 `android/app/build.gradle.kts` 配置 release 签名，并对 `bundleRelease` 强制检查签名配置。使用现有的 `android/key.properties` 或 `DAWNMESH_*` 签名环境变量即可；不要把密钥或口令提交到 Git。

在项目根目录执行：

```sh
./scripts/flutter.sh pub get --enforce-lockfile
./scripts/flutter.sh build appbundle --release --no-pub
```

本仓库的脚本会使用 `.tools/` 内的 Flutter、JDK 和 Android SDK。使用自行安装且版本匹配的工具链时，可改用 `flutter build appbundle --release`。

产物通常为 `build/app/outputs/bundle/release/app-release.aab`，以构建末尾打印的路径为准。AAB 是上传给 Play 的发布包，不可像 APK 一样直接安装；通过 Play 内部测试或 bundletool 生成设备 APK 进行安装验证。

后续更新必须使用大于 Play 已上传版本的 `versionCode`。在 `pubspec.yaml` 中修改 `version: 版本名+构建号`，本轮为 `1.2.4+65`；若 Play 已使用该构建号，按平台规则递增并同步两端。

签名检查：

```sh
bash -c 'source scripts/toolchain.sh; jarsigner -verify build/app/outputs/bundle/release/app-release.aab'
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

## 验证与验收

应用主页与隐私政策采用仓库内的 Jekyll 模板，编辑、域名配置和首次启用 Pages 见 [网站说明](../website/README.md)。部署并确认可公开访问后，在 Play Console 隐私政策字段填写 `https://dawnmesh.timelord.info/privacy/`。应用内入口位于“设置 → 关于 → 隐私政策”，需在实际上传的版本中包含该入口。政策正文为 `website/privacy.md`，主页文案为 `website/_data/home.yml`。

每次新包都需核对版本、签名、归档完整性及 16 KiB 对齐，记录统一见 [验证基线](VALIDATION.md)。下载使用对应 Release 随包 SHA-256，不沿用旧版本或其他重构建产物的哈希。

Play 内部测试、分发后的 APK 对齐和设备运行仍需通过控制台与 [真机验收](MANUAL_ACCEPTANCE.md) 完成；具体上架要求以官方当前规则为准。

## 官方资料

- [Flutter Android 发布](https://docs.flutter.dev/deployment/android)
- [应用签名与 Play App Signing](https://developer.android.com/studio/publish/app-signing)
- [Target API 要求](https://support.google.com/googleplay/android-developer/answer/11926878)
- [16 KB 页面兼容性](https://developer.android.com/guide/practices/page-sizes)
- [商店图片要求](https://support.google.com/googleplay/android-developer/answer/9866151)
- [前台服务声明](https://support.google.com/googleplay/android-developer/answer/13392821)
- [新个人开发者账号测试要求](https://support.google.com/googleplay/android-developer/answer/14151465)
