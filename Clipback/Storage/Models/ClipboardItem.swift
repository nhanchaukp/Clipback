import Foundation
import AppKit

/// Represents a single persistent clipboard history entry in Clipback
public struct ClipboardItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var timestamp: Date
    public var contentType: ContentType
    
    // Content payload
    public var textContent: String?
    public var htmlContent: String?
    public var colorHex: String?
    public var filePaths: [String]?
    
    // Image payload
    public var imageFileName: String?
    public var imageWidth: Double?
    public var imageHeight: Double?
    public var imageFileSize: Int?
    public var imageSHA256: String?
    public var ocrStatus: String?
    public var rtfContent: Data?
    
    // Vision OCR text extracted from images for full-text searchability
    public var ocrText: String?
    
    // QR Code payload extracted from images
    public var qrCodePayload: String?
    
    // Originating application metadata
    public var sourceAppBundleId: String?
    public var sourceAppName: String?
    
    // Pin status
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        contentType: ContentType,
        textContent: String? = nil,
        htmlContent: String? = nil,
        colorHex: String? = nil,
        filePaths: [String]? = nil,
        imageFileName: String? = nil,
        imageWidth: Double? = nil,
        imageHeight: Double? = nil,
        imageFileSize: Int? = nil,
        imageSHA256: String? = nil,
        ocrStatus: String? = nil,
        rtfContent: Data? = nil,
        ocrText: String? = nil,
        qrCodePayload: String? = nil,
        sourceAppBundleId: String? = nil,
        sourceAppName: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.contentType = contentType
        self.textContent = textContent
        self.htmlContent = htmlContent
        self.colorHex = colorHex
        self.filePaths = filePaths
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageFileSize = imageFileSize
        self.imageSHA256 = imageSHA256
        self.ocrStatus = ocrStatus
        self.rtfContent = rtfContent
        self.ocrText = ocrText
        self.qrCodePayload = qrCodePayload
        self.sourceAppBundleId = sourceAppBundleId
        self.sourceAppName = sourceAppName
        self.isPinned = isPinned
    }
    
    // MARK: - Display Helpers
    
    /// Short preview title displayed in the master history list
    public var displayTitle: String {
        switch contentType {
        case .text, .richText:
            let trimmed = (textContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = trimmed.prefix(240).split(whereSeparator: { $0.isNewline }).first
            return firstLine.map(String.init) ?? "Empty Text"
        case .image:
            if let w = imageWidth, let h = imageHeight {
                return "Image (\(Int(w)) × \(Int(h)))"
            }
            return "Image"
        case .colorHex:
            return colorHex ?? "Color Code"
        case .link:
            return textContent ?? "Web Link"
        case .file:
            if let firstFile = filePaths?.first {
                let name = URL(fileURLWithPath: firstFile).lastPathComponent
                if let count = filePaths?.count, count > 1 {
                    return "\(name) +\(count - 1)"
                }
                return name
            }
            return "File"
        }
    }
    
    /// Total word count for text contents
    public var wordCount: Int {
        guard let text = textContent, !text.isEmpty else { return 0 }
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
    
    /// Total character count for text contents
    public var characterCount: Int {
        return textContent?.count ?? 0
    }
    
    /// Relative time string (e.g. "2m ago", "1h ago")
    public var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    /// Checks whether the item contains a valid HTTP/HTTPS URL
    public var isURL: Bool {
        if contentType == .link { return true }
        guard let text = textContent?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              !text.contains("\n") else {
            return false
        }
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return true
        }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") {
            return true
        }
        return false
    }
}
