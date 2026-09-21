import SwiftUI
import AppKit

struct ClipboardImageView: View {
    let fileName: String
    let maxPixelSize: Int
    var fill = false
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: "\(fileName):\(maxPixelSize)") {
            image = nil
            failed = false
            let loaded = await ImageCacheManager.shared.preview(fileName: fileName, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            image = loaded
            failed = loaded == nil
        }
    }
}

@MainActor
final class SourceAppIconCache {
    static let shared = SourceAppIconCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() { cache.countLimit = 64 }
    func icon(for bundleID: String) -> NSImage? {
        if let icon = cache.object(forKey: bundleID as NSString) { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: bundleID as NSString)
        return icon
    }
}
