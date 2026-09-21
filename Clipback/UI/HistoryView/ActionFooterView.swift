import SwiftUI

/// Action Bar at the bottom of the HUD window with native SF Symbols and keycap badges
public struct ActionFooterView: View {
    public let itemCount: Int
    public let lang: AppLanguage
    public let isCurrentPinned: Bool
    public let onPaste: () -> Void
    public let onCopy: () -> Void
    public let onPastePlain: () -> Void
    public let onDelete: () -> Void
    public let onTogglePin: () -> Void
    
    public init(
        itemCount: Int,
        lang: AppLanguage,
        isCurrentPinned: Bool = false,
        onPaste: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onPastePlain: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onTogglePin: @escaping () -> Void
    ) {
        self.itemCount = itemCount
        self.lang = lang
        self.isCurrentPinned = isCurrentPinned
        self.onPaste = onPaste
        self.onCopy = onCopy
        self.onPastePlain = onPastePlain
        self.onDelete = onDelete
        self.onTogglePin = onTogglePin
    }
    
    public var body: some View {
        HStack(spacing: 16) {
            // Item count indicator with SF Symbol
            HStack(spacing: 5) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 11))
                Text(L10n.itemsCount(itemCount, lang: lang))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.secondary)
            
            Spacer()
            
            // Action shortcut buttons styled with native macOS keycaps
            HStack(spacing: 12) {
                // 1. Paste (Primary Action)
                actionButton(
                    label: L10n.actionPaste(lang: lang),
                    action: onPaste
                ) {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                }
                
                // 2. Copy to Clipboard
                actionButton(
                    label: L10n.actionCopy(lang: lang),
                    action: onCopy
                ) {
                    HStack(spacing: 2) {
                        Image(systemName: "command")
                            .font(.system(size: 9, weight: .semibold))
                        Text("C")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                }
                
                // 3. Paste as Plain Text
                actionButton(
                    label: L10n.actionPastePlain(lang: lang),
                    action: onPastePlain
                ) {
                    HStack(spacing: 2) {
                        Image(systemName: "option")
                            .font(.system(size: 9, weight: .semibold))
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                
                // 4. Toggle Pin
                actionButton(
                    label: isCurrentPinned ? L10n.actionUnpin(lang: lang) : L10n.actionPin(lang: lang),
                    action: onTogglePin
                ) {
                    HStack(spacing: 2) {
                        Image(systemName: "command")
                            .font(.system(size: 9, weight: .semibold))
                        Text("P")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                }
                
                // 5. Delete Item
                actionButton(
                    label: L10n.actionDelete(lang: lang),
                    action: onDelete
                ) {
                    HStack(spacing: 2) {
                        Image(systemName: "command")
                            .font(.system(size: 9, weight: .semibold))
                        Image(systemName: "delete.backward")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }
    
    // MARK: - Keycap Action Button
    
    private func actionButton<KeycapContent: View>(
        label: String,
        action: @escaping () -> Void,
        @ViewBuilder keycap: () -> KeycapContent
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                // Standard macOS Keycap badge frame
                HStack(spacing: 2) {
                    keycap()
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .foregroundColor(.primary)
                
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
