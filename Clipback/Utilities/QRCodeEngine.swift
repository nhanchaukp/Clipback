import Foundation
import AppKit
import CoreImage

/// High-performance native QR code generator and cache powered by Apple CoreImage
public final class QRCodeEngine: @unchecked Sendable {
    public static let shared = QRCodeEngine()
    
    // Thread-safe in-memory cache for generated QR code images
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        cache.countLimit = 50
    }
    
    /// Generates a razor-sharp NSImage QR code from a string (such as a URL)
    /// - Parameters:
    ///   - string: The payload string to encode
    ///   - size: Desired width and height of the square output image in points (default: 160)
    ///   - correctionLevel: Error correction level ("L", "M", "Q", "H"). Default is "M".
    /// - Returns: A crisp NSImage, or nil if generation fails
    public func generateQRCode(
        from string: String,
        size: CGFloat = 160,
        correctionLevel: String = "M"
    ) -> NSImage? {
        let cacheKey = "\(string)_\(Int(size))_\(correctionLevel)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")
        
        guard let outputCIImage = filter.outputImage else {
            return nil
        }
        
        // Native QR codes from CIQRCodeGenerator are very small (e.g. 27x27 pixels).
        // We scale it using nearest-neighbor affine transform to maintain sharp pixel edges without blur.
        let extent = outputCIImage.extent
        let scaleX = size / extent.width
        let scaleY = size / extent.height
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        let scaledCIImage = outputCIImage.transformed(by: transform)
        
        let rep = NSCIImageRep(ciImage: scaledCIImage)
        let nsImage = NSImage(size: NSSize(width: size, height: size))
        nsImage.addRepresentation(rep)
        
        cache.setObject(nsImage, forKey: cacheKey)
        return nsImage
    }
    
    /// Copies a generated QR code image to the general system pasteboard
    /// - Parameter image: The NSImage to copy
    @MainActor
    public func copyQRCodeImageToPasteboard(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(pngData, forType: .png)
        NSPasteboard.general.setData(tiffData, forType: .tiff)
        NSPasteboard.general.setData(Data([1]), forType: ClipboardMonitor.ownContentType)
    }
}
