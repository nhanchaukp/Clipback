import Foundation

/// Defines all supported clipboard content types in Clipback
public enum ContentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case text       // Plain text
    case richText   // Formatted text (RTF / HTML)
    case image      // Image data (PNG / JPEG / TIFF)
    case colorHex   // Color code (HEX, RGB, HSL)
    case link       // Web URL (http/https)
    case file       // System file URL (file://)

    public var id: String { rawValue }

    /// Returns the localized display name for the content type
    public func localizedName(lang: AppLanguage = .english) -> String {
        switch self {
        case .text:
            return L10n.contentTypeText(lang: lang)
        case .richText:
            return L10n.contentTypeRichText(lang: lang)
        case .image:
            return L10n.contentTypeImage(lang: lang)
        case .colorHex:
            return L10n.contentTypeColor(lang: lang)
        case .link:
            return L10n.contentTypeLink(lang: lang)
        case .file:
            return L10n.contentTypeFile(lang: lang)
        }
    }

    /// English display name fallback
    public var displayName: String {
        localizedName(lang: .english)
    }

    /// Native SF Symbol name for each content type
    public var systemImage: String {
        switch self {
        case .text: return "doc.text"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .colorHex: return "paintpalette"
        case .link: return "link"
        case .file: return "folder"
        }
    }
}
