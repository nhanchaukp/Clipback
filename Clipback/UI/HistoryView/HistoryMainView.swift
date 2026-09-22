import Combine
import SwiftUI
import AppKit

/// Main HUD window view of Clipback featuring split view, fuzzy search, and keyboard navigation
public struct HistoryMainView: View {
    @EnvironmentObject private var storage: StorageManager
    @EnvironmentObject private var settings: UserSettings
    
    @StateObject private var searchModel = HistorySearchModel()
    @ObservedObject private var pasteService = PasteService.shared
    @State private var panelVisible = false
    @State private var searchText: String = ""
    @State private var selectedFilter: ContentFilter = .all
    @State private var selectedItemId: UUID?
    @State private var shouldResetSelectionOnNextSnapshot: Bool = false
    @FocusState private var isSearchFocused: Bool
    @StateObject private var keyCoordinator = KeyNavigationCoordinator()
    @State private var isAccessibilityGranted: Bool = AccessibilityManager.shared.isAccessibilityGranted
    
    private struct ScrollCommand: Equatable {
        let id: UUID
        let count: UInt32
    }
    @State private var scrollCommand: ScrollCommand?
    
    public init() {}
    
    /// Filter categories for the top filter chips
    public enum ContentFilter: String, CaseIterable, Identifiable, Sendable {
        case all
        case text
        case image
        case color
        case link
        case pinned
        
        public var id: String { rawValue }
        
        public func title(lang: AppLanguage) -> String {
            switch self {
            case .all: return L10n.filterAll(lang: lang)
            case .text: return L10n.filterText(lang: lang)
            case .image: return L10n.filterImage(lang: lang)
            case .color: return L10n.filterColor(lang: lang)
            case .link: return L10n.filterLink(lang: lang)
            case .pinned: return L10n.filterPinned(lang: lang)
            }
        }
        
        public var icon: String {
            switch self {
            case .all: return "tray.2"
            case .text: return "doc.text"
            case .image: return "photo"
            case .color: return "paintpalette"
            case .link: return "link"
            case .pinned: return "pin.fill"
            }
        }
    }
    
    private var filteredItems: [ClipboardItem] { searchModel.snapshot.items }
    private var itemIndexMap: [UUID: Int] { searchModel.snapshot.indices }
    private var dateSections: [DateSection] { searchModel.snapshot.sections }

    private func refreshSearch() {
        guard panelVisible else { return }
        searchModel.update(items: storage.items, query: searchText, filter: selectedFilter, language: settings.appLanguage, revision: storage.revision)
    }

    private func resetOnPanelOpen() {
        searchText = ""
        selectedFilter = .all
        shouldResetSelectionOnNextSnapshot = true
        selectedItemId = storage.items.first?.id
        if let firstId = storage.items.first?.id {
            DispatchQueue.main.async {
                scrollCommand = ScrollCommand(id: firstId, count: (scrollCommand?.count ?? 0) &+ 1)
            }
        }
    }

    private var selectedItem: ClipboardItem? {
        if let id = selectedItemId {
            return filteredItems.first { $0.id == id } ?? filteredItems.first
        }
        return filteredItems.first
    }
    
    public var body: some View {
        ZStack {
            // 1. Native macOS HUD diffusion material
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            
            // 2. Semi-translucent window backing (subtle translucency + blur)
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.68)
            
            // 3. Subtle depth contrast layer
            Color(nsColor: .controlBackgroundColor)
                .opacity(0.18)
            
            VStack(spacing: 0) {
                // 1. Full-width Header Titlebar with native material blur
                headerView
                    .background(
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.4))
                    )
                
                Divider()
                    .opacity(0.35)
                
