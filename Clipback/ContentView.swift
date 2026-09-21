import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import AppKit

/// Available tabs in Clipback Settings
public enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case hotkeys
    case filters
    case storage
    case about
    
    public var id: String { rawValue }
    
    public func title(lang: AppLanguage) -> String {
        switch self {
        case .general: return L10n.tabGeneral(lang: lang)
        case .hotkeys: return L10n.tabHotkeys(lang: lang)
        case .filters: return L10n.tabFilters(lang: lang)
        case .storage: return L10n.tabStorage(lang: lang)
        case .about: return L10n.tabAbout(lang: lang)
        }
    }
    
    public var icon: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        case .filters: return "slider.horizontal.3"
        case .storage: return "cylinder"
        case .about: return "info.circle"
        }
    }
}

extension Notification.Name {
    public static let selectSettingsTab = Notification.Name("selectSettingsTab")
}

/// Native macOS Settings window featuring NavigationSplitView and unified grouped forms
public struct ContentView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var storage: StorageManager
    @ObservedObject private var updateChecker = UpdateChecker.shared
    
    @State private var selectedTab: SettingsTab? = .general
    @State private var history: [SettingsTab] = [.general]
    @State private var currentIndex: Int = 0
    @State private var isNavigatingHistory: Bool = false
    @State private var isAccessibilityGranted: Bool = AccessibilityManager.shared.isAccessibilityGranted
    @State private var showingClearConfirmation = false
    @State private var clearKeepPinnedTarget = true
    @State private var showingClearSuccessAlert = false
    @State private var customBundleIDInput = ""
    @State private var clearSuccessAlertMessage = ""
    
    private static let updateDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
    
    public init(initialTab: SettingsTab = .general) {
        _selectedTab = State(initialValue: initialTab)
        _history = State(initialValue: [initialTab])
    }
    
    private var lang: AppLanguage {
        settings.appLanguage
    }
    
    private var canGoBack: Bool {
        currentIndex > 0
    }
    
    private var canGoForward: Bool {
        currentIndex < history.count - 1
    }
    
    private func goBack() {
        guard canGoBack else { return }
        currentIndex -= 1
        isNavigatingHistory = true
        selectedTab = history[currentIndex]
        isNavigatingHistory = false
    }
    
    private func goForward() {
        guard canGoForward else { return }
        currentIndex += 1
        isNavigatingHistory = true
        selectedTab = history[currentIndex]
        isNavigatingHistory = false
    }
    
    private func updateWindowTitle(_ tab: SettingsTab) {
        if let window = NSApp.windows.first(where: { !($0 is FloatingPanel) }) {
            window.title = tab.title(lang: lang)
        }
    }
    
    public var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title(lang: lang), systemImage: tab.icon)
                    .fontWeight(.regular)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 175, ideal: 195, max: 230)
        } detail: {
            Group {
                switch selectedTab ?? .general {
                case .general:
                    generalTab
                case .hotkeys:
                    hotkeyTab
                case .filters:
                    contentFiltersTab
                case .storage:
                    storageTab
                case .about:
                    aboutTab
                }
            }
            .navigationTitle((selectedTab ?? .general).title(lang: lang))
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ControlGroup {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!canGoBack)
                        .keyboardShortcut("[", modifiers: .command)
                        
                        Button(action: goForward) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!canGoForward)
                        .keyboardShortcut("]", modifiers: .command)
                    }
                    .controlGroupStyle(.navigation)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 480, idealHeight: 560)
        .onChange(of: selectedTab) { _, newValue in
            guard let newTab = newValue else {
                selectedTab = history[currentIndex]
                return
            }
            if !isNavigatingHistory {
                if history[currentIndex] != newTab {
                    history = Array(history.prefix(through: currentIndex))
                    history.append(newTab)
                    currentIndex = history.count - 1
                }
            }
            updateWindowTitle(newTab)
        }
        .onChange(of: settings.appLanguage) { _, _ in
            updateWindowTitle(selectedTab ?? .general)
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectSettingsTab)) { notification in
            if let tab = notification.object as? SettingsTab {
                selectedTab = tab
            }
        }
        .onAppear {
            settings.launchAtLogin = LaunchAtLoginManager.shared.isEnabled
            updateWindowTitle(selectedTab ?? .general)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityGranted = AccessibilityManager.shared.isAccessibilityGranted
            settings.launchAtLogin = LaunchAtLoginManager.shared.isEnabled
        }
    }
    
    // MARK: - Tab 1: General Settings
    
    private var generalTab: some View {
        Form {
            Section {
                // Language Selection Picker
                Picker(selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                } label: {
                    Label(L10n.languageSetting(lang: lang), systemImage: "globe")
                }
                .pickerStyle(.menu)
                
                Toggle(isOn: $settings.launchAtLogin) {
                    Label(L10n.launchAtLogin(lang: lang), systemImage: "power")
                }
                .onChange(of: settings.launchAtLogin) { _, enabled in
                    guard LaunchAtLoginManager.shared.isEnabled != enabled else { return }
                    if !LaunchAtLoginManager.shared.setEnabled(enabled) {
                        settings.launchAtLogin = LaunchAtLoginManager.shared.isEnabled
                        storage.lastError = L10n.launchAtLoginError(lang: lang)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $settings.showInMenuBar) {
                        Label(L10n.showInMenuBar(lang: lang), systemImage: "menubar.rectangle")
                    }
                    .onChange(of: settings.showInMenuBar) { _, _ in
                        MenuBarManager.shared.updateVisibility()
                    }
                    
                    if !settings.showInMenuBar {
                        HStack(spacing: 5) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(L10n.menuBarHiddenTip(lang: lang))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }
                
                if settings.showInMenuBar {
                    Picker(selection: $settings.menuBarIconStyle) {
                        ForEach(MenuBarIconStyle.allCases) { style in
                            Text(style.title(lang: lang)).tag(style)
                        }
                    } label: {
                        Label(L10n.menuBarIconStyleHeader(lang: lang), systemImage: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: settings.menuBarIconStyle) { _, _ in
                        MenuBarManager.shared.updateIcon()
                    }
                }
                
                Toggle(isOn: $settings.playSounds) {
                    Label(L10n.soundEffects(lang: lang), systemImage: "speaker.wave.2")
                }
                
                if settings.playSounds {
                    HStack {
                        Picker(selection: $settings.soundName) {
                            ForEach(SoundEffectManager.availableSounds, id: \.self) { sound in
                                Text(sound).tag(sound)
                            }
                        } label: {
                            Label(L10n.soundSelection(lang: lang), systemImage: "waveform")
                        }
                        .pickerStyle(.menu)
                        .onChange(of: settings.soundName) { _, newSound in
                            SoundEffectManager.playSound(named: newSound)
                        }
                        
                        Button {
                            SoundEffectManager.playSound(named: settings.soundName)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(L10n.previewSound(lang: lang))
                    }
                }
            } header: {
                Text(L10n.tabGeneral(lang: lang))
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 2: Hotkeys & Permissions
    
    private var hotkeyTab: some View {
        Form {
            Section(L10n.globalHotkeyHeader(lang: lang)) {
                HStack {
                    Label(L10n.globalHotkeyHeader(lang: lang) + ":", systemImage: "keyboard")
                    Spacer()
                    HotKeyRecorderView()
                }
                
                Text(L10n.globalHotkeyDesc(lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section(L10n.accessibilitySection(lang: lang)) {
                HStack {
                    if isAccessibilityGranted {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.secondary)
                        Text(L10n.accessibilityGranted(lang: lang))
                            .font(.system(size: 13, weight: .medium))
                    } else {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Text(L10n.accessibilityNotGranted(lang: lang))
                            .font(.system(size: 13, weight: .medium))
                    }
                    
                    Spacer()
                    
                    Button(L10n.openSystemSettings(lang: lang)) {
                        AccessibilityManager.shared.openAccessibilitySettings()
                    }
                }
                
                Text(L10n.accessibilityDesc(lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 3: Content Filters
    
    private var contentFiltersTab: some View {
        Form {
            Section(L10n.privacyHeader(lang: lang)) {
                Toggle(isOn: $settings.monitoringPaused) {
                    Label(L10n.pauseRecording(lang: lang), systemImage: "pause.circle")
                }
                .onChange(of: settings.monitoringPaused) { _, _ in MenuBarManager.shared.refreshMenu() }
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(L10n.excludedApps(lang: lang), systemImage: "app.dashed")
                        Spacer()
                        Button {
                            openApplicationPicker()
                        } label: {
                            Label(lang == .vietnamese ? "Thêm ứng dụng..." : "Add Application...", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    let ids = excludedList
                    if ids.isEmpty {
                        Text(lang == .vietnamese ? "Chưa có ứng dụng nào bị loại trừ" : "No applications excluded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(ids, id: \.self) { bundleID in
                                excludedAppRow(bundleID)
                            }
                        }
                    }
                    
                    HStack(spacing: 8) {
                        TextField(lang == .vietnamese ? "Hoặc nhập bundle ID thủ công..." : "Or enter bundle ID manually...", text: $customBundleIDInput)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onSubmit {
                                addCustomBundleID()
                            }
                        
                        if !customBundleIDInput.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button(lang == .vietnamese ? "Thêm" : "Add") {
                                addCustomBundleID()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 2)
                    
                    Text(L10n.excludedAppsExample(lang: lang))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            
            Section {
                Toggle(isOn: $settings.saveText) {
                    Label(L10n.typeText(lang: lang), systemImage: "doc.plaintext")
                }
                
                Toggle(isOn: $settings.saveImages) {
                    Label(L10n.typeImage(lang: lang), systemImage: "photo")
                }
                
                if settings.saveImages {
                    Toggle(isOn: $settings.detectQrInImages) {
                        Label(L10n.detectQrInImages(lang: lang), systemImage: "qrcode.viewfinder")
                    }
                    .padding(.leading, 18)
                }
                
                Toggle(isOn: $settings.saveColors) {
                    Label(L10n.typeColor(lang: lang), systemImage: "paintpalette")
                }
                
                Toggle(isOn: $settings.saveFiles) {
                    Label(L10n.typeFile(lang: lang), systemImage: "folder")
                }
            } header: {
                Text(L10n.allowedTypesHeader(lang: lang))
            } footer: {
                Text(L10n.allowedTypesFooter(lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 4: Storage & Retention Policy
    
    private var storageTab: some View {
        Form {
            if let error = storage.lastError {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Text(error).foregroundStyle(.secondary)
                    }
                    Button(L10n.retrySave(lang: lang)) {
                        Task { if await storage.flush() { storage.lastError = nil } }
                    }
                }
            }
            Section {
                LabeledContent {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(storage.retainedBytes), countStyle: .file))
                        .foregroundStyle(.secondary)
                } label: {
                    Label(L10n.retainedContent(lang: lang), systemImage: "internaldrive")
                }
                
                Picker(selection: $settings.maxStorageMB) {
                    Text(L10n.unlimited(lang: lang)).tag(0)
                    Text("100 MB").tag(100)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1024)
                } label: {
                    Label(L10n.contentSizeLimit(lang: lang), systemImage: "chart.bar")
                }
                .onChange(of: settings.maxStorageMB) { _, _ in storage.pruneHistory() }
                
                Text(L10n.storageLimitNote(lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Retention strategy switcher (Count vs Time)
                Picker(selection: $settings.retentionMode) {
                    Text(L10n.retentionByCount(lang: lang)).tag(RetentionMode.byCount)
                    Text(L10n.retentionByTime(lang: lang)).tag(RetentionMode.byTime)
                } label: {
                    Label(L10n.retentionStrategy(lang: lang), systemImage: "clock.arrow.circlepath")
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.retentionMode) { _, _ in
                    storage.pruneHistory()
                }
                
                if settings.retentionMode == .byCount {
                    Picker(selection: $settings.maxHistoryCount) {
                        Text("100").tag(100)
                        Text("300").tag(300)
                        Text("500").tag(500)
                        Text("1000").tag(1000)
                        Text(L10n.countUnlimited(lang: lang)).tag(0)
                    } label: {
                        Label(L10n.maxItemsPicker(lang: lang), systemImage: "number")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: settings.maxHistoryCount) { _, _ in
                        storage.pruneHistory()
                    }
                } else {
                    Picker(selection: $settings.retentionDays) {
                        Text(L10n.duration7Days(lang: lang)).tag(7)
                        Text(L10n.duration14Days(lang: lang)).tag(14)
                        Text(L10n.duration30Days(lang: lang)).tag(30)
                        Text(L10n.duration90Days(lang: lang)).tag(90)
                        Text(L10n.durationForever(lang: lang)).tag(0)
                    } label: {
                        Label(L10n.maxDaysPicker(lang: lang), systemImage: "calendar")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: settings.retentionDays) { _, _ in
                        storage.pruneHistory()
                    }
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "pin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(L10n.pinNotice(lang: lang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            } header: {
                Text(L10n.storageLimitHeader(lang: lang))
            }
            
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    
                    Text(L10n.sensitiveDataBadge(lang: lang))
                        .font(.system(size: 13, weight: .medium))
                }
                
                Text(L10n.sensitiveDataDesc(lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.sensitiveDataHeader(lang: lang))
            }
            
            Section {
                // Option 1: Clear unpinned items
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "pin.slash")
                        .font(.system(size: 15))
                        .foregroundStyle(.orange)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.clearKeepPinned(lang: lang))
                            .font(.system(size: 13, weight: .medium))
                        Text(lang == .vietnamese 
                            ? "Chỉ xóa các mục thường, bảo toàn tất cả các mục bạn đã ghim."
                            : "Deletes all clipboard items except those you have pinned.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(lang == .vietnamese ? "Dọn dẹp" : "Clear") {
                        clearKeepPinnedTarget = true
                        showingClearConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(.vertical, 3)
                
                // Option 2: Clear all completely
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .foregroundStyle(.red)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.clearAllCompletely(lang: lang))
                            .font(.system(size: 13, weight: .medium))
                        Text(lang == .vietnamese 
                            ? "Xóa vĩnh viễn toàn bộ lịch sử bao gồm cả các mục đã ghim."
                            : "Permanently deletes all clipboard items, including pinned items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(lang == .vietnamese ? "Xóa tất cả" : "Clear All") {
                        clearKeepPinnedTarget = false
                        showingClearConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.regular)
                }
                .padding(.vertical, 3)
            } header: {
                Text(L10n.clearHistoryHeader(lang: lang))
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            clearKeepPinnedTarget
                ? L10n.clearConfirmTitle(lang: lang)
                : L10n.clearAllConfirmTitle(lang: lang),
            isPresented: $showingClearConfirmation
        ) {
            Button(L10n.cancelBtn(lang: lang), role: .cancel) {}
            Button(L10n.confirmBtn(lang: lang), role: .destructive) {
                let target = clearKeepPinnedTarget
                storage.clearAll(keepPinned: target)
                Task {
                    _ = await storage.flush()
                    await MainActor.run {
                        clearSuccessAlertMessage = target
                            ? L10n.clearSuccessKeepPinnedNotification(lang: lang)
                            : L10n.clearSuccessAllNotification(lang: lang)
                        showingClearSuccessAlert = true
                    }
                }
            }
        } message: {
            Text(
                clearKeepPinnedTarget
                    ? L10n.clearConfirmDesc(lang: lang)
                    : L10n.clearAllConfirmDesc(lang: lang)
            )
        }
        .alert(
            lang == .vietnamese ? "Thông báo" : "Notice",
            isPresented: $showingClearSuccessAlert
        ) {
            Button(lang == .vietnamese ? "Đóng" : "OK", role: .cancel) {}
        } message: {
            Text(clearSuccessAlertMessage)
        }
    }
    
    // MARK: - Tab 5: About Tab (Unified Form & Grouped Sections)
    
    private var appLogoImage: NSImage? {
        let targetSize = NSSize(width: 72, height: 72)
        
        let rawImage: NSImage? = {
            if let icnsPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
               let img = NSImage(contentsOfFile: icnsPath) {
                return img
            }
            if let pngPath = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
               let img = NSImage(contentsOfFile: pngPath) {
                return img
            }
            if let localImg = NSImage(contentsOfFile: "Resources/AppIcon.png") {
                return localImg
            }
            return NSImage(named: "AppIcon")
        }()
        
        guard let source = rawImage, source.isValid else { return nil }
        
        let result = NSImage(size: targetSize)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: source.size),
            operation: .copy,
            fraction: 1.0
        )
        result.unlockFocus()
        return result
    }
    
    private var aboutTab: some View {
        VStack(spacing: 0) {
            // Hero Section: Centered App Identity Header (Completely outside Form, No Card, No Background)
            VStack(spacing: 8) {
                if let logo = appLogoImage {
                    Image(nsImage: logo)
                        .interpolation(.high)
                        .antialiased(true)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                }
                
                Text("Clipback")
                    .font(.system(size: 20, weight: .bold))
                
                Text("\(L10n.aboutVersionPrefix(lang: lang)) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Text(L10n.aboutTagline(lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 6)
            
            Form {
                // Section 1: Application Details
                Section {
                    LabeledContent {
                        Text(L10n.aboutAuthorName(lang: lang))
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(L10n.aboutAuthor(lang: lang), systemImage: "person.crop.circle")
                    }
                    
                    LabeledContent {
                        Text(L10n.aboutLicenseName(lang: lang))
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(L10n.aboutLicense(lang: lang), systemImage: "checkmark.seal")
                    }
                } header: {
                    Text(L10n.tabAbout(lang: lang))
                }
                
                                        // Section 3: Software Updates
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.updateCheckButton(lang: lang))
                            .font(.system(size: 13, weight: .medium))
                        
                        switch updateChecker.status {
                        case .idle:
                            if let lastDate = settings.lastUpdateCheckDate {
                                let dateStr = Self.updateDateFormatter.string(from: lastDate)
                                Text(L10n.updateLastChecked(date: dateStr, lang: lang))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(L10n.updateUpToDate(lang: lang))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .checking:
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                                Text(L10n.updateChecking(lang: lang))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .upToDate:
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(L10n.updateUpToDate(lang: lang))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .updateAvailable(let release):
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(L10n.updateAvailableDesc(version: release.version, lang: lang))
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        case .error(let msg):
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if case .updateAvailable(let release) = updateChecker.status {
                        Button(L10n.updateDownloadButton(lang: lang)) {
                            updateChecker.openReleaseDownload(release)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    } else {
                        Button(action: {
                            Task {
                                await updateChecker.checkForUpdates(isUserInitiated: true)
                            }
                        }) {
                            Text(L10n.updateCheckButton(lang: lang))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(updateChecker.status == .checking)
                    }
                }
                .padding(.vertical, 2)
                
                Toggle(isOn: $settings.automaticallyCheckForUpdates) {
                    Label(L10n.updateAutoCheckToggle(lang: lang), systemImage: "bell")
                }
            } header: {
                Text(L10n.updateCheckButton(lang: lang))
            } footer: {
                Text(L10n.aboutCopyright(lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .formStyle(.grouped)
        }
    }
    // MARK: - Excluded Apps Helpers
    
    private var excludedList: [String] {
        settings.excludedAppBundleIDs
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    private func addExcludedBundleID(_ bundleID: String) {
        var list = excludedList
        if !list.contains(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) {
            list.append(bundleID)
            settings.excludedAppBundleIDs = list.joined(separator: ", ")
        }
    }
    
    private func removeExcludedBundleID(_ bundleID: String) {
        var list = excludedList
        list.removeAll { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
        settings.excludedAppBundleIDs = list.joined(separator: ", ")
    }
    
    private func addCustomBundleID() {
        let trimmed = customBundleIDInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        addExcludedBundleID(trimmed)
        customBundleIDInput = ""
    }
    
    private func openApplicationPicker() {
        let panel = NSOpenPanel()
        panel.title = lang == .vietnamese ? "Chọn ứng dụng để loại trừ" : "Select Application to Exclude"
        panel.prompt = lang == .vietnamese ? "Chọn" : "Choose"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        let response = panel.runModal()
        if response == .OK {
            for url in panel.urls {
                if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                    addExcludedBundleID(bundleID)
                } else {
                    let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
                    if let dict = NSDictionary(contentsOf: infoPlistURL),
                       let bundleID = dict["CFBundleIdentifier"] as? String {
                        addExcludedBundleID(bundleID)
                    }
                }
            }
        }
    }
    
    private func excludedAppRow(_ bundleID: String) -> some View {
        HStack(spacing: 8) {
            if let icon = appIcon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(appName(for: bundleID))
                    .font(.system(size: 13, weight: .medium))
                Text(bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                removeExcludedBundleID(bundleID)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help(lang == .vietnamese ? "Xóa" : "Remove")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
    }
    
    private func appIcon(for bundleID: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
    
    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }
}
