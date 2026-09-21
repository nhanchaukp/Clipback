import Foundation
import AppKit

@MainActor
public final class ClipboardMonitor {
    public static let shared = ClipboardMonitor()
    static let ownContentType = NSPasteboard.PasteboardType("com.clipback.internal-copy")
    static let legacyContentType = NSPasteboard.PasteboardType("com.clipory.internal-copy")
    private let pasteboard: NSPasteboard
    private let storage: StorageManager
    private let settings: UserSettings
    private let images: ImageCacheManager
    private var lastChangeCount: Int
    private var monitorTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var ocrTask: Task<Void, Never>?
    private var pending: [(ClipboardItem, Data?, Int)] = []
    private var pendingBytes = 0
    private var ocrQueue: [(UUID, String, Data?, Bool)] = []
    private var lastPrune = Date()

    init(pasteboard: NSPasteboard = .general, storage: StorageManager? = nil,
         settings: UserSettings? = nil, images: ImageCacheManager? = nil) {
        self.pasteboard = pasteboard
        self.storage = storage ?? .shared
        self.settings = settings ?? .shared
        self.images = images ?? .shared
        lastChangeCount = pasteboard.changeCount
    }

    public func startMonitoring() {
        guard monitorTask == nil else { return }
        lastChangeCount = pasteboard.changeCount
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { break }
                self?.checkForChanges()
            }
        }
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        pending.removeAll()
        pendingBytes = 0
        processingTask?.cancel()
        ocrQueue.removeAll()
        ocrTask?.cancel()
    }

    func finishStopping() async {
        await processingTask?.value
        await ocrTask?.value
    }

    func waitForPendingCapture() async { await processingTask?.value }

    /// Reading the pasteboard stays on MainActor; image work is queued separately.
    func checkForChanges() {
        guard !storage.isLoading else { return }
        if Date().timeIntervalSince(lastPrune) >= 60 {
            lastPrune = Date()
            if settings.retentionMode == .byTime { storage.pruneHistory() }
        }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard !settings.monitoringPaused, !PasteboardConcealed.isConcealed(pasteboard: pasteboard),
              pasteboard.data(forType: Self.ownContentType) == nil,
              pasteboard.data(forType: Self.legacyContentType) == nil else { return }
        let app = NSWorkspace.shared.frontmostApplication
        guard !settings.excludesApplication(app?.bundleIdentifier) else { return }

        var item: ClipboardItem?
        var imageData: Data?
        if settings.saveImages, let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            item = ClipboardItem(contentType: .image, ocrStatus: "pending")
            imageData = data
        } else if settings.saveFiles,
                  let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  !urls.isEmpty {
            item = ClipboardItem(contentType: .file, filePaths: urls.map(\.path))
        } else if let text = pasteboard.string(forType: .string) {
            item = Self.textItem(text, html: pasteboard.string(forType: .html), rtf: pasteboard.data(forType: .rtf), settings: settings)
        }
        // Do not combine payloads if another app replaced the clipboard during the read.
        guard var item, pasteboard.changeCount == count else { return }
        item.sourceAppBundleId = app?.bundleIdentifier
        item.sourceAppName = app?.localizedName
        let bytes = Self.queuedBytes(item, imageData)
        guard pending.count < 64, pendingBytes + bytes <= 128 * 1024 * 1024 else {
            storage.lastError = L10n.errorMonitorQueueFull(lang: settings.appLanguage)
            return
        }
        pending.append((item, imageData, storage.captureGeneration))
        pendingBytes += bytes
        if processingTask == nil { processingTask = Task { await processPending() } }
    }

    static func textItem(_ raw: String, html: String?, rtf: Data?, settings: UserSettings) -> ClipboardItem? {
        guard !raw.isEmpty else { return nil }
        let classified = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.saveColors, let hex = ColorExtractor.extractHexColor(from: classified) {
            return ClipboardItem(contentType: .colorHex, textContent: raw, htmlContent: html, colorHex: hex, rtfContent: rtf)
        }
        guard settings.saveText else { return nil }
        if let url = URL(string: classified), let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), url.host != nil,
           !classified.contains(where: \.isWhitespace) {
            return ClipboardItem(contentType: .link, textContent: raw, htmlContent: html, rtfContent: rtf)
        }
        return ClipboardItem(contentType: html != nil || rtf != nil ? .richText : .text,
                             textContent: raw, htmlContent: html, rtfContent: rtf)
    }

    private static func queuedBytes(_ item: ClipboardItem, _ image: Data?) -> Int {
        if let image { return image.count }
        var bytes = item.textContent?.utf8.count ?? 0
        bytes += item.htmlContent?.utf8.count ?? 0
        bytes += item.rtfContent?.count ?? 0
        return bytes
    }

    private func processPending() async {
        defer { processingTask = nil }
        while !pending.isEmpty, !Task.isCancelled {
            var (item, data, generation) = pending.removeFirst()
            pendingBytes -= Self.queuedBytes(item, data)
            guard generation == storage.captureGeneration, !settings.monitoringPaused else { continue }
            if let data {
                guard let saved = await images.saveImage(data: data) else {
                    storage.lastError = L10n.errorMonitorImageSaveFailed(lang: settings.appLanguage)
                    continue
                }
                guard !Task.isCancelled, generation == storage.captureGeneration, !settings.monitoringPaused,
                      !settings.excludesApplication(item.sourceAppBundleId) else {
                    await images.deleteImages([saved.fileName]); continue
                }
                item.imageFileName = saved.fileName
                item.imageWidth = saved.width
                item.imageHeight = saved.height
                item.imageFileSize = saved.fileSize
                item.imageSHA256 = saved.sha256
            }
            let retained = storage.addItem(item)
            if retained == nil, let name = item.imageFileName {
                // An image rejected by a quota is not part of any persisted snapshot.
                await images.deleteImages([name])
            }
            if let retained, retained.id == item.id, let name = retained.imageFileName {
                ocrQueue.append((retained.id, name, data, settings.detectQrInImages))
                if ocrTask == nil { ocrTask = Task { await processOCR() } }
            }
            if retained != nil, settings.playSounds {
                SoundEffectManager.playSound(named: settings.soundName)
            }
        }
    }

    private func processOCR() async {
        defer { ocrTask = nil }
        while !ocrQueue.isEmpty, !Task.isCancelled {
            let (id, file, cachedData, detectQR) = ocrQueue.removeFirst()
            let data: Data?
            if let cachedData {
                data = cachedData
            } else {
                data = await images.imageData(fileName: file)
            }
            guard let data, !Task.isCancelled, storage.items.contains(where: { $0.id == id }) else { continue }
            
            let result = await OCREngine.shared.recognizeProgressive(data: data, detectQR: detectQR) { [weak self] qrPayload in
                guard let qrPayload else { return }
                Task { @MainActor [weak self] in
                    self?.storage.updateQRPayload(for: id, qrPayload: qrPayload)
                }
            }
            guard !Task.isCancelled else { return }
            storage.updateOCRText(for: id, ocrText: result.text, failed: result.failed)
        }
    }
}
