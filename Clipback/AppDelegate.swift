import AppKit
import SwiftUI

/// AppKit application delegate managing the application lifecycle and background services
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure starting as an accessory agent (no Dock icon, like Raycast)
        NSApp.setActivationPolicy(.accessory)
        
        // 0. Ensure only a single instance of Clipback is running
        if isDuplicateInstance() {
            print("Another instance of Clipback is already running. Exiting.")
            exit(0)
        }
        
        // 1. Start background clipboard watcher
        ClipboardMonitor.shared.startMonitoring()
        
        // 2. Setup menu bar status item
        MenuBarManager.shared.updateVisibility()
        
        // 3. Register global hotkey (default: ⌘ + Shift + V)
        setupGlobalHotKey()
        
        // 4. Check for updates in background if enabled (delayed 5s to avoid impacting launch)
        if UserSettings.shared.automaticallyCheckForUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                let lastCheck = UserSettings.shared.lastUpdateCheckDate
                let shouldCheck = lastCheck == nil || Date().timeIntervalSince(lastCheck!) > 86400
                if shouldCheck {
                    Task {
                        await UpdateChecker.shared.checkForUpdates(isUserInitiated: false)
                    }
                }
            }
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stopMonitoring()
        HotKeyManager.shared.unregister()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ClipboardMonitor.shared.stopMonitoring()
        Task {
            await ClipboardMonitor.shared.finishStopping()
            let saved = await StorageManager.shared.flush()
            if saved {
                sender.reply(toApplicationShouldTerminate: true)
            } else {
                let alert = NSAlert()
                let lang = UserSettings.shared.appLanguage
                alert.messageText = L10n.alertUnsavedHistoryTitle(lang: lang)
                alert.informativeText = StorageManager.shared.lastError ?? ""
                alert.addButton(withTitle: L10n.alertUnsavedHistoryGoBack(lang: lang))
                alert.addButton(withTitle: L10n.alertUnsavedHistoryQuitAnyway(lang: lang))
                let quit = alert.runModal() == .alertSecondButtonReturn
                if !quit { ClipboardMonitor.shared.startMonitoring() }
                sender.reply(toApplicationShouldTerminate: quit)
            }
        }
        return .terminateLater
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PanelController.shared.showSettings()
        return true
    }
    
    /// Registers the global system-wide hotkey listener
    private func setupGlobalHotKey() {
        let settings = UserSettings.shared
        HotKeyManager.shared.onHotKeyPressed = {
            PanelController.shared.toggle()
        }
        if !HotKeyManager.shared.register(
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers
        ) {
            UserSettings.shared.showInMenuBar = true
            MenuBarManager.shared.updateVisibility()
            StorageManager.shared.lastError = L10n.alertHotkeyUnavailable(lang: settings.appLanguage)
        }
    }
    
    /// Detects if another instance of Clipback is already running.
    /// If an existing instance is found, it activates that instance and returns true.
    private func isDuplicateInstance() -> Bool {
        // Skip check during automated unit testing
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
           NSClassFromString("XCTestCase") != nil {
            return false
        }
        
        let myPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications
        
        // 1. Check by bundle identifier (when running as packaged .app)
        if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
            let matched = runningApps.filter { $0.processIdentifier != myPID && $0.bundleIdentifier == bundleID }
            if let existing = matched.first {
                existing.activate()
                return true
            }
        }
        
        // 2. Check by executable name (fallback for CLI debug runs like swift run)
        let myExecName = Bundle.main.executableURL?.lastPathComponent ?? "Clipback"
        let matchedExec = runningApps.filter { app in
            guard app.processIdentifier != myPID else { return false }
            return app.executableURL?.lastPathComponent == myExecName || app.localizedName == myExecName
        }
        if let existing = matchedExec.first {
            existing.activate()
            return true
        }
        
        return false
    }
}
