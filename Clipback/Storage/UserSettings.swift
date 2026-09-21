import Foundation
import Combine
import Carbon

/// History retention strategy modes
public enum RetentionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case byCount
    case byTime
    
    public var id: String { rawValue }
}

/// Menu bar icon display styles
public enum MenuBarIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case adaptiveColor
    case monochrome
    
    public var id: String { rawValue }
    
    public func title(lang: AppLanguage) -> String {
        switch self {
        case .adaptiveColor: return L10n.menuBarAdaptiveColor(lang: lang)
        case .monochrome: return L10n.menuBarMonochrome(lang: lang)
        }
    }
}

/// Manages all persistent user preferences using UserDefaults
@MainActor
public final class UserSettings: ObservableObject {
    public static let shared = UserSettings()
    
    private let defaults: UserDefaults
    @Published public var monitoringPaused: Bool {
        didSet { defaults.set(monitoringPaused, forKey: "monitoringPaused") }
    }
    @Published public var excludedAppBundleIDs: String {
        didSet { defaults.set(excludedAppBundleIDs, forKey: "excludedAppBundleIDs") }
    }
    /// Zero preserves the existing unlimited storage behavior.
    @Published public var maxStorageMB: Int {
        didSet { defaults.set(maxStorageMB, forKey: "maxStorageMB") }
    }

    public func excludesApplication(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedAppBundleIDs.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
    }
    
    // MARK: - Language & Localization
    
