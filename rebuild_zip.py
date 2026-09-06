#!/usr/bin/env python3
"""
rebuild_zip.py
把 授权计算器-merged(1).zip 中的 CompanySoftware/ 替换为本地 mond/ 最新版文件，
生成新的 授权计算器-merged-v2.zip 供 GitHub Actions 构建。
"""

import zipfile, shutil, os, sys
from pathlib import Path

REPO = Path(__file__).parent
ZIP_IN  = REPO / "授权计算器-merged(1).zip"
ZIP_OUT = REPO / "授权计算器-merged-v2.zip"
MOND    = REPO / "mond"

# ── 1. 本地 mond 文件映射到 zip 内路径 ──────────────────────────────────────
# key: zip 内目标路径（相对 授权计算器-merged/授权计算器/CompanySoftware/）
# val: 本地文件路径
mond_files = {
    # helpers
    "helpers/mg.swift":          MOND / "helpers/mg.swift",
    "helpers/respring.swift":    MOND / "helpers/respring.swift",
    "helpers/sbx.swift":        MOND / "helpers/sbx.swift",
    "helpers/utils.swift":       MOND / "helpers/utils.swift",
    "helpers/jailbreak.swift":   MOND / "helpers/jailbreak.swift",
    "helpers/diagnostics.swift": MOND / "helpers/diagnostics.swift",
    "helpers/mdm.swift":         MOND / "helpers/mdm.swift",
    # exploit
    "exploit/cmg.swift":                       MOND / "exploit/cmg.swift",
    "exploit/bad_query/bad_query.c":            MOND / "exploit/bad_query/bad_query.c",
    "exploit/bad_query/bad_query.h":            MOND / "exploit/bad_query/bad_query.h",
    # views – 用本地最新版替换
    "views/CompanyRootView.swift":  MOND / "views/ContentView.swift",   # 重命名
    "views/FileBrowserView.swift":  MOND / "views/FileBrowserView.swift",
    "views/LogView.swift":          MOND / "views/LogView.swift",
    "views/SettingsView.swift":     MOND / "views/SettingsView.swift",
    # bridging header – mond 自带的
    "bridging.h": MOND / "bridging.h",
}

# CompanySoftwareEntry.swift – 生成新版入口适配器
ENTRY_CONTENT = r'''//
//  CompanySoftwareEntry.swift
//  授权计算器 (CompanySoftwareKit)
//
//  入口适配器：把本地最新版 mond ContentView 以 CompanySoftwareEntry 形式暴露给宿主 App。
//  授权验证通过后，宿主 App 通过 CompanySoftwareEntry(onBack:) 进入本界面。
//

import SwiftUI
import PartyUI
import Foundation
import Darwin

// ── 全局变量（mond.swift 中原有，此处移植） ──────────────────────────────────
var pipe = Pipe()
var sema = DispatchSemaphore(value: 0)
var fm = FileManager.default

var path: String {
    let url = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("test.txt")
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }
    return url.path
}

// ── 公开入口（宿主 App 使用此类型） ──────────────────────────────────────────
/// 宿主 App 在授权验证成功后通过该类型嵌入 mond 文件管理主界面。
@MainActor
public struct CompanySoftwareEntry: View {
    private let onBack: () -> Void

    public init(onBack: @escaping () -> Void) {
        self.onBack = onBack
    }

    public var body: some View {
        AnyView(CompanySoftwareRoot(onBack: onBack))
    }
}

// ── 实际根视图（内部实现） ────────────────────────────────────────────────────
private struct CompanySoftwareRoot: View {
    @StateObject private var state = AppState()
    let onBack: () -> Void

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        UserDefaults.standard.register(defaults: ["exploit_method": "bad_query"])
        if !is_debugged() {
            setvbuf(stdout, nil, _IONBF, 0)
            dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        }
    }

    var body: some View {
        // CompanyRootView 即本地 mond ContentView（已重命名）
        CompanyRootView(onBack: onBack)
            .environmentObject(state)
            .onAppear {
                if !is_supported() {
                    Alertinator.shared.alert(
                        title: "当前系统可能不受支持",
                        body: "mond 支持 iOS 16.0 – 27.x。"
                    )
                }
            }
            .overlay {
                if state.show_respring {
                    RespringView()
                        .brightness(-1.0)
                        .ignoresSafeArea()
                        .onAppear {
                            print("(respring) respringing now...")
                        }
                }
            }
    }
}
'''

# ── 2. 更新后的 project.pbxproj ───────────────────────────────────────────────
# 新增文件的引用和 Sources Build Phase 条目
NEW_FILE_REFS = '''
\t\tBE0000000000000000000001 /* helpers/jailbreak.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = helpers/jailbreak.swift; sourceTree = "<group>"; };
\t\tBE0000000000000000000002 /* helpers/diagnostics.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = helpers/diagnostics.swift; sourceTree = "<group>"; };
\t\tBE0000000000000000000003 /* helpers/mdm.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = helpers/mdm.swift; sourceTree = "<group>"; };
'''

NEW_BUILD_FILES = '''
\t\tBE1000000000000000000001 /* helpers/jailbreak.swift in Sources */ = {isa = PBXBuildFile; fileRef = BE0000000000000000000001 /* helpers/jailbreak.swift */; };
\t\tBE1000000000000000000002 /* helpers/diagnostics.swift in Sources */ = {isa = PBXBuildFile; fileRef = BE0000000000000000000002 /* helpers/diagnostics.swift */; };
\t\tBE1000000000000000000003 /* helpers/mdm.swift in Sources */ = {isa = PBXBuildFile; fileRef = BE0000000000000000000003 /* helpers/mdm.swift */; };
'''

