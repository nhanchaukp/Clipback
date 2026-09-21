import Foundation
import AppKit
@preconcurrency import ApplicationServices

/// Checks and requests macOS Accessibility permissions
@MainActor
public final class AccessibilityManager {
    public static let shared = AccessibilityManager()
    
    private init() {}
    
    /// Checks whether the application is trusted for Accessibility without prompting
    public var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    /// Opens the Accessibility pane in System Settings directly without prompting the system dialog
    @discardableResult
    public func requestAccessibility() -> Bool {
        openAccessibilitySettings()
        return isAccessibilityGranted
    }
    
    /// Opens the Accessibility pane directly in macOS System Settings
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            if !NSWorkspace.shared.open(url) {
                if let fallbackUrl = URL(string: "x-apple.systempreferences:") {
                    NSWorkspace.shared.open(fallbackUrl)
                }
            }
        }
    }
}
