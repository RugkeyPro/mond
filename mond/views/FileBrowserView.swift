//
//  FileBrowserView.swift
//  mond
//
//  On-device browser for mond's container and the precise /private/var
//  targets exposed by bad_query. System writes are verified, opt-in and
//  backed up before destructive operations.
//

import Combine
import Darwin
import Foundation
import QuickLook
import SwiftUI
import UIKit

enum BrowserAccessMode: Hashable {
    case sandbox
    case systemManaged
}

struct BrowserRoot: Identifiable, Hashable {
    let title: String
    let subtitle: String
    let icon: String
    let url: URL
    let mode: BrowserAccessMode

    var id: String { "\(mode)-\(url.path)" }
}

struct FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?

    var id: String { url.path }
}

private struct SystemTarget: Identifiable, Hashable {
    let title: String
    let url: URL
    let queryPath: String
    let allowsManagedWrites: Bool

    var id: String { url.standardizedFileURL.path }
}

private enum FileBrowserError: LocalizedError {
    case exploitFailed(Int64, String)
    case grantDidNotOpenPath(String, String)
    case writeProbeFailed(String, String)
    case invalidName
    case readOnly
    case outsideRoot
    case directoryMutationBlocked
    case protectedSystemItem(String)
    case backupFailed(String)
    case deletionVerificationFailed(String)
    case editorUnsupported(String)
    case fileTooLarge(Int64)

    var errorDescription: String? {
        switch self {
        case let .exploitFailed(code, path):
            let reason: String
            switch code {
            case -1:
                reason = "无法加载 container-manager 核心符号。"
            case -2:
                reason = "无法创建容器查询请求。"
            case -3:
                reason = "containermanager 未返回有效对象。此路径或当前 iOS 系统版本可能不支持。"
            case -4:
                reason = "iOS 内核拒绝签发沙盒扩展 Token。"
            case -5:
                reason = "无法构造路径穿越（Traversal）参数。"
            case -254:
                reason = "目标路径在此设备上不存在。"
            case -255:
                reason = "请求的路径不是绝对路径。"
            default:
                reason = "沙盒扩展访问请求失败。"
            }
            return "无法打开 \(path)：bad_query 返回错误码 \(code)。\(reason)（系统版本：\(ProcessInfo.processInfo.operatingSystemVersionString)）"
        case let .grantDidNotOpenPath(path, reason):
            return "bad_query 已返回句柄，但路径 \(path) 仍不可读：\(reason)"
        case let .writeProbeFailed(path, reason):
            return "已获得读取权限，但系统未授予 \(path) 写入权限：\(reason)"
        case .invalidName:
            return "名称不能为空、不能为 '.' 或 '..'，且不能包含斜杠 '/'。"
        case .readOnly:
            return "当前位置未开启写入权限。"
        case .outsideRoot:
            return "请求的路径超出了选定根目录的范围。"
        case .directoryMutationBlocked:
            return "文件浏览器禁止对系统目录进行直接重命名或删除。"
        case let .protectedSystemItem(path):
            return "\(path) 是系统核心受保护文件，禁止重命名。可在备份后进行编辑或通过专门流程删除。"
        case let .backupFailed(reason):
            return "创建安全备份失败，为保护系统已取消本次操作：\(reason)"
        case let .deletionVerificationFailed(path):
            return "已执行删除，但在重新枚举目录后 \(path) 仍然存在。系统守护进程可能已自动重新生成。安全备份已保留。"
        case let .editorUnsupported(name):
            return "\(name) 不是支持编辑的文本、JSON、XML 或 Property List (plist) 文件。"
        case let .fileTooLarge(size):
            return "该文件大小为 \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))；内置编辑器最大支持 2 MB。"
        }
    }
}

final class FileBrowserModel: ObservableObject {
    @Published private(set) var currentURL: URL
    @Published private(set) var nodes: [FileNode] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var accessNote: String?
    @Published private(set) var operationMessage: String?
    @Published private(set) var unlockedWriteTarget: String?

    let root: BrowserRoot
    private var sandboxHandles: [Int64] = []
    private var grantedTargetPaths: Set<String> = []

