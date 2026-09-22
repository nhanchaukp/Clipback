import Foundation
import SwiftUI

/// Ultra-lightweight, zero-dependency JSON detector, pretty-formatter, and syntax highlighter
nonisolated public enum JSONFormatter {
    
    public struct FormatResult: Sendable {
        public let prettyString: String
        public let attributed: AttributedString
        
        public init(prettyString: String, attributed: AttributedString) {
            self.prettyString = prettyString
            self.attributed = attributed
        }
    }
    
    /// Fast heuristic check whether text could be a JSON object or array
    public static func isPotentialJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
               (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }
    
    /// Parses, pretty-prints, and highlights JSON using pure Foundation & SwiftUI
    public static func formatAndHighlight(_ raw: String, maxChars: Int = 100_000) -> FormatResult? {
        guard isPotentialJSON(raw) else { return nil }
        guard raw.utf8.count <= maxChars else { return nil }
        guard let data = raw.data(using: .utf8) else { return nil }
        
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: obj,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        
        let attributed = highlight(prettyString: prettyString)
        return FormatResult(prettyString: prettyString, attributed: attributed)
    }
    
    /// Pure regex-based syntax highlighter for pretty-printed JSON
    public static func highlight(prettyString: String) -> AttributedString {
        var attributed = AttributedString(prettyString)
        
        guard let regex = try? NSRegularExpression(
            pattern: "(\"(\\\\.|[^\"])*\"\\s*:)|(\"(\\\\.|[^\"])*\")|(\\b-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?\\b)|(\\b(true|false|null)\\b)",
            options: []
        ) else {
            return attributed
        }
        
        let nsString = prettyString as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: prettyString, options: [], range: fullRange)
        
        for match in matches {
            let matchRange = match.range
            guard let strRange = Range(matchRange, in: prettyString),
                  let attrRange = Range(strRange, in: attributed) else { continue }
            
            if match.range(at: 1).location != NSNotFound {
                // Key with trailing colon: color the quoted string portion
                let matchedText = nsString.substring(with: matchRange)
                if let colonIdx = matchedText.lastIndex(of: ":") {
                    let keySub = matchedText[..<colonIdx].trimmingCharacters(in: .whitespaces)
                    if let keyRangeInString = prettyString.range(of: keySub, range: strRange),
                       let keyAttrRange = Range(keyRangeInString, in: attributed) {
                        attributed[keyAttrRange].foregroundColor = .purple
                    }
                }
            } else if match.range(at: 3).location != NSNotFound {
                // String value
                attributed[attrRange].foregroundColor = .green
            } else if match.range(at: 5).location != NSNotFound {
                // Number
                attributed[attrRange].foregroundColor = .blue
            } else if match.range(at: 8).location != NSNotFound {
                // Boolean or null
                attributed[attrRange].foregroundColor = .orange
            }
        }
        
        return attributed
    }
}
