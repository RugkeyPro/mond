//
//  BAExtensionDelegate.swift
//  BAExtension
//
//  Created by roooot on 2026-08-13.
//

import Foundation
import BackgroundAssets

@objc(BAExtensionDelegate)
class BAExtensionDelegate: NSObject, BADownloaderExtension {
    func downloads(for request: BADownload.Request, manifestURL: URL, extensionInfo: BAExtensionInfo) -> [BADownload] {
        return []
    }
}
