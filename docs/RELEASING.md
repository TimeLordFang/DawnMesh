# 发布：本地预检、候选与正式晋级

当前目标应用版本为 **1.2.4+65**，本轮候选为 **v1.2.4-rc.1**。同一目标内修复使用 `rc.2`、`rc.3` 等轮次，不通过连续增加补丁版本来排查 CI；已发布正式标签和附件不覆盖。

## 本地预检

先按 [开发指南](DEVELOPMENT.md) 准备工具链，再执行：

```sh
./scripts/preflight-release.sh
```

真实中继用例需启动测试服务并设置 `DAWNMESH_FUSION_TEST_URL`；未配置时该项跳过，不能计为已验收。两端网络回归串行执行。

Android 的本地与标签 CI 共用同一预检入口，覆盖 Flutter、原生 sanitizer、JVM/Lint、签名 APK/AAB 及 16 KiB 对齐。

## Android 签名配置

发布构建读取被 Git 忽略的 `android/key.properties`，也可读取 `DAWNMESH_KEYSTORE_PATH`、`DAWNMESH_STORE_PASSWORD`、`DAWNMESH_KEY_ALIAS`、`DAWNMESH_KEY_PASSWORD`。配置不完整时失败，不回退 debug 签名。首次配置参考 `android/key.properties.example`；永久备份原 JKS 和密码，更新必须保持签名兼容。

GitHub Actions 使用以下仓库 Secrets：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | release JKS 的单行 Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 密钥密码 |

Base64 只是编码，不是加密；设置 Secret 后立即删除临时编码文件。JKS、口令、签名描述文件与本机账号配置不提交。签名发生在 Gradle 打包中，后续 `apksigner verify` 和复制重命名不会重新签名。

Play 首次上架、应用签名与上传密钥见 [Google Play](GOOGLE_PLAY.md)。

## 创建候选

1. 同步两端 `pubspec.yaml`、更新服务版本和中英文更新日志，准备 `docs/RELEASE_<版本>.md`。
2. 完成本地预检，按范围提交源代码和文档；排除个人 Team/Scheme、密钥、缓存及仅本地保存的研究稿。
3. 推送主分支与未占用的候选标签。当前示例：

```sh
git tag -a v1.2.4-rc.1 -m 'DawnMesh 1.2.4 build 65 candidate 1'
git push github main v1.2.4-rc.1
git push origin main v1.2.4-rc.1
```

Android GitHub 远程名为 `github`，另同步自建镜像 `origin`；iOS 的 GitHub 远程名为 `origin`。CI 将候选设为 Prerelease、非 Latest。应用内版本保持数字格式，不把 `-rc.N` 写进 iOS 版本字段。若上传 Play/TestFlight，构建号还需满足平台递增规则并同步两端。

## 同一提交提升为正式版

两端候选任务成功、附件与校验值齐全并完成相应验收后，正式标签必须指向该候选的同一个提交。源码或说明再有改变，就先验证新的候选。

```sh
git tag -a v1.2.4 'v1.2.4-rc.1^{commit}' -m 'DawnMesh 1.2.4'
git push github v1.2.4
git push origin v1.2.4
```

发布门禁核对候选不是草稿、具有 Prerelease 标记、包和 SHA-256 齐备、提交相同，且最近一次候选标签校验成功。正式标签仍会重新构建；重构建的哈希可能不同，下载时使用对应 Release 随包的校验文件。

正式 Release 提供 Android 签名 APK/AAB 或 iOS 两种未签名 App ZIP。iOS ZIP 不能直接安装，需相应签名。构建成功不替代 [真机验收](MANUAL_ACCEPTANCE.md)；当前证据见 [验证基线](VALIDATION.md)。
