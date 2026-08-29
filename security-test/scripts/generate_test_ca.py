#!/usr/bin/env python3
"""
generate_test_ca.py — 为安全测试生成自签名 CA 证书

用法：
  python3 generate_test_ca.py

输出：
  test-ca.key    - 私钥（保管好，用于签发企业证书）
  test-ca.crt    - CA 证书 PEM 格式
  test-ca.der    - CA 证书 DER 格式
  test-ca.b64    - CA 证书 Base64（填入 mobileconfig）
  test-enterprise.crt/.key  - 用 CA 签发的企业证书

安全说明：仅用于自己设备的 MDM 安全测试，不用于任何生产环境。
"""

import subprocess
import base64
import os
import json
from pathlib import Path
from datetime import datetime

OUTPUT_DIR = Path("generated-certs")
OUTPUT_DIR.mkdir(exist_ok=True)

def run(cmd, check=True):
    print(f"  $ {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"  错误: {result.stderr}")
        raise RuntimeError(f"命令失败: {' '.join(cmd)}")
    return result

def generate_test_ca():
    """生成测试 CA 根证书"""
    print("\n[1/4] 生成测试 CA 私钥...")
    run(["openssl", "genrsa", "-out", str(OUTPUT_DIR / "test-ca.key"), "2048"])

    print("[2/4] 生成测试 CA 自签名证书（有效期 30 天）...")
    run([
        "openssl", "req", "-new", "-x509",
        "-key", str(OUTPUT_DIR / "test-ca.key"),
        "-out", str(OUTPUT_DIR / "test-ca.crt"),
        "-days", "30",
        "-subj", "/CN=MDM Security Test CA/O=Security Research/C=CN",
        "-extensions", "v3_ca",
    ])

    print("[3/4] 转换为 DER 格式...")
    run([
        "openssl", "x509",
        "-in", str(OUTPUT_DIR / "test-ca.crt"),
        "-outform", "DER",
        "-out", str(OUTPUT_DIR / "test-ca.der"),
    ])

    print("[4/4] 生成 Base64 编码（用于 mobileconfig）...")
    der_data = (OUTPUT_DIR / "test-ca.der").read_bytes()
    b64_data = base64.b64encode(der_data).decode()
    (OUTPUT_DIR / "test-ca.b64").write_text(b64_data)

    return b64_data


def generate_enterprise_cert(ca_key_path, ca_cert_path):
    """用测试 CA 签发企业证书（模拟企业分发签名）"""
    print("\n[1/3] 生成企业证书私钥...")
    run(["openssl", "genrsa", "-out", str(OUTPUT_DIR / "enterprise.key"), "2048"])

    print("[2/3] 生成企业证书签名请求...")
    run([
        "openssl", "req", "-new",
        "-key", str(OUTPUT_DIR / "enterprise.key"),
        "-out", str(OUTPUT_DIR / "enterprise.csr"),
        "-subj", "/CN=MDM Security Test Enterprise/O=Security Research/C=CN",
    ])

    print("[3/3] 用 CA 签发企业证书...")
    run([
        "openssl", "x509", "-req",
        "-in", str(OUTPUT_DIR / "enterprise.csr"),
        "-CA", str(ca_cert_path),
        "-CAkey", str(ca_key_path),
        "-CAcreateserial",
        "-out", str(OUTPUT_DIR / "enterprise.crt"),
        "-days", "30",
    ])


def update_mobileconfig(ca_b64):
    """将 CA Base64 注入到测试 mobileconfig"""
    profile_path = Path("profiles/test-a2-ca.mobileconfig")
    if not profile_path.exists():
        print(f"  警告: {profile_path} 不存在，跳过更新")
        return

    content = profile_path.read_text()
    content = content.replace(
        "PLACEHOLDER_REPLACE_WITH_YOUR_TEST_CA_BASE64",
        ca_b64
    )
    profile_path.write_text(content)
    print(f"  ✅ 已更新: {profile_path}")


def generate_ota_signing():
    """
    生成用于 OTA 分发的签名环境
    理论上：用企业证书签名 IPA → 通过 itms-services:// 分发
    """
    print("\n生成 OTA 签名证书...")
    # 实际 OTA 分发需要 Apple 颁发的企业开发者证书
    # 这里生成自签名版本用于测试 OTA 通道是否被检查签名
    
    p12_pass = "security-test-2026"
    
    # 合并证书和私钥为 .p12 格式
    run([
        "openssl", "pkcs12", "-export",
        "-in", str(OUTPUT_DIR / "enterprise.crt"),
        "-inkey", str(OUTPUT_DIR / "enterprise.key"),
        "-out", str(OUTPUT_DIR / "enterprise.p12"),
        "-passout", f"pass:{p12_pass}",
        "-name", "MDM Security Test Enterprise Cert",
    ])
    
    print(f"  ✅ P12 证书: {OUTPUT_DIR}/enterprise.p12")
    print(f"  🔑 P12 密码: {p12_pass}")
    return p12_pass


def generate_manifest_plist(ipa_url):
    """生成 OTA manifest.plist"""
    manifest = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key>
          <string>software-package</string>
          <key>url</key>
          <string>{ipa_url}</string>
        </dict>
        <dict>
          <key>kind</key>
          <string>display-image</string>
          <key>url</key>
          <string>https://your-server.com/icon-57x57.png</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key>
        <string>com.security.test.app</string>
        <key>bundle-version</key>
        <string>1.0.0</string>
        <key>kind</key>
        <string>software</string>
        <key>title</key>
        <string>Security Test App</string>
        <key>subtitle</key>
        <string>MDM Security Research</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>'''.format(ipa_url=ipa_url)
    
    Path("ota/manifest.plist").write_text(manifest)
    print(f"  ✅ OTA manifest 已生成: ota/manifest.plist")
    print(f"  🔗 OTA URL: itms-services://?action=download-manifest&url=你的服务器/ota/manifest.plist")


def print_summary(ca_b64):
    """打印测试摘要"""
    print("\n" + "="*60)
    print("  测试证书生成完成")
    print("="*60)
    print(f"\n  输出目录: {OUTPUT_DIR.absolute()}")
    print(f"\n  文件清单:")
    for f in OUTPUT_DIR.iterdir():
        size = f.stat().st_size
        print(f"    {f.name:<30} {size:>8} bytes")
    
    print(f"\n  CA 证书 Base64 (前64字符):")
    print(f"    {ca_b64[:64]}...")
    
    print(f"\n  ★ 下一步操作:")
    print(f"  1. 部署到 HTTPS 服务器（GitHub Pages 推荐）")
    print(f"  2. 设备访问: https://你的域名/security-test/")
    print(f"  3. 点击测试按钮，观察系统响应")
    print(f"  4. 记录结果到安全报告")
    
    print(f"\n  ⚠️  安全提示:")
    print(f"  - 测试完成后删除所有生成的证书")
    print(f"  - 不要将 CA 私钥上传到公开 Git 仓库")
    print(f"  - 仅在自己的设备上测试")


if __name__ == "__main__":
    print("=" * 60)
    print("  MDM 安全测试 - 测试证书生成工具")
    print("  仅供安全研究，在自己的设备上使用")
    print("=" * 60)
    
    # 检查 openssl 是否可用
    try:
        result = run(["openssl", "version"], check=False)
        print(f"\n  OpenSSL: {result.stdout.strip()}")
    except FileNotFoundError:
        print("  ❌ 错误: openssl 未安装")
        print("  安装方法: brew install openssl  或  apt install openssl")
        exit(1)
    
    print("\n[阶段 1] 生成测试 CA 根证书")
    ca_b64 = generate_test_ca()
    
    print("\n[阶段 2] 生成企业分发证书（CA 签发）")
    generate_enterprise_cert(
        OUTPUT_DIR / "test-ca.key",
        OUTPUT_DIR / "test-ca.crt"
    )
    
    print("\n[阶段 3] 更新测试描述文件")
    update_mobileconfig(ca_b64)
    
    print("\n[阶段 4] 生成 P12 证书包（OTA 签名用）")
    try:
        p12_pass = generate_ota_signing()
    except Exception as e:
        print(f"  跳过 P12 生成: {e}")
    
    print("\n[阶段 5] 生成 OTA manifest")
    generate_manifest_plist("https://YOUR-SERVER/security-test/ota/test-dummy.ipa")
    
    print_summary(ca_b64)
