#!/usr/bin/env python3
"""
patch_passphrase.py
在 授权计算器-merged-v2.zip 的 AuthorizationService.swift 中插入本地通行码，
生成 授权计算器-merged-v3.zip。
"""
import zipfile, sys
from pathlib import Path

REPO = Path(__file__).parent
ZIP_IN  = REPO / "授权计算器-merged-v2.zip"
ZIP_OUT = REPO / "授权计算器-merged-v3.zip"
PASSPHRASE = "19990513"

TARGET = "        isVerifying = true\n        defer { isVerifying = false }"

BYPASS = (
    "        // Local passphrase – no network needed\n"
    "        if trimmed == \"" + PASSPHRASE + "\" {\n"
    "            isAuthorized = true\n"
    "            statusText = \"本地授权成功\"\n"
    "            return true\n"
    "        }\n\n"
)

with zipfile.ZipFile(ZIP_IN, "r") as zin, \
     zipfile.ZipFile(ZIP_OUT, "w", zipfile.ZIP_DEFLATED) as zout:
    for item in zin.infolist():
        data = zin.read(item.filename)
        if "AuthorizationService.swift" in item.filename:
            text = data.decode("utf-8")
            assert TARGET in text, f"Pattern not found in {item.filename}"
            text = text.replace(TARGET, BYPASS + TARGET, 1)
            data = text.encode("utf-8")
            print(f"Patched: {item.filename}")
        zout.writestr(item, data)

print(f"Done: {ZIP_OUT}")
