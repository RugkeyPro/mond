import BackgroundAssets

@available(iOS 16.4, *)
class BAExtensionDelegate: BADownloaderExtension {
    required init() {}
    func backgroundDownload(_ download: BADownload, failedWithError error: Error) {}
    func backgroundDownload(_ download: BADownload, finishedWithFileURL fileURL: URL) {}
}