    private let supportedSystemTargets: [SystemTarget] = [
        SystemTarget(
            title: "MobileGestalt 缓存",
            url: URL(fileURLWithPath: TweakPaths.gestalt_dir, isDirectory: true).standardizedFileURL,
            queryPath: TweakPaths.gestalt_dir,
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "MDM 描述文件存储",
            url: URL(fileURLWithPath: TweakPaths.mdm_profiles, isDirectory: true),
            queryPath: TweakPaths.mdm_profiles_dir,
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "系统数据容器 (System Data)",
            url: URL(fileURLWithPath: "/private/var/containers/Data/System", isDirectory: true),
            queryPath: "/private/var/containers/Data/System/",
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "应用数据容器 (Application Data)",
            url: URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application", isDirectory: true),
            queryPath: "/private/var/mobile/Containers/Data/Application/",
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "内部守护进程容器 (Internal Daemon)",
            url: URL(fileURLWithPath: "/private/var/mobile/Containers/Data/InternalDaemon", isDirectory: true),
            queryPath: "/private/var/mobile/Containers/Data/InternalDaemon/",
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "插件扩展容器 (PluginKit Plugin)",
            url: URL(fileURLWithPath: "/private/var/mobile/Containers/Data/PluginKitPlugin", isDirectory: true),
            queryPath: "/private/var/mobile/Containers/Data/PluginKitPlugin/",
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "共享应用组 (App Groups)",
            url: URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup", isDirectory: true),
            queryPath: "/private/var/mobile/Containers/Shared/AppGroup/",
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "PosterBoard 锁屏海报存储",
            url: URL(fileURLWithPath: TweakPaths.posterboard, isDirectory: true),
            queryPath: TweakPaths.posterboard_dir,
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "用户偏好设置 (Preferences)",
            url: URL(fileURLWithPath: TweakPaths.preferences, isDirectory: true),
            queryPath: TweakPaths.preferences_dir,
            allowsManagedWrites: true
        ),
    ]

    init(root: BrowserRoot) {
        self.root = root
        currentURL = root.url.standardizedFileURL
    }

    deinit {
        for handle in sandboxHandles {
            bad_query_release(handle)
        }
    }

    var canEdit: Bool {
        guard contains(currentURL) else { return false }
        if root.mode == .sandbox { return true }
        guard let target = systemTarget(containing: currentURL) else { return false }
        return unlockedWriteTarget == target.id
    }

    var canUnlockSystemEditing: Bool {
        guard root.mode == .systemManaged,
              !isSystemIndex,
              let target = systemTarget(containing: currentURL) else { return false }
        return target.allowsManagedWrites && unlockedWriteTarget != target.id
    }

    var canGoUp: Bool {
        currentURL.standardizedFileURL.path != root.url.standardizedFileURL.path
    }

    var isSystemIndex: Bool {
        root.mode == .systemManaged &&
        currentURL.standardizedFileURL.path == root.url.standardizedFileURL.path
    }

    var displayPath: String {
        let rootPath = root.url.standardizedFileURL.path
        let currentPath = currentURL.standardizedFileURL.path
        guard currentPath != rootPath else { return rootPath }
        return currentPath.replacingOccurrences(of: rootPath, with: root.title, options: [.anchored])
    }

