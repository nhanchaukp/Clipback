import SwiftUI
import AppKit

/// Renders a single row in the master clipboard history list with native macOS selection styling
public struct ItemRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false
    
    public let item: ClipboardItem
    public let isSelected: Bool
    public let shortcutIndex: Int? // 1..9 for ⌘1..⌘9 quick paste
    public let lang: AppLanguage
    
    public init(
        item: ClipboardItem,
        isSelected: Bool,
        shortcutIndex: Int?,
        showBadge: Bool = false,
        showAppIcon: Bool = false,
        showThumbnail: Bool = true,
        lang: AppLanguage = .english
    ) {
        self.item = item
        self.isSelected = isSelected
        self.shortcutIndex = shortcutIndex
        self.lang = lang
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            // Content Type Icon or Color Hex Circle
            contentIconView
                .frame(width: 18, height: 18)
            
            // Preview title and metadata
            HStack(spacing: 5) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .orange)
                }
                
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 6)
            
            // Image thumbnail preview (always visible if copied item is an image)
            if item.contentType == .image, let fileName = item.imageFileName {
                ClipboardImageView(fileName: fileName, maxPixelSize: 84, fill: true)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isSelected ? Color.white.opacity(0.35) : Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            }
            
            // Quick paste keycap badge: ⌘1 .. ⌘9
            if let index = shortcutIndex, index <= 9 {
                HStack(spacing: 2) {
                    Image(systemName: "command")
                        .font(.system(size: 8, weight: .medium))
                    Text("\(index)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.white.opacity(0.22) : Color(nsColor: .controlBackgroundColor))
                        .shadow(color: isSelected ? .clear : .black.opacity(0.08), radius: 1, y: 0.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Color.white.opacity(0.28) : Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
                )
                .foregroundColor(isSelected ? .white : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : (isHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.6) : Color.clear))
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.displayTitle)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
    
    // MARK: - Subviews & Visual Helpers
    
    @ViewBuilder
    private var contentIconView: some View {
        if item.contentType == .colorHex, let hex = item.colorHex, let color = ColorExtractor.nsColor(from: hex) {
            Circle()
                .fill(Color(nsColor: color))
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? Color.white.opacity(0.4) : Color.primary.opacity(0.22), lineWidth: 0.75)
                )
        } else {
            Image(systemName: item.contentType.systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(isSelected ? .white : .secondary)
        }
    }
}
