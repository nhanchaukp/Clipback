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
                
                // Sticky Detection Cards (QR, OCR, Link QR) - 100% full width, pinned above metadata footer
                if hasDetectionCards(for: item) {
                    Divider()
                        .opacity(0.3)
                    
                    detectionCards(for: item)
                }
                
                Divider()
                    .opacity(0.3)
                
                // Metadata footer card (Source application, precise timestamp, dimensions)
                metadataFooter(for: item)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.02))
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.25))
        .task(id: item?.id) {
            showFullText = false
            textStatistics = nil
            jsonFormatResult = nil
            isPrettyMode = true
            
            let text = item?.textContent ?? ""
            guard !text.isEmpty else { return }
            
            // Asynchronously detect and format JSON in background
            if JSONFormatter.isPotentialJSON(text) {
                let jsonTask = Task.detached(priority: .userInitiated) { () -> JSONFormatter.FormatResult? in
                    if Task.isCancelled { return nil }
                    return JSONFormatter.formatAndHighlight(text)
                }
                if let formatted = await jsonTask.value, !Task.isCancelled {
                    jsonFormatResult = formatted
                }
            }
            
            // Asynchronously calculate word and character statistics in background
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
            HStack(spacing: 8) {
                if jsonFormatResult != nil {
                    // JSON Badge
                    HStack(spacing: 4) {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 10, weight: .bold))
                        Text(L10n.jsonBadge(lang: lang))
                            .font(.caption.bold())
                    }
                    .foregroundColor(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(5)
                } else {
                    Label(L10n.textTypeLabel(lang: lang), systemImage: "doc.text")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // If JSON is detected, show Pretty / Raw toggle + Copy Formatted button
                if let jsonResult = jsonFormatResult {
                    HStack(spacing: 6) {
                        // Toggle Pretty / Raw
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isPrettyMode.toggle()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isPrettyMode ? "text.alignleft" : "curlybraces")
                                    .font(.system(size: 10))
                                Text(isPrettyMode ? L10n.jsonRaw(lang: lang) : L10n.jsonPretty(lang: lang))
                                    .font(.caption2.bold())
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        
                        // Copy active mode content
                        Button {
                            let textToCopy = isPrettyMode ? jsonResult.prettyString : (item.textContent ?? "")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(textToCopy, forType: .string)
                            NSPasteboard.general.setData(Data([1]), forType: ClipboardMonitor.ownContentType)
                            StorageManager.shared.touchItem(item)
                            if UserSettings.shared.playSounds { SoundEffectManager.playSound(named: UserSettings.shared.soundName) }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(L10n.actionCopy(lang: lang))
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
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
                Button(L10n.previewOpenFullImage(lang: lang)) {
                    if let url = ImageCacheManager.shared.url(for: fileName) { NSWorkspace.shared.open(url) }
                }
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
                
                // Open URL icon button (if link) without label
                if let url = URL(string: qr), (url.scheme == "http" || url.scheme == "https") {
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
                
                // Copy QR text icon button without label
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(qr, forType: .string)
                    NSPasteboard.general.setData(Data([1]), forType: ClipboardMonitor.ownContentType)
                    if let item = item { StorageManager.shared.touchItem(item) }
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            if qr.count > 160 || qr.contains("\n") {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(qr)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .thinScrollbar()
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 90)
                .thinScrollbar()
            } else {
                Text(qr)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
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
                    if let item = item { StorageManager.shared.touchItem(item) }
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
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            if ocr.count > 160 || ocr.contains("\n") {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(ocr)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .thinScrollbar()
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 110)
                .thinScrollbar()
            } else {
                Text(ocr)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
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
                if let item = item { StorageManager.shared.touchItem(item) }
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
    
    // 4. Web URLs & Generated QR Code
    private func linkPreview(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.webLink(lang: lang), systemImage: "link")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            Text(item.textContent ?? "")
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .underline(true, color: .secondary.opacity(0.4))
                .textSelection(.enabled)
            
            if let urlStr = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               let url = URL(string: urlStr) {
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label(L10n.openInBrowser(lang: lang), systemImage: "arrow.up.right.square")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
    
    // 5. File System URLs
    private func filePreview(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.systemFiles(lang: lang), systemImage: "folder")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
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
    
    private func generatedQRCard(qrImage: NSImage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: qrImage)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .padding(4)
                .background(Color.white)
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "qrcode")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(L10n.qrGenerateTab(lang: lang))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                
                Text(L10n.qrGenerateTip(lang: lang))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Button {
                    QRCodeEngine.shared.copyQRCodeImageToPasteboard(qrImage)
                    isQRCopiedFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        isQRCopiedFlash = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isQRCopiedFlash ? "checkmark" : "doc.on.doc")
                        Text(isQRCopiedFlash ? L10n.qrImageCopied(lang: lang) : L10n.copyQrImage(lang: lang))
                    }
                    .font(.caption2.bold())
                    .foregroundColor(isQRCopiedFlash ? .green : .secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // 6. Metadata Footer Card
    
    private func metadataFooter(for item: ClipboardItem) -> some View {
        HStack(spacing: 10) {
            // Source Application
            if let appName = item.sourceAppName {
                HStack(spacing: 4) {
                    if let bundleId = item.sourceAppBundleId,
                       let icon = SourceAppIconCache.shared.icon(for: bundleId) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                    Text(appName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Text specifications (Characters & Words) in footer
            if (item.contentType == .text || item.contentType == .richText),
               let stats = textStatistics {
                if item.sourceAppName != nil {
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                
                Text(L10n.textStats(chars: stats.characters, words: stats.words, lang: lang))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Image specifications (Dimensions & File Size) in footer
            if item.contentType == .image, let w = item.imageWidth, let h = item.imageHeight {
                if item.sourceAppName != nil {
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "aspectratio")
                        .font(.system(size: 10))
                    Text("\(Int(w)) × \(Int(h))")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
                
                if let size = item.imageFileSize {
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Precise Timestamp
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(formattedDate(item.timestamp))
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
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
