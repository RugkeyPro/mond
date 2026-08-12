//
//  FileBrowserView.swift
//  mond
//
//  A small on-device browser for mond's own container and the directory
//  exposed by bad_query. System locations intentionally stay read-only.
//

import Combine
import Foundation
import QuickLook
import SwiftUI
import UIKit

enum BrowserAccessMode: Hashable {
    case sandbox
    case systemReadOnly
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

private enum FileBrowserError: LocalizedError {
    case exploitFailed(Int64, String)
    case invalidName
    case readOnly
    case outsideRoot

    var errorDescription: String? {
        switch self {
        case let .exploitFailed(code, path):
            return "bad_query could not grant access to \(path) (error \(code)). This path is only available on a supported iOS build."
        case .invalidName:
            return "Names cannot be empty or contain a slash."
        case .readOnly:
            return "System locations are read-only in this build."
        case .outsideRoot:
            return "The requested path is outside the selected root."
        }
    }
}

final class FileBrowserModel: ObservableObject {
    @Published private(set) var currentURL: URL
    @Published private(set) var nodes: [FileNode] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var accessNote: String?

    let root: BrowserRoot
    private var sandboxHandles: [Int64] = []
    private var grantedPaths: Set<String> = []

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
        root.mode == .sandbox && contains(currentURL)
    }

    var canGoUp: Bool {
        currentURL.standardizedFileURL.path != root.url.standardizedFileURL.path
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

        do {
            if root.mode == .systemReadOnly {
                try grantReadAccess(to: currentURL)
            }

            let keys: [URLResourceKey] = [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .isHiddenKey,
            ]
            let urls: [URL]
            var fallbackDirectoryPaths: Set<String> = []
            do {
                urls = try FileManager.default.contentsOfDirectory(
                    at: currentURL,
                    includingPropertiesForKeys: keys,
                    options: []
                )
            } catch {
                let knownURLs = knownSystemChildren(of: currentURL)
                guard root.mode == .systemReadOnly, !knownURLs.isEmpty else { throw error }
                urls = knownURLs
                fallbackDirectoryPaths = Set(knownURLs.map { $0.standardizedFileURL.path })
                accessNote = "Direct enumeration was blocked. Showing known child paths so you can continue navigating."
            }

            nodes = urls.compactMap { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return FileNode(
                    url: url,
                    isDirectory: values?.isDirectory ?? fallbackDirectoryPaths.contains(url.standardizedFileURL.path),
                    size: values?.fileSize.map(Int64.init),
                    modified: values?.contentModificationDate
                )
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
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
        guard contains(parent) else { return }
        currentURL = parent
        reload()
    }

    func createFolder(named name: String) {
        performEditableOperation {
            let destination = try destinationURL(for: name)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        }
    }

    func createEmptyFile(named name: String) {
        performEditableOperation {
            let destination = try destinationURL(for: name)
            guard FileManager.default.createFile(atPath: destination.path, contents: Data()) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    func rename(_ node: FileNode, to name: String) {
        performEditableOperation {
            let cleanName = try validatedName(name)
            let destination = node.url.deletingLastPathComponent().appendingPathComponent(cleanName)
            guard contains(destination) else { throw FileBrowserError.outsideRoot }
            try FileManager.default.moveItem(at: node.url, to: destination)
        }
    }

    func delete(_ node: FileNode) {
        performEditableOperation {
            guard contains(node.url) else { throw FileBrowserError.outsideRoot }
            try FileManager.default.removeItem(at: node.url)
        }
    }

    private func performEditableOperation(_ operation: () throws -> Void) {
        do {
            guard canEdit else { throw FileBrowserError.readOnly }
            try operation()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func destinationURL(for name: String) throws -> URL {
        let cleanName = try validatedName(name)
        let destination = currentURL.appendingPathComponent(cleanName)
        guard contains(destination) else { throw FileBrowserError.outsideRoot }
        return destination
    }

    private func validatedName(_ name: String) throws -> String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanName.contains("/") else {
            throw FileBrowserError.invalidName
        }
        return cleanName
    }

    private func contains(_ url: URL) -> Bool {
        let rootPath = root.url.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate == rootPath || candidate.hasPrefix(rootPath + "/")
    }

    private func grantReadAccess(to url: URL) throws {
        let path = url.standardizedFileURL.path
        guard !grantedPaths.contains(path) else { return }

        var pathBytes = path.utf8CString
        let handle = pathBytes.withUnsafeMutableBufferPointer { buffer -> Int64 in
            guard let baseAddress = buffer.baseAddress else { return -255 }
            return bad_query(baseAddress, false, nil, false)
        }

        guard handle >= 0 else {
            throw FileBrowserError.exploitFailed(handle, path)
        }

        sandboxHandles.append(handle)
        grantedPaths.insert(path)
    }

    private func knownSystemChildren(of url: URL) -> [URL] {
        let names: [String]
        switch url.standardizedFileURL.path {
        case "/private/var":
            names = ["containers", "db", "log", "mobile", "preferences", "root", "run", "tmp"]
        case "/private/var/containers":
            names = ["Bundle", "Data", "Shared", "Temp"]
        case "/private/var/mobile":
            names = ["Documents", "Library", "Media"]
        default:
            names = []
        }

        return names.map { url.appendingPathComponent($0, isDirectory: true) }
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
                subtitle: "Read-only system view; requires supported bad_query",
                icon: "internaldrive",
                url: URL(fileURLWithPath: "/private/var", isDirectory: true),
                mode: .systemReadOnly
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
                Text("System paths are intentionally read-only. Files in mond's own container can be created, renamed, deleted and shared.")
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
                    Image(systemName: model.root.mode == .systemReadOnly ? "lock.fill" : "pencil")
                        .foregroundStyle(model.root.mode == .systemReadOnly ? .orange : .green)
                    Text(model.root.mode == .systemReadOnly
                         ? "Read-only system view. Navigation and preview are enabled; modification is blocked to reduce bootloop and data-loss risk."
                         : "Editable app container. Long-press a row to rename or delete it.")
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
                Section("Directory listing") {
                    Label(accessNote, systemImage: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(.secondary)
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
                                FileNodeRow(node: node)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                editableMenu(for: node)
                            }
                        } else {
                            NavigationLink {
                                FilePreviewView(node: node, allowSharing: model.root.mode == .sandbox)
                            } label: {
                                FileNodeRow(node: node)
                            }
                            .contextMenu {
                                editableMenu(for: node)
                            }
                        }
                    }
                    .onDelete { offsets in
                        guard model.canEdit else { return }
                        for index in offsets {
                            deleteNode = model.nodes[index]
                            break
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
                    Button("Up", systemImage: "arrow.up") {
                        model.goUp()
                    }
                }

                Button("Reload", systemImage: "arrow.clockwise") {
                    model.reload()
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
                if let node = renameNode {
                    model.rename(node, to: pendingName)
                }
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
                if let node = deleteNode {
                    model.delete(node)
                }
                deleteNode = nil
            }
            Button("Cancel", role: .cancel) { deleteNode = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    @ViewBuilder
    private func editableMenu(for node: FileNode) -> some View {
        if model.canEdit {
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.isDirectory ? "folder.fill" : iconName)
                .foregroundStyle(node.isDirectory ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(node.url.lastPathComponent)
                    .lineLimit(1)
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

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

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

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
