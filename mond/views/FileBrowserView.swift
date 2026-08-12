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

    var errorDescription: String? {
        switch self {
        case let .exploitFailed(code, path):
            let reason: String
            switch code {
            case -1:
                reason = "Required container-manager symbols are unavailable."
            case -2:
                reason = "The container query could not be created."
            case -3:
                reason = "containermanager returned no object. This exact path or iOS build is not supported."
            case -4:
                reason = "iOS refused to issue a sandbox extension."
            case -5:
                reason = "The traversal path could not be constructed."
            case -254:
                reason = "The path does not exist on this device."
            case -255:
                reason = "The requested path is not absolute."
            default:
                reason = "The access request failed."
            }
            return "Could not open \(path): bad_query returned \(code). \(reason) Device: \(ProcessInfo.processInfo.operatingSystemVersionString)."
        case let .grantDidNotOpenPath(path, reason):
            return "bad_query returned a handle, but \(path) is still unreadable: \(reason)"
        case let .writeProbeFailed(path, reason):
            return "Read access works, but iOS did not grant writes to \(path): \(reason)"
        case .invalidName:
            return "Names cannot be empty, '.', '..', or contain a slash."
        case .readOnly:
            return "Writes are not enabled for this location."
        case .outsideRoot:
            return "The requested path is outside the selected root."
        case .directoryMutationBlocked:
            return "System directories cannot be renamed or deleted by this browser."
        case let .protectedSystemItem(path):
            return "\(path) is protected from rename and deletion because removing it can prevent iOS from booting. Use mond's dedicated editor or Revert Tweaks instead."
        case let .backupFailed(reason):
            return "The safety backup failed, so the system change was cancelled: \(reason)"
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

    // bad_query cannot normally grant /private/var itself. It must be called
    // once for an exact target root, after which that grant is reused for all
    // descendants. The first target exactly matches TweakPaths.gestalt_dir.
    private let supportedSystemTargets: [SystemTarget] = [
        SystemTarget(
            title: "MobileGestalt Cache",
            url: URL(fileURLWithPath: TweakPaths.gestalt_dir, isDirectory: true).standardizedFileURL,
            queryPath: TweakPaths.gestalt_dir,
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "System Data Containers",
            url: URL(fileURLWithPath: "/private/var/containers/Data/System", isDirectory: true),
            queryPath: "/private/var/containers/Data/System/",
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "Application Containers",
            url: URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application", isDirectory: true),
            queryPath: "/private/var/mobile/Containers/Data/Application/",
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "Internal Daemon Containers",
            url: URL(fileURLWithPath: "/private/var/mobile/Containers/Data/InternalDaemon", isDirectory: true),
            queryPath: "/private/var/mobile/Containers/Data/InternalDaemon/",
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "Plugin Containers",
            url: URL(fileURLWithPath: "/private/var/mobile/Containers/Data/PluginKitPlugin", isDirectory: true),
            queryPath: "/private/var/mobile/Containers/Data/PluginKitPlugin/",
            allowsManagedWrites: true
        ),
        SystemTarget(
            title: "App Groups",
            url: URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup", isDirectory: true),
            queryPath: "/private/var/mobile/Containers/Shared/AppGroup/",
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
            accessNote = "The /private/var parent is not requested. Select an exact target; mond then reuses one verified grant for that target and all of its children."
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

            try grantSystemAccess(to: target.url)
            errno = 0
            let result = target.id.withCString { Darwin.access($0, W_OK) }
            guard result == 0 else {
                let detail = String(cString: strerror(errno))
                throw FileBrowserError.writeProbeFailed(target.id, detail)
            }

            unlockedWriteTarget = target.id
            operationMessage = "Managed writes verified for \(target.id). System file rename/delete is backed up first; system directories remain protected."
        } catch {
            unlockedWriteTarget = nil
            errorMessage = error.localizedDescription
        }
    }

    func lockSystemEditing() {
        unlockedWriteTarget = nil
        operationMessage = "System writes locked for this session."
    }

    func canRenameOrDelete(_ node: FileNode) -> Bool {
        guard canEdit else { return false }
        if root.mode == .sandbox { return true }
        return !node.isDirectory && !isProtectedSystemItem(node.url)
    }

    func createFolder(named name: String) {
        performEditableOperation(successMessage: "Folder created.") {
            let destination = try destinationURL(for: name)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        }
    }

    func createEmptyFile(named name: String) {
        performEditableOperation(successMessage: "Empty file created.") {
            let destination = try destinationURL(for: name)
            guard FileManager.default.createFile(atPath: destination.path, contents: Data()) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    func rename(_ node: FileNode, to name: String) {
        performEditableOperation(successMessage: "Item renamed.") {
            guard contains(node.url) else { throw FileBrowserError.outsideRoot }
            if root.mode == .systemManaged {
                try validateSystemFileMutation(node)
                let backup = try backupSystemFile(node.url)
                operationMessage = "Safety backup saved to \(backup.path)."
            }

            let cleanName = try validatedName(name)
            let destination = node.url.deletingLastPathComponent().appendingPathComponent(cleanName)
            guard contains(destination) else { throw FileBrowserError.outsideRoot }
            try FileManager.default.moveItem(at: node.url, to: destination)
        }
    }

    func delete(_ node: FileNode) {
        performEditableOperation(successMessage: "Item deleted after backup.") {
            guard contains(node.url) else { throw FileBrowserError.outsideRoot }
            if root.mode == .systemManaged {
                try validateSystemFileMutation(node)
                let backup = try backupSystemFile(node.url)
                operationMessage = "Safety backup saved to \(backup.path)."
            }
            try FileManager.default.removeItem(at: node.url)
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

    private func grantSystemAccess(to url: URL) throws {
        guard let target = systemTarget(containing: url) else {
            throw FileBrowserError.outsideRoot
        }
        guard !grantedTargetPaths.contains(target.id) else { return }

        // ContentView normally runs grant_mg_write() before the browser opens.
        // Reuse that process-wide extension when the target is already readable.
        if canEnumerate(target.url) {
            grantedTargetPaths.insert(target.id)
            accessNote = "Verified real access to \(target.id) using the process's existing sandbox extension."
            return
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
        accessNote = "bad_query granted and verified real access to \(target.id)."
    }

    private func canEnumerate(_ url: URL) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return true
        } catch {
            return false
        }
    }

    private func validateSystemFileMutation(_ node: FileNode) throws {
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
            let backupDirectory = backupRoot.appendingPathComponent(stamp, isDirectory: true)
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
                title: "Documents",
                subtitle: "Editable and visible through Files/iTunes sharing",
                icon: "doc.on.doc",
                url: documents,
                mode: .sandbox
            ),
            BrowserRoot(
                title: "Library",
                subtitle: "Editable app support and preference files",
                icon: "books.vertical",
                url: library,
                mode: .sandbox
            ),
            BrowserRoot(
                title: "Temporary",
                subtitle: "Editable cache cleared by iOS when needed",
                icon: "clock.arrow.circlepath",
                url: temporary,
                mode: .sandbox
            ),
            BrowserRoot(
                title: "/private/var",
                subtitle: "Real precise-path access; writes require verification and opt-in",
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
                Text("/private/var is not globally granted. Select a precise target. Only verified targets can be unlocked; system files are backed up before rename or deletion.")
            }
        }
        .navigationTitle("Files")
    }
}

struct FileBrowserView: View {
    @StateObject private var model: FileBrowserModel
    @State private var creationKind: CreationKind?
    @State private var pendingName = ""
    @State private var renameNode: FileNode?
    @State private var deleteNode: FileNode?
    @State private var showUnlockConfirmation = false

    private enum CreationKind: String, Identifiable {
        case folder = "New Folder"
        case file = "New Empty File"

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
                Section("Access status") {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            if let accessNote = model.accessNote {
                Section("Access verification") {
                    Label(accessNote, systemImage: "checkmark.shield")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let operationMessage = model.operationMessage {
                Section("Last operation") {
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
                    ContentUnavailableView("Empty Folder", systemImage: "folder")
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
                                FilePreviewView(node: node, allowSharing: model.root.mode == .sandbox)
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
                            if model.canRenameOrDelete(candidate) {
                                deleteNode = candidate
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
                    Button("Up", systemImage: "arrow.up") { model.goUp() }
                }

                Button("Reload", systemImage: "arrow.clockwise") { model.reload() }

                if model.root.mode == .systemManaged && !model.isSystemIndex {
                    if model.canEdit {
                        Button("Lock writes", systemImage: "lock.open.fill") {
                            model.lockSystemEditing()
                        }
                    } else if model.canUnlockSystemEditing {
                        Button("Verify and enable writes", systemImage: "lock.fill") {
                            showUnlockConfirmation = true
                        }
                    }
                }

                if model.canEdit {
                    Menu {
                        Button("New Folder", systemImage: "folder.badge.plus") {
                            pendingName = "New Folder"
                            creationKind = .folder
                        }
                        Button("New Empty File", systemImage: "doc.badge.plus") {
                            pendingName = "untitled.txt"
                            creationKind = .file
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .alert("Enable system writes?", isPresented: $showUnlockConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Verify and Enable") { model.unlockSystemEditing() }
        } message: {
            Text("mond will first verify that iOS granted write access. Existing regular files are backed up to Documents/SystemFileBackups before rename or deletion. System directories and MobileGestalt.plist cannot be renamed or deleted here.")
        }
        .alert(creationKind?.rawValue ?? "Create", isPresented: Binding(
            get: { creationKind != nil },
            set: { if !$0 { creationKind = nil } }
        )) {
            TextField("Name", text: $pendingName)
            Button("Cancel", role: .cancel) { creationKind = nil }
            Button("Create") {
                if creationKind == .folder {
                    model.createFolder(named: pendingName)
                } else {
                    model.createEmptyFile(named: pendingName)
                }
                creationKind = nil
            }
        }
        .alert("Rename", isPresented: Binding(
            get: { renameNode != nil },
            set: { if !$0 { renameNode = nil } }
        )) {
            TextField("Name", text: $pendingName)
            Button("Cancel", role: .cancel) { renameNode = nil }
            Button("Rename") {
                if let node = renameNode { model.rename(node, to: pendingName) }
                renameNode = nil
            }
        }
        .confirmationDialog(
            "Delete \(deleteNode?.url.lastPathComponent ?? "item")?",
            isPresented: Binding(
                get: { deleteNode != nil },
                set: { if !$0 { deleteNode = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let node = deleteNode { model.delete(node) }
                deleteNode = nil
            }
            Button("Cancel", role: .cancel) { deleteNode = nil }
        } message: {
            Text(model.root.mode == .systemManaged
                 ? "The regular file will be copied to Documents/SystemFileBackups before deletion."
                 : "This cannot be undone.")
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
            return "Editable app container. Long-press a row to rename or delete it."
        }
        if model.isSystemIndex {
            return "Select a precise /private/var target. No virtual folders are shown as successful access."
        }
        if model.canEdit {
            return "Real read/write access is verified for this target. System file changes use safety backups."
        }
        return "Real read access is required before files appear. Use the lock button to verify and opt in to writes."
    }

    @ViewBuilder
    private func editableMenu(for node: FileNode) -> some View {
        if model.canRenameOrDelete(node) {
            Button("Rename", systemImage: "pencil") {
                pendingName = node.url.lastPathComponent
                renameNode = node
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteNode = node
            }
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
