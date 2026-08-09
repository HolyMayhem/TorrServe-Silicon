import SwiftUI

struct PlayerStatusButton: View {
    let player: DetectedPlayer
    let isPreferred: Bool
    let language: AppLanguage
    let select: () -> Void
    let download: () -> Void

    var body: some View {
        Button(action: player.isInstalled ? select : download) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(player.choice.title(language: language))
                        .font(.caption.weight(.semibold))
                    if isPreferred {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Text(status)
                    .font(.system(size: 9.5))
                    .foregroundStyle(isPreferred ? Color.green : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var status: String {
        if isPreferred {
            return language == .russian ? "По умолчанию" : "Default"
        }
        if player.isInstalled {
            return language == .russian ? "Установлен" : "Installed"
        }
        return language == .russian ? "Скачать" : "Download"
    }
}

struct StartStopCircleButton: View {
    @ObservedObject var model: MainWindowModel
    let texts: Texts

    private var isRunning: Bool { model.canStop }
    private var isEnabled: Bool { model.canStart || model.canStop }

    var body: some View {
        Button {
            if isRunning {
                model.onStop?()
            } else {
                model.onStart?()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(isEnabled ? 0.055 : 0.025))

                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        isEnabled
                            ? (isRunning ? Color.red : Color.green)
                            : Color.secondary.opacity(0.45)
                    )
                    .offset(x: isRunning ? 0 : 1)
            }
            .frame(width: 40, height: 40)
            .serverCircularActionSurface(
                tint: isRunning ? .red : .green,
                isEnabled: isEnabled
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(isRunning ? texts.stop : texts.start)
        .accessibilityLabel(isRunning ? texts.stop : texts.start)
    }
}

struct ServerActionCapsuleButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .serverActionSurface()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

struct GlassActionButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                if isProminent {
                    Button(action: action) {
                        Label(title, systemImage: systemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button(action: action) {
                        Label(title, systemImage: systemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            } else {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(isProminent ? .green : nil)
            }
        }
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}

struct GlassToggleRow: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    var isEnabled = true
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Toggle(
                "",
                isOn: Binding(
                    get: { isOn },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.22)) {
                            onChange(newValue)
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!isEnabled)
            .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 29)
    }
}

struct GlassLanguagePicker: View {
    let language: AppLanguage
    let russianTitle: String
    let englishTitle: String
    let onChange: (AppLanguage) -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.24)) {
                onChange(language == .russian ? .english : .russian)
            }
        } label: {
            ZStack(alignment: language == .russian ? .leading : .trailing) {
                languageTrack

                languageThumb
                    .padding(3)

                HStack(spacing: 0) {
                    languageLabel(russianTitle, value: .russian)
                    languageLabel(englishTitle, value: .english)
                }
            }
            .frame(width: 230, height: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            language == .russian ? russianTitle : englishTitle
        )
        .accessibilityHint(
            language == .russian ? englishTitle : russianTitle
        )
    }

    @ViewBuilder
    private var languageTrack: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(Color.secondary.opacity(0.10))
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(Color.secondary.opacity(0.18))
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private var languageThumb: some View {
        let thumb = Capsule()
            .fill(Color.accentColor.opacity(0.72))
            .frame(width: 112, height: 22)

        if #available(macOS 26.0, *) {
            thumb.glassEffect(
                .regular.tint(Color.accentColor.opacity(0.45)).interactive(),
                in: Capsule()
            )
        } else {
            thumb.shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
    }

    private func languageLabel(_ title: String, value: AppLanguage) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: language == value ? .semibold : .regular))
            .foregroundStyle(language == value ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
    }
}

struct GlassJackettPicker: View {
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.24)) {
                onChange(!isEnabled)
            }
        } label: {
            ZStack(alignment: isEnabled ? .leading : .trailing) {
                jackettTrack

                jackettThumb
                    .padding(3)

                HStack(spacing: 0) {
                    optionLabel("Jackett", selected: isEnabled)
                    optionLabel("Off", selected: !isEnabled)
                }
            }
            .frame(width: 230, height: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jackett")
        .accessibilityValue(isEnabled ? "Jackett" : "Off")
        .accessibilityHint(isEnabled ? "Off" : "Jackett")
    }

    @ViewBuilder
    private var jackettTrack: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(Color.secondary.opacity(0.10))
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(Color.secondary.opacity(0.18))
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private var jackettThumb: some View {
        let thumb = Capsule()
            .fill(Color.accentColor.opacity(0.72))
            .frame(width: 112, height: 22)

        if #available(macOS 26.0, *) {
            thumb.glassEffect(
                .regular.tint(Color.accentColor.opacity(0.45)).interactive(),
                in: Capsule()
            )
        } else {
            thumb.shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
    }

    private func optionLabel(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
    }
}

