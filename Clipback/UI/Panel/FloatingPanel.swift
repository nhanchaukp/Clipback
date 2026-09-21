import AppKit
import SwiftUI

/// Borderless, non-activating floating HUD panel with native vibrancy and spotlight presentation
public final class FloatingPanel: NSPanel {
    
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.animationBehavior = .utilityWindow
        self.minSize = contentRect.size
        self.maxSize = contentRect.size
    }
    
    public override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        var rect = frameRect
        rect.size = NSSize(width: PanelController.panelWidth, height: PanelController.panelHeight)
        super.setFrame(rect, display: displayFlag)
    }
    
    /// Must return true so the window can receive keyboard input for search and navigation
    public override var canBecomeKey: Bool {
        return true
    }
    
    public override var canBecomeMain: Bool {
        return true
    }
    
    /// Automatically closes when the user clicks outside or the panel loses focus
    public override func resignKey() {
        super.resignKey()
        PanelController.shared.hide()
    }
    
    /// Closes when the Escape key is pressed
    public override func cancelOperation(_ sender: Any?) {
        PanelController.shared.hide()
    }
}
