#!/usr/bin/env python3
"""
mdm_bypass_pc_v2.py — 增强版电脑端 MDM 绕过脚本

学习目标：
  演示 pymobiledevice3 如何通过 USB lockdownd 协议绕过 MDM 的
  App 安装限制，直接在 PC 端修改设备 MDM 描述文件。

技术原理：
  iOS lockdownd 守护进程暴露了多个服务端点（如 AFC、house_arrest、
  文件中继 等），这些端点由系统层提供，MDM 的 allowAppInstallation
  策略仅影响上层 App 安装流程，不影响这些底层 USB 协议通道。

  pymobiledevice3 实现了这些协议，因此可在不安装任何 App 的情况下：
    - 读写设备文件系统
    - 安装/卸载 App（通过 instproxy）
    - 操作 MDM 描述文件

注意事项（学习用途）：
  - 仅对自己拥有的设备操作
  - 修改 MDM 前请备份
  - 理解原理，不用于破坏他人管理的设备

用法:
  python mdm_bypass_pc_v2.py info
  python mdm_bypass_pc_v2.py list
  python mdm_bypass_pc_v2.py backup
  python mdm_bypass_pc_v2.py neuter
  python mdm_bypass_pc_v2.py restore
  python mdm_bypass_pc_v2.py install --ipa path/to/mond.ipa
"""

import argparse
import sys
import os
import json
import datetime
import plistlib
import tempfile
from pathlib import Path

# ── 颜色输出 ──────────────────────────────────────────────────────────────────
def c(text, code): return f"\033[{code}m{text}\033[0m" if sys.stdout.isatty() else text
def ok(msg):   print(c(f"  ✅ {msg}", 32))
def err(msg):  print(c(f"  ❌ {msg}", 31))
def warn(msg): print(c(f"  ⚠️  {msg}", 33))
def info(msg): print(c(f"  ℹ️  {msg}", 36))

# ── 常量 ──────────────────────────────────────────────────────────────────────
MDM_DIR = (
    "/private/var/containers/Shared/SystemGroup/"
    "systemgroup.com.apple.configurationprofiles/"
    "Library/ConfigurationProfiles"
)
MDM_FILES = [
    "CloudConfigurationDetails.plist",
    "ClientTruth.plist",
    "CloudConfigurationSetAsideDetails.plist",
    "MDM.plist",
    "MCProfileEvents.plist",
    "MDMEvents.plist",
    "ProfileTruth.plist",
    "MCFeatureOverrides.plist",
    "ProfilePreferences.plist",
]
EMPTY_PLIST_XML = (
    b'<?xml version="1.0" encoding="UTF-8"?>\n'
    b'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"'
    b' "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    b'<plist version="1.0">\n<dict/>\n</plist>\n'
)
BACKUP_DIR = Path("mdm_backups_v2")

# ── 检查 pymobiledevice3 ──────────────────────────────────────────────────────
def check_deps():
    try:
        import pymobiledevice3
    except ImportError:
        err("pymobiledevice3 未安装。")
        print()
        print("  请执行以下命令安装：")
        print("    pip install pymobiledevice3")
        print("  或（推荐隔离环境）：")
        print("    pipx install pymobiledevice3")
        sys.exit(1)

# ── 获取设备连接 ──────────────────────────────────────────────────────────────
def get_lockdown():
    """
    创建 LockdownClient 连接。
    
    技术说明：
      LockdownClient 通过 USB 连接到 iOS 设备的 /var/run/lockdownd.sock
      （设备端）和主机端的 usbmuxd（USB 多路复用守护进程）。
      不受 MDM App 安装限制影响。
    """
    from pymobiledevice3.lockdown import create_using_usbmux
    try:
        lockdown = create_using_usbmux()
        return lockdown
    except Exception as e:
        err(f"无法连接设备: {e}")
        print()
        print("  请检查：")
        print("  1. USB 数据线已连接（非纯充电线）")
        print("  2. 设备已解锁")
        print("  3. 设备弹出「信任此电脑？」后已点击「信任」")
        print("  4. 若首次连接，设备输入密码后重试")
        sys.exit(1)


