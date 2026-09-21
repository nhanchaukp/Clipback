import SwiftUI
import AppKit
import Carbon

/// Interactive hotkey recorder without border, displaying a Raycast-style popover to record shortcuts
public struct HotKeyRecorderView: View {
    @EnvironmentObject private var settings: UserSettings
    
    @State private var showPopover: Bool = false
    @State private var isHovered: Bool = false
    
    // Popover recording state
    @State private var pendingKeyCode: UInt32 = 9
    @State private var pendingModifiers: UInt32 = 0
    @State private var hasNewShortcut: Bool = false
    @State private var heldModifiers: NSEvent.ModifierFlags = []
    @State private var validationWarning: String? = nil
    @State private var eventMonitor: Any? = nil
    
    private var lang: AppLanguage {
        settings.appLanguage
    }
    
    private var isDefaultShortcut: Bool {
        settings.hotkeyKeyCode == 9 && settings.hotkeyModifiers == UInt32(cmdKey | shiftKey)
    }
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 6) {
            // Hotkey trigger button: clean keycaps, NO border
            Button {
                showPopover = true
            } label: {
                HStack(spacing: 4) {
                    let tokens = HotKeyManager.modifierTokens(from: settings.hotkeyModifiers)
                    let key = HotKeyManager.keyName(for: settings.hotkeyKeyCode)
                    
                    ForEach(tokens, id: \.self) { token in
                        keyCapView(token)
                    }
                    keyCapView(key)
                    
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(isHovered ? .accentColor : .secondary)
                        .padding(.leading, 3)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help(lang == .vietnamese ? "Nhấp để đổi phím tắt" : "Click to change shortcut")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                raycastPopoverContent
            }
            
            // Reset to Default button (⌘ ⇧ V)
            if !isDefaultShortcut {
                Button {
                    _ = settings.updateHotkey(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey))
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help(L10n.recordShortcutReset(lang: lang))
            }
        }
    }
    
    // MARK: - Row Keycap (No border)
    
    private func keyCapView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.07))
            )
    }
    
    // MARK: - Raycast-Style Popover Content
    
    private var raycastPopoverContent: some View {
        VStack(spacing: 0) {
            // Main Recording Area (Centered Large Keycaps)
            VStack {
                Spacer()
                
                if let warning = validationWarning {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 22))
                        Text(warning)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                } else {
                    HStack(spacing: 10) {
                        let tokens: [String] = {
                            if hasNewShortcut {
                                return HotKeyManager.modifierTokens(from: pendingModifiers)
                            } else if !heldModifiers.isEmpty {
                                return activeModifierTokens()
                            } else {
                                return HotKeyManager.modifierTokens(from: settings.hotkeyModifiers)
                            }
                        }()
                        
                        let keyString: String? = {
                            if hasNewShortcut {
                                return HotKeyManager.keyName(for: pendingKeyCode)
                            } else if !heldModifiers.isEmpty {
                                return "•••"
                            } else {
                                return HotKeyManager.keyName(for: settings.hotkeyKeyCode)
                            }
                        }()
                        
                        ForEach(tokens, id: \.self) { token in
                            largeKeyCap(token, isHighlighted: hasNewShortcut || !heldModifiers.isEmpty)
                        }
                        
                        if let key = keyString {
                            largeKeyCap(key, isHighlighted: hasNewShortcut)
                        }
                    }
                }
                
                Spacer()
            }
            .frame(height: 110)
            
            Divider()
                .opacity(0.4)
            
            // Footer (Raycast style: Action label on left, Close Esc / Save ↵ on right)
            HStack(spacing: 8) {
                // Left: Icon + Action Title
                HStack(spacing: 8) {
                    if let logo = appLogoImage {
                        Image(nsImage: logo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.accentColor.opacity(0.85))
                                .frame(width: 20, height: 20)
                            Image(systemName: "paperclip")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    Text(lang == .vietnamese ? "Mở Clipback" : "Toggle Clipback")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // Right: Keyboard Hints (Save ↵ / Close Esc)
                HStack(spacing: 10) {
                    if hasNewShortcut {
                        HStack(spacing: 4) {
                            Text(lang == .vietnamese ? "Lưu" : "Save")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            footerKeyBadge("↵")
                        }
                        .transition(.opacity)
                    }
                    
                    HStack(spacing: 4) {
                        Text(lang == .vietnamese ? "Đóng" : "Close")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        footerKeyBadge("Esc")
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
        }
        .frame(width: 320, height: 148)
        .onAppear {
            startRecording()
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    // Large centered keycap (Raycast style: 42x42 rounded rect)
    private func largeKeyCap(_ text: String, isHighlighted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: text.count > 2 ? 14 : 19, weight: .medium, design: .rounded))
            .foregroundColor(.primary)
            .frame(minWidth: 42, minHeight: 42)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isHighlighted ? 0.12 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isHighlighted ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
    
    // Tiny footer key badge e.g. [Esc], [↵]
    private func footerKeyBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
            )
    }
    
    // MARK: - Event Monitoring & Capture
    
    private func startRecording() {
        pendingKeyCode = settings.hotkeyKeyCode
        pendingModifiers = settings.hotkeyModifiers
        hasNewShortcut = false
        validationWarning = nil
        heldModifiers = []
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                self.heldModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
                self.validationWarning = nil
                return nil
            }
            
            if event.type == .keyDown {
                // Esc key (code 53) cancels
                if event.keyCode == 53 {
                    self.cancelRecording()
                    return nil
                }
                
                // Return / Enter key (code 36 or 76) saves
                if event.keyCode == 36 || event.keyCode == 76 {
                    self.saveRecording()
                    return nil
                }
                
                let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
                let isFunctionKey = Set<UInt16>([122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]).contains(event.keyCode)
                
                if flags.isEmpty && !isFunctionKey {
                    self.validationWarning = L10n.recordShortcutModifierNeeded(lang: self.lang)
                    NSSound.beep()
                    return nil
                }
                
                self.pendingKeyCode = UInt32(event.keyCode)
                self.pendingModifiers = HotKeyManager.carbonModifiers(from: flags)
                self.hasNewShortcut = true
                self.validationWarning = nil
                return nil
            }
            
            return event
        }
    }
    
    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        heldModifiers = []
        validationWarning = nil
    }
    
    private func saveRecording() {
        guard settings.updateHotkey(keyCode: pendingKeyCode, modifiers: pendingModifiers) else {
            validationWarning = L10n.warningHotkeyRegistrationFailed(lang: lang)
            return
        }
        stopRecording()
        showPopover = false
    }
    
    private func cancelRecording() {
        stopRecording()
        showPopover = false
    }
    
    private func activeModifierTokens() -> [String] {
        var tokens: [String] = []
        if heldModifiers.contains(.control) { tokens.append("⌃") }
        if heldModifiers.contains(.option) { tokens.append("⌥") }
        if heldModifiers.contains(.shift) { tokens.append("⇧") }
        if heldModifiers.contains(.command) { tokens.append("⌘") }
        return tokens
    }
    
    private var appLogoImage: NSImage? {
        if let imagePath = Bundle.main.path(forResource: "AppIcon", ofType: "png") ??
                           Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: imagePath) {
            return img
        }
        if let localImg = NSImage(contentsOfFile: "Resources/AppIcon.png") {
            return localImg
        }
        return NSImage(named: "AppIcon")
    }
}
