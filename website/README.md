# DawnMesh 应用主页模板

这是一个自包含的 Jekyll 应用展示模板，使用 GitHub 官方 Pages 构建流程。公开页面不需要 JavaScript、登录、外部字体或统计服务。没有主题订阅或付费依赖，可在 GitHub 网页中直接编辑文案。

## 最常编辑的文件

| 文件 | 用途 |
| --- | --- |
| `_data/home.yml` | 主页标题、介绍、连接方式、功能与常见问题。保留缩进和字段名，修改引号内文字。 |
| `privacy.md` | 隐私政策正文，使用 Markdown。修改政策时同步顶部 `updated` 日期。 |
| `_config.yml` | 应用名称、联系人、邮箱、下载链接与网站域名／子路径。 |
| `assets/style.css` | 页面配色、字体、间距和手机布局。 |
| `_layouts/default.html` | 所有页面共用的页头、导航与页脚。 |
| `_layouts/policy.html` | 隐私政策版式和目录；新增政策章节时也更新目录。 |
| `index.html` | 主页的区块结构，通常只改文案不需要修改它。 |

`assets/icon.png` 复制自 `../assets/branding/google-play-icon.png`，更新品牌图标时同步替换。模板与本项目同为 Apache-2.0。

## 首次启用 GitHub Pages

1. 将这些文件提交并推送到 `TimeLordFang/DawnMesh` 的 `main` 分支。
2. 打开仓库 **Settings → Pages → Build and deployment → Source**，选择 **GitHub Actions**。
3. 在 **Actions → Deploy application website** 中运行工作流，或在启用后再推送一次网站修改。
4. 等待 `build` 与 `deploy` 成功，然后用未登录浏览器检查以下地址。若设置中提供 **Enforce HTTPS**，保持启用。

主页：`https://timelordfang.github.io/DawnMesh/`

隐私政策：`https://timelordfang.github.io/DawnMesh/privacy/`

以上为预期地址；只有部署成功并实际访问正常后，才能填写 Google Play。不要提交仓库源文件地址、编辑链接、README 或 PDF 地址。GitHub Pages 无法保证任何运营商和地区的网络可达性，发布后还需从目标地区检查。

后续可以直接在 GitHub 打开上述文件，点击编辑按钮，保存到 `main`，网站便会自动更新。更换仓库、域名时，修改 `_config.yml` 的 `url` 和 `baseurl`，并同步 Android 中的隐私政策固定地址。

## 本地预览

需要 Ruby 和 Bundler。仓库根目录执行：

```sh
cd website
bundle install
bundle exec jekyll serve --host 127.0.0.1 --port 4000
```

访问 `http://127.0.0.1:4000/DawnMesh/` 和 `http://127.0.0.1:4000/DawnMesh/privacy/`。`bundle install` 生成的锁文件可以保留在本机；正式发布由官方 `jekyll-build-pages` 构建。

## Google Play 提交前

- 核实联系人、发布主体和商店应用名称；本页使用仓库作者明确确认的联系人。
- 确保网页版政策的内容适用于本次实际提交的 APK／AAB，包括第三方库、自选服务器、管理员收听和可选持久化功能。
- 本次代码在 **设置 → 关于 → 隐私政策** 提供网页入口；需要重新构建并上传包含此入口的版本，已经发布的旧安装包不会自动获得此按钮。
- 隐私政策与 Play Console 数据安全表单应保持一致；不能因为没有广告或遥测，就把语音、图片等所有处理一概声明为不存在。
- 公网页面与应用内入口可用，并不表示已经完成 Google 审核。
