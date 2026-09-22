import AppKit
import SwiftUI

/// Extracts and formats color strings (HEX, RGB, HSL)
public struct ColorExtractor {
    
    /// Regular expression matching standard HEX color strings (#RGB, #RRGGBB, #RRGGBBAA)
    private static let hexRegex = try? NSRegularExpression(
        pattern: "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$",
        options: []
    )
    
    /// Validates and extracts a clean HEX color string from text
    public static func extractHexColor(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        guard let regex = hexRegex else { return nil }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        guard regex.firstMatch(in: trimmed, options: [], range: range) != nil else { return nil }
        
        return trimmed.uppercased()
    }
    
    /// Converts a HEX string into NSColor
    public static func nsColor(from hexString: String) -> NSColor? {
        var cleanHex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        
        var rgbValue: UInt64 = 0
        guard Scanner(string: cleanHex).scanHexInt64(&rgbValue) else { return nil }
        
        let r, g, b, a: CGFloat
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            r = CGFloat((rgbValue >> 8) & 0xF) / 15.0
            g = CGFloat((rgbValue >> 4) & 0xF) / 15.0
            b = CGFloat(rgbValue & 0xF) / 15.0
            a = 1.0
        case 6: // RGB (24-bit)
            r = CGFloat((rgbValue >> 16) & 0xFF) / 255.0
            g = CGFloat((rgbValue >> 8) & 0xFF) / 255.0
            b = CGFloat(rgbValue & 0xFF) / 255.0
            a = 1.0
        case 8: // RGBA (32-bit)
            r = CGFloat((rgbValue >> 24) & 0xFF) / 255.0
            g = CGFloat((rgbValue >> 16) & 0xFF) / 255.0
            b = CGFloat((rgbValue >> 8) & 0xFF) / 255.0
            a = CGFloat(rgbValue & 0xFF) / 255.0
        default:
            return nil
        }
        
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    
    /// Converts HEX to formatted RGB string: "rgb(255, 255, 255)"
    public static func rgbString(from hexString: String) -> String? {
        guard let color = nsColor(from: hexString) else { return nil }
        let r = Int(round(color.redComponent * 255))
        let g = Int(round(color.greenComponent * 255))
        let b = Int(round(color.blueComponent * 255))
        return "rgb(\(r), \(g), \(b))"
    }
    
    /// Converts HEX to formatted HSL string: "hsl(210, 100%, 50%)"
    public static func hslString(from hexString: String) -> String? {
        guard let color = nsColor(from: hexString) else { return nil }
        let h = Int(round(color.hueComponent * 360))
        let s = Int(round(color.saturationComponent * 100))
        let l = Int(round(color.brightnessComponent * 100))
        return "hsl(\(h), \(s)%, \(l)%)"
    }
}