struct GlassMetadataProviderPicker: View {
    let provider: MetadataProvider
    let onChange: (MetadataProvider) -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.24)) {
                onChange(provider == .tmdb ? .omdb : .tmdb)
            }
        } label: {
            ZStack(alignment: provider == .tmdb ? .leading : .trailing) {
                providerTrack

                providerThumb
                    .padding(3)

                HStack(spacing: 0) {
                    optionLabel("TMDB", value: .tmdb)
                    optionLabel("OMDb", value: .omdb)
                }
            }
            .frame(width: 230, height: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Metadata provider")
        .accessibilityValue(provider.displayName)
    }

    @ViewBuilder
    private var providerTrack: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(Color.secondary.opacity(0.10))
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(Color.secondary.opacity(0.18))
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private var providerThumb: some View {
        let thumb = Capsule()
            .fill(Color.accentColor.opacity(0.72))
            .frame(width: 112, height: 22)

        if #available(macOS 26.0, *) {
            thumb.glassEffect(
                .regular.tint(Color.accentColor.opacity(0.45)).interactive(),
                in: Capsule()
            )
        } else {
            thumb.shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
    }

    private func optionLabel(_ title: String, value: MetadataProvider) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: provider == value ? .semibold : .regular))
            .foregroundStyle(provider == value ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
    }
}

struct GlassSpeedUnitPicker: View {
    let unit: SpeedDisplayUnit
    let automaticTitle: String
    let megabytesTitle: String
    let megabitsTitle: String
    let onChange: (SpeedDisplayUnit) -> Void

    private let width: CGFloat = 230
    private let height: CGFloat = 28
    private let inset: CGFloat = 3

    private var selectedIndex: Int {
        switch unit {
        case .automatic: return 0
        case .megabytes: return 1
        case .megabits: return 2
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            speedTrack

            GeometryReader { geometry in
                let segmentWidth = (geometry.size.width - inset * 2) / 3

                speedThumb
                    .frame(width: segmentWidth, height: height - inset * 2)
                    .offset(
                        x: inset + CGFloat(selectedIndex) * segmentWidth,
                        y: inset
                    )
            }

            HStack(spacing: 0) {
                speedOption(automaticTitle, value: .automatic)
                speedOption(megabytesTitle, value: .megabytes)
                speedOption(megabitsTitle, value: .megabits)
            }
        }
        .frame(width: width, height: height)
        .animation(.easeInOut(duration: 0.24), value: unit)
    }

    @ViewBuilder
    private var speedTrack: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(Color.secondary.opacity(0.10))
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(Color.secondary.opacity(0.18))
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private var speedThumb: some View {
        let thumb = Capsule()
            .fill(Color.accentColor.opacity(0.72))

        if #available(macOS 26.0, *) {
            thumb.glassEffect(
                .regular.tint(Color.accentColor.opacity(0.45)).interactive(),
                in: Capsule()
            )
        } else {
            thumb.shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
    }

    private func speedOption(
        _ title: String,
        value: SpeedDisplayUnit
    ) -> some View {
        Button {
            onChange(value)
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: unit == value ? .semibold : .regular))
                .foregroundStyle(unit == value ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(unit == value ? .isSelected : [])
    }
}

extension View {
    @ViewBuilder
    func glassSection() -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        if #available(macOS 26.0, *) {
            self
                .padding(16)
                .glassEffect(.regular, in: shape)
        } else {
            self
                .padding(16)
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func serverActionSurface() -> some View {
        let shape = Capsule()

        if #available(macOS 26.0, *) {
            self
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func serverCircularActionSurface(tint: Color, isEnabled: Bool) -> some View {
        let shape = Circle()

        if #available(macOS 26.0, *) {
            self
                .glassEffect(
                    .regular
                        .tint(tint.opacity(isEnabled ? 0.08 : 0.02))
                        .interactive(),
                    in: shape
                )
                .overlay(
                    shape.stroke(tint.opacity(isEnabled ? 0.24 : 0.08), lineWidth: 0.6)
                )
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(
                    shape.stroke(tint.opacity(isEnabled ? 0.24 : 0.08), lineWidth: 0.6)
                )
        }
    }

    @ViewBuilder
    func serverBottomPanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        if #available(macOS 26.0, *) {
            self
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 102, maxHeight: 102, alignment: .top)
                .glassEffect(.regular, in: shape)
        } else {
            self
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 102, maxHeight: 102, alignment: .top)
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.10), lineWidth: 0.5))
        }
    }
}
