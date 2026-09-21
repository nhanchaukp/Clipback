import AppKit
import SwiftUI

/// Coordinates presentation and screen centering of the FloatingPanel and auxiliary windows
@MainActor
public final class PanelController: NSObject, NSWindowDelegate {
    public static let shared = PanelController()
    
    static let didShow = Notification.Name("ClipbackPanelDidShow")
    static let didHide = Notification.Name("ClipbackPanelDidHide")
    private var panel: FloatingPanel?
    private var settingsWindow: NSWindow?
    
    private override init() {
        super.init()
    }
    
    /// Toggles visibility of the Clipback search HUD
    public func toggle() {
        if let panel = panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }
    
    /// Presents the floating panel centered on the screen containing the mouse cursor
    public func show() {
        // Record active app before opening for Direct Paste simulation
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            PasteService.shared.previousApplication = frontApp
        }
        
        if panel == nil {
            setupPanel()
        }
        
        guard let panel = panel else { return }
        
        centerPanelOnActiveScreen(panel)
        
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: Self.didShow, object: panel)
    }
    
    /// Hides the floating panel
    public func hide() {
        panel?.orderOut(nil)
        NotificationCenter.default.post(name: Self.didHide, object: panel)
    }
    
    /// Fixed panel dimensions for the Spotlight-style HUD
    public static let panelWidth: CGFloat = 780
    public static let panelHeight: CGFloat = 490
    
    /// Initializes the panel with the root SwiftUI view hierarchy
    private func setupPanel() {
        let fixedSize = NSSize(width: Self.panelWidth, height: Self.panelHeight)
        let rect = NSRect(origin: .zero, size: fixedSize)
        let floatingPanel = FloatingPanel(contentRect: rect)
        
        let contentView = HistoryMainView()
            .environmentObject(StorageManager.shared)
            .environmentObject(UserSettings.shared)
        
        let hostingView = NSHostingView(rootView: contentView)
        floatingPanel.contentView = hostingView
        floatingPanel.minSize = fixedSize
        floatingPanel.maxSize = fixedSize
        floatingPanel.setContentSize(fixedSize)
        floatingPanel.showsResizeIndicator = false
        
        self.panel = floatingPanel
    }
    
    /// Centers the panel on the display where the user's mouse is currently positioned
    private func centerPanelOnActiveScreen(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let activeScreen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? screens.first
        
        let fixedSize = NSSize(width: Self.panelWidth, height: Self.panelHeight)
        panel.setContentSize(fixedSize)
        
        guard let screen = activeScreen else {
            panel.center()
            return
        }
        
        let screenRect = screen.visibleFrame
        let x = screenRect.origin.x + (screenRect.width - Self.panelWidth) / 2
        // Position slightly above the exact center (Spotlight style: ~65% from bottom)
        let y = screenRect.origin.y + (screenRect.height - Self.panelHeight) * 0.65
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    // MARK: - Auxiliary Windows
    
    /// Opens the unified Settings window (Raycast style: reveals Dock icon only when open)
    public func showSettings(tab: SettingsTab = .general) {
        // 1. Show icon in Dock
        NSApp.setActivationPolicy(.regular)
        
        if settingsWindow == nil {
            let contentView = ContentView(initialTab: tab)
                .environmentObject(UserSettings.shared)
                .environmentObject(StorageManager.shared)
            
            let hostingController = NSHostingController(rootView: contentView)
            let window = NSWindow(contentViewController: hostingController)
            let lang = UserSettings.shared.appLanguage
            window.title = tab.title(lang: lang)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.minSize = NSSize(width: 640, height: 480)
            window.setContentSize(NSSize(width: 700, height: 560))
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.settingsWindow = window
        } else {
            NotificationCenter.default.post(name: .selectSettingsTab, object: tab)
        }
        
        guard let window = settingsWindow else { return }
        
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - NSWindowDelegate
    
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        // When settings window closes, hide app icon from Dock (Raycast style)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
