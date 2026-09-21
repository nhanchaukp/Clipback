import AppKit

/// Manages the status bar item and menu in the macOS Menu Bar
@MainActor
public final class MenuBarManager: NSObject {
    public static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    
    private override init() {
        super.init()
    }
    
    /// Updates status bar visibility based on user preferences
    public func updateVisibility() {
        if UserSettings.shared.showInMenuBar {
            setupStatusItem()
        } else {
            removeStatusItem()
        }
    }
    
    /// Re-renders menu titles when language changes
    public func refreshMenu() {
        guard let item = statusItem else { return }
        let lang = UserSettings.shared.appLanguage
        
        let menu = NSMenu()
        
        let keyCode = UserSettings.shared.hotkeyKeyCode
        let carbonMods = UserSettings.shared.hotkeyModifiers
        let keyChar = HotKeyManager.keyEquivalentString(for: keyCode)
        let cocoaMods = HotKeyManager.cocoaModifiers(from: carbonMods)
        
        let showItem = createMenuItem(
            title: L10n.menuOpenClipback(lang: lang),
            action: #selector(openClipboard),
            keyEquivalent: keyChar,
            symbolName: "interface.window",
            modifierMask: cocoaMods
        )
        menu.addItem(showItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = createMenuItem(
            title: L10n.menuSettings(lang: lang),
            action: #selector(openSettings),
            keyEquivalent: ",",
            symbolName: "gearshape"
        )
        menu.addItem(settingsItem)
        
        let checkUpdatesItem = createMenuItem(
            title: L10n.menuCheckUpdates(lang: lang),
            action: #selector(checkUpdates),
            symbolName: "arrow.triangle.2.circlepath"
        )
        menu.addItem(checkUpdatesItem)
        
        let aboutItem = createMenuItem(
            title: L10n.menuAbout(lang: lang),
            action: #selector(openAbout),
            symbolName: "info.circle"
        )
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = createMenuItem(
            title: L10n.menuQuit(lang: lang),
            action: #selector(quitApp),
            keyEquivalent: "q",
            symbolName: "power"
        )
        menu.addItem(quitItem)
        
        item.menu = menu
    }
    
    /// Helper to create an NSMenuItem with explicit SF Symbol image
    private func createMenuItem(
        title: String,
        action: Selector?,
        keyEquivalent: String = "",
        symbolName: String? = nil,
        modifierMask: NSEvent.ModifierFlags? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let modifierMask = modifierMask {
            item.keyEquivalentModifierMask = modifierMask
        }
        if let symbolName = symbolName, let icon = menuIcon(symbolName) {
            item.image = icon
        }
        return item
    }
    
    /// Creates a rendered template SF Symbol image formatted for NSMenuItem
    private func menuIcon(_ symbolName: String) -> NSImage? {
        let pointSize: CGFloat = 13
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            return nil
        }
        
        let targetSize = NSSize(width: 16, height: 16)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        let symSize = symbol.size
        let drawRect = NSRect(
            x: (targetSize.width - symSize.width) / 2,
            y: (targetSize.height - symSize.height) / 2,
            width: symSize.width,
            height: symSize.height
        )
        symbol.draw(in: drawRect)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
    
    /// Initializes the NSStatusItem in the system menu bar
    private func setupStatusItem() {
        guard statusItem == nil else {
            updateIcon()
            refreshMenu()
            return
        }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        refreshMenu()
    }
    
    /// Updates the menu bar icon based on user preference and macOS appearance
    public func updateIcon() {
        guard let button = statusItem?.button else { return }
        
        let style = UserSettings.shared.menuBarIconStyle
        let iconSize = NSSize(width: 18, height: 18)
        
        switch style {
        case .monochrome:
            if let templateImg = loadResourceImage("MenuBarIcon_Template") {
                templateImg.size = iconSize
                templateImg.isTemplate = true
                button.image = templateImg
            } else {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                let image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Clipback")?
                    .withSymbolConfiguration(config)
                image?.isTemplate = true
                button.image = image
            }
            
        case .adaptiveColor:
            let colorImg = loadResourceImage("MenuBarIcon_Color")
                ?? loadResourceImage("MenuBarIcon_Light")
                ?? loadResourceImage("MenuBarIcon_Dark")
                ?? loadResourceImage("AppIcon")
            
            if let img = colorImg {
                img.size = iconSize
                img.isTemplate = false
                button.image = img
            } else {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                let image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Clipback")?
                    .withSymbolConfiguration(config)
                image?.isTemplate = true
                button.image = image
            }
        }
        
        let shortcutStr = HotKeyManager.displayString(
            keyCode: UserSettings.shared.hotkeyKeyCode,
            modifiers: UserSettings.shared.hotkeyModifiers
        )
        button.toolTip = L10n.menuBarTooltip(shortcut: shortcutStr, lang: UserSettings.shared.appLanguage)
    }
    
    /// Helper to locate and load image resources from app bundle or local directory
    private func loadResourceImage(_ name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let bundleResources = Bundle.main.resourcePath {
            let path = (bundleResources as NSString).appendingPathComponent("\(name).png")
            if let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        if let img = NSImage(contentsOfFile: "Resources/\(name).png") {
            return img
        }
        return nil
    }
    
    /// Removes the status item from the system menu bar
    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
    
    // MARK: - Menu Actions
    
    @objc private func openClipboard() {
        PanelController.shared.toggle()
    }

    @objc private func openSettings() {
        PanelController.shared.showSettings(tab: .general)
    }

    @objc private func checkUpdates() {
        PanelController.shared.showSettings(tab: .about)
        Task { @MainActor in
            await UpdateChecker.shared.checkForUpdates()
        }
    }
    
    @objc private func openAbout() {
        PanelController.shared.showSettings(tab: .about)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
