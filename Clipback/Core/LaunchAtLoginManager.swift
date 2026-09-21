import Foundation
import ServiceManagement

/// Manages system login item registration using modern SMAppService (macOS 13+)
@MainActor
public final class LaunchAtLoginManager {
    public static let shared = LaunchAtLoginManager()
    
    private init() {}
    
    /// Checks whether launch at login is currently registered
    public var isEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }
    
    /// Enables or disables launch at login for the main application bundle
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            return false
        }
        return isEnabled == enabled
    }
}
