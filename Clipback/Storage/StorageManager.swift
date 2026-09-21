import Foundation
import Combine

@MainActor
public final class StorageManager: ObservableObject {
    public static let shared = StorageManager()
    @Published public private(set) var items: [ClipboardItem] = []
    @Published public private(set) var isLoading = true
    @Published public private(set) var revision = 0
    @Published public private(set) var lastDeletedItem: ClipboardItem?
    @Published public var lastError: String?
    private(set) var captureGeneration = 0
    private let fileURL: URL
    private let settings: UserSettings
    private let images: ImageCacheManager
    private let queue = DispatchQueue(label: "com.clipback.storage", qos: .utility)
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var knownImages: Set<String> = []
    private var canWrite = true
    private var recoveryImages: Set<String> = []

    init(directory: URL? = nil, settings: UserSettings? = nil, images: ImageCacheManager? = nil) {
        let defaultAppSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let newDir = defaultAppSupport.appendingPathComponent("Clipback", isDirectory: true)
        let oldDir = defaultAppSupport.appendingPathComponent("Clipory", isDirectory: true)

        if directory == nil && !FileManager.default.fileExists(atPath: newDir.path) && FileManager.default.fileExists(atPath: oldDir.path) {
            try? FileManager.default.moveItem(at: oldDir, to: newDir)
        }

        let targetDir = directory ?? newDir
        fileURL = targetDir.appendingPathComponent("history.json")
        self.settings = settings ?? .shared
        self.images = images ?? .shared
        loadTask = Task { await loadItems() }
    }

    func waitUntilLoaded() async { await loadTask?.value }

    public var retainedBytes: Int {
        items.reduce(0) { $0 + Self.payloadBytes($1) }
    }

    private static func payloadBytes(_ item: ClipboardItem) -> Int {
        var bytes = item.imageFileSize ?? 0
        bytes += item.rtfContent?.count ?? 0
        for text in [item.textContent, item.htmlContent, item.ocrText, item.qrCodePayload] {
            bytes += text?.utf8.count ?? 0
        }
        return bytes
    }

    @discardableResult
    public func addItem(_ newItem: ClipboardItem) -> ClipboardItem? {
        guard !isLoading, canWrite else { return nil }
        if let name = newItem.imageFileName { knownImages.insert(name) }
        if let index = items.firstIndex(where: { Self.isDuplicate($0, newItem) }) {
            var existing = items.remove(at: index)
            existing.timestamp = newItem.timestamp
            existing.sourceAppBundleId = newItem.sourceAppBundleId ?? existing.sourceAppBundleId
            existing.sourceAppName = newItem.sourceAppName ?? existing.sourceAppName
            items.insert(existing, at: 0)
            changed()
            return existing
        }
        items.insert(newItem, at: 0)
        pruneHistory(forceSave: true)
        return items.first(where: { $0.id == newItem.id })
    }

    /// Moves an item to the top of the history and updates its timestamp to the current time (Most Recently Used)
    public func touchItem(_ item: ClipboardItem) {
        guard !isLoading, canWrite else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if index == 0 {
            items[0].timestamp = Date()
            changed()
            return
        }
        var updated = items.remove(at: index)
        updated.timestamp = Date()
        items.insert(updated, at: 0)
        changed()
    }

    static func isDuplicate(_ a: ClipboardItem, _ b: ClipboardItem) -> Bool {
        guard a.contentType == b.contentType else { return false }
        switch a.contentType {
        case .text, .link, .colorHex: return a.textContent == b.textContent && a.htmlContent == b.htmlContent && a.rtfContent == b.rtfContent
        case .richText: return a.textContent == b.textContent && a.htmlContent == b.htmlContent && a.rtfContent == b.rtfContent
        case .file: return a.filePaths == b.filePaths
        case .image:
            guard let hash = a.imageSHA256, let other = b.imageSHA256 else { return false }
            return hash == other
        }
    }

    public func updateOCRData(for itemId: UUID, ocrText: String?, qrPayload: String?, failed: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[index].ocrText = ocrText
        items[index].qrCodePayload = qrPayload
        items[index].ocrStatus = failed ? "failed" : "complete"
        pruneHistory(forceSave: true)
    }

