//
//  jailbreak.swift
//  mond
//
//  Runtime jailbreak detection and sandbox escape.
//  Supports Dopamine, palera1n, Def1nit3lyN0tAJworB, and generic rootless/rootful jailbreaks.
//

import Foundation
import Darwin

/// Try to dynamically unsandbox the current process using jailbreak APIs.
/// Returns a string describing the method that succeeded, or nil if all failed.
func jailbreak_unsandbox() -> String? {
    // ── Method 1: Dopamine / ElleKit jailbreaks ──────────────────────────────
    // Dopamine 2.x provides libjailbreak.dylib with jbclient_process_unsandbox
    let dopaminePaths = [
        "/var/jb/usr/lib/libjailbreak.dylib",
        "/var/jb/basebin/libjailbreak.dylib",
        "/usr/lib/libjailbreak.dylib"
    ]
    for libPath in dopaminePaths {
        if let lib = dlopen(libPath, RTLD_NOW) {
            // Try jbclient_process_unsandbox (Dopamine 2.x)
            if let sym = dlsym(lib, "jbclient_process_unsandbox") {
                typealias unsandbox_fn = @convention(c) () -> Int32
                let unsandbox = unsafeBitCast(sym, to: unsandbox_fn.self)
                let ret = unsandbox()
                if ret == 0 {
                    print("(jb) jbclient_process_unsandbox succeeded via \(libPath)")
                    return "dopamine-unsandbox"
                }
                print("(jb) jbclient_process_unsandbox returned \(ret)")
            }

            // Try jbdProcessUnsandbox (older Dopamine)
            if let sym = dlsym(lib, "jbdProcessUnsandbox") {
                typealias unsandbox_fn = @convention(c) (pid_t) -> Int32
                let unsandbox = unsafeBitCast(sym, to: unsandbox_fn.self)
                let ret = unsandbox(getpid())
                if ret == 0 {
                    print("(jb) jbdProcessUnsandbox succeeded via \(libPath)")
                    return "jbd-unsandbox"
                }
                print("(jb) jbdProcessUnsandbox returned \(ret)")
            }

            dlclose(lib)
        }
    }

    // ── Method 2: palera1n / Def1nit3lyN0tAJworB ─────────────────────────────
    // palera1n uses jailbreakd XPC service
    let paleraLibPaths = [
        "/usr/lib/libjailbreak.dylib",
        "/var/jb/usr/lib/libjailbreak.dylib"
    ]
    for libPath in paleraLibPaths {
        if let lib = dlopen(libPath, RTLD_NOW) {
            // Try jbclient_platform_set_process_debugged (removes sandbox restrictions)
            if let sym = dlsym(lib, "jbclient_platform_set_process_debugged") {
                typealias debug_fn = @convention(c) (pid_t) -> Int32
                let setDebug = unsafeBitCast(sym, to: debug_fn.self)
                let ret = setDebug(getpid())
                if ret == 0 {
                    print("(jb) jbclient_platform_set_process_debugged succeeded")
                    return "palera-debugged"
                }
            }

            // Try jbclient_entitle_now (adds entitlements at runtime)
            if let sym = dlsym(lib, "jbclient_entitle_now") {
                typealias entitle_fn = @convention(c) (pid_t, UnsafePointer<CChar>) -> Int32
                let entitle = unsafeBitCast(sym, to: entitle_fn.self)
                let ret = "com.apple.private.security.no-sandbox".withCString {
                    entitle(getpid(), $0)
                }
                if ret == 0 {
                    print("(jb) jbclient_entitle_now(no-sandbox) succeeded")
                    return "palera-entitle"
                }
            }

            dlclose(lib)
        }
    }

    // ── Method 3: Generic setuid(0) ──────────────────────────────────────────
    // Some jailbreaks (rootful) patch setuid to allow any process to escalate
    let origUID = getuid()
    if Darwin.setuid(0) == 0 {
        print("(jb) setuid(0) succeeded (was uid=\(origUID))")
        // Restore if needed for file ownership
        return "setuid-root"
    }

    // ── Method 4: sandbox_apply with null profile ────────────────────────────
    // Try to load a permissive sandbox profile
    if let libsbx = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW) {
        // sandbox_init with no-internet profile (least restrictive built-in)
        if dlsym(libsbx, "sandbox_free_error") != nil {
            print("(jb) sandbox_free_error found but cannot remove sandbox at runtime")
        }
        dlclose(libsbx)
    }

    print("(jb) all unsandbox methods failed")
    return nil
}

/// Check if a jailbreak environment is detected.
func is_jailbroken() -> Bool {
    let indicators = [
        "/var/jb",
        "/var/jb/usr/bin/sh",
        "/usr/bin/dpkg",
        "/var/jb/usr/bin/dpkg",
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/var/jb/Applications/Sileo.app",
        "/private/etc/apt",
        "/var/jb/etc/apt",
        "/usr/lib/libjailbreak.dylib",
        "/var/jb/usr/lib/libjailbreak.dylib"
    ]
    for path in indicators {
        if FileManager.default.fileExists(atPath: path) {
            return true
        }
    }
    // Check if we can access typical jailbreak-only paths via opendir
    // (fork() is unavailable on iOS)
    if let dir = opendir("/var/jb") {
        closedir(dir)
        return true
    }
    return false
}
