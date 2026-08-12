# mond 文件浏览版：IPA 构建与安装

## 当前功能

- `Documents`、`Library`、`tmp`：可浏览、新建文件夹、新建空文件、重命名、删除和分享。
- `/private/var`：不再直接请求根目录，而是对精确路径调用 `bad_query`；授权后可浏览。点击锁按钮后，程序会在当前目录执行可回滚的“创建—读取—重命名—原子替换—删除”探针，全部成功才开放写操作。
- 内置编辑器支持不超过 2 MB 的 plist、JSON、XML 和常见文本文件；二进制 plist 会转换为 XML 供编辑，保存时恢复原格式，非法 plist/JSON 会被拒绝。
- 系统文件在内容修改、重命名或删除前自动备份到 `Documents/SystemFileBackups`；系统目录仍禁止重命名或删除。`com.apple.MobileGestalt.plist` 可在解锁后编辑，也可在输入 `DELETE` 二次确认后备份、删除并重新枚举验证。
- 已启用 iOS 文件共享，`Documents` 可通过“文件”App、Finder 或 iTunes 访问。

## 为什么 IPA 压缩包内没有真实 `/var`

IPA 是 App 安装包，只包含 `Payload/mond.app`。手机上的 `/private/var` 是 iOS 运行时文件系统，不会也不应复制进 IPA。安装后，应用通过自身沙盒访问 `Documents/Library/tmp`；仅在受支持系统上，仓库现有的 `bad_query` 才可能临时开放真实 `/private/var`。

## 自动构建无签名 IPA

1. 将本项目推送到你自己的 GitHub 仓库。
2. 打开仓库的 **Actions** 页面，选择 **build and release**。
3. 点击 **Run workflow**。
4. 构建完成后，从该次运行的 **Artifacts** 下载 `mond-var-browser-unsigned`，其中包含：
   - `mond.ipa`
   - `mond.ipa.sha256`

工作流也会在仓库的 `latest` Release 中发布同一个 IPA。

## 安装

GitHub Actions 生成的是未签名 IPA，不能直接通过系统安装。需使用你自己的证书重新签名，或使用 AltStore、Sideloadly、TrollStore 等与你设备环境匹配的安装方式。不要把来源不明的签名证书或 Apple ID 凭据发给他人。

## 兼容性和风险

- 文件浏览界面最低支持 iOS 17。
- 真实 `/private/var` 访问依赖上游 `bad_query`，上游目前仅声明支持 iOS 27.0 beta 1–4；其他版本通常只能使用应用自身沙盒。
- `/private/var` 不存在一个可全局授予的根权限；每个精确目标都必须单独成功授权。`access(..., W_OK)` 不能可靠反映 sandbox extension 的实际能力，因此新版以真实但可回滚的文件操作作为写权限判定；任何一步失败都会保持只读并显示系统错误。
- MobileGestalt 修改仍是高风险功能，操作前请保留设备备份；仓库上游明确提示错误修改可能导致 bootloop。
