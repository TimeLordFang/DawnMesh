# GitHub 自动发布

仓库内的 `.github/workflows/release.yml` 会在 GitHub 收到 `v*` 标签时执行完整检查、构建签名 APK，并创建对应的 GitHub Release。也可以在 GitHub 的 **Actions → Android release → Run workflow** 中选择一个已经存在的标签重新运行。

Runner 使用 Temurin **Java 25 LTS** 运行 Gradle 9.7.1。应用字节码仍以 Java 17 为目标，不会提高 Android 最低版本。

## 一次性配置签名 Secret

打开 GitHub 仓库的 **Settings → Secrets and variables → Actions → New repository secret**，添加以下四项：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | release JKS 文件的单行 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 签名别名，本项目本地默认是 `dawnmesh` |
| `ANDROID_KEY_PASSWORD` | key 密码 |

在 macOS 上生成可粘贴的 JKS Base64 文件：

```bash
base64 -i android/keystore/dawnmesh.jks -o /tmp/dawnmesh-keystore.base64
```

打开 `/tmp/dawnmesh-keystore.base64`，把完整内容保存为 `ANDROID_KEYSTORE_BASE64`。Base64 只是传输编码；真正的保护来自 GitHub Actions Secret。不要提交 JKS、`android/key.properties`、密码或生成的 Base64 文件。

也可以使用已登录的 GitHub CLI 写入 Secret：

```bash
gh secret set ANDROID_KEYSTORE_BASE64 < /tmp/dawnmesh-keystore.base64
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
```

工作流已经声明最小的 `contents: write` 权限，用于创建 Release。如果运行到发布步骤时出现 HTTP 403，并且仓库属于受管组织，请检查 **Settings → Actions → General → Workflow permissions** 是否被组织策略限制为只读。

## 发布一个版本

先修改 `pubspec.yaml`。例如：

```yaml
version: 0.1.0-dev.18+18
```

提交代码并把同名标签推送到 GitHub：

```bash
git add pubspec.yaml
git commit -m "Release 0.1.0-dev.18"
git push origin main
git push github main
git tag -a v0.1.0-dev.18 -m "DawnMesh 0.1.0-dev.18"
git push origin v0.1.0-dev.18
git push github v0.1.0-dev.18
```

工作流会检查标签必须等于 `v` 加 `pubspec.yaml` 的 versionName。检查通过后，Release 包含签名 APK、SHA-256 文件和 GitHub 自动生成的更新记录；名称含 `-dev`、`-alpha`、`-beta` 或其他连字符时会标为 prerelease。

签名由 `android/app/build.gradle.kts` 的 `release` signingConfig 在 Gradle `packageRelease` 期间完成。工作流中的 `apksigner verify` 只验证结果，`cp` 到 `dist/` 只负责按版本重命名。Runner 最后会删除临时还原的 JKS。
