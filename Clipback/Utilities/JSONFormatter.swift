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
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(";") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
               (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }
    
    /// Parses, pretty-prints, and highlights JSON using pure Foundation & SwiftUI
    public static func formatAndHighlight(_ raw: String, maxChars: Int = 200_000) -> FormatResult? {
        guard isPotentialJSON(raw) else { return nil }
        guard raw.utf8.count <= maxChars else { return nil }
        
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(";") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 1. Try standard JSONSerialization first
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let prettyData = try? JSONSerialization.data(
               withJSONObject: obj,
               options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
           ),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            let attributed = highlight(prettyString: prettyString)
            return FormatResult(prettyString: prettyString, attributed: attributed)
        }
        
        // 2. Try auto-repairing common JSON flaws (missing commas between lines, trailing commas)
        let repaired = repairJSON(trimmed)
        if let data = repaired.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let prettyData = try? JSONSerialization.data(
               withJSONObject: obj,
               options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
           ),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            let attributed = highlight(prettyString: prettyString)
            return FormatResult(prettyString: prettyString, attributed: attributed)
        }
        
        // 3. Resilient Fallback: Best-effort pretty print and syntax highlight even with imperfect syntax
        let prettyString = trimmed.contains("\n") ? trimmed : lenientPrettyPrint(trimmed)
        let attributed = highlight(prettyString: prettyString)
        return FormatResult(prettyString: prettyString, attributed: attributed)
    }
    
    /// Heuristic repair for common developer JSON flaws (missing commas between lines, trailing commas)
    public static func repairJSON(_ text: String) -> String {
        var s = text
        
        // Missing comma between lines:
        // after } or ] or "string" or number/true/false/null, followed by newline and next "key":
        let missingCommaPattern = #"([}\]"\d]|true|false|null)\s*\n(\s*"[^"\n]+"\s*:)"#
        if let regex = try? NSRegularExpression(pattern: missingCommaPattern, options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "$1,\n$2")
        }
        
        // Trailing commas before } or ]
        let trailingCommaPattern = #",\s*([}\]])"#
        if let regex = try? NSRegularExpression(pattern: trailingCommaPattern, options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "$1")
        }
        
        return s
    }
    
    /// Token-based lenient indentation formatter when JSONSerialization cannot parse
    public static func lenientPrettyPrint(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count + text.count / 4)
        
        var indentLevel = 0
        let indent = "  "
        var inQuotes = false
        var isEscaped = false
        
        var i = text.startIndex
        while i < text.endIndex {
            let char = text[i]
            
            if isEscaped {
                result.append(char)
                isEscaped = false
                i = text.index(after: i)
                continue
            }
            
            if char == "\\" {
                result.append(char)
                isEscaped = true
                i = text.index(after: i)
                continue
            }
            
            if char == "\"" {
                inQuotes.toggle()
                result.append(char)
                i = text.index(after: i)
                continue
            }
            
            if inQuotes {
                result.append(char)
                i = text.index(after: i)
                continue
            }
            
            switch char {
            case "{", "[":
                result.append(char)
                indentLevel += 1
                result.append("\n")
                result.append(String(repeating: indent, count: max(0, indentLevel)))
            case "}", "]":
                indentLevel = max(0, indentLevel - 1)
                result.append("\n")
                result.append(String(repeating: indent, count: indentLevel))
                result.append(char)
            case ",":
                result.append(char)
                result.append("\n")
                result.append(String(repeating: indent, count: max(0, indentLevel)))
            case ":":
                result.append(": ")
            case " ", "\t", "\n", "\r":
                break
            default:
                result.append(char)
            }
            
            i = text.index(after: i)
        }
        
        return result
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
