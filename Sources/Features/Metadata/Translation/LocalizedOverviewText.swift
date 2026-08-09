import AppKit
import SwiftUI
import Translation

enum OverviewTranslationPolicy {
    static func shouldTranslate(
        _ text: String,
        provider: MetadataProvider?,
        language: AppLanguage,
        mode: OverviewTranslationMode
    ) -> Bool {
        guard mode == .automatic,
              language == .russian,
              provider == .omdb,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let cyrillicCount = text.unicodeScalars.reduce(into: 0) { count, scalar in
            if (0x0400...0x04FF).contains(scalar.value) {
                count += 1
            }
        }
        return cyrillicCount < 3
    }
}

struct LocalizedOverviewText: View {
    let sourceText: String
    let provider: MetadataProvider?
    let mediaID: String?
    let language: AppLanguage
    let translationMode: OverviewTranslationMode
    let lineLimit: Int
    let expandedMaximumHeight: CGFloat?

    @State private var translatedText: String?
    @State private var isTranslating = false
    @State private var configuration: TranslationSession.Configuration?
    @State private var isExpanded = false
    @State private var fullTextHeight: CGFloat = 0

    init(
        sourceText: String,
        provider: MetadataProvider?,
        mediaID: String?,
        language: AppLanguage,
        translationMode: OverviewTranslationMode,
        lineLimit: Int,
        expandedMaximumHeight: CGFloat? = nil
    ) {
        self.sourceText = sourceText
        self.provider = provider
        self.mediaID = mediaID
        self.language = language
        self.translationMode = translationMode
        self.lineLimit = lineLimit
        self.expandedMaximumHeight = expandedMaximumHeight
    }

    private var requestID: String {
        [
            provider?.rawValue ?? "-",
            mediaID ?? "-",
            language.rawValue,
            translationMode.rawValue,
            sourceText
        ].joined(separator: "|")
    }

    private var shouldTranslate: Bool {
        OverviewTranslationPolicy.shouldTranslate(
            sourceText,
            provider: provider,
            language: language,
            mode: translationMode
        )
    }

    private var displayedText: String {
        translatedText ?? sourceText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            overviewBody

            if translatedText != nil {
                Label("OMDb · Переведено Apple", systemImage: "translate")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else if isTranslating {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Перевод…")
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard expandedMaximumHeight != nil else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                isExpanded.toggle()
            }
        }
        .task(id: requestID) {
            isExpanded = false
            fullTextHeight = 0
            await prepareTranslation(for: requestID)
        }
        .translationTask(configuration) { session in
            await translate(using: session, requestID: requestID)
        }
        .onChange(of: translatedText) {
            fullTextHeight = 0
        }
    }

    @ViewBuilder
    private var overviewBody: some View {
        if isExpanded, let maximumHeight = expandedMaximumHeight {
            ScrollView(.vertical) {
                overviewText
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: OverviewTextHeightKey.self,
                                value: geometry.size.height
                            )
                        }
                    }
                    .background(ThinScrollViewConfigurator())
            }
            .frame(height: min(max(fullTextHeight, 18), maximumHeight))
            .scrollIndicators(fullTextHeight > maximumHeight + 1 ? .visible : .hidden)
            .onPreferenceChange(OverviewTextHeightKey.self) { height in
                guard abs(fullTextHeight - height) > 0.5 else { return }
                withAnimation(.easeInOut(duration: 0.20)) {
                    fullTextHeight = height
                }
            }
        } else {
            overviewText
                .lineLimit(lineLimit)
        }
    }

    private var overviewText: some View {
        Text(displayedText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
    }

    @MainActor
    private func prepareTranslation(for currentRequestID: String) async {
        translatedText = nil
        isTranslating = false
        configuration = nil
        guard shouldTranslate, let provider else { return }

        if let cached = await OverviewTranslationCache.shared.value(
            provider: provider,
            mediaID: mediaID,
            sourceText: sourceText,
            targetLanguage: "ru"
        ) {
            guard currentRequestID == requestID else { return }
            translatedText = cached
            return
        }

        guard currentRequestID == requestID else { return }
        isTranslating = true
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "ru")
        )
    }

    @MainActor
    private func translate(
        using session: TranslationSession,
        requestID currentRequestID: String
    ) async {
        guard shouldTranslate, let provider else { return }
        do {
            let response = try await session.translate(sourceText)
            guard currentRequestID == requestID else { return }
            let value = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                isTranslating = false
                return
            }
            await OverviewTranslationCache.shared.save(
                value,
                provider: provider,
                mediaID: mediaID,
                sourceText: sourceText,
                targetLanguage: "ru"
            )
            guard currentRequestID == requestID else { return }
            translatedText = value
            isTranslating = false
        } catch {
            guard currentRequestID == requestID else { return }
            isTranslating = false
        }
    }
}

private struct OverviewTextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ThinScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ThinScrollConfigurationView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ThinScrollConfigurationView)?.scheduleConfiguration()
    }
}

private final class ThinScrollConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleConfiguration()
    }

    func scheduleConfiguration() {
        DispatchQueue.main.async { [weak self] in
            guard let scrollView = self?.enclosingScrollView else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = true
            if !(scrollView.verticalScroller is ThinOverlayScroller) {
                let scroller = ThinOverlayScroller()
                scroller.controlSize = .mini
                scrollView.verticalScroller = scroller
            }
        }
    }
}

private final class ThinOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        5
    }

    override func drawKnob() {
        let knobRect = rect(for: .knob).insetBy(dx: 1, dy: 2)
        guard knobRect.width > 0, knobRect.height > 0 else { return }
        NSColor.secondaryLabelColor.withAlphaComponent(0.42).setFill()
        NSBezierPath(
            roundedRect: knobRect,
            xRadius: knobRect.width / 2,
            yRadius: knobRect.width / 2
        ).fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}
