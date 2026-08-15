<p align="right">
  <img align="right" height="140" src="https://github.com/rooootdev/mond/blob/main/mond.png?raw=true" style="float: right;"/>
</p>

<div style="width: calc(100% - 180px);">
  <h1 style="margin-bottom: 0;">mond (全中文增强版)</h1>
</div>

<p align="left">基于 MCM 与 bad_query 漏洞的 iOS MobileGestalt 微调工具与精确路径文件管理器！支持 iOS 17.0 - 27.x</p>

> [!WARNING]  
> 部分底层系统微调项具有导致设备故障或变砖（Bootloop）的潜在风险！使用前请务必保留设备备份并谨慎操作。

### 🌟 本版本已实现的全部功能：
- **全界面中文本地化**：主界面、文件浏览器、设置、控制台日志、所有弹窗及错误信息深度汉化。
- **MDM 监管深度管理与绕过**：
  - 支持将 MDM 描述文件（`CloudConfigurationDetails.plist`、`MDM.plist` 等）原子覆写为空 Payload，防止守护进程自愈恢复。
  - 具备多重沙盒逃逸兜底（越狱环境 unsandbox、direct sandbox extension、cmg-activate、bad_query 识别重定向、UUID 路径绕过及 BackgroundAssets 守护进程清除）。
  - 支持 MDM 描述文件的一键安全备份与一键还原。
- **精确 `/private/var` 系统文件浏览器**：
  - 支持 Documents、Library、tmp 应用沙盒以及系统 `/private/var` 精确目标浏览。
  - 支持目标包括：MobileGestalt 缓存、MDM 描述文件、系统数据容器、应用数据容器、内部守护进程容器、插件扩展容器、共享应用组、PosterBoard 锁屏海报存储、用户偏好设置。
  - 受控可逆写入探针验证（必须通过创建/读取/重命名/原子替换/删除探针后才解锁写权限）。
  - 内置 plist、JSON、XML 及文本编辑器，修改前自动为系统文件创建安全备份。
  - 启用 iOS 文件共享，Documents 目录可通过“文件”App 或电脑端直接访问。
- **全面的 MobileGestalt 硬件与软件微调**：
  - 机型子类型切换（关闭灵动岛、iPhone 14 Pro/Pro Max、iPhone 15 Pro Max、iPhone 16 Pro/Pro Max、iPhone Air、iPhone X 全面屏手势）。
  - 灵动岛、全天候显示 (AOD) 及鲜艳度、80% 充电上限、开机提示音、Liquid Glass 低电量模式。
  - 相机控制按键、操作按钮、车祸检测、轻点唤醒、PWM 防频闪调光。
  - 去除地区限制（拍照静音/美版功能）、Apple Intelligence 资格激活、机型伪装（iPhone 15 Pro 至 17 Pro Max、iPad Pro M4 等）。
  - iPadOS 特性（安装 iPadOS 专属 App、Apple Pencil 随手写、台前调度、TrollPad 分屏多任务）。
  - 内部调试（内部存储选项、AppleInternal 内部设置、全局 Metal 性能监视 HUD）。

---

### 致谢与鸣谢 (Credits)
- [roooot](https://github.com/rooootdev) - 主要开发者
- [forcequit](https://github.com/forcequitOS) - bad_query 漏洞发现与实现
- [johnny](https://github.com/0xjohnnydev) - MCM 漏洞类研究与贡献
- [jailbreak.party](https://github.com/jailbreakdotparty) - PartyUI、GestaltView 与注销（Respring）实现
