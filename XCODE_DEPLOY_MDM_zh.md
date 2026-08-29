# MDM 监管机安装 mond 指南（iOS 26.0–26.6）

> **适用场景**：设备处于 MDM 监管模式且 `allowAppInstallation` 被禁用，无法通过 App Store、全能签、AltStore 等常规方式安装 App。

---

## 方案一：Xcode USB 直连部署（推荐）

MDM 的 `allowAppInstallation` 限制仅作用于 App Store 和 OTA 描述文件安装。**Xcode 通过 USB 调试通道（lockdownd + DeveloperDiskImage）直接部署 App 不受此限制**。

### 前置条件

| 条件 | 说明 |
|------|------|
| macOS 电脑 | 实体 Mac / Hackintosh / VMware macOS 虚拟机均可 |
| Xcode 18+ | 需包含 iOS 26 SDK（Xcode 18.0 beta 或更高） |
| Apple ID | 免费账号即可（7 天有效期）；付费开发者 365 天 |
| USB 数据线 | Lightning 或 USB-C，确保是数据线而非纯充电线 |
| 开发者模式 | 设备上的"开发者模式"开关需可用 |

### 操作步骤

#### 第 1 步：检查开发者模式是否可用

```
设置 → 隐私与安全性 → 开发者模式
```

- ✅ 如果能看到开关并可以打开 → 继续
- ❌ 如果开关灰色/不存在 → MDM 禁用了开发者模式，跳转方案二

#### 第 2 步：克隆仓库

```bash
git clone <你的 mond 仓库 URL>
cd mond
```

#### 第 3 步：用 Xcode 打开项目

```bash
open mond.xcodeproj
```

#### 第 4 步：配置签名

1. 在 Xcode 左侧导航栏点击项目根节点 `mond`
2. 选择 Target → `mond`
3. 选择 **Signing & Capabilities** 标签
4. 勾选 **Automatically manage signing**
5. **Team**: 点击下拉菜单，选择你的 Apple ID（Personal Team）
   - 如果没有，点击 **Add an Account...** 登录 Apple ID
6. **Bundle Identifier**: 修改为唯一值，例如：
   ```
   com.yourname.mond.学习版
   ```
7. 对 `BAExtension` Target 也执行相同的签名配置

> ⚠️ **免费 Apple ID 限制**：
> - 最多同时签名 3 个 App
> - 签名有效期 7 天，到期后需重新连接 Xcode 部署
> - 不影响已修改的 MobileGestalt 设置（修改已写入系统文件）

#### 第 5 步：连接设备

1. USB 连接 iPhone
2. 设备弹出"信任此电脑？" → 点击 **信任**
3. Xcode 顶部设备选择器中选择你的设备
4. 如提示 "Device is not available"，等待 Xcode 处理设备符号（首次约需 5-15 分钟）

#### 第 6 步：Build & Run

- 快捷键 `⌘R` 或点击播放按钮
- 首次在设备上运行时，需要在 iPhone 上信任开发者证书：
  ```
  设置 → 通用 → VPN 与设备管理 → 你的 Apple ID → 信任
  ```

#### 第 7 步：使用 mond 绕过 MDM

mond 安装成功后：
1. 打开 mond
2. 进入 **MDM 监管管理** 部分
3. 点击 **"绕过 MDM (将描述文件覆盖为空字典)"**
4. 等待操作完成
5. **重启设备**
6. 重启后 MDM 限制应已解除（包括 `allowAppInstallation`）

> ⚠️ 修改前 mond 会自动创建安全备份到 `Documents/SystemFileBackups/MDM`，后续可通过 mond 一键还原。

---

## 方案二：pymobiledevice3 电脑端操作（免安装任何 App）

如果开发者模式也被 MDM 禁用，可以使用 Python 工具 `pymobiledevice3` 在电脑端直接操作设备文件系统。

### 安装 pymobiledevice3

```bash
pip install pymobiledevice3
# 或使用 pipx
pipx install pymobiledevice3
```

### 使用项目中的 mdm_bypass_pc.py 脚本

```bash
python scripts/mdm_bypass_pc.py
```

详细使用说明见 `scripts/mdm_bypass_pc.py` 脚本头部注释。

---

## 方案三：通过 GitHub Actions 构建 IPA + TrollStore 安装

如果设备支持 TrollStore，可以完全不需要 Mac：

1. Fork 本仓库到你的 GitHub 账号
2. 进入 **Actions** → **build and release** → **Run workflow**
3. 下载产物 `mond.ipa`
4. 通过 AirDrop / iCloud Drive / USB 传输到设备
5. 在 TrollStore 中打开安装

TrollStore 安装本身不受 `allowAppInstallation` 限制，因为它走 CoreTrust 签名路径。

---

## 故障排查

### Q: Xcode 报 "Unable to install app" 错误
- 检查 Bundle ID 是否冲突
- 尝试删除设备上已有的同名 App
- 清理 Xcode 缓存：`Product → Clean Build Folder (⇧⌘K)`

### Q: 部署成功但 mond 的 MDM 绕过提示"所有沙盒逃逸方式均失败"
- 通过 Xcode 安装的 App 使用标准沙盒签名，mond 会依次尝试多种沙盒逃逸：
  - `sandbox_extension_issue_file`
  - `container_object_sandbox_extension_activate`（cmg-activate）
  - `bad_query`（MCM 漏洞）
  - UUID 路径绕过
- 如果全部失败，说明当前 iOS 版本可能已修补这些漏洞
- 此时请尝试方案二（pymobiledevice3 电脑端操作）

### Q: 设备绑定了 DEP（Apple Business Manager），刷机后 MDM 重新下发
- DEP 绑定的设备在联网激活时会自动重新注册 MDM
- 激活时**断开 Wi-Fi**可临时跳过，但长期不可靠
- 建议联系原管理员解除 DEP 绑定

---

> **免责声明**：本文档仅供个人学习 iOS 安全机制使用。请仅在你个人拥有的设备上操作。