# ── 方法 A：AfcService 读写（基础方式，对非沙盒路径权限有限）──────────────────
def get_afc(lockdown):
    """
    AFC = Apple File Conduit，iOS 文件访问协议。
    
    学习要点：
      - AFC 服务由 lockdownd 的 com.apple.afc 端点提供
      - 默认 AFC 只能访问 /var/mobile/Media（相册/文件共享目录）
      - house_arrest AFC 可访问特定 App 的沙盒目录
      - 对系统路径（/private/var/containers）权限不足
    """
    from pymobiledevice3.services.afc import AfcService
    return AfcService(lockdown=lockdown)


# ── 方法 B：FileRelay（旧版系统路径访问，已在新版 iOS 禁用）──────────────────
# 仅作学习记录，现代 iOS 已不可用


# ── 方法 C：通过 instproxy 安装 IPA ──────────────────────────────────────────
def install_ipa_via_instproxy(lockdown, ipa_path: Path):
    """
    通过 instproxy（Installation Proxy）安装 IPA。
    
    学习要点：
      instproxy 是 iOS App 安装服务，Xcode 使用的就是这个通道。
      MDM 的 allowAppInstallation 在某些版本会影响此服务，
      但通过 Xcode/DeveloperImage 通道注入的安装请求通常可绕过。
      
      关键：需要设备开启「开发者模式」或挂载 DeveloperDiskImage。
    """
    from pymobiledevice3.services.installation_proxy import InstallationProxyService
    from pymobiledevice3.services.afc import AfcService
    import zipfile

    info(f"准备安装: {ipa_path.name}")

    # 1. 将 IPA 上传到设备的 /PublicStaging/ 目录
    afc = AfcService(lockdown=lockdown)
    staging_path = f"/PublicStaging/{ipa_path.stem}"

    info("上传 IPA 到设备暂存目录 /PublicStaging/ ...")
    try:
        afc.makedirs(staging_path)
        # 上传 IPA 内容
        with ipa_path.open("rb") as f:
            ipa_data = f.read()
        with afc.open(f"{staging_path}/mond.ipa", "wb") as remote:
            remote.write(ipa_data)
        ok(f"IPA 已上传到设备: {staging_path}/mond.ipa")
    except Exception as e:
        err(f"上传失败: {e}")
        warn("AFC 可能无法写入 PublicStaging，尝试使用 instproxy 直接安装...")

    # 2. 调用 instproxy 安装
    info("调用 InstallationProxy 安装 App...")
    try:
        with InstallationProxyService(lockdown=lockdown) as svc:
            svc.install_from_local(ipa_path)
        ok("安装成功！请在设备上信任开发者证书（如果提示）。")
        info("信任路径：设置 → 通用 → VPN 与设备管理 → 开发者 App → 信任")
    except Exception as e:
        err(f"安装失败: {e}")
        warn("提示：MDM 可能拦截了安装请求。请先用 neuter 命令绕过 MDM。")
        warn("如果设备未开启开发者模式，instproxy 也可能被拦截。")


# ── 方法 D：通过 pymobiledevice3 的 tunnel/debugserver 注入 ──────────────────
def try_read_mdm_via_crash_reports(lockdown):
    """
    尝试通过 CrashReportMover 服务读取系统路径。
    
    学习要点：
      com.apple.crashreportmover 服务有更高的系统权限。
      部分 iOS 版本中，通过特定路径遍历可访问系统目录。
      这是研究性技术，现代 iOS 已经修补。
    """
    from pymobiledevice3.services.crash_reports import CrashReportsManager
    try:
        mgr = CrashReportsManager(lockdown=lockdown)
        # 尝试列出目录
        files = mgr.ls("/")
        return files
    except Exception as e:
        return None


