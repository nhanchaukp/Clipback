import Combine
import AppKit
import Foundation

/// DTO representing release asset from GitHub Releases API
public struct GitHubAsset: Codable, Sendable, Equatable {
    public let name: String
    public let browserDownloadURL: String
    public let size: Int?
    public let contentType: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case contentType = "content_type"
    }
    
    public init(name: String, browserDownloadURL: String, size: Int? = nil, contentType: String? = nil) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.size = size
        self.contentType = contentType
    }
}

/// DTO representing GitHub release response
public struct GitHubRelease: Codable, Sendable, Equatable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: String
    public let publishedAt: String?
    public let assets: [GitHubAsset]?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
    
    public init(
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        htmlURL: String,
        publishedAt: String? = nil,
        assets: [GitHubAsset]? = nil
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.assets = assets
    }
}

/// Information about an available application release
public struct ReleaseInfo: Sendable, Equatable {
    public let tagName: String
    public let version: String
    public let name: String
    public let body: String
    public let htmlURL: URL
    public let dmgDownloadURL: URL?
    public let dmgSize: Int?
    public let publishedAt: Date?
    
    public init(
        tagName: String,
        version: String,
        name: String,
        body: String,
        htmlURL: URL,
        dmgDownloadURL: URL? = nil,
        dmgSize: Int? = nil,
        publishedAt: Date? = nil
    ) {
        self.tagName = tagName
        self.version = version
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.dmgDownloadURL = dmgDownloadURL
        self.dmgSize = dmgSize
        self.publishedAt = publishedAt
    }
}

/// Current status of the update check
public enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case updateAvailable(ReleaseInfo)
    case error(String)
}

