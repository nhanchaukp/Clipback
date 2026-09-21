import Foundation
import Carbon
import AppKit

/// Manages system-wide global hotkeys using the native Carbon Event HotKey API
@MainActor
public final class HotKeyManager {
    public static let shared = HotKeyManager()
    
    private var registeredKeys: (UInt32, UInt32)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyID = EventHotKeyID(signature: OSType(0x434C5059), id: 1) // "CLPY", 1
    
    public var onHotKeyPressed: (@MainActor @Sendable () -> Void)?
    
    private init() {
        installCarbonEventHandler()
    }
    
    /// Installs a low-level Carbon event handler for keyboard hotkey triggers
    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let event = event, let userData = userData else { return noErr }
            
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if status == noErr {
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                Task { @MainActor in manager.handleHotKeyEvent(id: id) }
            }
            return noErr
        }
        
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
    }
    
    private func handleHotKeyEvent(id: UInt32) {
        if id == hotKeyID.id {
            Task { @MainActor [weak self] in
                self?.onHotKeyPressed?()
            }
        }
    }
    
    /// Registers a global hotkey
    /// - Parameters:
    ///   - keyCode: Virtual key code (default: 9 for 'V')
    ///   - modifiers: Modifier flags (default: cmdKey | shiftKey)
    @discardableResult
    public func register(keyCode: UInt32 = 9, modifiers: UInt32 = UInt32(cmdKey | shiftKey)) -> Bool {
        if let keys = registeredKeys, keys.0 == keyCode, keys.1 == modifiers { return true }
        let nextID = EventHotKeyID(signature: hotKeyID.signature, id: hotKeyID.id &+ 1)
        var nextRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, nextID, GetApplicationEventTarget(), 0, &nextRef)
        guard status == noErr else { return false }
        unregister()
        hotKeyRef = nextRef
        hotKeyID = nextID
        registeredKeys = (keyCode, modifiers)
        return true
    }
    
    /// Unregisters the active global hotkey
    public func unregister() {
        registeredKeys = nil
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
    
    // MARK: - Key Names & Conversions
    
    /// Complete mapping table of macOS virtual keycodes to human-readable labels
    nonisolated public static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
    
    /// Returns human-readable name for a given macOS virtual key code
    nonisolated public static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key(\(keyCode))"
    }
    
    /// Converts Carbon modifier bitmask into an ordered array of symbols (e.g. ["⌃", "⌥", "⇧", "⌘"])
    nonisolated public static func modifierTokens(from modifiers: UInt32) -> [String] {
        var tokens: [String] = []
        if modifiers & UInt32(controlKey) != 0 { tokens.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { tokens.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { tokens.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { tokens.append("⌘") }
        return tokens
    }
    
    /// Formats key code and modifiers into a human-readable display string (e.g. "⌘ ⇧ V" or "⌥ Space")
    nonisolated public static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        let tokens = modifierTokens(from: modifiers)
        let key = keyName(for: keyCode)
        if tokens.isEmpty {
            return key
        }
        return (tokens + [key]).joined(separator: " ")
    }
    
    /// Converts Cocoa NSEvent.ModifierFlags to Carbon modifier mask
    nonisolated public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }
    
    /// Converts Carbon modifier mask to Cocoa NSEvent.ModifierFlags
    nonisolated public static func cocoaModifiers(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }
    
    /// Returns lowercase key equivalent string for NSMenuItem
    nonisolated public static func keyEquivalentString(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return " "
        case 36: return "\r"
        case 48: return "\t"
        case 51: return "\u{7f}"
        default:
            if let name = keyNames[keyCode], name.count == 1 {
                return name.lowercased()
            }
            return "v"
        }
    }
}
