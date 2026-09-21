import Foundation

/// Supported application languages (English is the default)
public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case vietnamese = "vi"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }
}

/// Centralized localization engine reading standard `Localizable.strings` files
nonisolated public struct L10n {
    
    // MARK: - Core Localization Engine
    
    private final class Storage: @unchecked Sendable {
        static let shared = Storage()
        private let lock = NSLock()
        private var tableCache: [String: [String: String]] = [:]
        
        func string(forKey key: String, lang: AppLanguage) -> String {
            lock.lock()
            defer { lock.unlock() }
            
            let code = lang.rawValue
            if let table = tableCache[code], let val = table[key] {
                return val
            }
            
            // Load table if not yet cached
            let table = loadTable(for: lang)
            tableCache[code] = table
            if let val = table[key] {
                return val
            }
            
            // Fallback to English if missing in target language
            if lang != .english {
                let enTable = tableCache["en"] ?? {
                    let loaded = loadTable(for: .english)
                    tableCache["en"] = loaded
                    return loaded
                }()
                if let enVal = enTable[key] {
                    return enVal
                }
            }
            
            return key
        }
        
        private func loadTable(for lang: AppLanguage) -> [String: String] {
            let langCode = lang.rawValue
            let fileName = "Localizable.strings"
            let lprojName = "\(langCode).lproj"
            
            // 1. Check inside main bundle (packaged App)
            if let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: lprojName),
               let dict = NSDictionary(contentsOfFile: path) as? [String: String] {
                return dict
            }
            
            // 2. Check main bundle resources path directly
            if let resPath = Bundle.main.resourcePath {
                let directPath = (resPath as NSString).appendingPathComponent("\(lprojName)/\(fileName)")
                if let dict = NSDictionary(contentsOfFile: directPath) as? [String: String] {
                    return dict
                }
            }
            
            // 3. Check working directory `Resources/<lang>.lproj/Localizable.strings` (for `swift run`)
            let cwdPath = "Resources/\(lprojName)/\(fileName)"
            if let dict = NSDictionary(contentsOfFile: cwdPath) as? [String: String] {
                return dict
            }
            
            // 4. Resolve relative to source file directory (for `swift test`)
            let thisFile = URL(fileURLWithPath: #filePath)
            // #filePath: Sources/Clipback/Utilities/Localization.swift
            let repoRoot = thisFile
                .deletingLastPathComponent() // Utilities
                .deletingLastPathComponent() // Clipback
                .deletingLastPathComponent() // Sources
                .deletingLastPathComponent() // Repo Root
            let devPath = repoRoot.appendingPathComponent("Resources/\(lprojName)/\(fileName)").path
            if let dict = NSDictionary(contentsOfFile: devPath) as? [String: String] {
                return dict
            }
            
            return [:]
        }
    }
    
    /// Translates a localized key with optional format arguments
    public static func tr(_ key: String, lang: AppLanguage, _ args: CVarArg...) -> String {
        let format = Storage.shared.string(forKey: key, lang: lang)
        if args.isEmpty {
            return format
        }
        return String(format: format, arguments: args)
    }

    // MARK: - Navigation & Filters
    public static func filterAll(lang: AppLanguage) -> String { tr("filter.all", lang: lang) }
    public static func filterText(lang: AppLanguage) -> String { tr("filter.text", lang: lang) }
    public static func filterImage(lang: AppLanguage) -> String { tr("filter.image", lang: lang) }
    public static func filterColor(lang: AppLanguage) -> String { tr("filter.color", lang: lang) }
    public static func filterLink(lang: AppLanguage) -> String { tr("filter.link", lang: lang) }
    public static func filterPinned(lang: AppLanguage) -> String { tr("filter.pinned", lang: lang) }

    // MARK: - Search & HUD
    public static func searchPlaceholder(lang: AppLanguage) -> String { tr("search.placeholder", lang: lang) }
    public static func noResults(lang: AppLanguage) -> String { tr("search.noResults", lang: lang) }
    public static func selectItemPreview(lang: AppLanguage) -> String { tr("search.selectItemPreview", lang: lang) }
    public static func itemsCount(_ count: Int, lang: AppLanguage) -> String {
        if lang == .vietnamese || count != 1 {
            return tr("search.itemsCount.plural", lang: lang, count)
        } else {
            return tr("search.itemsCount.singular", lang: lang)
        }
    }
    public static func settingsTooltip(lang: AppLanguage) -> String { tr("search.settingsTooltip", lang: lang) }
    public static func loadingHistory(lang: AppLanguage) -> String { tr("search.loadingHistory", lang: lang) }
    public static func emptyPrompt(lang: AppLanguage) -> String { tr("search.emptyPrompt", lang: lang) }

    // MARK: - Action Bar
    public static func actionPaste(lang: AppLanguage) -> String { tr("action.paste", lang: lang) }
    public static func actionCopy(lang: AppLanguage) -> String { tr("action.copy", lang: lang) }
    public static func actionPastePlain(lang: AppLanguage) -> String { tr("action.pastePlain", lang: lang) }
    public static func actionPin(lang: AppLanguage) -> String { tr("action.pin", lang: lang) }
    public static func actionUnpin(lang: AppLanguage) -> String { tr("action.unpin", lang: lang) }
    public static func actionDelete(lang: AppLanguage) -> String { tr("action.delete", lang: lang) }

    // MARK: - Detail Inspector
    public static func textTypeLabel(lang: AppLanguage) -> String { tr("detail.textTypeLabel", lang: lang) }
    public static func textStats(chars: Int, words: Int, lang: AppLanguage) -> String {
        tr("detail.textStats", lang: lang, chars, words)
    }
    public static func ocrHeader(lang: AppLanguage) -> String { tr("detail.ocrHeader", lang: lang) }
    public static func openInBrowser(lang: AppLanguage) -> String { tr("detail.openInBrowser", lang: lang) }
    public static func webLink(lang: AppLanguage) -> String { tr("detail.webLink", lang: lang) }
    public static func systemFiles(lang: AppLanguage) -> String { tr("detail.systemFiles", lang: lang) }
    public static func qrDetectedHeader(lang: AppLanguage) -> String { tr("detail.qrDetectedHeader", lang: lang) }
    public static func qrGenerateTab(lang: AppLanguage) -> String { tr("detail.qrGenerateTab", lang: lang) }
    public static func qrGenerateTip(lang: AppLanguage) -> String { tr("detail.qrGenerateTip", lang: lang) }
    public static func copyQrImage(lang: AppLanguage) -> String { tr("detail.copyQrImage", lang: lang) }
    public static func qrImageCopied(lang: AppLanguage) -> String { tr("detail.qrImageCopied", lang: lang) }
    public static func copyQrText(lang: AppLanguage) -> String { tr("detail.copyQrText", lang: lang) }
    public static func openQrLink(lang: AppLanguage) -> String { tr("detail.openQrLink", lang: lang) }

    // MARK: - Settings Window Tabs
    public static func settingsTitle(lang: AppLanguage) -> String { tr("settings.title", lang: lang) }
    public static func tabGeneral(lang: AppLanguage) -> String { tr("settings.tab.general", lang: lang) }
    public static func tabHotkeys(lang: AppLanguage) -> String { tr("settings.tab.hotkeys", lang: lang) }
    public static func tabFilters(lang: AppLanguage) -> String { tr("settings.tab.filters", lang: lang) }
    public static func tabStorage(lang: AppLanguage) -> String { tr("settings.tab.storage", lang: lang) }
    public static func tabAbout(lang: AppLanguage) -> String { tr("settings.tab.about", lang: lang) }

    // MARK: - Settings General
    public static func languageSetting(lang: AppLanguage) -> String { tr("settings.general.language", lang: lang) }
    public static func launchAtLogin(lang: AppLanguage) -> String { tr("settings.general.launchAtLogin", lang: lang) }
    public static func showInMenuBar(lang: AppLanguage) -> String { tr("settings.general.showInMenuBar", lang: lang) }
    public static func menuBarHiddenTip(lang: AppLanguage) -> String { tr("settings.general.menuBarHiddenTip", lang: lang) }
    public static func menuBarIconStyleHeader(lang: AppLanguage) -> String { tr("settings.general.menuBarIconStyleHeader", lang: lang) }
    public static func menuBarAdaptiveColor(lang: AppLanguage) -> String { tr("settings.general.menuBarAdaptiveColor", lang: lang) }
    public static func menuBarDarkColor(lang: AppLanguage) -> String { tr("settings.general.menuBarDarkColor", lang: lang) }
    public static func menuBarLightColor(lang: AppLanguage) -> String { tr("settings.general.menuBarLightColor", lang: lang) }
    public static func menuBarMonochrome(lang: AppLanguage) -> String { tr("settings.general.menuBarMonochrome", lang: lang) }
    public static func soundEffects(lang: AppLanguage) -> String { tr("settings.general.soundEffects", lang: lang) }
    public static func directPaste(lang: AppLanguage) -> String { tr("settings.general.directPaste", lang: lang) }
    public static func directPasteFooter(lang: AppLanguage) -> String { tr("settings.general.directPasteFooter", lang: lang) }
    public static func hudOpacityHeader(lang: AppLanguage) -> String { tr("settings.general.hudOpacityHeader", lang: lang) }
    public static func hudOpacityAntiGlare(lang: AppLanguage) -> String { tr("settings.general.hudOpacityAntiGlare", lang: lang) }
    public static func hudOpacitySolid(lang: AppLanguage) -> String { tr("settings.general.hudOpacitySolid", lang: lang) }
    public static func hudOpacityTranslucent(lang: AppLanguage) -> String { tr("settings.general.hudOpacityTranslucent", lang: lang) }
    public static func launchAtLoginError(lang: AppLanguage) -> String { tr("settings.general.launchAtLoginError", lang: lang) }

    // MARK: - Hotkeys & Permissions
    public static func globalHotkeyHeader(lang: AppLanguage) -> String { tr("settings.hotkeys.globalHotkeyHeader", lang: lang) }
    public static func globalHotkeyDesc(lang: AppLanguage) -> String { tr("settings.hotkeys.globalHotkeyDesc", lang: lang) }
    public static func toggleShortcutRowTitle(lang: AppLanguage) -> String { tr("settings.hotkeys.toggleShortcutRowTitle", lang: lang) }
    public static func recordShortcutChangeBtn(lang: AppLanguage) -> String { tr("settings.hotkeys.recordShortcutChangeBtn", lang: lang) }
    public static func recordShortcutCancelBtn(lang: AppLanguage) -> String { tr("settings.hotkeys.recordShortcutCancelBtn", lang: lang) }
    public static func recordShortcutPrompt(lang: AppLanguage) -> String { tr("settings.hotkeys.recordShortcutPrompt", lang: lang) }
    public static func recordShortcutActive(lang: AppLanguage) -> String { tr("settings.hotkeys.recordShortcutActive", lang: lang) }
    public static func recordShortcutModifierNeeded(lang: AppLanguage) -> String { tr("settings.hotkeys.recordShortcutModifierNeeded", lang: lang) }
    public static func recordShortcutReset(lang: AppLanguage) -> String { tr("settings.hotkeys.recordShortcutReset", lang: lang) }
    public static func recordShortcutCancelTip(lang: AppLanguage) -> String { tr("settings.hotkeys.recordShortcutCancelTip", lang: lang) }
    public static func accessibilitySection(lang: AppLanguage) -> String { tr("settings.accessibility.section", lang: lang) }
    public static func accessibilityGranted(lang: AppLanguage) -> String { tr("settings.accessibility.granted", lang: lang) }
    public static func accessibilityNotGranted(lang: AppLanguage) -> String { tr("settings.accessibility.notGranted", lang: lang) }
    public static func openSystemSettings(lang: AppLanguage) -> String { tr("settings.accessibility.openSettings", lang: lang) }
    public static func accessibilityDesc(lang: AppLanguage) -> String { tr("settings.accessibility.desc", lang: lang) }
    public static func accessibilityWarningBanner(lang: AppLanguage) -> String { tr("settings.accessibility.warningBanner", lang: lang) }
    public static func grantPermissionBtn(lang: AppLanguage) -> String { tr("settings.accessibility.grantBtn", lang: lang) }
    public static func accessibilityDialogTitle(lang: AppLanguage) -> String { tr("dialog.accessibility.title", lang: lang) }
    public static func accessibilityDialogMessage(lang: AppLanguage) -> String { tr("dialog.accessibility.message", lang: lang) }

    // MARK: - Filters & Privacy
    public static func privacyHeader(lang: AppLanguage) -> String { tr("settings.filters.privacy", lang: lang) }
    public static func pauseRecording(lang: AppLanguage) -> String { tr("settings.filters.pauseRecording", lang: lang) }
    public static func excludedApps(lang: AppLanguage) -> String { tr("settings.filters.excludedApps", lang: lang) }
    public static func excludedAppsExample(lang: AppLanguage) -> String { tr("settings.filters.excludedAppsExample", lang: lang) }
    public static func allowedTypesHeader(lang: AppLanguage) -> String { tr("settings.filters.allowedTypesHeader", lang: lang) }
    public static func typeText(lang: AppLanguage) -> String { tr("settings.filters.typeText", lang: lang) }
    public static func typeImage(lang: AppLanguage) -> String { tr("settings.filters.typeImage", lang: lang) }
    public static func detectQrInImages(lang: AppLanguage) -> String { tr("settings.filters.detectQrInImages", lang: lang) }
    public static func typeColor(lang: AppLanguage) -> String { tr("settings.filters.typeColor", lang: lang) }
    public static func typeFile(lang: AppLanguage) -> String { tr("settings.filters.typeFile", lang: lang) }
    public static func allowedTypesFooter(lang: AppLanguage) -> String { tr("settings.filters.allowedTypesFooter", lang: lang) }

    // MARK: - Retention Policies
    public static func storageLimitHeader(lang: AppLanguage) -> String { tr("settings.storage.header", lang: lang) }
    public static func retrySave(lang: AppLanguage) -> String { tr("settings.storage.retrySave", lang: lang) }
    public static func retainedContent(lang: AppLanguage) -> String { tr("settings.storage.retainedContent", lang: lang) }
    public static func contentSizeLimit(lang: AppLanguage) -> String { tr("settings.storage.contentSizeLimit", lang: lang) }
    public static func storageLimitNote(lang: AppLanguage) -> String { tr("settings.storage.limitNote", lang: lang) }
    public static func unlimited(lang: AppLanguage) -> String { tr("settings.storage.unlimited", lang: lang) }
    public static func retentionStrategy(lang: AppLanguage) -> String { tr("settings.storage.retentionStrategy", lang: lang) }
    public static func retentionByCount(lang: AppLanguage) -> String { tr("settings.storage.retentionByCount", lang: lang) }
    public static func retentionByTime(lang: AppLanguage) -> String { tr("settings.storage.retentionByTime", lang: lang) }
    public static func maxItemsPicker(lang: AppLanguage) -> String { tr("settings.storage.maxItemsPicker", lang: lang) }
    public static func maxDaysPicker(lang: AppLanguage) -> String { tr("settings.storage.maxDaysPicker", lang: lang) }
    public static func duration7Days(lang: AppLanguage) -> String { tr("settings.storage.duration7Days", lang: lang) }
    public static func duration14Days(lang: AppLanguage) -> String { tr("settings.storage.duration14Days", lang: lang) }
    public static func duration30Days(lang: AppLanguage) -> String { tr("settings.storage.duration30Days", lang: lang) }
    public static func duration90Days(lang: AppLanguage) -> String { tr("settings.storage.duration90Days", lang: lang) }
    public static func durationForever(lang: AppLanguage) -> String { tr("settings.storage.durationForever", lang: lang) }
    public static func countUnlimited(lang: AppLanguage) -> String { tr("settings.storage.countUnlimited", lang: lang) }
    public static func pinNotice(lang: AppLanguage) -> String { tr("settings.storage.pinNotice", lang: lang) }
    public static func sensitiveDataHeader(lang: AppLanguage) -> String { tr("settings.storage.sensitiveDataHeader", lang: lang) }
    public static func sensitiveDataBadge(lang: AppLanguage) -> String { tr("settings.storage.sensitiveDataBadge", lang: lang) }
    public static func sensitiveDataDesc(lang: AppLanguage) -> String { tr("settings.storage.sensitiveDataDesc", lang: lang) }
    public static func clearHistoryHeader(lang: AppLanguage) -> String { tr("settings.storage.clearHistoryHeader", lang: lang) }
    public static func clearKeepPinned(lang: AppLanguage) -> String { tr("settings.storage.clearKeepPinned", lang: lang) }
    public static func clearAllCompletely(lang: AppLanguage) -> String { tr("settings.storage.clearAllCompletely", lang: lang) }
    public static func clearAllConfirmTitle(lang: AppLanguage) -> String { tr("settings.storage.clearAllConfirmTitle", lang: lang) }
    public static func clearAllConfirmDesc(lang: AppLanguage) -> String { tr("settings.storage.clearAllConfirmDesc", lang: lang) }
    public static func clearSuccessKeepPinnedNotification(lang: AppLanguage) -> String { tr("settings.storage.clearSuccessKeepPinnedNotification", lang: lang) }
    public static func clearSuccessAllNotification(lang: AppLanguage) -> String { tr("settings.storage.clearSuccessAllNotification", lang: lang) }

    // MARK: - About Tab
    public static func aboutTagline(lang: AppLanguage) -> String { tr("about.tagline", lang: lang) }
    public static func aboutAuthor(lang: AppLanguage) -> String { tr("about.author", lang: lang) }
    public static func aboutAuthorName(lang: AppLanguage) -> String { tr("about.authorName", lang: lang) }
    public static func aboutGithub(lang: AppLanguage) -> String { tr("about.github", lang: lang) }
    public static func aboutGithubRepo(lang: AppLanguage) -> String { tr("about.githubRepo", lang: lang) }
    public static func aboutViewGithub(lang: AppLanguage) -> String { tr("about.viewGithub", lang: lang) }
    public static func aboutLicense(lang: AppLanguage) -> String { tr("about.license", lang: lang) }
    public static func aboutLicenseName(lang: AppLanguage) -> String { tr("about.licenseName", lang: lang) }
    public static func aboutTech(lang: AppLanguage) -> String { tr("about.tech", lang: lang) }
    public static func aboutTechDesc(lang: AppLanguage) -> String { tr("about.techDesc", lang: lang) }
    public static func aboutCopyright(lang: AppLanguage) -> String { tr("about.copyright", lang: lang) }
    public static func aboutVersionPrefix(lang: AppLanguage) -> String { tr("about.versionPrefix", lang: lang) }

    // MARK: - Menu Bar
    public static func menuOpenClipback(lang: AppLanguage) -> String { tr("menu.openClipback", lang: lang) }
    public static func menuOpenClipory(lang: AppLanguage) -> String { menuOpenClipback(lang: lang) }
    public static func menuSettings(lang: AppLanguage) -> String { tr("menu.settings", lang: lang) }
    public static func menuAbout(lang: AppLanguage) -> String { tr("menu.about", lang: lang) }
    public static func menuCheckUpdates(lang: AppLanguage) -> String { tr("menu.checkUpdates", lang: lang) }
    public static func menuClearHistory(lang: AppLanguage) -> String { tr("menu.clearHistory", lang: lang) }
    public static func menuQuit(lang: AppLanguage) -> String { tr("menu.quit", lang: lang) }
    public static func clearConfirmTitle(lang: AppLanguage) -> String { tr("menu.clearConfirmTitle", lang: lang) }
    public static func clearConfirmDesc(lang: AppLanguage) -> String { tr("menu.clearConfirmDesc", lang: lang) }
    public static func confirmBtn(lang: AppLanguage) -> String { tr("menu.confirmBtn", lang: lang) }
    public static func cancelBtn(lang: AppLanguage) -> String { tr("menu.cancelBtn", lang: lang) }

    // MARK: - Date Sections & List Appearance
    public static func todaySection(lang: AppLanguage) -> String { tr("date.today", lang: lang) }
    public static func yesterdaySection(lang: AppLanguage) -> String { tr("date.yesterday", lang: lang) }
    public static func daysAgoSection(_ days: Int, lang: AppLanguage) -> String {
        if days == 1 {
            return tr("date.oneDayAgo", lang: lang)
        }
        return tr("date.daysAgo", lang: lang, days)
    }
    public static func listAppearanceHeader(lang: AppLanguage) -> String { tr("settings.appearance.header", lang: lang) }
    public static func showSourceAppIconToggle(lang: AppLanguage) -> String { tr("settings.appearance.showSourceAppIcon", lang: lang) }
    public static func showContentTypeBadgeToggle(lang: AppLanguage) -> String { tr("settings.appearance.showContentTypeBadge", lang: lang) }
    public static func showImageThumbnailToggle(lang: AppLanguage) -> String { tr("settings.appearance.showImageThumbnail", lang: lang) }
    public static func listAppearanceFooter(lang: AppLanguage) -> String { tr("settings.appearance.footer", lang: lang) }

    // MARK: - Update Checker
    public static func updateMenuCheck(lang: AppLanguage) -> String { tr("update.menuCheck", lang: lang) }
    public static func updateCheckButton(lang: AppLanguage) -> String { tr("update.checkButton", lang: lang) }
    public static func updateChecking(lang: AppLanguage) -> String { tr("update.checking", lang: lang) }
    public static func updateUpToDate(lang: AppLanguage) -> String { tr("update.upToDate", lang: lang) }
    public static func updateAvailableTitle(lang: AppLanguage) -> String { tr("update.availableTitle", lang: lang) }
    public static func updateAvailableDesc(version: String, lang: AppLanguage) -> String { tr("update.availableDesc", lang: lang, version) }
    public static func updateDownloadButton(lang: AppLanguage) -> String { tr("update.downloadButton", lang: lang) }
    public static func updateViewRelease(lang: AppLanguage) -> String { tr("update.viewRelease", lang: lang) }
    public static func updateAutoCheckToggle(lang: AppLanguage) -> String { tr("update.autoCheckToggle", lang: lang) }
    public static func updateLastChecked(date: String, lang: AppLanguage) -> String { tr("update.lastChecked", lang: lang, date) }
    public static func updateFailed(lang: AppLanguage) -> String { tr("update.failed", lang: lang) }
    public static func updateFailedDesc(error: String, lang: AppLanguage) -> String { tr("update.failedDesc", lang: lang, error) }
    public static func updateDismiss(lang: AppLanguage) -> String { tr("update.dismiss", lang: lang) }

    // MARK: - Alerts & Errors
    public static func alertUnsavedHistoryTitle(lang: AppLanguage) -> String { tr("alert.unsavedHistory.title", lang: lang) }
    public static func alertUnsavedHistoryGoBack(lang: AppLanguage) -> String { tr("alert.unsavedHistory.goBack", lang: lang) }
    public static func alertUnsavedHistoryQuitAnyway(lang: AppLanguage) -> String { tr("alert.unsavedHistory.quitAnyway", lang: lang) }
    public static func alertHotkeyUnavailable(lang: AppLanguage) -> String { tr("alert.hotkeyUnavailable", lang: lang) }
    public static func menuBarTooltip(shortcut: String, lang: AppLanguage) -> String { tr("menu.tooltip", lang: lang, shortcut) }
    public static func updateUpToDateDesc(version: String, lang: AppLanguage) -> String { tr("update.upToDateDesc", lang: lang, version) }

    // MARK: - Storage & Monitor Errors
    public static func errorStorageSaveFailed(lang: AppLanguage) -> String { tr("error.storage.saveFailed", lang: lang) }
    public static func errorStorageCorruptBackup(lang: AppLanguage) -> String { tr("error.storage.corruptBackup", lang: lang) }
    public static func errorStorageReadFailed(lang: AppLanguage) -> String { tr("error.storage.readFailed", lang: lang) }
    public static func errorMonitorQueueFull(lang: AppLanguage) -> String { tr("error.monitor.queueFull", lang: lang) }
    public static func errorMonitorImageSaveFailed(lang: AppLanguage) -> String { tr("error.monitor.imageSaveFailed", lang: lang) }

    // MARK: - Paste Errors
    public static func errorPasteItemUnavailable(lang: AppLanguage) -> String { tr("error.paste.itemUnavailable", lang: lang) }
    public static func errorPasteClipboardChanged(lang: AppLanguage) -> String { tr("error.paste.clipboardChanged", lang: lang) }
    public static func errorPasteWriteFailed(lang: AppLanguage) -> String { tr("error.paste.writeFailed", lang: lang) }
    public static func errorPasteCancelledFocusChanged(lang: AppLanguage) -> String { tr("error.paste.cancelledFocusChanged", lang: lang) }

    // MARK: - Hotkey Warnings
    public static func warningHotkeyDefaultUnavailable(lang: AppLanguage) -> String { tr("warning.hotkey.defaultUnavailable", lang: lang) }
    public static func warningHotkeyRegistrationFailed(lang: AppLanguage) -> String { tr("warning.hotkey.registrationFailed", lang: lang) }

    // MARK: - HUD & Status
    public static func actionDismiss(lang: AppLanguage) -> String { tr("action.dismiss", lang: lang) }
    public static func statusRecordingPaused(lang: AppLanguage) -> String { tr("status.recordingPaused", lang: lang) }
    public static func statusItemDeleted(lang: AppLanguage) -> String { tr("status.itemDeleted", lang: lang) }
    public static func actionUndo(lang: AppLanguage) -> String { tr("action.undo", lang: lang) }
    public static func accessibilityClearSearch(lang: AppLanguage) -> String { tr("accessibility.clearSearch", lang: lang) }

    // MARK: - Preview Actions & Labels
    public static func previewShowFullText(lang: AppLanguage) -> String { tr("preview.showFullText", lang: lang) }
    public static func previewFullTextNotice(lang: AppLanguage) -> String { tr("preview.fullTextNotice", lang: lang) }
    public static func previewOpenFullImage(lang: AppLanguage) -> String { tr("preview.openFullImage", lang: lang) }
    public static func previewRecognizingOcr(lang: AppLanguage) -> String { tr("preview.recognizingOcr", lang: lang) }
    public static func previewRecognitionFailed(lang: AppLanguage) -> String { tr("preview.recognitionFailed", lang: lang) }

    // MARK: - Content Types
    public static func contentTypeText(lang: AppLanguage) -> String { tr("contentType.text", lang: lang) }
    public static func contentTypeRichText(lang: AppLanguage) -> String { tr("contentType.richText", lang: lang) }
    public static func contentTypeImage(lang: AppLanguage) -> String { tr("contentType.image", lang: lang) }
    public static func contentTypeColor(lang: AppLanguage) -> String { tr("contentType.color", lang: lang) }
    public static func contentTypeLink(lang: AppLanguage) -> String { tr("contentType.link", lang: lang) }
    public static func contentTypeFile(lang: AppLanguage) -> String { tr("contentType.file", lang: lang) }
}
