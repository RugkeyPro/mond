# 弦光 (授权计算器)：GitHub 云端自动编译与导出指南

本项目现已支持在 GitHub Actions 云端自动将 `授权计算器-merged(1).zip` 编译并导出为未签名 iOS IPA 安装包（桌面名称：“弦光”，Bundle ID：`com.beiqizou.xianguang`）。

---

## 快速使用

### 1. 自动构建与发布

1. 提交并推送以下文件至 GitHub 仓库（`main` 分支）：
   - `授权计算器-merged(1).zip`
   - `.github/workflows/build-xianguang.yml`
2. 推送后，GitHub Actions 会自动触发 **build and release xianguang** 工作流。
3. 你也可以随时在 GitHub 仓库页面手动运行：
   - 进入 **Actions** 选项卡；
   - 在左侧列表中选择 **build and release xianguang**；
   - 点击 **Run workflow** -> **Run workflow**。

### 2. 下载编译导出的 IPA

构建耗时通常约 1~2 分钟，完成后可通过以下两种方式下载：

- **方式 A（Release 页面，推荐）**：
  进入仓库右侧的 **Releases** 页面，找到 `xianguang-latest`（标题为：*弦光 (授权计算器) 最新构建*），直接下载：
  - `xianguang.ipa`：编译导出的未签名应用安装包；
  - `xianguang.ipa.sha256`：SHA-256 完整性校验文件。
- **方式 B（Actions Artifacts）**：
  进入该次构建的详情页，在底部 **Artifacts** 区域下载 `xianguang-unsigned` 压缩包。

---

## 安装说明

GitHub Actions 生成的为未签名（Ad-hoc）IPA，并已预置越狱/沙盒逃逸所需的 `com.apple.private.security.no-sandbox` 权限：

- **TrollStore 设备**：直接通过 TrollStore 导入安装，可直接获得完全系统权限。
- **未越狱设备**：可使用 **AltStore**、**Sideloadly** 或个人开发者证书签名后安装。

---

## 技术架构说明

- **宿主 App**：`授权计算器`（SwiftUI 原生应用，桌面图标及名称为“弦光”）。
- **内置功能**：全屏计算器界面与本地账本，输入 8 位数字授权码后调用后台进行设备绑定与兑换验证。
- **内嵌模块**：验证通过后自动进入 `CompanySoftwareKit.framework`（已整合原 `mond` 文件浏览器与 `bad_query` 漏洞链）。
