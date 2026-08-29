#!/usr/bin/env python3
"""
mdm_bypass_pc.py — 电脑端 MDM 描述文件操作脚本（免安装 App）

适用场景：
  MDM 监管设备的 allowAppInstallation 被禁用，且开发者模式也无法开启，
  无法安装任何 App（包括 mond）。此脚本通过 pymobiledevice3 在电脑端
  直接操作设备的 MDM 描述文件。

原理：
  pymobiledevice3 通过 USB lockdownd 服务与设备通信，使用 AFC / 
  DeveloperDiskImage / Crash Report 等系统服务读写设备文件。
  这些服务是系统级的，不受 MDM 的 App 安装限制影响。

前置条件：
  1. Python 3.9+
  2. pip install pymobiledevice3
  3. USB 数据线连接设备
  4. 设备已信任此电脑

免责声明：
  仅供个人学习 iOS 安全机制使用。请仅在你个人拥有的设备上操作。

用法：
  python mdm_bypass_pc.py --action list       # 列出 MDM 描述文件
  python mdm_bypass_pc.py --action backup      # 备份 MDM 描述文件到电脑
  python mdm_bypass_pc.py --action neuter      # 将 MDM 描述文件覆写为空字典
  python mdm_bypass_pc.py --action restore     # 从电脑端备份还原 MDM 描述文件
  python mdm_bypass_pc.py --action info        # 显示设备 MDM 监管状态
"""

import argparse
import datetime
import os
import plistlib
import shutil
import subprocess
import sys
import time
from pathlib import Path

# ─── 常量 ────────────────────────────────────────────────────────────────────

MDM_PROFILE_DIR = (
    "/private/var/containers/Shared/SystemGroup/"
    "systemgroup.com.apple.configurationprofiles/"
    "Library/ConfigurationProfiles"
)

