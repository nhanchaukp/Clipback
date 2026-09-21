import AppKit
import Combine

@MainActor
protocol PasteEnvironment {
    var activePID: pid_t? { get }
    var isTrusted: Bool { get }
    func isAlive(_ pid: pid_t) -> Bool
    func activate(_ pid: pid_t) -> Bool
    func requestPermission()
    func postPaste(to pid: pid_t) -> Bool
}

@MainActor
private struct SystemPasteEnvironment: PasteEnvironment {
    var activePID: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    var isTrusted: Bool { AccessibilityManager.shared.isAccessibilityGranted }
    func isAlive(_ pid: pid_t) -> Bool { NSRunningApplication(processIdentifier: pid)?.isTerminated == false }
    func activate(_ pid: pid_t) -> Bool { NSRunningApplication(processIdentifier: pid)?.activate() ?? false }
    func requestPermission() {
        AccessibilityManager.shared.requestAccessibility()
        AccessibilityManager.shared.openAccessibilitySettings()
    }
    func postPaste(to pid: pid_t) -> Bool {
        guard activePID == pid, isAlive(pid), isTrusted else { return false }
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        // Both events target the same process, even if focus changes immediately afterward.
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }
}

@MainActor
public final class PasteService: ObservableObject {
    public static let shared = PasteService()
    public var previousApplication: NSRunningApplication?
    @Published public private(set) var isBusy = false
    @Published public var lastError: String?
    private let pasteboard: NSPasteboard
    private let images: ImageCacheManager
    private let settings: UserSettings
    private let environment: any PasteEnvironment
    private var operationID = UUID()

    init(pasteboard: NSPasteboard = .general, images: ImageCacheManager? = nil,
         settings: UserSettings? = nil, environment: (any PasteEnvironment)? = nil) {
        self.pasteboard = pasteboard
        self.images = images ?? .shared
        self.settings = settings ?? .shared
        self.environment = environment ?? SystemPasteEnvironment()
    }

    private func fail(_ message: String) -> Bool {
        lastError = message
        return false
    }

    /// Build a complete payload before replacing the clipboard, including lossless whitespace/RTF.
    private func payload(for item: ClipboardItem, plainTextOnly: Bool) async -> [NSPasteboardItem]? {
        let entry = NSPasteboardItem()
        switch item.contentType {
        case .text, .colorHex, .link, .richText:
            guard let text = item.textContent else { return nil }
            entry.setString(text, forType: .string)
            if !plainTextOnly {
                if let html = item.htmlContent { entry.setString(html, forType: .html) }
                if let rtf = item.rtfContent { entry.setData(rtf, forType: .rtf) }
            }
        case .image:
            guard let name = item.imageFileName, let data = await images.imageData(fileName: name) else { return nil }
            entry.setData(data, forType: .png)
        case .file:
            guard let paths = item.filePaths, !paths.isEmpty, paths.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else { return nil }
            return paths.map { path in
                let file = NSPasteboardItem()
                file.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
                file.setData(Data([1]), forType: ClipboardMonitor.ownContentType)
                return file
            }
        }
        entry.setData(Data([1]), forType: ClipboardMonitor.ownContentType)
        return [entry]
    }

    @discardableResult
    public func copyToClipboard(_ item: ClipboardItem, plainTextOnly: Bool = false, playSound: Bool = true) async -> Bool {
        operationID = UUID() // Any new copy cancels an earlier pending paste.
        let token = operationID
        let previousCount = pasteboard.changeCount
        guard let objects = await payload(for: item, plainTextOnly: plainTextOnly) else {
            return fail(L10n.errorPasteItemUnavailable(lang: settings.appLanguage))
        }
        guard token == operationID, previousCount == pasteboard.changeCount else {
            return fail(L10n.errorPasteClipboardChanged(lang: settings.appLanguage))
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(objects) else {
            return fail(L10n.errorPasteWriteFailed(lang: settings.appLanguage))
        }
        lastError = nil
        if playSound && settings.playSounds {
            SoundEffectManager.playSound(named: settings.soundName)
        }
        return true
    }

    @discardableResult
    public func pasteItem(_ item: ClipboardItem, plainTextOnly: Bool = false) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        let target = previousApplication?.processIdentifier ?? environment.activePID
        guard await copyToClipboard(item, plainTextOnly: plainTextOnly, playSound: !settings.pasteDirectly) else { return false }
        guard settings.pasteDirectly else { return true }
        guard environment.isTrusted else {
            // Accessibility is not granted: item has been copied to clipboard.
            // Silently close HUD without alerts or opening system settings.
            if settings.playSounds { SoundEffectManager.playSound(named: settings.soundName) }
            return true
        }
        guard let target, target != ProcessInfo.processInfo.processIdentifier,
              environment.isAlive(target), environment.activate(target) else {
            if settings.playSounds { SoundEffectManager.playSound(named: settings.soundName) }
            return true
        }
        let token = operationID
        let count = pasteboard.changeCount
        var stableSamples = 0
        for _ in 0..<20 {
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return false }
            guard token == operationID, count == pasteboard.changeCount, environment.isAlive(target) else { break }
            let active = environment.activePID
            // Never steal focus back from a different destination chosen by the user.
            if active != target && active != ProcessInfo.processInfo.processIdentifier { break }
            stableSamples = active == target ? stableSamples + 1 : 0
            if stableSamples >= 2 {
                guard environment.postPaste(to: target) else { break }
                if settings.playSounds { SoundEffectManager.playSound(named: settings.soundName) }
                return true
            }
        }
        return fail(L10n.errorPasteCancelledFocusChanged(lang: settings.appLanguage))
    }
}