# 在 PBXGroup for CompanySoftwareKit 中添加 children
NEW_GROUP_CHILDREN = '''\t\t\t\tBE0000000000000000000001 /* helpers/jailbreak.swift */,
\t\t\t\tBE0000000000000000000002 /* helpers/diagnostics.swift */,
\t\t\t\tBE0000000000000000000003 /* helpers/mdm.swift */,
'''

# 在 Sources Build Phase for CompanySoftwareKit 中添加 files
NEW_SOURCES = '''\t\t\t\tBE1000000000000000000001 /* helpers/jailbreak.swift in Sources */,
\t\t\t\tBE1000000000000000000002 /* helpers/diagnostics.swift in Sources */,
\t\t\t\tBE1000000000000000000003 /* helpers/mdm.swift in Sources */,
'''


def patch_pbxproj(content: str) -> str:
    """Add new file refs, build files, group children, and source build phase entries."""
    import re

    # 1. Add file references
    marker = "/* End PBXFileReference section */"
    content = content.replace(marker, NEW_FILE_REFS + "\t" + marker)

    # 2. Add build files
    marker2 = "/* End PBXBuildFile section */"
    content = content.replace(marker2, NEW_BUILD_FILES + "\t" + marker2)

    # 3. Add to PBXGroup (CompanySoftwareKit group children)
    # Insert before B30000000000000000000013 /* bridging.h */
    content = content.replace(
        "\t\t\t\tB30000000000000000000013 /* bridging.h */,",
        NEW_GROUP_CHILDREN + "\t\t\t\tB30000000000000000000013 /* bridging.h */,"
    )

    # 4. Add to Sources build phase for CompanySoftwareKit
    # Insert after last existing source entry: B40000000000000000000011 /* exploit/bad_query/bad_query.c in Sources */,
    content = content.replace(
        "\t\t\t\tB40000000000000000000011 /* exploit/bad_query/bad_query.c in Sources */,",
        "\t\t\t\tB40000000000000000000011 /* exploit/bad_query/bad_query.c in Sources */,\n" + NEW_SOURCES
    )

    return content


def patch_root_view(content: str) -> str:
    """
    CompanyRootView.swift 是从 mond ContentView.swift 复制而来。
    需要把 'struct ContentView' 改为 'struct CompanyRootView'，
    并添加 onBack 回调参数（紧跟在第一个 @EnvironmentObject / @AppStorage 声明之前）。
    """
    # 重命名主 struct
    content = content.replace(
        "struct ContentView: View {",
        "struct CompanyRootView: View {"
    )
    # 在 struct 开头第一行属性之前插入 onBack
    # 找到 struct 声明后的第一个属性行（@EnvironmentObject 或 @AppStorage 开头）
    lines = content.splitlines(keepends=True)
    out = []
    in_struct = False
    onback_inserted = False
    for line in lines:
        if "struct CompanyRootView: View {" in line:
            in_struct = True
            out.append(line)
            continue
        if in_struct and not onback_inserted and line.strip().startswith(("@EnvironmentObject", "@AppStorage", "@State", "@Environment")):
            # Insert onBack before the first property
            out.append("    var onBack: (() -> Void)? = nil\n")
            onback_inserted = True
        out.append(line)
    return "".join(out)


def main():
    print(f"Reading: {ZIP_IN}")
    assert ZIP_IN.exists(), f"ZIP not found: {ZIP_IN}"

    with zipfile.ZipFile(ZIP_IN, 'r') as zin, \
         zipfile.ZipFile(ZIP_OUT, 'w', compression=zipfile.ZIP_DEFLATED) as zout:

        # Files to skip (will be replaced)
        COMPANY_PREFIX = "授权计算器-merged/授权计算器/CompanySoftware/"
        replace_keys = set(mond_files.keys()) | {"CompanySoftwareEntry.swift"}

        written_inner = set()

        for item in zin.infolist():
            name = item.filename

            # ── project.pbxproj: patch in-place ──────────────────────────────
            if name == "授权计算器-merged/授权计算器.xcodeproj/project.pbxproj":
                raw = zin.read(name).decode('utf-8')
                patched = patch_pbxproj(raw)
                zout.writestr(item, patched.encode('utf-8'))
                print(f"  patched: {name}")
                continue

            # ── CompanySoftware files: skip if being replaced ─────────────────
            if name.startswith(COMPANY_PREFIX):
                inner = name[len(COMPANY_PREFIX):]
                if inner in replace_keys or inner == "":
                    continue  # will write fresh below
                # keep any other file as-is
                zout.writestr(item, zin.read(name))
                continue

            # All other files: copy as-is
            zout.writestr(item, zin.read(name))

        # ── Write CompanySoftwareEntry.swift ─────────────────────────────────
        entry_path = COMPANY_PREFIX + "CompanySoftwareEntry.swift"
        zout.writestr(entry_path, ENTRY_CONTENT.encode('utf-8'))
        print(f"  wrote: {entry_path}")

        # ── Write all mond replacement files ─────────────────────────────────
        for inner_path, local_path in mond_files.items():
            zip_path = COMPANY_PREFIX + inner_path
            assert local_path.exists(), f"Local file missing: {local_path}"
            content = local_path.read_bytes()

            # Special handling for CompanyRootView.swift (from ContentView.swift)
            if inner_path == "views/CompanyRootView.swift":
                text = content.decode('utf-8')
                text = patch_root_view(text)
                content = text.encode('utf-8')

            zout.writestr(zip_path, content)
            print(f"  wrote: {zip_path} ({len(content):,} bytes)")

    print(f"\nDone. Output: {ZIP_OUT}")


if __name__ == "__main__":
    main()
