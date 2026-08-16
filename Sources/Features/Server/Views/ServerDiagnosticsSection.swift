import SwiftUI

struct ServerDiagnosticsSection: View {
    @ObservedObject var model: MainWindowModel

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var language: AppLanguage { model.language }

    private var isServerCheckRunning: Bool {
        model.isRunningDiagnostics
            || model.portDiagnostic.kind == .checking
            || model.processDiagnostic.kind == .checking
            || model.executableDiagnostic.kind == .checking
    }

    private var isBusy: Bool {
        isServerCheckRunning
            || model.isStoppingExternalProcesses
            || model.isTestingAllMetadataAPIKeys
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Label(title, systemImage: "stethoscope")
                    .font(.headline)

                Spacer()

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    model.onRunFullDiagnostics?()
                } label: {
                    Label(fullCheckTitle, systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isBusy)

                Button {
                    model.onTestAllMetadataAPIKeys?()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: diagnosticIcon(model.metadataKeysDiagnostic.kind))
                            .foregroundStyle(diagnosticColor(model.metadataKeysDiagnostic.kind))
                        Text(testKeysTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isBusy)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                diagnosticAction(
                    title: language == .russian ? "Проверить порт 8090" : "Check port 8090",
                    systemImage: "network",
                    result: model.portDiagnostic,
                    action: { model.onCheckPort?() }
                )

                diagnosticAction(
                    title: processCleanupTitle,
                    systemImage: "square.stack.3d.up",
                    result: model.processDiagnostic,
                    action: { model.onStopExternalProcesses?() }
                )

                diagnosticAction(
                    title: language == .russian ? "Проверить файл" : "Check executable",
                    systemImage: "checkmark.shield",
                    result: model.executableDiagnostic,
                    action: { model.onCheckExecutable?() }
                )

                diagnosticAction(
                    title: language == .russian ? "Скопировать отчёт" : "Copy report",
                    systemImage: "doc.on.doc",
                    action: { model.onCopyDiagnosticReport?() }
                )

                diagnosticAction(
                    title: language == .russian ? "Сохранить отчёт" : "Save report",
                    systemImage: "square.and.arrow.down",
                    action: { model.onSaveDiagnosticReport?() }
                )
            }

            HStack(spacing: 10) {
                Button {
                    model.onDownload?()
                } label: {
                    Label(
                        language == .russian ? "Скачать свежий TorrServer" : "Download latest TorrServer",
                        systemImage: "arrow.down.circle"
                    )
                }
                .buttonStyle(.link)
                .disabled(isBusy || !model.canDownload)

                Spacer()

                if !model.latestDiagnostic.message.isEmpty,
                   model.latestDiagnostic.kind != .checking {
                    Label(
                        model.latestDiagnostic.message,
                        systemImage: diagnosticIcon(model.latestDiagnostic.kind)
                    )
                    .font(.caption)
                    .foregroundStyle(diagnosticColor(model.latestDiagnostic.kind))
                    .lineLimit(2)
                }
            }
        }
        .serverSettingsPanel()
    }

    private func diagnosticAction(
        title: String,
        systemImage: String,
        result: DiagnosticResult = .idle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: result.kind == .idle
                    ? systemImage
                    : diagnosticIcon(result.kind))
                    .foregroundStyle(diagnosticColor(result.kind))
                    .frame(width: 18)

                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                if result.kind == .checking {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
        .help(result.message.isEmpty ? title : result.message)
        .accessibilityLabel(title)
    }

    private var title: String {
        language == .russian ? "Диагностика" : "Diagnostics"
    }

    private var description: String {
        language == .russian
            ? "Проверка сервера, порта, исполняемого файла, внешних процессов и ключей метаданных."
            : "Check the server, port, executable, external processes, and metadata API keys."
    }

    private var fullCheckTitle: String {
        language == .russian ? "Полная проверка TorrServer" : "Run full TorrServer check"
    }

    private var testKeysTitle: String {
        language == .russian ? "Проверить все API-ключи" : "Test all API keys"
    }

    private var processCleanupTitle: String {
        let count = model.processScan.processes.count
        guard count > 0 else {
            return language == .russian
                ? "Найти и остановить лишние копии"
                : "Find and stop extra copies"
        }
        return language == .russian
            ? "Остановить лишние копии: \(count)"
            : "Stop extra copies: \(count)"
    }

    private func diagnosticIcon(_ kind: DiagnosticResultKind) -> String {
        switch kind {
        case .idle: return "circle"
        case .checking: return "hourglass"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    private func diagnosticColor(_ kind: DiagnosticResultKind) -> Color {
        switch kind {
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        default: return .secondary
        }
    }
}
