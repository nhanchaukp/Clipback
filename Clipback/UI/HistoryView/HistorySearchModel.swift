import Combine
import SwiftUI

struct HistorySnapshot: Sendable {
    var items: [ClipboardItem] = []
    var indices: [UUID: Int] = [:]
    var sections: [HistoryMainView.DateSection] = []

    nonisolated init(
        items: [ClipboardItem] = [],
        indices: [UUID: Int] = [:],
        sections: [HistoryMainView.DateSection] = []
    ) {
        self.items = items
        self.indices = indices
        self.sections = sections
    }
}

actor HistorySearchIndex {
    private var cache: [UUID: (ClipboardItem, String)] = [:]
    private var indexedRevision: Int?

    func search(items: [ClipboardItem], query: String, filter: HistoryMainView.ContentFilter,
                language: AppLanguage, now: Date = Date(), revision: Int? = nil) -> HistorySnapshot {
        let query = Self.normalize(query)
        var result: [ClipboardItem] = []
        let changed = revision == nil || indexedRevision != revision
        if changed {
            let current = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            // Invalidate changed payloads even when the active query is empty or filtered.
            cache = cache.filter { current[$0.key] == $0.value.0 }
            indexedRevision = revision
        }
        for item in items {
            if Task.isCancelled { return HistorySnapshot() }
            let matchesType: Bool
            switch filter {
            case .all: matchesType = true
            case .text: matchesType = item.contentType == .text || item.contentType == .richText
            case .image: matchesType = item.contentType == .image
            case .color: matchesType = item.contentType == .colorHex
            case .link: matchesType = item.contentType == .link
            case .pinned: matchesType = item.isPinned
            }
            guard matchesType else { continue }
            if !query.isEmpty {
                if cache[item.id] == nil {
                    let fields = [item.textContent, item.colorHex, item.sourceAppName, item.ocrText, item.qrCodePayload]
                        .compactMap { $0 } + (item.filePaths ?? [])
                    cache[item.id] = (item, Self.normalize(fields.joined(separator: "\0")))
                }
                guard cache[item.id]?.1.contains(query) == true else { continue }
            }
            result.append(item)
        }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .vietnamese ? "vi_VN" : "en_US")
        formatter.dateStyle = .medium
        var buckets: [Date: [ClipboardItem]] = [:]
        var days: [Date] = []
        for item in result {
            let day = calendar.startOfDay(for: item.timestamp)
            if buckets[day] == nil { days.append(day) }
            buckets[day, default: []].append(item)
        }
        let today = calendar.startOfDay(for: now)
        let sections = days.map { day in
            let difference = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            let title: String
            switch difference {
            case 0: title = ""
            case 1: title = L10n.yesterdaySection(lang: language)
            case 2...7: title = L10n.daysAgoSection(difference, lang: language)
            default: title = formatter.string(from: day)
            }
            return HistoryMainView.DateSection(id: String(day.timeIntervalSince1970), title: title, items: buckets[day] ?? [])
        }
        return HistorySnapshot(items: result, indices: Dictionary(uniqueKeysWithValues: result.enumerated().map { ($1.id, $0) }), sections: sections)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
    }
}

@MainActor
final class HistorySearchModel: ObservableObject {
    @Published private(set) var snapshot = HistorySnapshot()
    @Published private(set) var isSearching = false
    private let index = HistorySearchIndex()
    private var task: Task<Void, Never>?

    func update(items: [ClipboardItem], query: String, filter: HistoryMainView.ContentFilter, language: AppLanguage, revision: Int) {
        task?.cancel()
        isSearching = true
        task = Task {
            if !query.isEmpty {
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            }
            let result = await index.search(items: items, query: query, filter: filter, language: language, revision: revision)
            guard !Task.isCancelled else { return }
            snapshot = result
            isSearching = false
        }
    }
}
