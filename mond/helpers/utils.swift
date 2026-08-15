//
//  utils.swift
//  mond
//
//  Created by ruter on 18.07.26.
//

import Darwin
import Foundation
import UIKit

func is_debugged() -> Bool {
    var info = kinfo_proc()
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var size = MemoryLayout<kinfo_proc>.stride

    let rc = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
    if rc != 0 { return false }

    let P_TRACED: Int32 = 0x00000800
    return (info.kp_proc.p_flag & P_TRACED) != 0
}

func is_supported() -> Bool {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return v.majorVersion >= 16 && v.majorVersion <= 27
}

func hasHomeButton() -> Bool {
    let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }

    return windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0 > 0
}

enum AppPaths {
    static var backups: String {
        let url = backupsURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url.path
    }

    private static var backupsURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL.appendingPathComponent("backups", isDirectory: true)
    }
}

enum TweakPaths {
    static var gestalt = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
    static var gestalt_dir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/"
    static var mdm_profiles = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
    static var mdm_profiles_dir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/"
    static var posterboard = "/private/var/mobile/Library/PosterBoard"
    static var posterboard_dir = "/private/var/mobile/Library/PosterBoard/"
    static var preferences = "/private/var/mobile/Library/Preferences"
    static var preferences_dir = "/private/var/mobile/Library/Preferences/"
}