# ── 实际可行：通过 pymobiledevice3 的 RemoteXPC / DeveloperModeService ────────
def try_developer_mode_write(lockdown, file_path: str, data: bytes) -> bool:
    """
    尝试通过开发者服务写入文件。
    
    学习要点：
      pymobiledevice3 实现了多种 iOS 内部服务协议。
      DvtSecureSocketProxy、RemoteXPC 等服务在开发者模式下
      具有比 AFC 更高的系统访问权限。
    """
    try:
        # 尝试使用 DVT 文件系统代理（需要设备处于开发者模式）
        from pymobiledevice3.services.dvt.dvt_secure_socket_proxy import DvtSecureSocketProxyService
        from pymobiledevice3.services.dvt.instruments.file_manager import FileManagerService
        
        with DvtSecureSocketProxyService(lockdown=lockdown) as dvt:
            with FileManagerService(dvt) as fm:
                fm.write_file(file_path, data)
                return True
    except Exception as e:
        return False


# ── 命令实现 ──────────────────────────────────────────────────────────────────

def cmd_info(lockdown):
    """显示设备 MDM 监管状态及技术信息"""
    print()
    print("=" * 60)
    print("  设备信息与 MDM 状态")
    print("=" * 60)

    # lockdown 提供设备基础信息
    all_values = lockdown.all_values
    
    print(f"\n  设备名称:    {all_values.get('DeviceName', '未知')}")
    print(f"  型号标识:    {all_values.get('ProductType', '未知')}")
    print(f"  iOS 版本:    {all_values.get('ProductVersion', '未知')}")
    print(f"  内部版本号:  {all_values.get('BuildVersion', '未知')}")
    print(f"  序列号:      {all_values.get('SerialNumber', '未知')}")
    print(f"  UDID:        {all_values.get('UniqueDeviceID', '未知')}")
    
    supervised = all_values.get("IsSupervised", False)
    print(f"\n  MDM 监管:    {'✅ 受监管 (Supervised)' if supervised else '❌ 未监管'}")
    
    if supervised:
        org = all_values.get("OrganizationInfo", {})
        warn(f"监管组织: {org}")
        warn("设备可能受以下限制：allowAppInstallation / allowDeveloperMode / allowEnterpriseAppTrust")
    
    # 获取 MDM 策略（如果可以读取）
    try:
        mc_restrictions = lockdown.get_value("com.apple.mobile.restrictions", None)
        if mc_restrictions:
            info(f"MCM 限制策略: {mc_restrictions}")
    except Exception:
        pass

    print()


def cmd_list(lockdown):
    """列出设备 MDM 描述文件"""
    print()
    print("=" * 60)
    print("  MDM 描述文件列表")
    print("=" * 60)
    print(f"\n  目标路径: {MDM_DIR}")
    print()

    afc = get_afc(lockdown)
    found = 0
    not_found = 0

    for fname in MDM_FILES:
        fpath = f"{MDM_DIR}/{fname}"
        try:
            stat = afc.stat(fpath)
            size = stat.get("st_size", 0)
            
            # 尝试读取并解析 plist
            try:
                with afc.open(fpath, "rb") as f:
                    data = f.read()
                plist = plistlib.loads(data)
                keys = len(plist) if isinstance(plist, dict) else "N/A"
                status = f"✅ 存在 ({size} bytes, {keys} keys)"
                if isinstance(plist, dict) and len(plist) == 0:
                    status += " [已绕过 - 空字典]"
            except Exception:
                status = f"✅ 存在 ({size} bytes)"
            found += 1
        except Exception:
            status = "❌ 不存在或无法访问"
            not_found += 1
        
        print(f"  {fname:<45s} {status}")

    print()
    print(f"  合计: {found} 存在, {not_found} 缺失/不可访问")
    
    if found == 0:
        warn("AFC 无法访问该路径。可能原因：")
        warn("1. 此路径不在 AFC 的访问范围（需要更高权限）")
        warn("2. 设备未受 MDM 监管（文件不存在）")
        info("请尝试：python mdm_bypass_pc_v2.py info 确认监管状态")
    print()


