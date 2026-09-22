import SwiftUI
import AppKit

/// Detail Inspector pane on the right side of the HUD window
public struct DetailPreviewView: View {
    public let item: ClipboardItem?
    public let lang: AppLanguage
    
    @State private var showFullText = false
    @State private var textStatistics: (characters: Int, words: Int)?
    @State private var isQRCopiedFlash: Bool = false
    @State private var isOCRCopiedFlash: Bool = false
    @State private var jsonFormatResult: JSONFormatter.FormatResult? = nil
    @State private var isPrettyMode: Bool = true
    @State private var isURLToggled: Bool = false
    @State private var isActionCopied: Bool = false
    
    public init(item: ClipboardItem?, lang: AppLanguage = .english) {
        self.item = item
        self.lang = lang
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if let item = item {
                // Main scrollable content preview
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        contentPreview(for: item)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .thinScrollbar()
                }
                .frame(maxHeight: .infinity)
                .thinScrollbar()
                
                // Sticky Detection Cards (QR, OCR, Link QR) - 100% full width, pinned above footer
                if hasDetectionCards(for: item) {
                    Divider()
                        .opacity(0.3)
                    
                    detectionCards(for: item)
                }
                
                Divider()
                    .opacity(0.3)
                
                // Pinned Footer Section: Action Controls + Metadata
                footerSection(for: item)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.25))
        .task(id: item?.id) {
            updateItemState(for: item)
            
            let text = item?.textContent ?? ""
            guard !text.isEmpty else { return }
            
            // Asynchronously calculate exact word and character statistics in background
            let calculation = Task.detached(priority: .utility) {
                var words = 0
                var insideWord = false
                for scalar in text.unicodeScalars {
                    if Task.isCancelled { return (0, 0) }
                    let whitespace = CharacterSet.whitespacesAndNewlines.contains(scalar)
                    if !whitespace && !insideWord { words += 1 }
                    insideWord = !whitespace
                }
                return (text.count, words)
            }
            let result = await withTaskCancellationHandler {
                await calculation.value
            } onCancel: {
                calculation.cancel()
            }
            guard !Task.isCancelled else { return }
            textStatistics = result
        }
    }
    
    private func updateItemState(for item: ClipboardItem?) {
        showFullText = false
        textStatistics = nil
        isPrettyMode = true
        isURLToggled = false
        isActionCopied = false
        
        let text = item?.textContent ?? ""
        if !text.isEmpty && JSONFormatter.isPotentialJSON(text) {
            jsonFormatResult = JSONFormatter.formatAndHighlight(text)
        } else {
            jsonFormatResult = nil
        }
    }
    
    // MARK: - Footer Section (Actions & Metadata)
    
    private func footerSection(for item: ClipboardItem) -> some View {
        VStack(spacing: 0) {
            // Row 1: Action Controls (Copy, Pretty/Raw, Open in Browser, Send Email, etc.)
            actionToolbar(for: item)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            
            Divider()
                .opacity(0.3)
            
            // Row 2: Metadata Line 1 - Content Type (left) <Spacer> Word/Char Count (right)
            HStack(spacing: 8) {
                contentTypeLabel(for: item)
                
                Spacer()
                
                if let stats = contentStats(for: item) {
                    Text(stats)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            
            Divider()
                .opacity(0.3)
            
            // Row 3: Metadata Line 2 - Source App (left) <Spacer> Timestamp (right)
            HStack(spacing: 8) {
                if let appName = item.sourceAppName {
                    HStack(spacing: 4) {
                        if let bundleId = item.sourceAppBundleId,
                           let icon = SourceAppIconCache.shared.icon(for: bundleId) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 13, height: 13)
                        }
                        Text(appName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(formattedDate(item.timestamp))
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
        .background(Color.primary.opacity(0.02))
    }
    
    // MARK: - Action Toolbar
    
    @ViewBuilder
    private func actionToolbar(for item: ClipboardItem) -> some View {
        HStack(spacing: 8) {
            if let jsonResult = jsonFormatResult {
                // JSON: Pretty / Raw Toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isPrettyMode.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isPrettyMode ? "text.alignleft" : "curlybraces")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14, height: 14)
                        Text(isPrettyMode ? L10n.jsonRaw(lang: lang) : L10n.jsonPretty(lang: lang))
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                
                // JSON: Copy
                actionButton(
                    title: L10n.actionCopy(lang: lang),
                    icon: "doc.on.doc",
                    isSuccess: isActionCopied
                ) {
                    let textToCopy = isPrettyMode ? jsonResult.prettyString : (item.textContent ?? "")
                    copyText(textToCopy)
                }
            } else if let email = item.detectedEmail {
                // Email: Send Email + Copy
                actionButton(
                    title: L10n.sendEmail(lang: lang),
                    icon: "envelope.fill"
                ) {
                    if let url = URL(string: "mailto:\(email)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                actionButton(
                    title: L10n.actionCopy(lang: lang),
                    icon: "doc.on.doc",
                    isSuccess: isActionCopied
                ) {
                    copyText(email)
                }
            } else if item.isURL || item.contentType == .link,
                      let urlStr = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !urlStr.isEmpty {
                // Link: Open in Browser + Decode/Encode Toggle + Copy Link
                actionButton(
                    title: L10n.openInBrowser(lang: lang),
                    icon: "arrow.up.right.square"
                ) {
                    if let url = URL(string: urlStr) ?? URL(string: urlEncoded(urlStr)) {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                // Decode / Encode Utility Button
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isURLToggled.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "percent")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14, height: 14)
                        Text(urlToggleLabel(for: urlStr))
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundColor(isURLToggled ? .accentColor : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isURLToggled ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                
                actionButton(
                    title: L10n.actionCopy(lang: lang),
                    icon: "doc.on.doc",
                    isSuccess: isActionCopied
                ) {
                    copyText(transformedURL(for: urlStr))
                }
            } else if item.contentType == .image, let fileName = item.imageFileName {
                // Image: Open Full Image + Copy Image
                actionButton(
                    title: L10n.previewOpenFullImage(lang: lang),
                    icon: "arrow.up.right.square"
                ) {
                    if let url = ImageCacheManager.shared.url(for: fileName) {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                actionButton(
                    title: L10n.actionCopy(lang: lang),
                    icon: "doc.on.doc",
                    isSuccess: isActionCopied
                ) {
                    if let url = ImageCacheManager.shared.url(for: fileName),
                       let data = try? Data(contentsOf: url) {
                        NSPasteboard.general.clearContents()
                        let entry = NSPasteboardItem()
                        entry.setData(data, forType: .png)
                        entry.setData(Data([1]), forType: ClipboardMonitor.ownContentType)
                        NSPasteboard.general.writeObjects([entry])
                        triggerCopyFeedback()
                    }
                }
            } else if item.contentType == .file, let paths = item.filePaths, !paths.isEmpty {
                // File: Show in Finder + Open + Copy Path
                actionButton(
                    title: L10n.showInFinder(lang: lang),
                    icon: "folder"
                ) {
                    if let first = paths.first {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: first)])
                    }
                }
                
                actionButton(
                    title: L10n.openFile(lang: lang),
                    icon: "arrow.up.right.square"
                ) {
                    if let first = paths.first {
                        NSWorkspace.shared.open(URL(fileURLWithPath: first))
                    }
                }
                
                actionButton(
                    title: L10n.copyPath(lang: lang),
                    icon: "doc.on.doc",
                    isSuccess: isActionCopied
                ) {
                    copyText(paths.joined(separator: "\n"))
                }
            } else if item.contentType == .colorHex, let hex = item.colorHex {
                // Color: Copy HEX + Copy RGB
                actionButton(
                    title: "HEX",
                    icon: "doc.on.doc",
                    isSuccess: isActionCopied
                ) {
                    copyText(hex)
                }
                
                if let rgb = ColorExtractor.rgbString(from: hex) {
                    actionButton(
                        title: "RGB",
                        icon: "doc.on.doc"
                    ) {
                        copyText(rgb)
                    }
                }
            } else if let text = item.textContent, !text.isEmpty {
                // Default Text: Copy
                actionButton(
                    title: L10n.actionCopy(lang: lang),
                    icon: "doc.on.doc",
                    isSuccess: isActionCopied
                ) {
                    copyText(text)
                }
            }
            
            Spacer()
        }
    }
    
    private func actionButton(
        title: String,
        icon: String,
        isSuccess: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isSuccess ? "checkmark" : icon)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .foregroundColor(isSuccess ? .green : .secondary)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(isSuccess ? .green : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
    
    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        NSPasteboard.general.setData(Data([1]), forType: ClipboardMonitor.ownContentType)
        triggerCopyFeedback()
    }
    
    private func triggerCopyFeedback() {
        if UserSettings.shared.playSounds {
            SoundEffectManager.playSound(named: UserSettings.shared.soundName)
        }
        isActionCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isActionCopied = false
        }
    }
    
    // MARK: - Content Type Label (Icon + Text without badge background)
    
    @ViewBuilder
    private func contentTypeLabel(for item: ClipboardItem) -> some View {
        if jsonFormatResult != nil {
            typeLabel(title: L10n.jsonBadge(lang: lang), icon: "curlybraces", color: .purple)
        } else if item.isEmail {
            typeLabel(title: L10n.emailBadge(lang: lang), icon: "envelope.fill", color: .blue)
        } else if item.isURL {
            typeLabel(title: L10n.contentTypeLink(lang: lang), icon: "link", color: .blue)
        } else {
            switch item.contentType {
            case .text, .richText:
                typeLabel(title: L10n.textTypeLabel(lang: lang), icon: "doc.text", color: .secondary)
            case .image:
                typeLabel(title: L10n.contentTypeImage(lang: lang), icon: "photo", color: .teal)
            case .colorHex:
                typeLabel(title: L10n.contentTypeColor(lang: lang), icon: "paintpalette.fill", color: .pink)
            case .link:
                typeLabel(title: L10n.contentTypeLink(lang: lang), icon: "link", color: .blue)
            case .file:
                typeLabel(title: L10n.contentTypeFile(lang: lang), icon: "folder.fill", color: .orange)
            }
        }
    }
    
    private func typeLabel(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
        }
    }
    
    private func contentStats(for item: ClipboardItem) -> String? {
        if item.contentType == .text || item.contentType == .richText {
            let chars = textStatistics?.characters ?? item.characterCount
            let words = textStatistics?.words ?? item.wordCount
            return L10n.textStats(chars: chars, words: words, lang: lang)
        } else if item.contentType == .image, let w = item.imageWidth, let h = item.imageHeight {
            var parts = ["\(Int(w)) × \(Int(h))"]
            if let size = item.imageFileSize {
                parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
            return parts.joined(separator: " • ")
        } else if item.contentType == .file, let paths = item.filePaths {
            return "\(paths.count) \(L10n.systemFiles(lang: lang).lowercased())"
        }
        return nil
    }
    
    // MARK: - Content Previews by Type
    
    @ViewBuilder
    private func contentPreview(for item: ClipboardItem) -> some View {
        switch item.contentType {
        case .text, .richText:
            if item.isURL {
                linkPreview(item)
            } else {
                textPreview(item)
            }
        case .image:
            imagePreview(item)
        case .colorHex:
            colorPreview(item)
        case .link:
            linkPreview(item)
        case .file:
            filePreview(item)
        }
    }
    
    // 1. Plain & Rich Text Preview
    private func textPreview(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let jsonResult = jsonFormatResult, isPrettyMode {
                Text(jsonResult.attributed)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(showFullText ? (item.textContent ?? "") : String((item.textContent ?? "").prefix(12_000)))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !showFullText, (item.textContent?.utf8.count ?? 0) > 12_000 {
                    Button(L10n.previewShowFullText(lang: lang)) { showFullText = true }
                    Text(L10n.previewFullTextNotice(lang: lang))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // 2. Image Preview, QR Code & OCR Text
    private func imagePreview(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let fileName = item.imageFileName {
                ClipboardImageView(fileName: fileName, maxPixelSize: 1200)
                    .frame(maxHeight: 220)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            }
            if item.ocrStatus == "pending" {
                HStack { ProgressView().controlSize(.small); Text(L10n.previewRecognizingOcr(lang: lang)) }
                    .font(.callout)
            } else if item.ocrStatus == "failed" || item.ocrStatus == "interrupted" {
                Text(L10n.previewRecognitionFailed(lang: lang))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    
    // QR Code Detected Content
    private func qrPayloadContent(qr: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "qrcode")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text(L10n.qrDetectedHeader(lang: lang))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Copy QR text icon button without label
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(qr, forType: .string)
                    NSPasteboard.general.setData(Data([1]), forType: ClipboardMonitor.ownContentType)
                    isQRCopiedFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        isQRCopiedFlash = false
                    }
                } label: {
                    Image(systemName: isQRCopiedFlash ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .frame(width: 14, height: 14, alignment: .center)
                        .foregroundColor(isQRCopiedFlash ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22, alignment: .center)
                .help(L10n.copyQrText(lang: lang))
                
                // Open link button (only if QR content is a URL)
                if let url = URL(string: qr), url.scheme == "http" || url.scheme == "https" {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                            .frame(width: 14, height: 14, alignment: .center)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 22, height: 22, alignment: .center)
                    .help(L10n.openQrLink(lang: lang))
                }
            }
            
            Text(qr)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // OCR Recognized Text Content
    private func ocrTextContent(ocr: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text(L10n.ocrHeader(lang: lang))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Copy OCR text icon button without label
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ocr, forType: .string)
                    NSPasteboard.general.setData(Data([1]), forType: ClipboardMonitor.ownContentType)
                    isOCRCopiedFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        isOCRCopiedFlash = false
                    }
                } label: {
                    Image(systemName: isOCRCopiedFlash ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .frame(width: 14, height: 14, alignment: .center)
                        .foregroundColor(isOCRCopiedFlash ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22, alignment: .center)
                .help(L10n.actionCopy(lang: lang))
            }
            
            Text(ocr)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // Generated QR Code Card for Web Links
    private func generatedQRCard(qrImage: NSImage) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .background(Color.white)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                    
                    Text(L10n.qrGenerateTab(lang: lang))
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                }
                
                Text(L10n.qrGenerateTip(lang: lang))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([qrImage])
                    NSPasteboard.general.setData(Data([1]), forType: ClipboardMonitor.ownContentType)
                    isQRCopiedFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isQRCopiedFlash = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isQRCopiedFlash ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(isQRCopiedFlash ? L10n.qrImageCopied(lang: lang) : L10n.copyQrImage(lang: lang))
                            .font(.caption2)
                    }
                    .foregroundColor(isQRCopiedFlash ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }
            
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // 3. Color Codes
    private func colorPreview(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let hex = item.colorHex, let nsColor = ColorExtractor.nsColor(from: hex) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: nsColor))
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                
                VStack(spacing: 8) {
                    colorInfoRow(label: "HEX", value: hex)
                    if let rgb = ColorExtractor.rgbString(from: hex) {
                        colorInfoRow(label: "RGB", value: rgb)
                    }
                    if let hsl = ColorExtractor.hslString(from: hex) {
                        colorInfoRow(label: "HSL", value: hsl)
                    }
                }
            }
        }
    }
    
    private func colorInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)
            
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                NSPasteboard.general.setData(Data([1]), forType: ClipboardMonitor.ownContentType)
                triggerCopyFeedback()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .frame(width: 14, height: 14, alignment: .center)
            }
            .buttonStyle(.borderless)
            .frame(width: 22, height: 22, alignment: .center)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
    
    // 4. Web URLs
    private func linkPreview(_ item: ClipboardItem) -> some View {
        let original = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayed = transformedURL(for: original)
        
        return VStack(alignment: .leading, spacing: 12) {
            Text(displayed)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .underline(true, color: .secondary.opacity(0.4))
                .textSelection(.enabled)
        }
    }
    
    // MARK: - URL Transform Helpers
    
    private func isOriginallyEncoded(_ text: String) -> Bool {
        return text.contains("%") && (text.removingPercentEncoding != text)
    }
    
    private func transformedURL(for original: String) -> String {
        let isEncoded = isOriginallyEncoded(original)
        if isEncoded {
            return isURLToggled ? (original.removingPercentEncoding ?? original) : original
        } else {
            return isURLToggled ? urlEncoded(original) : original
        }
    }
    
    private func urlToggleLabel(for original: String) -> String {
        let isEncoded = isOriginallyEncoded(original)
        if isEncoded {
            return isURLToggled ? L10n.urlEncode(lang: lang) : L10n.urlDecode(lang: lang)
        } else {
            return isURLToggled ? L10n.urlDecode(lang: lang) : L10n.urlEncode(lang: lang)
        }
    }
    
    private func urlEncoded(_ text: String) -> String {
        let allowed = CharacterSet.urlQueryAllowed
            .union(CharacterSet.urlPathAllowed)
            .union(CharacterSet.urlHostAllowed)
            .union(CharacterSet(charactersIn: "#[]"))
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
    
    // 5. File System URLs
    private func filePreview(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let paths = item.filePaths {
                ForEach(paths, id: \.self) { path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
                }
            }
        }
    }
    
    // MARK: - Sticky Detection Cards (Full-Width Edge-to-Edge)
    
    private func hasDetectionCards(for item: ClipboardItem) -> Bool {
        switch item.contentType {
        case .image:
            let hasQR = !(item.qrCodePayload?.isEmpty ?? true)
            let hasOCR = !(item.ocrText?.isEmpty ?? true)
            return hasQR || hasOCR
        case .link, .text, .richText:
            if item.isURL, let urlStr = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               URL(string: urlStr) != nil {
                return true
            }
            return false
        default:
            return false
        }
    }
    
    @ViewBuilder
    private func detectionCards(for item: ClipboardItem) -> some View {
        switch item.contentType {
        case .image:
            let hasQR = !(item.qrCodePayload?.isEmpty ?? true)
            let hasOCR = !(item.ocrText?.isEmpty ?? true)
            
            VStack(spacing: 0) {
                if let qr = item.qrCodePayload, !qr.isEmpty {
                    qrPayloadContent(qr: qr)
                }
                
                if hasQR && hasOCR {
                    Divider()
                        .opacity(0.3)
                }
                
                if let ocr = item.ocrText, !ocr.isEmpty {
                    ocrTextContent(ocr: ocr)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            
        case .link, .text, .richText:
            if let urlStr = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               let qrImage = QRCodeEngine.shared.generateQRCode(from: urlStr, size: 120) {
                generatedQRCard(qrImage: qrImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            }
            
        default:
            EmptyView()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(L10n.selectItemPreview(lang: lang))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