    public func updateQRPayload(for itemId: UUID, qrPayload: String?) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        guard items[index].qrCodePayload != qrPayload else { return }
        items[index].qrCodePayload = qrPayload
        pruneHistory(forceSave: true)
    }

    public func updateOCRText(for itemId: UUID, ocrText: String?, failed: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[index].ocrText = ocrText
        items[index].ocrStatus = failed ? "failed" : "complete"
        pruneHistory(forceSave: true)
    }

    public func togglePin(for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        pruneHistory(forceSave: true)
    }

    public func deleteItem(_ item: ClipboardItem) {
        guard items.contains(where: { $0.id == item.id }) else { return }
        lastDeletedItem = item
        items.removeAll { $0.id == item.id }
        changed()
    }

    public func undoDelete() {
        guard let deleted = lastDeletedItem else { return }
        lastDeletedItem = nil
        items.append(deleted)
        items.sort { $0.timestamp > $1.timestamp }
        // A manual Undo restores the item; retention applies on the next ordinary mutation.
        changed()
    }

    public func clearAll(keepPinned: Bool = true) {
        guard !isLoading else { return }
        captureGeneration += 1
        lastDeletedItem = nil
        items = keepPinned ? items.filter(\.isPinned) : []
        changed()
    }

    public func pruneHistory(forceSave: Bool = false) {
        guard !isLoading else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.retentionDays, to: Date()) ?? .distantPast
        let budget = settings.maxStorageMB > 0 ? Int64(settings.maxStorageMB) * 1024 * 1024 : Int64.max
        var bytes = items.filter(\.isPinned).reduce(Int64(0)) { $0 + Int64(Self.payloadBytes($1)) }
        var normalCount = 0
        let kept = items.filter { item in
            if item.isPinned { return true }
            if settings.retentionMode == .byTime, settings.retentionDays > 0, item.timestamp < cutoff { return false }
            if settings.retentionMode == .byCount, settings.maxHistoryCount > 0, normalCount >= settings.maxHistoryCount { return false }
            let size = Int64(Self.payloadBytes(item))
            guard bytes + size <= budget else { return false }
            bytes += size
            normalCount += 1
            return true
        }
        let pruned = kept.count != items.count
        if pruned { items = kept }
        if pruned || forceSave { changed() }
    }

    private func changed() {
        revision += 1
        saveTask?.cancel()
        saveTask = Task {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            _ = await persist()
        }
    }

    /// Called before termination; a failed write is reported instead of silently losing history.
    @discardableResult
    public func flush() async -> Bool {
        await waitUntilLoaded()
        saveTask?.cancel()
        return await persist()
    }

    private func persist() async -> Bool {
        guard canWrite, !isLoading else { return false }
        let snapshot = items
        let target = fileURL
        let savedRevision = revision
        let result: Bool = await withCheckedContinuation { continuation in
            queue.async {
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    try encoder.encode(snapshot).write(to: target, options: .atomic)
                    continuation.resume(returning: true)
                } catch { continuation.resume(returning: false) }
            }
        }
        guard result else {
            lastError = L10n.errorStorageSaveFailed(lang: settings.appLanguage)
            return false
        }
        // A newer revision may reference files that an older snapshot does not contain.
        if savedRevision == revision {
            var retained = Set(items.compactMap(\.imageFileName))
            retained.formUnion(recoveryImages)
            if let name = lastDeletedItem?.imageFileName { retained.insert(name) }
            let retired = knownImages.subtracting(retained)
            knownImages.subtract(retired)
            await images.deleteImages(retired)
        }
        return true
    }

    private func loadItems() async {
        let target = fileURL
        let existingImages = await images.storedFileNames()
        let result: Result<([ClipboardItem], Bool, Set<String>), Error> = await withCheckedContinuation { continuation in
            queue.async {
                do {
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let directoryFiles = try FileManager.default.contentsOfDirectory(at: target.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                    var protectedImages: Set<String> = []
                    for backup in directoryFiles where backup.lastPathComponent.hasPrefix("history.corrupt.") && !backup.lastPathComponent.hasSuffix(".images.json") {
                        let manifest = backup.appendingPathExtension("images.json")
                        if let data = try? Data(contentsOf: manifest), let names = try? JSONDecoder().decode(Set<String>.self, from: data) {
                            protectedImages.formUnion(names)
                        } else {
                            // Older recovery backups have no manifest: preserve their potential images.
                            protectedImages.formUnion(existingImages)
                        }
                    }
                    guard FileManager.default.fileExists(atPath: target.path) else {
                        continuation.resume(returning: .success(([], false, protectedImages))); return
                    }
                    let data = try Data(contentsOf: target)
                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let decoded = try decoder.decode([ClipboardItem].self, from: data)
                        guard Set(decoded.map(\.id)).count == decoded.count else { throw CocoaError(.fileReadCorruptFile) }
                        continuation.resume(returning: .success((decoded, false, protectedImages)))
                    } catch {
                        // Preserve original bytes and their image files before allowing new writes.
                        let backup = target.deletingLastPathComponent().appendingPathComponent("history.corrupt.\(UUID().uuidString).json")
                        try data.write(to: backup, options: .withoutOverwriting)
                        try JSONEncoder().encode(existingImages).write(to: backup.appendingPathExtension("images.json"), options: .withoutOverwriting)
                        protectedImages.formUnion(existingImages)
                        continuation.resume(returning: .success(([], true, protectedImages)))
                    }
                } catch { continuation.resume(returning: .failure(error)) }
            }
        }
        switch result {
        case .success(let (loaded, recovered, protectedImages)):
            items = loaded.map { item in
                var item = item
                if item.ocrStatus == "pending" { item.ocrStatus = "interrupted" }
                return item
            }
            recoveryImages = protectedImages
            knownImages = existingImages
            if recovered {
                lastError = L10n.errorStorageCorruptBackup(lang: settings.appLanguage)
            }
            isLoading = false
            pruneHistory(forceSave: true)
        case .failure:
            canWrite = false
            isLoading = false
            lastError = L10n.errorStorageReadFailed(lang: settings.appLanguage)
        }
    }
}