def cmd_backup(lockdown):
    """备份 MDM 描述文件到电脑"""
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = BACKUP_DIR / timestamp
    backup_path.mkdir(parents=True, exist_ok=True)

    print()
    print("=" * 60)
    print("  备份 MDM 描述文件")
    print("=" * 60)
    print(f"\n  备份路径: {backup_path.absolute()}")
    print()

    afc = get_afc(lockdown)
    backed = 0

    for fname in MDM_FILES:
        fpath = f"{MDM_DIR}/{fname}"
        local = backup_path / fname
        try:
            with afc.open(fpath, "rb") as f:
                data = f.read()
            local.write_bytes(data)
            ok(f"{fname} → 已备份 ({len(data)} bytes)")
            backed += 1
        except Exception as e:
            info(f"{fname} → 跳过 ({e})")

    print()
    if backed > 0:
        ok(f"成功备份 {backed} 个文件到: {backup_path.absolute()}")
        warn("请妥善保管备份，还原时需要使用。")
    else:
        err("未成功备份任何文件（AFC 可能权限不足）")
        warn("如果设备受 MDM 监管，AFC 通常无法直接读取 SystemGroup 路径。")
        info("建议：先使用 mond App 在设备上做备份，再通过文件共享导出。")
    print()
    return backed > 0


def cmd_neuter(lockdown):
    """将 MDM 描述文件覆写为空字典"""
    print()
    print("=" * 60)
    print("  MDM 绕过 - 覆写描述文件为空字典")
    print("=" * 60)
    print()
    warn("此操作将把 MDM 描述文件覆写为空 <dict/>")
    warn("修改后需重启设备生效")
    warn("建议先运行 backup 命令创建备份")
    print()

    confirm = input("  输入 'YES' 确认执行: ").strip()
    if confirm != "YES":
        info("已取消")
        return

    # 先自动备份
    print("\n  [自动备份] 执行操作前备份...")
    cmd_backup(lockdown)

    afc = get_afc(lockdown)
    neutered = 0
    failed = 0

    for fname in MDM_FILES:
        fpath = f"{MDM_DIR}/{fname}"
        try:
            with afc.open(fpath, "wb") as f:
                f.write(EMPTY_PLIST_XML)
            ok(f"{fname} → 已覆写为空字典")
            neutered += 1
        except Exception as e:
            err(f"{fname} → 失败: {e}")
            failed += 1

    print()
    if neutered > 0:
        ok(f"成功覆写 {neutered} 个文件")
        warn("请重启设备以使更改生效")
    
    if failed > 0:
        err(f"{failed} 个文件操作失败")
        print()
        print("  AFC 写入失败的常见原因与解决方案：")
        print()
        print("  ┌─────────────────────────────────────────────────────────┐")
        print("  │ 方案 1：pymobiledevice3 tunnel 模式（需 iOS 17+）       │")
        print("  │   sudo pymobiledevice3 remote tunnel start              │")
        print("  │   # 另一个终端：                                        │")
        print("  │   pymobiledevice3 afc shell                             │")
        print("  │   # 在 shell 中手动写入                                 │")
        print("  ├─────────────────────────────────────────────────────────┤")
        print("  │ 方案 2：通过 DeveloperDiskImage 挂载后使用 DVT 接口     │")
        print("  │   pymobiledevice3 mounter auto-mount                    │")
        print("  │   # 挂载后重试此脚本                                    │")
        print("  ├─────────────────────────────────────────────────────────┤")
        print("  │ 方案 3（推荐）：先安装 mond App 再在设备上操作          │")
        print("  │   参见：XCODE_DEPLOY_MDM_zh.md                         │")
        print("  └─────────────────────────────────────────────────────────┘")
    print()


