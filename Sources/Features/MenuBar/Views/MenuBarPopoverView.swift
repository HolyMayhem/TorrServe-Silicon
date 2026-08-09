import AppKit
import SwiftUI

final class MenuBarPopoverModel: ObservableObject {
    @Published var language: AppLanguage = .systemDefault
    @Published var statusText = ""
    @Published var statusKind: MainStatusKind = .stopped
    @Published var isRunning = false
    @Published var canStart = false
    @Published var canStop = false
    @Published var canOpenWeb = true
    @Published var canDownload = true
    @Published var isDownloading = false

    @Published var speedText = ""
    @Published var speedSamples: [Double] = []
    @Published var activeTitle: String?
    @Published var materialIsActive = false
    @Published var activeSizeText = ""
    @Published var bufferProgress: Double?
    @Published var seeders = 0
    @Published var peers = 0
    @Published var isLoadingMaterial = false

    @Published var webUIAddress = ""
    @Published var qrImage: NSImage?
    @Published var showsQRCode = false

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onOpenWeb: (() -> Void)?
    var onShowWindow: (() -> Void)?
    var onDownload: (() -> Void)?
    var onQuit: (() -> Void)?
    var onQRCodeVisibilityChanged: (() -> Void)?
}

struct MenuBarPopoverView: View {
    @ObservedObject var model: MenuBarPopoverModel

    private var texts: Texts {
        Texts(language: model.language)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.44),
                    Color.green.opacity(0.055),
                    Color(nsColor: .windowBackgroundColor).opacity(0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                header
                currentMaterialCard
                speedCard
                actionButtons
                webUICard
                footer
            }
            .padding(13)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(model.statusKind.color.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(model.statusKind.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("TorrServer")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if model.isRunning {
                Text(model.speedText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .popoverGlass(in: Capsule())
            }
        }
    }

    private var currentMaterialCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    model.materialIsActive ? texts.currentMaterial : texts.recentMaterial,
                    systemImage: "film.stack"
                )
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                if model.isLoadingMaterial {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let title = model.activeTitle {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !model.activeSizeText.isEmpty {
                    Text(model.activeSizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let progress = model.bufferProgress {
                    VStack(spacing: 5) {
                        HStack {
                            Text(texts.buffer)
                            Spacer()
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ProgressView(value: progress)
                            .tint(.green)
                    }
                }

                HStack(spacing: 8) {
                    statisticBadge(
                        title: texts.seeds,
                        value: model.seeders,
                        systemImage: "arrow.up.circle.fill"
                    )
                    statisticBadge(
                        title: texts.peers,
                        value: model.peers,
                        systemImage: "person.2.fill"
                    )
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(.secondary)
                    Text(texts.noActiveMaterial)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 5)
            }
        }
        .frame(height: 140, alignment: .top)
        .popoverSection()
    }

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(texts.speedHistory, systemImage: "chart.xyaxis.line")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(model.speedText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            SpeedSparkline(samples: model.speedSamples)
                .frame(height: 58)
        }
        .popoverSection()
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            PopoverActionButton(
                title: model.canStop ? texts.stop : texts.start,
                systemImage: model.canStop ? "stop.fill" : "play.fill",
                isEnabled: model.canStop || model.canStart,
                isProminent: true,
                action: {
                    if model.canStop {
                        model.onStop?()
                    } else {
                        model.onStart?()
                    }
                }
            )

            PopoverActionButton(
                title: texts.webUI,
                systemImage: "safari",
                isEnabled: model.canOpenWeb,
                action: { model.onOpenWeb?() }
            )

            PopoverActionButton(
                title: texts.openWindow,
                systemImage: "macwindow",
                isEnabled: true,
                action: { model.onShowWindow?() }
            )
        }
    }

    private var webUICard: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    model.showsQRCode.toggle()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    model.onQRCodeVisibilityChanged?()
                }
            } label: {
                HStack {
                    Label(
                        model.showsQRCode ? texts.hideQRCode : texts.showQRCode,
                        systemImage: "qrcode"
                    )
                    Spacer()
                    Image(systemName: model.showsQRCode ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if model.showsQRCode {
                Divider()

                VStack(spacing: 8) {
                    if let image = model.qrImage {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 154, height: 154)
                            .padding(8)
                            .background(Color.white, in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            ))
                    }

                    Text(texts.localWebUI)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.webUIAddress)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .popoverSection()
    }

    private var footer: some View {
        HStack {
            Button {
                model.onDownload?()
            } label: {
                Label(texts.downloadArm, systemImage: "arrow.down.circle")
            }
            .buttonStyle(.plain)
            .disabled(!model.canDownload)

            Spacer()

            Button(texts.quit) {
                model.onQuit?()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 4)
    }

    private func statisticBadge(
        title: String,
        value: Int,
        systemImage: String
    ) -> some View {
        Label("\(title) \(value)", systemImage: systemImage)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .popoverGlass(in: Capsule())
    }
}

private struct SpeedSparkline: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { geometry in
            let values = samples.isEmpty ? [0, 0] : samples
            let maximum = max(values.max() ?? 0, 1)
            let points = values.enumerated().map { index, value in
                let denominator = CGFloat(max(values.count - 1, 1))
                return CGPoint(
                    x: CGFloat(index) / denominator * geometry.size.width,
                    y: geometry.size.height
                        - CGFloat(value / maximum) * (geometry.size.height - 6)
                        - 3
                )
            }

            ZStack {
                Path { path in
                    for row in 1...2 {
                        let y = geometry.size.height * CGFloat(row) / 3
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.secondary.opacity(0.12), style: StrokeStyle(
                    lineWidth: 0.5,
                    dash: [3, 4]
                ))

                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geometry.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(
                            x: points[points.count - 1].x,
                            y: geometry.size.height
                        ))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.green.opacity(0.30),
                                Color.green.opacity(0.015)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(
                        Color.green,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .accessibilityLabel("Download speed graph")
    }
}

private struct PopoverActionButton: View {
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
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button(action: action) {
                        Label(title, systemImage: systemImage)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            } else {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(isProminent ? .green : nil)
            }
        }
        .controlSize(.regular)
        .disabled(!isEnabled)
    }
}

private extension View {
    @ViewBuilder
    func popoverGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.10), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func popoverSection() -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if #available(macOS 26.0, *) {
            self
                .padding(12)
                .glassEffect(.regular, in: shape)
        } else {
            self
                .padding(12)
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.10), lineWidth: 0.5))
        }
    }
}