                // 2. Split View Layer (Sidebar + Detail Inspector)
                HStack(spacing: 0) {
                    // Left Column (Sidebar)
                    leftListView
                        .frame(width: 320)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                    
                    Divider()
                        .opacity(0.3)
                    
                    // Right Column (Detail Inspector)
                    rightPreviewView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
                
                Divider()
                    .opacity(0.3)
                
                // 3. Footer: Action Bar
                ActionFooterView(
                    itemCount: filteredItems.count,
                    lang: settings.appLanguage,
                    isCurrentPinned: selectedItem?.isPinned ?? false,
                    onPaste: { pasteCurrent(plainText: false) },
                    onCopy: { copyCurrent() },
                    onPastePlain: { pasteCurrent(plainText: true) },
                    onDelete: { deleteCurrent() },
                    onTogglePin: { togglePinCurrent() }
                )
                .disabled(filteredItems.isEmpty || searchModel.isSearching || pasteService.isBusy || storage.isLoading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            }
        }
        .frame(width: PanelController.panelWidth, height: PanelController.panelHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onAppear {
            panelVisible = true
            isSearchFocused = true
            isAccessibilityGranted = AccessibilityManager.shared.isAccessibilityGranted
            resetOnPanelOpen()
            refreshSearch()
            updateKeyCoordinator()
            keyCoordinator.start()
        }
        .onDisappear {
            panelVisible = false
            keyCoordinator.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: PanelController.didShow)) { _ in
            panelVisible = true
            isSearchFocused = true
            isAccessibilityGranted = AccessibilityManager.shared.isAccessibilityGranted
            resetOnPanelOpen()
            refreshSearch()
            updateKeyCoordinator()
            keyCoordinator.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: PanelController.didHide)) { _ in
            panelVisible = false
            keyCoordinator.stop()
        }
        .onChange(of: storage.revision) { _, _ in refreshSearch() }
        .onChange(of: selectedFilter) { _, _ in
            refreshSearch()
        }
        .onChange(of: settings.appLanguage) { _, _ in refreshSearch() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityGranted = AccessibilityManager.shared.isAccessibilityGranted
        }
        .onReceive(searchModel.$snapshot) { snapshot in
            let newItems = snapshot.items
            if shouldResetSelectionOnNextSnapshot {
                shouldResetSelectionOnNextSnapshot = false
                selectedItemId = newItems.first?.id
                if let firstId = newItems.first?.id {
                    scrollCommand = ScrollCommand(id: firstId, count: (scrollCommand?.count ?? 0) &+ 1)
                }
            } else if let id = selectedItemId, !newItems.contains(where: { $0.id == id }) {
                if let oldIndex = itemIndexMap[id] {
                    let nextIndex = min(oldIndex, max(0, newItems.count - 1))
                    let candidateId = newItems.indices.contains(nextIndex) ? newItems[nextIndex].id : newItems.first?.id
                    selectedItemId = candidateId
                    if let candidateId {
                        scrollCommand = ScrollCommand(id: candidateId, count: (scrollCommand?.count ?? 0) &+ 1)
                    }
                } else {
                    selectedItemId = newItems.first?.id
                }
            } else if selectedItemId == nil {
                selectedItemId = newItems.first?.id
            }
            updateKeyCoordinator()
        }
        .onChange(of: selectedItemId) { _, _ in
            updateKeyCoordinator()
        }
        .onChange(of: searchText) { _, newText in
            if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                shouldResetSelectionOnNextSnapshot = true
            }
            refreshSearch()
            updateKeyCoordinator()
        }
    }
    
    // MARK: - Header Titlebar & Toolbar View (Full Width)
    
    private var headerView: some View {
        VStack(spacing: 8) {
            // Clean borderless and background-free Search Field Row
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField(L10n.searchPlaceholder(lang: settings.appLanguage), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isSearchFocused)
                
                if searchModel.isSearching {
                    ProgressView().controlSize(.small)
                }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.accessibilityClearSearch(lang: settings.appLanguage))
                }
                
                // Gear Settings Button
                Button {
                    PanelController.shared.hide()
                    PanelController.shared.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L10n.settingsTooltip(lang: settings.appLanguage))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 2)
            
            // Category Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ContentFilter.allCases) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: filter.icon)
                                    .font(.system(size: 10))
                                Text(filter.title(lang: settings.appLanguage))
                                    .font(.system(size: 11, weight: selectedFilter == filter ? .semibold : .regular))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule()
                                    .fill(selectedFilter == filter ? Color.primary.opacity(0.14) : Color.primary.opacity(0.06))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(selectedFilter == filter ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 0.5)
                            )
                            .foregroundColor(selectedFilter == filter ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
    }
    
    // MARK: - Date Grouping Structure
    
    public struct DateSection: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let items: [ClipboardItem]
    }
    
    private func sectionHeaderView(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(nil)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
    
    // MARK: - Left Master List
    
    private var leftListView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    if let error = storage.lastError ?? pasteService.lastError {
                        HStack {
                            Text(error).font(.caption).foregroundStyle(.orange)
                            Spacer()
                            Button(L10n.actionDismiss(lang: settings.appLanguage)) {
                                storage.lastError = nil
                                pasteService.lastError = nil
                            }
                        }.padding(8)
                    }
                    if settings.monitoringPaused {
                        Text(L10n.statusRecordingPaused(lang: settings.appLanguage))
                            .font(.caption).foregroundStyle(.secondary).padding(4)
                    }
                    if storage.lastDeletedItem != nil {
                        HStack {
                            Text(L10n.statusItemDeleted(lang: settings.appLanguage))
                            Button(L10n.actionUndo(lang: settings.appLanguage)) { storage.undoDelete() }
                            Spacer()
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .transition(.opacity)
                    }

                    if filteredItems.isEmpty {
                        VStack(spacing: 8) {
                            Spacer(minLength: 40)
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                            Text(storage.isLoading
                                ? L10n.loadingHistory(lang: settings.appLanguage)
                                : (storage.items.isEmpty
                                    ? L10n.emptyPrompt(lang: settings.appLanguage)
                                    : L10n.noResults(lang: settings.appLanguage)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(dateSections) { section in
                            Section {
                                ForEach(section.items) { item in
                                    let index = itemIndexMap[item.id] ?? 999
                                    ItemRowView(
                                        item: item,
                                        isSelected: selectedItemId == item.id,
                                        shortcutIndex: index < 9 ? (index + 1) : nil,
                                        lang: settings.appLanguage
                                    )
                                    .id(item.id)
                                    .onTapGesture {
                                        selectedItemId = item.id
                                    }
                                    .simultaneousGesture(
                                        TapGesture(count: 2).onEnded {
                                            selectedItemId = item.id
                                            pasteCurrent(plainText: false)
                                        }
                                    )
                                }
                            } header: {
                                if !section.title.isEmpty {
                                    sectionHeaderView(title: section.title)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .thinScrollbar()
            }
            .contentMargins(.vertical, 8, for: .scrollContent)
            .frame(maxWidth: .infinity)
            .thinScrollbar()
            .onChange(of: scrollCommand) { _, command in
                if let command {
                    withAnimation(.easeInOut(duration: 0.08)) {
                        proxy.scrollTo(command.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Right Detail Preview
    
    private var rightPreviewView: some View {
        DetailPreviewView(item: selectedItem, lang: settings.appLanguage)
    }
    
    // MARK: - Actions
    
    private func pasteCurrent(plainText: Bool) {
        guard !searchModel.isSearching, !pasteService.isBusy, let item = selectedItem else { return }
        performPaste(for: item, plainText: plainText)
    }
    
    private func copyCurrent() {
        guard !searchModel.isSearching, !pasteService.isBusy, let item = selectedItem else { return }
        storage.touchItem(item)
        Task {
            if await pasteService.copyToClipboard(item) { PanelController.shared.hide() }
        }
    }
    
    private func deleteCurrent() {
        guard !searchModel.isSearching, let item = selectedItem else { return }
        storage.deleteItem(item)
    }
    
    private func togglePinCurrent() {
        guard let item = selectedItem else { return }
        storage.togglePin(for: item)
    }
    
    private func quickPasteAtIndex(_ index: Int) {
        guard !searchModel.isSearching, !pasteService.isBusy, index >= 0 && index < filteredItems.count else { return }
        let item = filteredItems[index]
        performPaste(for: item, plainText: false)
    }

    private func performPaste(for item: ClipboardItem, plainText: Bool) {
        storage.touchItem(item)
        let isTrusted = AccessibilityManager.shared.isAccessibilityGranted
        isAccessibilityGranted = isTrusted
        
        if settings.pasteDirectly && !isTrusted {
            showAccessibilityPermissionDialog(for: item, plainText: plainText)
            return
        }
        
        PanelController.shared.hide()
        Task {
            if !(await pasteService.pasteItem(item, plainTextOnly: plainText)), isTrusted {
                PanelController.shared.show()
            }
        }
    }

    private func showAccessibilityPermissionDialog(for item: ClipboardItem, plainText: Bool) {
        Task { await pasteService.copyToClipboard(item, plainTextOnly: plainText) }
        PanelController.shared.hide()
        
        let lang = settings.appLanguage
        let alert = NSAlert()
        alert.messageText = L10n.accessibilityDialogTitle(lang: lang)
        alert.informativeText = L10n.accessibilityDialogMessage(lang: lang)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.grantPermissionBtn(lang: lang))
        alert.addButton(withTitle: L10n.cancelBtn(lang: lang))
        
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityManager.shared.openAccessibilitySettings()
        }
    }
    
    // MARK: - Keyboard Navigation
    
    private func updateKeyCoordinator() {
        guard panelVisible else { keyCoordinator.stop(); return }
        keyCoordinator.onCopy = { copyCurrent() }
        keyCoordinator.onUndo = { storage.undoDelete() }
        keyCoordinator.onReturn = { isOption in
            pasteCurrent(plainText: isOption)
        }
        keyCoordinator.onDownArrow = {
            selectNextItem()
        }
        keyCoordinator.onUpArrow = {
            selectPreviousItem()
        }
        keyCoordinator.onNumberShortcut = { num in
            quickPasteAtIndex(num - 1)
        }
        keyCoordinator.onDelete = {
            deleteCurrent()
        }
        keyCoordinator.onTogglePin = {
            togglePinCurrent()
        }
        keyCoordinator.onSettings = {
            PanelController.shared.hide()
            PanelController.shared.showSettings()
        }
    }
    
    private func selectNextItem() {
        guard !filteredItems.isEmpty else { return }
        if let currentId = selectedItemId,
           let currentIndex = filteredItems.firstIndex(where: { $0.id == currentId }) {
            if currentIndex + 1 < filteredItems.count {
                let nextId = filteredItems[currentIndex + 1].id
                selectedItemId = nextId
                scrollCommand = ScrollCommand(id: nextId, count: (scrollCommand?.count ?? 0) &+ 1)
            }
            // Stop at bottom: do NOT wrap to the top
        } else if let first = filteredItems.first {
            selectedItemId = first.id
            scrollCommand = ScrollCommand(id: first.id, count: (scrollCommand?.count ?? 0) &+ 1)
        }
    }
    
    private func selectPreviousItem() {
        guard !filteredItems.isEmpty else { return }
        if let currentId = selectedItemId,
           let currentIndex = filteredItems.firstIndex(where: { $0.id == currentId }) {
            if currentIndex - 1 >= 0 {
                let prevId = filteredItems[currentIndex - 1].id
                selectedItemId = prevId
                scrollCommand = ScrollCommand(id: prevId, count: (scrollCommand?.count ?? 0) &+ 1)
            }
            // Stop at top: do NOT wrap to the bottom
        } else if let first = filteredItems.first {
            selectedItemId = first.id
            scrollCommand = ScrollCommand(id: first.id, count: (scrollCommand?.count ?? 0) &+ 1)
        }
    }
}

// MARK: - Key Navigation Coordinator

/// Intercepts local window keyboard events cleanly without leaking monitors or stale captures
@MainActor
private final class KeyNavigationCoordinator: ObservableObject {
    var onCopy: (() -> Void)?
    var onUndo: (() -> Void)?
    var onReturn: ((Bool) -> Void)?
    var onDownArrow: (() -> Void)?
    var onUpArrow: (() -> Void)?
    var onNumberShortcut: ((Int) -> Void)?
    var onDelete: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onSettings: (() -> Void)?
    
    private var monitor: KeyMonitorToken?
    
    func start() {
        monitor?.remove()
        monitor = nil
        let token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let window = event.window as? FloatingPanel,
                  window.isVisible, window.isKeyWindow else { return event }
            let editor = window.firstResponder as? NSTextView
            if editor?.hasMarkedText() == true { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "c" {
                if let editor, editor.selectedRange().length > 0 { return event }
                self.onCopy?()
                return nil
            }
            if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "z" {
                if let editor, editor.isEditable, editor.undoManager?.canUndo == true { return event }
                self.onUndo?()
                return nil
            }
            
            // 1. Enter: Return (36) or Keypad Enter (76)
            if event.keyCode == 36 || event.keyCode == 76 {
                let isOption = event.modifierFlags.contains(.option)
                self.onReturn?(isOption)
                return nil
            }
            
            // 2. Down Arrow: Select next item
            if event.keyCode == 125 && modifiers.isEmpty {
                self.onDownArrow?()
                return nil
            }
            
            // 3. Up Arrow: Select previous item
            if event.keyCode == 126 && modifiers.isEmpty {
                self.onUpArrow?()
                return nil
            }
            
            // 4. Command shortcuts
            if event.modifierFlags.contains(.command) {
                // ⌘ , : Open Settings
                if event.charactersIgnoringModifiers == "," {
                    self.onSettings?()
                    return nil
                }
                
                // ⌘1..9 Quick Paste
                if let characters = event.charactersIgnoringModifiers,
                   let num = Int(characters), num >= 1 && num <= 9 {
                    self.onNumberShortcut?(num)
                    return nil
                }
                
                // ⌘ + Delete: Delete item
                if event.keyCode == 51 {
                    self.onDelete?()
                    return nil
                }
                
                // ⌘ + P: Toggle Pin
                if event.charactersIgnoringModifiers?.lowercased() == "p" {
                    self.onTogglePin?()
                    return nil
                }
            }
            
            return event
        }
        monitor = token.map { KeyMonitorToken($0) }
    }
    
    func stop() {
        if let monitor = monitor {
            monitor.remove()
            self.monitor = nil
        }
        onCopy = nil
        onUndo = nil
        onReturn = nil
        onDownArrow = nil
        onUpArrow = nil
        onNumberShortcut = nil
        onDelete = nil
        onTogglePin = nil
        onSettings = nil
    }
    
    deinit {
        if let monitor = monitor {
            Task { @MainActor in monitor.remove() }
        }
    }
}

/// The opaque token is immutable and can only be used through a MainActor method.
/// This lets nonisolated deinit schedule cleanup without transferring an arbitrary Any value.
private final class KeyMonitorToken: @unchecked Sendable {
    private let value: Any
    @MainActor init(_ value: Any) { self.value = value }
    @MainActor func remove() { NSEvent.removeMonitor(value) }
}