KNOWN_MDM_FILES = [
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

EMPTY_PLIST = b"""\
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
"""

BACKUP_DIR = Path("mdm_backups")

# ─── 帮助工具 ────────────────────────────────────────────────────────────────


def check_pymobiledevice3():
    """检查 pymobiledevice3 是否已安装。"""
    try:
        import pymobiledevice3  # noqa: F401

        return True
    except ImportError:
        return False


def run_cmd(args: list[str], check: bool = True, capture: bool = True) -> str:
    """运行命令并返回 stdout。"""
    try:
        result = subprocess.run(
            args,
            check=check,
            capture_output=capture,
            text=True,
            timeout=30,
        )
        return result.stdout.strip() if capture else ""
    except subprocess.CalledProcessError as e:
        print(f"[!] 命令执行失败: {' '.join(args)}")
        if e.stderr:
            print(f"    stderr: {e.stderr.strip()}")
        raise
    except subprocess.TimeoutExpired:
        print(f"[!] 命令超时: {' '.join(args)}")
        raise


def pymobiledevice3_cmd(subcmd: list[str]) -> str:
    """构建并执行 pymobiledevice3 CLI 命令。"""
    return run_cmd([sys.executable, "-m", "pymobiledevice3"] + subcmd)


def get_device_info() -> dict:
    """获取设备基本信息。"""
    info = {}
    try:
        output = pymobiledevice3_cmd(["lockdown", "info"])
        for line in output.splitlines():
            if ":" in line:
                key, _, value = line.partition(":")
                info[key.strip()] = value.strip()
    except Exception:
        pass
    return info


# ─── 操作函数 ────────────────────────────────────────────────────────────────


def action_info():
    """显示设备 MDM 监管状态。"""
    print("=" * 60)
    print("  设备 MDM 监管状态查询")
    print("=" * 60)

    info = get_device_info()
    if not info:
        print("[!] 无法连接设备。请确认：")
        print("    1. USB 线已连接")
        print("    2. 设备已解锁")
        print("    3. 已点击'信任此电脑'")
        return False

    print(f"  设备名称: {info.get('DeviceName', '未知')}")
    print(f"  型号:     {info.get('ProductType', '未知')}")
    print(f"  iOS 版本: {info.get('ProductVersion', '未知')}")
    print(f"  序列号:   {info.get('SerialNumber', '未知')}")

    is_supervised = info.get("IsSupervised", "false").lower() == "true"
    print(f"\n  监管状态: {'✅ 受监管 (Supervised)' if is_supervised else '❌ 未监管'}")

    if is_supervised:
        org = info.get("OrganizationInfo", "未知")
        print(f"  监管组织: {org}")
        print("\n  [提示] 设备处于监管状态，MDM 限制可能包括：")
        print("         - 禁止安装 App (allowAppInstallation)")
        print("         - 禁止删除 App (allowAppRemoval)")
        print("         - 禁止开发者模式 (allowDeveloperMode)")

    return True


def action_list():
    """列出设备上的 MDM 描述文件。"""
    print("=" * 60)
    print("  MDM 描述文件列表")
    print("=" * 60)
    print(f"  目标目录: {MDM_PROFILE_DIR}")
    print()

    found = 0
    not_found = 0

    for filename in KNOWN_MDM_FILES:
        filepath = f"{MDM_PROFILE_DIR}/{filename}"
        try:
            # 尝试通过 AFC 或 lockdown 读取文件
            output = pymobiledevice3_cmd(
                ["afc", "cat", filepath]
            )
            size = len(output.encode("utf-8", errors="replace"))
            # 尝试解析 plist 内容
            try:
                plist_data = plistlib.loads(output.encode("utf-8"))
                key_count = len(plist_data) if isinstance(plist_data, dict) else "N/A"
                status = f"✅ 存在 ({size} bytes, {key_count} keys)"
                if isinstance(plist_data, dict) and len(plist_data) == 0:
                    status += " [空字典 - 已绕过]"
            except Exception:
                status = f"✅ 存在 ({size} bytes, 格式未知)"
            found += 1
        except Exception:
            status = "❌ 不存在或无法访问"
            not_found += 1

        print(f"  {filename:45s} {status}")

    print()
    print(f"  共计: {found} 个文件存在, {not_found} 个文件缺失")

    if found == 0 and not_found == len(KNOWN_MDM_FILES):
        print("\n  [提示] 未检测到任何 MDM 描述文件，设备可能未加入 MDM 监管。")


def action_backup():
    """备份 MDM 描述文件到电脑。"""
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = BACKUP_DIR / timestamp
    backup_path.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("  备份 MDM 描述文件")
    print("=" * 60)
    print(f"  备份目录: {backup_path.absolute()}")
    print()

    backed_up = 0
    for filename in KNOWN_MDM_FILES:
        filepath = f"{MDM_PROFILE_DIR}/{filename}"
        local_path = backup_path / filename
        try:
            output = pymobiledevice3_cmd(["afc", "cat", filepath])
            local_path.write_text(output, encoding="utf-8")
            print(f"  ✅ {filename} → 已备份")
            backed_up += 1
        except Exception:
            print(f"  ⏭️  {filename} → 跳过 (不存在或无法访问)")

    print()
    if backed_up > 0:
        print(f"  成功备份 {backed_up} 个文件到: {backup_path.absolute()}")
        print("  [重要] 请妥善保管此备份，还原时需要使用。")
    else:
        print("  [!] 未备份到任何文件。")

    return backed_up > 0


def action_neuter():
    """将 MDM 描述文件覆写为空字典。"""
    print("=" * 60)
    print("  绕过 MDM 描述文件")
    print("=" * 60)
    print()
    print("  ⚠️  此操作将把所有 MDM 描述文件覆写为空 <dict/>。")
    print("  ⚠️  修改后需要 重启设备 才能生效。")
    print("  ⚠️  建议先执行 --action backup 创建安全备份。")
    print()

    confirm = input("  确认执行？输入 'YES' 继续: ").strip()
    if confirm != "YES":
        print("  已取消操作。")
        return

    # 自动先备份
    print("\n  [自动备份] 执行操作前自动创建备份...")
    action_backup()
    print()

    neutered = 0
    failed = 0

    for filename in KNOWN_MDM_FILES:
        filepath = f"{MDM_PROFILE_DIR}/{filename}"

        # 写入空 plist
        try:
            # 使用 pymobiledevice3 afc push
            import tempfile

            with tempfile.NamedTemporaryFile(
                mode="wb", suffix=".plist", delete=False
            ) as tmp:
                tmp.write(EMPTY_PLIST)
                tmp_path = tmp.name

            try:
                pymobiledevice3_cmd(["afc", "push", tmp_path, filepath])
                print(f"  ✅ {filename} → 已覆写为空字典")
                neutered += 1
            except Exception as e:
                print(f"  ❌ {filename} → 覆写失败: {e}")
                failed += 1
            finally:
                os.unlink(tmp_path)
        except Exception as e:
            print(f"  ❌ {filename} → 操作失败: {e}")
            failed += 1

    print()
    if neutered > 0:
        print(f"  成功覆写 {neutered} 个 MDM 描述文件。")
        print("  ⚠️  请 重启设备 以使更改生效！")
    if failed > 0:
        print(f"\n  [!] {failed} 个文件操作失败。")
        print("  [提示] AFC 服务可能不具备写入 SystemGroup 容器的权限。")
        print("         请尝试以下替代方案：")
        print("         1. 使用 Xcode 直连安装 mond App")
        print("         2. 使用 pymobiledevice3 developer 服务")
        print("         3. 在越狱环境下运行此脚本")


def action_restore():
    """从电脑端备份还原 MDM 描述文件。"""
    print("=" * 60)
    print("  还原 MDM 描述文件")
    print("=" * 60)

    if not BACKUP_DIR.exists():
        print(f"\n  [!] 备份目录不存在: {BACKUP_DIR.absolute()}")
        print("  请先使用 --action backup 创建备份。")
        return

    backups = sorted(BACKUP_DIR.iterdir(), reverse=True)
    if not backups:
        print("\n  [!] 未找到任何备份。")
        return

    print("\n  可用备份:")
    for i, b in enumerate(backups):
        files = list(b.glob("*.plist"))
        print(f"    [{i}] {b.name} ({len(files)} 个文件)")

    choice = input("\n  选择备份编号 (默认 0 = 最新): ").strip()
    idx = int(choice) if choice.isdigit() else 0
    if idx < 0 or idx >= len(backups):
        print("  [!] 无效选择。")
        return

    selected = backups[idx]
    print(f"\n  从 {selected.name} 还原...")

    restored = 0
    for plist_file in selected.glob("*.plist"):
        filepath = f"{MDM_PROFILE_DIR}/{plist_file.name}"
        try:
            pymobiledevice3_cmd(["afc", "push", str(plist_file), filepath])
            print(f"  ✅ {plist_file.name} → 已还原")
            restored += 1
        except Exception as e:
            print(f"  ❌ {plist_file.name} → 还原失败: {e}")

    print()
    if restored > 0:
        print(f"  成功还原 {restored} 个文件。请 重启设备 以使原配置生效。")


# ─── 入口 ────────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(
        description="MDM 监管描述文件电脑端操作工具（基于 pymobiledevice3）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
示例:
  %(prog)s --action info       查看设备监管状态
  %(prog)s --action list       列出 MDM 描述文件
  %(prog)s --action backup     备份到电脑
  %(prog)s --action neuter     覆写为空字典（绕过 MDM）
  %(prog)s --action restore    从备份还原

注意: 此脚本仅供个人学习 iOS 安全机制使用。
""",
    )
    parser.add_argument(
        "--action",
        required=True,
        choices=["info", "list", "backup", "neuter", "restore"],
        help="要执行的操作",
    )

    args = parser.parse_args()

    # 检查 pymobiledevice3
    if not check_pymobiledevice3():
        print("[!] pymobiledevice3 未安装。")
        print("    请执行: pip install pymobiledevice3")
        print("    或:     pipx install pymobiledevice3")
        sys.exit(1)

    print()
    actions = {
        "info": action_info,
        "list": action_list,
        "backup": action_backup,
        "neuter": action_neuter,
        "restore": action_restore,
    }
    actions[args.action]()
    print()


if __name__ == "__main__":
    main()
