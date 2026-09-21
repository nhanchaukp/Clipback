import Foundation
import AppKit
@preconcurrency import ApplicationServices

/// Checks and requests macOS Accessibility permissions
@MainActor
public final class AccessibilityManager {
    public static let shared = AccessibilityManager()
    
    private init() {}
    
    /// Checks whether the application is trusted for Accessibility
    public var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    /// Prompts the system permission dialog if not already trusted
    @discardableResult
    public func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// Opens the Accessibility pane directly in macOS System Settings
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
