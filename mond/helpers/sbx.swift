//
//  sbx.swift
//  symlin4k
//
//  Created by ruter on 10.07.26.
//

import Foundation

func sandbox_extension_consume(_ token: String) -> Int64? {
    typealias sbx_consume_func = @convention(c) (UnsafePointer<CChar>?) -> Int64
    
    guard let libsys_sbx = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW) else { return nil }
    defer { dlclose(libsys_sbx) }
    
    guard let sbx_consume_sym = dlsym(libsys_sbx, "sandbox_extension_consume") else { return nil }
    let consume = unsafeBitCast(sbx_consume_sym, to: sbx_consume_func.self)
    let result = consume(token)
    
    return result
}

func sandbox_extension_issue_file(path: String) -> String? {
    typealias sbx_issue_func = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32, Int32) -> UnsafeMutablePointer<CChar>?

    guard let libsys_sbx = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW) else { return nil }
    defer { dlclose(libsys_sbx) }
    
    guard let sbx_issue_sym = dlsym(libsys_sbx, "sandbox_extension_issue_file") else { return nil }
    let issue = unsafeBitCast(sbx_issue_sym, to: sbx_issue_func.self)

    guard let ptr = issue("com.apple.app-sandbox.read-write", path, 0, 0) else { return nil }
    defer { free(ptr) }

    return String(cString: ptr)
}

@objc protocol BAAgentClientXPCProtocol {
    func markPurgeableWithFileURL(_ url: URL, sandboxToken: String, reply: @escaping (NSError?) -> Void)
}

func ba_purge_file(url: URL) -> Bool {
    guard let token = sandbox_extension_issue_file(path: url.path) else {
        print("(ba) failed to issue token for \(url.path)")
        return false
    }

    let connection = NSXPCConnection(machServiceName: "com.apple.backgroundassets.user", options: [])
    let interface = NSXPCInterface(with: BAAgentClientXPCProtocol.self)
    connection.remoteObjectInterface = interface
    connection.resume()

    let semaphore = DispatchSemaphore(value: 0)
    var success = false

    if let remote = connection.remoteObjectProxyWithErrorHandler({ error in
        print("(ba) xpc proxy error: \(error)")
        semaphore.signal()
    }) as? BAAgentClientXPCProtocol {
        remote.markPurgeableWithFileURL(url, sandboxToken: token) { error in
            if let error {
                print("(ba) markPurgeable error: \(error)")
            } else {
                print("(ba) successfully purged file via BAAgent: \(url.path)")
                success = true
            }
            semaphore.signal()
        }
    } else {
        semaphore.signal()
    }

    _ = semaphore.wait(timeout: .now() + 3.0)
    connection.invalidate()

    return success || !FileManager.default.fileExists(atPath: url.path)
}