/// Lightweight, native service checking for new application versions directly from GitHub Releases
@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()
    
    /// Repository owner and name on GitHub
    public static let repositoryOwner = "nhanchaukp"
    public static let repositoryName = "clipback"
    
    /// Published status observable by SwiftUI views
    @Published public private(set) var status: UpdateStatus = .idle
    @Published public private(set) var latestRelease: ReleaseInfo?
    
    private let session: URLSession
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    /// Current running application version string
    public static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    
    /// Clean semantic version string (strips 'v' or 'V' prefix)
    public static func cleanVersion(_ versionStr: String) -> String {
        var clean = versionStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasPrefix("v") {
            clean.removeFirst()
        }
        return clean
    }
    
    /// Compares two semantic version strings (e.g., "1.0.1" vs "1.0.0")
    public static func isVersion(_ remote: String, newerThan current: String) -> Bool {
        let v1Components = cleanVersion(remote).split(separator: ".").compactMap { Int($0) }
        let v2Components = cleanVersion(current).split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(v1Components.count, v2Components.count)
        for i in 0..<maxCount {
            let num1 = i < v1Components.count ? v1Components[i] : 0
            let num2 = i < v2Components.count ? v2Components[i] : 0
            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }
        return false
    }
    
    /// Asynchronously checks for new updates from GitHub Releases
    @discardableResult
    public func checkForUpdates(isUserInitiated: Bool = true) async -> UpdateStatus {
        guard status != .checking else { return status }
        
        status = .checking
        
        guard let apiURL = URL(string: "https://api.github.com/repos/\(Self.repositoryOwner)/\(Self.repositoryName)/releases/latest") else {
            let err = "Invalid GitHub API URL"
            status = .error(err)
            if isUserInitiated { showAlert(for: status) }
            return status
        }
        
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Clipback/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let err = "Invalid server response"
                status = .error(err)
                if isUserInitiated { showAlert(for: status) }
                return status
            }
            
            if httpResponse.statusCode == 404 {
                // No releases created yet on this repository
                let now = Date()
                UserSettings.shared.lastUpdateCheckDate = now
                status = .upToDate(checkedAt: now)
                if isUserInitiated { showAlert(for: status) }
                return status
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let err = "GitHub API returned status code \(httpResponse.statusCode)"
                status = .error(err)
                if isUserInitiated { showAlert(for: status) }
                return status
            }
            
            let decoder = JSONDecoder()
            let ghRelease = try decoder.decode(GitHubRelease.self, from: data)
            
            let releaseInfo = parseRelease(ghRelease)
            let now = Date()
            UserSettings.shared.lastUpdateCheckDate = now
            
            if Self.isVersion(releaseInfo.version, newerThan: Self.currentVersion) {
                latestRelease = releaseInfo
                status = .updateAvailable(releaseInfo)
                // Always show alert when update is available
                showAlert(for: status)
            } else {
                status = .upToDate(checkedAt: now)
                if isUserInitiated {
                    showAlert(for: status)
                }
            }
            return status
            
        } catch {
            let now = Date()
            UserSettings.shared.lastUpdateCheckDate = now
            let errMessage = error.localizedDescription
            status = .error(errMessage)
            if isUserInitiated {
                showAlert(for: status)
            }
            return status
        }
    }
    
    /// Parses GitHubRelease into domain model ReleaseInfo
    public func parseRelease(_ gh: GitHubRelease) -> ReleaseInfo {
        let tag = gh.tagName
        let version = Self.cleanVersion(tag)
        let title = gh.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (gh.name ?? "Clipback \(version)")
            : "Clipback \(version)"
        let body = gh.body ?? ""
        let htmlURL = URL(string: gh.htmlURL) ?? URL(string: "https://github.com/\(Self.repositoryOwner)/\(Self.repositoryName)/releases")!
        
        // Find .dmg asset if available
        var dmgURL: URL?
        var dmgSize: Int?
        if let assets = gh.assets {
            if let dmgAsset = assets.first(where: { $0.name.hasSuffix(".dmg") }) {
                dmgURL = URL(string: dmgAsset.browserDownloadURL)
                dmgSize = dmgAsset.size
            }
        }
        
        var pubDate: Date?
        if let pubStr = gh.publishedAt {
            let formatter = ISO8601DateFormatter()
            pubDate = formatter.date(from: pubStr)
        }
        
        return ReleaseInfo(
            tagName: tag,
            version: version,
            name: title,
            body: body,
            htmlURL: htmlURL,
            dmgDownloadURL: dmgURL,
            dmgSize: dmgSize,
            publishedAt: pubDate
        )
    }
    
    /// Opens the direct download URL for the .dmg or falls back to GitHub release page
    public func openReleaseDownload(_ release: ReleaseInfo) {
        let target = release.dmgDownloadURL ?? release.htmlURL
        NSWorkspace.shared.open(target)
    }
    
    /// Displays a native macOS modal alert with the check results
    private func showAlert(for status: UpdateStatus) {
        let lang = UserSettings.shared.appLanguage
        let alert = NSAlert()
        
        switch status {
        case .updateAvailable(let release):
            alert.alertStyle = .informational
            alert.messageText = L10n.updateAvailableTitle(lang: lang)
            
            var info = L10n.updateAvailableDesc(version: release.version, lang: lang)
            if !release.name.isEmpty && release.name != release.version {
                info += "\n\n" + release.name
            }
            if !release.body.isEmpty {
                // Short preview of release notes (up to 300 characters)
                let preview = release.body.prefix(300)
                info += "\n\n" + preview + (release.body.count > 300 ? "..." : "")
            }
            alert.informativeText = info
            
            alert.addButton(withTitle: L10n.updateDownloadButton(lang: lang))
            alert.addButton(withTitle: L10n.updateViewRelease(lang: lang))
            alert.addButton(withTitle: L10n.updateDismiss(lang: lang))
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                openReleaseDownload(release)
            } else if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(release.htmlURL)
            }
            
        case .upToDate:
            alert.alertStyle = .informational
            alert.messageText = L10n.updateUpToDate(lang: lang)
            alert.informativeText = L10n.updateUpToDateDesc(version: Self.currentVersion, lang: lang)
            alert.addButton(withTitle: "OK")
            alert.runModal()
            
        case .error(let errorMsg):
            alert.alertStyle = .warning
            alert.messageText = L10n.updateFailed(lang: lang)
            alert.informativeText = L10n.updateFailedDesc(error: errorMsg, lang: lang)
            alert.addButton(withTitle: "OK")
            alert.runModal()
            
        case .idle, .checking:
            break
        }
    }
}
