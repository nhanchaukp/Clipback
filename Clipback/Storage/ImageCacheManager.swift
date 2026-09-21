import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Immutable configuration, a serial I/O queue, and a thread-safe NSCache.
public final class ImageCacheManager: @unchecked Sendable {
    public static let shared = ImageCacheManager()
    let imagesDirectory: URL
    private let queue = DispatchQueue(label: "com.clipback.images", qos: .utility)
    private let previews = NSCache<NSString, CGImage>()

    struct SavedImage: Sendable {
        let fileName: String
        let width: Double
        let height: Double
        let fileSize: Int
        let sha256: String
    }

    init(directory: URL? = nil) {
        let defaultAppSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let newDir = defaultAppSupport.appendingPathComponent("Clipback/Images", isDirectory: true)
        let oldDir = defaultAppSupport.appendingPathComponent("Clipory/Images", isDirectory: true)

        if directory == nil && !FileManager.default.fileExists(atPath: newDir.path) && FileManager.default.fileExists(atPath: oldDir.path) {
            try? FileManager.default.createDirectory(at: newDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: oldDir, to: newDir)
        }

        imagesDirectory = directory ?? newDir
        previews.totalCostLimit = 32 * 1024 * 1024
        previews.countLimit = 200
    }

    func url(for fileName: String) -> URL? {
        guard !fileName.isEmpty, fileName == (fileName as NSString).lastPathComponent,
              fileName != ".", fileName != ".." else { return nil }
        return imagesDirectory.appendingPathComponent(fileName)
    }

    func saveImage(data: Data) async -> SavedImage? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: autoreleasepool { self.save(data) }) }
        }
    }

    private func save(_ data: Data) -> SavedImage? {
        guard data.count <= 256 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 100_000_000 else { return nil }
        let png: Data
        if CGImageSourceGetType(source) as String? == UTType.png.identifier {
            png = data
        } else {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImageFromSource(destination, source, 0, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            png = output as Data
        }
        let name = UUID().uuidString + ".png"
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            try png.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
            return SavedImage(fileName: name, width: Double(width), height: Double(height), fileSize: png.count,
                              sha256: SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined())
        } catch { return nil }
    }

    func imageData(fileName: String) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.url(for: fileName).flatMap { try? Data(contentsOf: $0) }) }
        }
    }

    /// Decode only the pixels needed by the list or inspector; never cache originals.
    func preview(fileName: String, maxPixelSize: Int) async -> CGImage? {
        let key = "\(fileName):\(maxPixelSize)"
        if let image = previews.object(forKey: key as NSString) { return image }
        return await withCheckedContinuation { continuation in
            queue.async {
                let image: CGImage? = autoreleasepool {
                    if let cached = self.previews.object(forKey: key as NSString) { return cached }
                    guard let url = self.url(for: fileName),
                          let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
                    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                        kCGImageSourceShouldCacheImmediately: true]
                    guard let result = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
                    self.previews.setObject(result, forKey: key as NSString, cost: result.bytesPerRow * result.height)
                    return result
                }
                continuation.resume(returning: image)
            }
        }
    }

    func deleteImages(_ names: Set<String>) async {
        guard !names.isEmpty else { return }
        await withCheckedContinuation { continuation in
            queue.async {
                for name in names {
                    if let url = self.url(for: name) { try? FileManager.default.removeItem(at: url) }
                }
                self.previews.removeAllObjects()
                continuation.resume()
            }
        }
    }

    /// Only UUID-named PNG files belong to this store; leave unrelated files alone.
    func storedFileNames() async -> Set<String> {
        await withCheckedContinuation { continuation in
            queue.async {
                let urls = (try? FileManager.default.contentsOfDirectory(at: self.imagesDirectory, includingPropertiesForKeys: nil)) ?? []
                continuation.resume(returning: Set(urls.filter {
                    $0.pathExtension == "png" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil
                }.map(\.lastPathComponent)))
            }
        }
    }
}