    @Published public var appLanguage: AppLanguage {
        didSet { defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage) }
    }
    
    // MARK: - System & Launch
    
    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    
    @Published public var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) }
    }
    
    @Published public var menuBarIconStyle: MenuBarIconStyle {
        didSet { defaults.set(menuBarIconStyle.rawValue, forKey: Keys.menuBarIconStyle) }
    }
    
    @Published public var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Keys.playSounds) }
    }
    
    @Published public var pasteDirectly: Bool {
        didSet { defaults.set(pasteDirectly, forKey: Keys.pasteDirectly) }
    }
    
    /// Opacity level of the floating HUD window background (0.85, 0.96, 1.0)
    @Published public var hudOpacity: Double {
        didSet { defaults.set(hudOpacity, forKey: Keys.hudOpacity) }
    }
    
    // MARK: - Content Type Filters
    
    @Published public var saveText: Bool {
        didSet { defaults.set(saveText, forKey: Keys.saveText) }
    }
    
    @Published public var saveImages: Bool {
        didSet { defaults.set(saveImages, forKey: Keys.saveImages) }
    }
    
    @Published public var detectQrInImages: Bool {
        didSet { defaults.set(detectQrInImages, forKey: Keys.detectQrInImages) }
    }
    
    @Published public var saveColors: Bool {
        didSet { defaults.set(saveColors, forKey: Keys.saveColors) }
    }
    
    @Published public var saveFiles: Bool {
        didSet { defaults.set(saveFiles, forKey: Keys.saveFiles) }
    }
    
    // MARK: - List Item Row Appearance
    
    @Published public var showContentTypeBadge: Bool {
        didSet { defaults.set(showContentTypeBadge, forKey: Keys.showContentTypeBadge) }
    }
    
    @Published public var showSourceAppIcon: Bool {
        didSet { defaults.set(showSourceAppIcon, forKey: Keys.showSourceAppIcon) }
    }
    
    @Published public var showImageThumbnail: Bool {
        didSet { defaults.set(showImageThumbnail, forKey: Keys.showImageThumbnail) }
    }
    
    // MARK: - History Retention Policy (Count vs Time)
    
    @Published public var retentionMode: RetentionMode {
        didSet { defaults.set(retentionMode.rawValue, forKey: Keys.retentionMode) }
    }
    
    /// Max history item count (0 = Unlimited, 100, 300, 500, 1000)
    @Published public var maxHistoryCount: Int {
        didSet { defaults.set(maxHistoryCount, forKey: Keys.maxHistoryCount) }
    }
    
    /// Max history retention duration in days (0 = Forever, 7, 14, 30, 90)
    @Published public var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Keys.retentionDays) }
    }
    
    // MARK: - Global Hotkey Configuration
    
    /// Virtual key code (default is keycode 9 for 'V' in macOS Carbon)
    @Published public var hotkeyKeyCode: UInt32 {
        didSet {
            defaults.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode)
        }
    }
    
    /// Key modifiers mask (default: ⌘ + Shift)
    @Published public var hotkeyModifiers: UInt32 {
        didSet {
            defaults.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers)
        }
    }
    
    // MARK: - Updates

    @Published public var automaticallyCheckForUpdates: Bool {
        didSet { defaults.set(automaticallyCheckForUpdates, forKey: Keys.automaticallyCheckForUpdates) }
    }

    @Published public var lastUpdateCheckDate: Date? {
        didSet { defaults.set(lastUpdateCheckDate, forKey: Keys.lastUpdateCheckDate) }
    }

    /// Resets the global hotkey to default ⌘ + Shift + V
    public func resetHotkeyToDefault() {
        _ = updateHotkey(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey))
    }

    @discardableResult
    public func updateHotkey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard HotKeyManager.shared.register(keyCode: keyCode, modifiers: modifiers) else { return false }
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        MenuBarManager.shared.refreshMenu()
        return true
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.monitoringPaused = defaults.bool(forKey: "monitoringPaused")
        self.excludedAppBundleIDs = defaults.string(forKey: "excludedAppBundleIDs") ?? ""
        self.maxStorageMB = max(0, defaults.integer(forKey: "maxStorageMB"))
        let savedLang = defaults.string(forKey: Keys.appLanguage) ?? AppLanguage.english.rawValue
        self.appLanguage = AppLanguage(rawValue: savedLang) ?? .english
        
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.showInMenuBar = defaults.object(forKey: Keys.showInMenuBar) as? Bool ?? true
        let savedIconStyle = defaults.string(forKey: Keys.menuBarIconStyle) ?? MenuBarIconStyle.adaptiveColor.rawValue
        self.menuBarIconStyle = MenuBarIconStyle(rawValue: savedIconStyle) ?? .adaptiveColor
        self.playSounds = defaults.object(forKey: Keys.playSounds) as? Bool ?? true
        self.pasteDirectly = defaults.object(forKey: Keys.pasteDirectly) as? Bool ?? true
        self.hudOpacity = defaults.object(forKey: Keys.hudOpacity) as? Double ?? 0.96
        
        self.saveText = defaults.object(forKey: Keys.saveText) as? Bool ?? true
        self.saveImages = defaults.object(forKey: Keys.saveImages) as? Bool ?? true
        self.detectQrInImages = defaults.object(forKey: Keys.detectQrInImages) as? Bool ?? true
        self.saveColors = defaults.object(forKey: Keys.saveColors) as? Bool ?? true
        self.saveFiles = defaults.object(forKey: Keys.saveFiles) as? Bool ?? true
        
        self.showContentTypeBadge = defaults.object(forKey: Keys.showContentTypeBadge) as? Bool ?? true
        self.showSourceAppIcon = defaults.object(forKey: Keys.showSourceAppIcon) as? Bool ?? true
        self.showImageThumbnail = defaults.object(forKey: Keys.showImageThumbnail) as? Bool ?? true
        
        let savedMode = defaults.string(forKey: Keys.retentionMode) ?? RetentionMode.byCount.rawValue
        self.retentionMode = RetentionMode(rawValue: savedMode) ?? .byCount
        self.maxHistoryCount = defaults.object(forKey: Keys.maxHistoryCount) as? Int ?? 500
        self.retentionDays = defaults.object(forKey: Keys.retentionDays) as? Int ?? 30
        
        self.automaticallyCheckForUpdates = defaults.object(forKey: Keys.automaticallyCheckForUpdates) as? Bool ?? true
        self.lastUpdateCheckDate = defaults.object(forKey: Keys.lastUpdateCheckDate) as? Date
        
        // Keycode 9 is 'V', Carbon cmdKey (256) | shiftKey (512) = 768
        self.hotkeyKeyCode = defaults.object(forKey: Keys.hotkeyKeyCode) as? UInt32 ?? 9
        self.hotkeyModifiers = defaults.object(forKey: Keys.hotkeyModifiers) as? UInt32 ?? (256 | 512)
    }
    
    private enum Keys {
        static let appLanguage = "appLanguage"
        static let launchAtLogin = "launchAtLogin"
        static let showInMenuBar = "showInMenuBar"
        static let menuBarIconStyle = "menuBarIconStyle"
        static let playSounds = "playSounds"
        static let pasteDirectly = "pasteDirectly"
        static let hudOpacity = "hudOpacity"
        static let saveText = "saveText"
        static let saveImages = "saveImages"
        static let detectQrInImages = "detectQrInImages"
        static let saveColors = "saveColors"
        static let saveFiles = "saveFiles"
        static let showContentTypeBadge = "showContentTypeBadge"
        static let showSourceAppIcon = "showSourceAppIcon"
        static let showImageThumbnail = "showImageThumbnail"
        static let retentionMode = "retentionMode"
        static let maxHistoryCount = "maxHistoryCount"
        static let retentionDays = "retentionDays"
        static let automaticallyCheckForUpdates = "automaticallyCheckForUpdates"
        static let lastUpdateCheckDate = "lastUpdateCheckDate"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
    }
}