    func reload() {
        guard contains(currentURL) else {
            errorMessage = FileBrowserError.outsideRoot.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        accessNote = nil

        if isSystemIndex {
            nodes = supportedSystemTargets.map {
                FileNode(url: $0.url, isDirectory: true, size: nil, modified: nil)
            }
            accessNote = "未全局请求 /private/var 根目录。请选择具体的精确目标；mond 将为该目标及其子目录复用经校验的沙盒授权。"
            isLoading = false
            return
        }

        do {
            if root.mode == .systemManaged {
                try grantSystemAccess(to: currentURL)
            }
            nodes = try readNodes(at: currentURL)
        } catch {
            nodes = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func open(_ node: FileNode) {
        guard node.isDirectory else { return }
        let destination = node.url.standardizedFileURL
        guard contains(destination) else {
            errorMessage = FileBrowserError.outsideRoot.localizedDescription
            return
        }
        currentURL = destination
        reload()
    }

    func goUp() {
        guard canGoUp else { return }
        let parent = currentURL.deletingLastPathComponent().standardizedFileURL

        if root.mode == .systemManaged {
            let currentPath = currentURL.standardizedFileURL.path
            let target = supportedSystemTargets.first { containsPath(currentPath, in: $0.id) }
            if let target {
                let parentPath = parent.path
                currentURL = (currentPath == target.id || !containsPath(parentPath, in: target.id))
                    ? root.url.standardizedFileURL
                    : parent
            } else {
                currentURL = root.url.standardizedFileURL
            }
        } else {
            guard contains(parent) else { return }
            currentURL = parent
        }
        reload()
    }

    func unlockSystemEditing() {
        do {
            guard root.mode == .systemManaged,
                  let target = systemTarget(containing: currentURL),
                  target.allowsManagedWrites else {
                throw FileBrowserError.readOnly
            }

            do {
                try grantSystemAccess(to: target.url, requireFreshExtension: true)
            } catch {
                guard canEnumerate(target.url) else { throw error }
                accessNote = "全新写入授权失败（\(error.localizedDescription)）；正在通过真实文件操作测试现有可读扩展。"
            }
            try verifyWriteOperations(in: currentURL)

            unlockedWriteTarget = target.id
            operationMessage = "已在 \(currentURL.path) 成功验证创建、重命名、原子替换和删除探针。现有系统文件在修改前将自动备份。"
        } catch {
            unlockedWriteTarget = nil
            errorMessage = error.localizedDescription
        }
    }

    func lockSystemEditing() {
        unlockedWriteTarget = nil
        operationMessage = "已锁定本次会话的系统写入权限。"
    }

    func canRename(_ node: FileNode) -> Bool {
        guard canEdit else { return false }
        if root.mode == .sandbox { return true }
        return !node.isDirectory && !isProtectedSystemItem(node.url)
    }

    func canDelete(_ node: FileNode) -> Bool {
        guard canEdit else { return false }
        if root.mode == .sandbox { return true }
        return !node.isDirectory
    }

    func requiresCriticalDeleteConfirmation(_ node: FileNode) -> Bool {
        root.mode == .systemManaged && isProtectedSystemItem(node.url)
    }

    func canEditContents(_ node: FileNode) -> Bool {
        guard canEdit, !node.isDirectory else { return false }
        if let size = node.size, size > 2_000_000 { return false }
        return editableExtensions.contains(node.url.pathExtension.lowercased())
    }

    func editableText(for node: FileNode) throws -> String {
        guard !node.isDirectory, contains(node.url) else { throw FileBrowserError.outsideRoot }
        if let size = node.size, size > 2_000_000 { throw FileBrowserError.fileTooLarge(size) }

        let ext = node.url.pathExtension.lowercased()
        guard editableExtensions.contains(ext) else {
            throw FileBrowserError.editorUnsupported(node.url.lastPathComponent)
        }

        let data = try Data(contentsOf: node.url)
        if ext == "plist" {
            var format = PropertyListSerialization.PropertyListFormat.xml
            let object = try PropertyListSerialization.propertyList(
                from: data,
                options: [.mutableContainersAndLeaves],
                format: &format
            )
            let xml = try PropertyListSerialization.data(
                fromPropertyList: object,
                format: .xml,
                options: 0
            )
            guard let text = String(data: xml, encoding: .utf8) else {
                throw FileBrowserError.editorUnsupported(node.url.lastPathComponent)
            }
            return text
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw FileBrowserError.editorUnsupported(node.url.lastPathComponent)
        }
        return text
    }

    func saveEditedText(_ text: String, to node: FileNode) throws {
        guard canEditContents(node), contains(node.url) else { throw FileBrowserError.readOnly }
        let data = try validatedEditorData(text, for: node)

        if root.mode == .systemManaged {
            let backup = try backupSystemFile(node.url)
            operationMessage = "安全备份已保存至 \(backup.path)。"
        }

        try atomicallyReplaceFile(at: node.url, with: data)
        operationMessage = "已保存 \(node.url.lastPathComponent)。\(operationMessage ?? "")"
        reload()
    }

    func createFolder(named name: String) {
        performEditableOperation(successMessage: "文件夹已创建。") {
            let destination = try destinationURL(for: name)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        }
    }

    func createEmptyFile(named name: String) {
        performEditableOperation(successMessage: "空白文件已创建。") {
            let destination = try destinationURL(for: name)
            guard FileManager.default.createFile(atPath: destination.path, contents: Data()) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    func rename(_ node: FileNode, to name: String) {
        performEditableOperation(successMessage: "重命名成功。") {
            guard contains(node.url) else { throw FileBrowserError.outsideRoot }
            if root.mode == .systemManaged {
                try validateSystemFileRename(node)
                let backup = try backupSystemFile(node.url)
                operationMessage = "安全备份已保存至 \(backup.path)。"
            }

            let cleanName = try validatedName(name)
            let destination = node.url.deletingLastPathComponent().appendingPathComponent(cleanName)
            guard contains(destination) else { throw FileBrowserError.outsideRoot }
            try FileManager.default.moveItem(at: node.url, to: destination)
        }
    }

    func delete(_ node: FileNode) {
        do {
            guard canEdit else { throw FileBrowserError.readOnly }
            guard contains(node.url) else { throw FileBrowserError.outsideRoot }

            var backup: URL?
            if root.mode == .systemManaged {
                guard !node.isDirectory else { throw FileBrowserError.directoryMutationBlocked }
                backup = try backupSystemFile(node.url)
            }

            try FileManager.default.removeItem(at: node.url)

            let remainingNodes = try readNodes(at: node.url.deletingLastPathComponent())
            let stillListed = remainingNodes.contains {
                $0.url.standardizedFileURL.path == node.url.standardizedFileURL.path
            }
            guard !FileManager.default.fileExists(atPath: node.url.path), !stillListed else {
                throw FileBrowserError.deletionVerificationFailed(node.url.path)
            }

            errorMessage = nil
            if let backup {
                operationMessage = "已删除并验证 \(node.url.lastPathComponent)。安全备份: \(backup.path)"
            } else {
                operationMessage = "已删除并验证 \(node.url.lastPathComponent)。"
            }
            reload()
        } catch {
            let operationError = error.localizedDescription
            reload()
            errorMessage = operationError
        }
    }

    func overwriteWithEmptyDict(_ node: FileNode) {
        do {
            guard canEdit else { throw FileBrowserError.readOnly }
            guard contains(node.url) else { throw FileBrowserError.outsideRoot }
            guard !node.isDirectory else { throw FileBrowserError.directoryMutationBlocked }

            let emptyXmlPlist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict/>
            </plist>
            """
            let data = node.url.pathExtension.lowercased() == "plist" 
                ? Data(emptyXmlPlist.utf8)
                : Data()

            if root.mode == .systemManaged {
                let backup = try backupSystemFile(node.url)
                operationMessage = "安全备份已保存至 \(backup.path)。"
            }

            try atomicallyReplaceFile(at: node.url, with: data)
            operationMessage = "已将 \(node.url.lastPathComponent) 覆写为空 Payload（防止守护进程自愈恢复）。"
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func readNodes(at url: URL) throws -> [FileNode] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isHiddenKey,
            .isSymbolicLinkKey,
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        )

        return urls.compactMap { child in
            let values = try? child.resourceValues(forKeys: Set(keys))
            return FileNode(
                url: child,
                isDirectory: values?.isDirectory ?? false,
                size: values?.fileSize.map(Int64.init),
                modified: values?.contentModificationDate
            )
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }

    private func performEditableOperation(successMessage: String, _ operation: () throws -> Void) {
        do {
            guard canEdit else { throw FileBrowserError.readOnly }
            try operation()
            if operationMessage == nil || root.mode == .sandbox {
                operationMessage = successMessage
            } else if root.mode == .systemManaged {
                operationMessage = "\(successMessage) \(operationMessage ?? "")"
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func destinationURL(for name: String) throws -> URL {
        let cleanName = try validatedName(name)
        let destination = currentURL.appendingPathComponent(cleanName).standardizedFileURL
        guard contains(destination) else { throw FileBrowserError.outsideRoot }
        return destination
    }

    private func validatedName(_ name: String) throws -> String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              cleanName != ".",
              cleanName != "..",
              !cleanName.contains("/") else {
            throw FileBrowserError.invalidName
        }
        return cleanName
    }

    private var editableExtensions: Set<String> {
        ["plist", "json", "xml", "txt", "log", "md", "conf", "cfg", "ini", "strings"]
    }

    private func validatedEditorData(_ text: String, for node: FileNode) throws -> Data {
        let input = Data(text.utf8)
        switch node.url.pathExtension.lowercased() {
        case "plist":
            var editedFormat = PropertyListSerialization.PropertyListFormat.xml
            let object = try PropertyListSerialization.propertyList(
                from: input,
                options: [.mutableContainersAndLeaves],
                format: &editedFormat
            )

            var originalFormat = PropertyListSerialization.PropertyListFormat.xml
            let original = try Data(contentsOf: node.url)
            _ = try PropertyListSerialization.propertyList(
                from: original,
                options: [],
                format: &originalFormat
            )
            let outputFormat: PropertyListSerialization.PropertyListFormat = originalFormat == .binary ? .binary : .xml
            return try PropertyListSerialization.data(fromPropertyList: object, format: outputFormat, options: 0)
        case "json":
            _ = try JSONSerialization.jsonObject(with: input, options: [.fragmentsAllowed])
            return input
        default:
            return input
        }
    }

    private func verifyWriteOperations(in directory: URL) throws {
        let fm = FileManager.default
        let nonce = UUID().uuidString
        let first = directory.appendingPathComponent(".mond-write-probe-\(nonce)-a")
        let moved = directory.appendingPathComponent(".mond-write-probe-\(nonce)-b")
        let replacement = directory.appendingPathComponent(".mond-write-probe-\(nonce)-c")
        let payload = Data("mond-write-probe".utf8)
        let replacementPayload = Data("mond-atomic-replace-probe".utf8)

        defer {
            try? fm.removeItem(at: first)
            try? fm.removeItem(at: moved)
            try? fm.removeItem(at: replacement)
        }

        do {
            try payload.write(to: first, options: [.withoutOverwriting])
            guard try Data(contentsOf: first) == payload else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try fm.moveItem(at: first, to: moved)
            try replacementPayload.write(to: replacement, options: [.withoutOverwriting])
            _ = try fm.replaceItemAt(moved, withItemAt: replacement)
            guard try Data(contentsOf: moved) == replacementPayload else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try fm.removeItem(at: moved)
        } catch {
            throw FileBrowserError.writeProbeFailed(directory.path, error.localizedDescription)
        }
    }

    private func atomicallyReplaceFile(at destination: URL, with data: Data) throws {
        let fm = FileManager.default
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".mond-edit-\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: [.withoutOverwriting])
        defer { try? fm.removeItem(at: temporary) }

        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: destination)
        }
    }

    private func contains(_ url: URL) -> Bool {
        containsPath(url.standardizedFileURL.path, in: root.url.standardizedFileURL.path)
    }

    private func containsPath(_ candidate: String, in rootPath: String) -> Bool {
        candidate == rootPath || candidate.hasPrefix(rootPath + "/")
    }

    private func systemTarget(containing url: URL) -> SystemTarget? {
        let candidate = url.standardizedFileURL.path
        return supportedSystemTargets.first { containsPath(candidate, in: $0.id) }
    }

    private func grantSystemAccess(to url: URL, requireFreshExtension: Bool = false) throws {
        guard let target = systemTarget(containing: url) else {
            throw FileBrowserError.outsideRoot
        }
        if !requireFreshExtension, grantedTargetPaths.contains(target.id) { return }

        if !requireFreshExtension, canEnumerate(target.url) {
            grantedTargetPaths.insert(target.id)
            accessNote = "已使用当前进程已有的沙盒扩展成功验证对 \(target.id) 的访问。"
            return
        }

        if target.queryPath == TweakPaths.mdm_profiles_dir || target.queryPath == TweakPaths.mdm_profiles {
            if let _ = grant_mdm_access(), canEnumerate(target.url) {
                grantedTargetPaths.insert(target.id)
                accessNote = "通过 grant_mdm_access 成功授权并验证了对 \(target.id) 的真实访问。"
                return
            }
        }

        var pathBytes = target.queryPath.utf8CString
        let handle = pathBytes.withUnsafeMutableBufferPointer { buffer -> Int64 in
            guard let baseAddress = buffer.baseAddress else { return -255 }
            return bad_query(baseAddress, false, nil, false)
        }

        guard handle >= 0 else {
            throw FileBrowserError.exploitFailed(handle, target.queryPath)
        }

        guard canEnumerate(target.url) else {
            bad_query_release(handle)
            let reason = String(cString: strerror(errno))
            throw FileBrowserError.grantDidNotOpenPath(target.id, reason)
        }

        sandboxHandles.append(handle)
        grantedTargetPaths.insert(target.id)
        accessNote = "bad_query 已成功授权并验证了对 \(target.id) 的真实访问。"
    }

    private func canEnumerate(_ url: URL) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return true
        } catch {
            return false
        }
    }

    private func validateSystemFileRename(_ node: FileNode) throws {
        guard !node.isDirectory else { throw FileBrowserError.directoryMutationBlocked }
        guard !isProtectedSystemItem(node.url) else {
            throw FileBrowserError.protectedSystemItem(node.url.path)
        }
    }

    private func isProtectedSystemItem(_ url: URL) -> Bool {
        url.standardizedFileURL.path == URL(fileURLWithPath: TweakPaths.gestalt).standardizedFileURL.path
    }

    private func backupSystemFile(_ source: URL) throws -> URL {
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let backupRoot = documents.appendingPathComponent("SystemFileBackups", isDirectory: true)
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backupDirectory = backupRoot
                .appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try FileManager.default.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true
            )

            let destination = backupDirectory.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)

            let metadata: [String: String] = [
                "originalPath": source.path,
                "backupDate": ISO8601DateFormatter().string(from: Date()),
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            try metadataData.write(to: backupDirectory.appendingPathComponent("metadata.json"), options: [.atomic])
            return destination
        } catch {
            throw FileBrowserError.backupFailed(error.localizedDescription)
        }
    }
}

struct FileBrowserHomeView: View {
    private var roots: [BrowserRoot] {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return [
            BrowserRoot(
                title: "文稿 (Documents)",
                subtitle: "应用沙盒主目录，可通过‘文件’App / iTunes 共享查看",
                icon: "doc.on.doc",
                url: documents,
                mode: .sandbox
            ),
            BrowserRoot(
                title: "资源库 (Library)",
                subtitle: "应用支持文件与用户偏好设置目录",
                icon: "books.vertical",
                url: library,
                mode: .sandbox
            ),
            BrowserRoot(
                title: "临时目录 (Temporary)",
                subtitle: "可编辑的缓存目录，系统在需要时会自动清理",
                icon: "clock.arrow.circlepath",
                url: temporary,
                mode: .sandbox
            ),
            BrowserRoot(
                title: "/private/var 系统目录",
                subtitle: "真实精确路径访问；写操作需经探针验证与二次授权",
                icon: "internaldrive",
                url: URL(fileURLWithPath: "/private/var", isDirectory: true),
                mode: .systemManaged
            ),
        ]
    }

    var body: some View {
        List {
            Section {
                ForEach(roots) { root in
                    NavigationLink {
                        FileBrowserView(root: root)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(root.title)
                                Text(root.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: root.icon)
                                .frame(width: 24)
                        }
                    }
                }
            } footer: {
                Text("出于安全保护，/private/var 不开放全局根目录权限。请选择具体的精确目标路径。写入权限仅在探针可逆操作验证成功后开放；系统文件在修改、重命名或删除前会自动备份。")
            }
        }
        .navigationTitle("文件浏览")
    }
}

struct FileBrowserView: View {
    @StateObject private var model: FileBrowserModel
    @State private var creationKind: CreationKind?
    @State private var pendingName = ""
    @State private var renameNode: FileNode?
    @State private var deleteNode: FileNode?
    @State private var criticalDeleteNode: FileNode?
    @State private var criticalDeleteConfirmation = ""
    @State private var showUnlockConfirmation = false

    private enum CreationKind: String, Identifiable {
        case folder = "新建文件夹"
        case file = "新建空白文件"

        var id: String { rawValue }
    }

    init(root: BrowserRoot) {
        _model = StateObject(wrappedValue: FileBrowserModel(root: root))
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                    Text(statusText)
                        .font(.footnote)
                }
            }

            if let errorMessage = model.errorMessage {
                Section("访问状态") {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            if let accessNote = model.accessNote {
                Section("权限验证") {
                    Label(accessNote, systemImage: "checkmark.shield")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let operationMessage = model.operationMessage {
                Section("最近操作") {
                    Label(operationMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section {
                if model.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if model.nodes.isEmpty && model.errorMessage == nil {
                    ContentUnavailableView("空文件夹", systemImage: "folder")
                } else {
                    ForEach(model.nodes) { node in
                        if node.isDirectory {
                            Button {
                                model.open(node)
                            } label: {
                                FileNodeRow(node: node, showFullPath: model.isSystemIndex)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { editableMenu(for: node) }
                        } else {
                            NavigationLink {
                                FilePreviewView(
                                    node: node,
                                    allowSharing: model.root.mode == .sandbox,
                                    model: model
                                )
                            } label: {
                                FileNodeRow(node: node, showFullPath: model.isSystemIndex)
                            }
                            .contextMenu { editableMenu(for: node) }
                        }
                    }
                    .onDelete { offsets in
                        guard model.canEdit else { return }
                        for index in offsets {
                            let candidate = model.nodes[index]
                            if model.canDelete(candidate) {
                                requestDelete(candidate)
                                break
                            }
                        }
                    }
                }
            } header: {
                Text(model.displayPath)
                    .textCase(nil)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(model.currentURL.lastPathComponent.isEmpty ? model.root.title : model.currentURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.reload() }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if model.canGoUp {
                    Button("上一级", systemImage: "arrow.up") { model.goUp() }
                }

                Button("刷新", systemImage: "arrow.clockwise") { model.reload() }

                if model.root.mode == .systemManaged && !model.isSystemIndex {
                    if model.canEdit {
                        Button("锁定写入", systemImage: "lock.open.fill") {
                            model.lockSystemEditing()
                        }
                    } else if model.canUnlockSystemEditing {
                        Button("验证并解锁写入", systemImage: "lock.fill") {
                            showUnlockConfirmation = true
                        }
                    }
                }

                if model.canEdit {
                    Menu {
                        Button("新建文件夹", systemImage: "folder.badge.plus") {
                            pendingName = "新建文件夹"
                            creationKind = .folder
                        }
                        Button("新建空白文件", systemImage: "doc.badge.plus") {
                            pendingName = "untitled.txt"
                            creationKind = .file
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .alert("开启系统文件写入？", isPresented: $showUnlockConfirmation) {
            Button("取消", role: .cancel) {}
            Button("验证并开启") { model.unlockSystemEditing() }
        } message: {
            Text("mond 将在目标目录执行临时的探针文件创建、重命名、原子替换和删除测试，不会修改现有文件。修改系统文件前会自动创建备份。系统目录无法被重命名或删除。删除 MobileGestalt.plist 需单独输入确认。")
        }
        .alert(creationKind?.rawValue ?? "创建", isPresented: Binding(
            get: { creationKind != nil },
            set: { if !$0 { creationKind = nil } }
        )) {
            TextField("名称", text: $pendingName)
            Button("取消", role: .cancel) { creationKind = nil }
            Button("创建") {
                if creationKind == .folder {
                    model.createFolder(named: pendingName)
                } else {
                    model.createEmptyFile(named: pendingName)
                }
                creationKind = nil
            }
        }
        .alert("重命名", isPresented: Binding(
            get: { renameNode != nil },
            set: { if !$0 { renameNode = nil } }
        )) {
            TextField("名称", text: $pendingName)
            Button("取消", role: .cancel) { renameNode = nil }
            Button("重命名") {
                if let node = renameNode { model.rename(node, to: pendingName) }
                renameNode = nil
            }
        }
        .confirmationDialog(
            "确定删除 \(deleteNode?.url.lastPathComponent ?? "条目")？",
            isPresented: Binding(
                get: { deleteNode != nil },
                set: { if !$0 { deleteNode = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let node = deleteNode { model.delete(node) }
                deleteNode = nil
            }
            Button("取消", role: .cancel) { deleteNode = nil }
        } message: {
            Text(model.root.mode == .systemManaged
                 ? "普通文件在删除前将自动备份至 Documents/SystemFileBackups。"
                 : "此操作无法撤销。")
        }
        .alert("删除系统核心文件？", isPresented: Binding(
            get: { criticalDeleteNode != nil },
            set: {
                if !$0 {
                    criticalDeleteNode = nil
                    criticalDeleteConfirmation = ""
                }
            }
        )) {
            TextField("请输入 DELETE", text: $criticalDeleteConfirmation)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("取消", role: .cancel) {
                criticalDeleteNode = nil
                criticalDeleteConfirmation = ""
            }
            Button("备份并删除", role: .destructive) {
                if let node = criticalDeleteNode { model.delete(node) }
                criticalDeleteNode = nil
                criticalDeleteConfirmation = ""
            }
            .disabled(criticalDeleteConfirmation != "DELETE")
        } message: {
            Text("删除 com.apple.MobileGestalt.plist 可能会导致 iOS 系统不稳定甚至无法开机（Bootloop）。mond 会先将其备份至 Documents/SystemFileBackups，然后执行删除并重新枚举目录验证结果。请输入 DELETE 以确认继续。")
        }
    }

    private var statusIcon: String {
        if model.root.mode == .sandbox { return "pencil" }
        return model.canEdit ? "lock.open.fill" : "lock.fill"
    }

    private var statusColor: Color {
        if model.root.mode == .sandbox || model.canEdit { return .green }
        return .orange
    }

    private var statusText: String {
        if model.root.mode == .sandbox {
            return "应用沙盒目录（可自由读写）。长按条目可重命名或删除。"
        }
        if model.isSystemIndex {
            return "请选择具体的 /private/var 系统目标。真实路径访问成功后方可浏览。"
        }
        if model.canEdit {
            return "已验证真实读写权限。修改与删除前会自动创建安全备份；删除核心文件需二次确认。"
        }
        return "已验证真实读取权限。点击右上角‘锁’图标执行写操作探针以解锁写入。"
    }

    @ViewBuilder
    private func editableMenu(for node: FileNode) -> some View {
        if model.canEdit && !node.isDirectory {
            Button("覆盖为空 Payload ({})", systemImage: "xmark.bin") {
                model.overwriteWithEmptyDict(node)
            }
        }
        if model.canRename(node) {
            Button("重命名", systemImage: "pencil") {
                pendingName = node.url.lastPathComponent
                renameNode = node
            }
        }
        if model.canDelete(node) {
            Button("删除", systemImage: "trash", role: .destructive) {
                requestDelete(node)
            }
        }
    }

    private func requestDelete(_ node: FileNode) {
        if model.requiresCriticalDeleteConfirmation(node) {
            criticalDeleteConfirmation = ""
            criticalDeleteNode = node
        } else {
            deleteNode = node
        }
    }
}

private struct FileNodeRow: View {
    let node: FileNode
    let showFullPath: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.isDirectory ? "folder.fill" : iconName)
                .foregroundStyle(node.isDirectory ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(showFullPath ? node.url.path : node.url.lastPathComponent)
                    .lineLimit(showFullPath ? 3 : 1)
                HStack(spacing: 8) {
                    if let size = node.size, !node.isDirectory {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                    if let modified = node.modified {
                        Text(modified, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch node.url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "gif": return "photo"
        case "plist", "json", "xml": return "list.bullet.rectangle"
        case "txt", "log", "md": return "doc.text"
        case "zip", "ipa": return "doc.zipper"
        default: return "doc"
        }
    }
}

private struct FilePreviewView: View {
    let node: FileNode
    let allowSharing: Bool
    @ObservedObject var model: FileBrowserModel

    var body: some View {
        VStack(spacing: 0) {
            QuickLookPreview(url: node.url)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.url.path)
                        .font(.caption)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    if let size = node.size {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if allowSharing {
                    ShareLink(item: node.url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(node.url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.canEditContents(node) {
                NavigationLink {
                    TextFileEditorView(node: node, model: model)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
            }
        }
    }
}

private struct TextFileEditorView: View {
    let node: FileNode
    @ObservedObject var model: FileBrowserModel
    @State private var text = ""
    @State private var loadError: String?
    @State private var isLoaded = false
    @State private var showSaveConfirmation = false
    @State private var saveResult: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "无法编辑",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if !isLoaded {
                ProgressView("正在加载…")
            } else {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(6)
            }
        }
        .navigationTitle(node.url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .toolbar {
            if isLoaded {
                Button("保存", systemImage: "square.and.arrow.down") {
                    showSaveConfirmation = true
                }
                .disabled(!model.canEditContents(node))
            }
        }
        .alert("保存更改？", isPresented: $showSaveConfirmation) {
            Button("取消", role: .cancel) {}
            Button("保存", role: .destructive, action: save)
        } message: {
            Text(model.root.mode == .systemManaged
                 ? "当前文件将被备份到 Documents/SystemFileBackups，经格式校验后原子替换写入。非法的 plist 或 JSON 内容将被拒绝。"
                 : "文件将在必要时进行格式校验并以原子方式安全替换写入。")
        }
        .alert("编辑器状态", isPresented: Binding(
            get: { saveResult != nil },
            set: { if !$0 { saveResult = nil } }
        )) {
            Button("好") { saveResult = nil }
        } message: {
            Text(saveResult ?? "")
        }
    }

    private func load() {
        guard !isLoaded, loadError == nil else { return }
        do {
            text = try model.editableText(for: node)
            isLoaded = true
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        do {
            try model.saveEditedText(text, to: node)
            saveResult = "保存成功。已为系统文件创建安全备份。"
        } catch {
            saveResult = error.localizedDescription
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