def cmd_restore(lockdown):
    """从电脑备份还原 MDM 描述文件"""
    print()
    print("=" * 60)
    print("  还原 MDM 描述文件")
    print("=" * 60)

    if not BACKUP_DIR.exists():
        err(f"备份目录不存在: {BACKUP_DIR.absolute()}")
        info("请先执行 backup 命令")
        return

    backups = sorted(BACKUP_DIR.iterdir(), reverse=True)
    if not backups:
        err("未找到任何备份")
        return

    print("\n  可用备份：")
    for i, b in enumerate(backups):
        files = list(b.glob("*.plist"))
        print(f"    [{i}] {b.name} ({len(files)} 个文件)")

    choice = input("\n  选择备份编号（默认 0 = 最新）: ").strip()
    idx = int(choice) if choice.isdigit() else 0
    if not (0 <= idx < len(backups)):
        err("无效选择")
        return

    selected = backups[idx]
    afc = get_afc(lockdown)
    restored = 0

    for pfile in selected.glob("*.plist"):
        fpath = f"{MDM_DIR}/{pfile.name}"
        try:
            data = pfile.read_bytes()
            with afc.open(fpath, "wb") as f:
                f.write(data)
            ok(f"{pfile.name} → 已还原")
            restored += 1
        except Exception as e:
            err(f"{pfile.name} → 失败: {e}")

    if restored > 0:
        ok(f"成功还原 {restored} 个文件")
        warn("请重启设备使原 MDM 配置生效")
    print()


def cmd_install(lockdown, ipa_path: Path):
    """通过 instproxy 安装 IPA（不受 App Store 限制，但需要开发者模式）"""
    print()
    print("=" * 60)
    print("  通过 USB 安装 IPA")
    print("=" * 60)
    print()
    
    if not ipa_path.exists():
        err(f"IPA 文件不存在: {ipa_path}")
        return
    
    info(f"IPA 文件: {ipa_path} ({ipa_path.stat().st_size // 1024} KB)")
    info("正在尝试通过 instproxy 安装...")
    info("说明：此方式等同于 Xcode 安装，需要设备开启开发者模式")
    
    install_ipa_via_instproxy(lockdown, ipa_path)


# ── 主入口 ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="增强版 MDM 绕过工具（学习用途）",
        epilog="""
示例:
  python mdm_bypass_pc_v2.py info        # 查看设备 MDM 状态
  python mdm_bypass_pc_v2.py list        # 列出 MDM 描述文件
  python mdm_bypass_pc_v2.py backup      # 备份到电脑
  python mdm_bypass_pc_v2.py neuter      # 覆写为空字典（绕过）
  python mdm_bypass_pc_v2.py restore     # 从备份还原
  python mdm_bypass_pc_v2.py install --ipa mond.ipa  # 安装 IPA

注意：仅供学习 iOS 安全机制研究使用，请在自己的设备上操作。
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("action",
        choices=["info", "list", "backup", "neuter", "restore", "install"])
    parser.add_argument("--ipa", type=Path, help="install 命令使用的 IPA 文件路径")
    args = parser.parse_args()

    check_deps()
    print()
    info("正在连接设备...")
    lockdown = get_lockdown()
    ok(f"已连接: {lockdown.udid}")
    
    dispatch = {
        "info":    lambda: cmd_info(lockdown),
        "list":    lambda: cmd_list(lockdown),
        "backup":  lambda: cmd_backup(lockdown),
        "neuter":  lambda: cmd_neuter(lockdown),
        "restore": lambda: cmd_restore(lockdown),
        "install": lambda: cmd_install(lockdown, args.ipa or Path("mond.ipa")),
    }
    dispatch[args.action]()


if __name__ == "__main__":
    main()
