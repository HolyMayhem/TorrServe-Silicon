import SwiftUI

struct ServerDiagnosticsSection: View {
    @ObservedObject var model: MainWindowModel

    private let columns = [
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

            primaryDiagnosticAction

            Text(language == .russian ? "ИНСТРУМЕНТЫ" : "TOOLS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)

            LazyVGrid(columns: columns, spacing: 8) {
                diagnosticAction(
                    title: language == .russian ? "Проверить порт 8090" : "Check port 8090",
                    systemImage: "network",
                    result: model.portDiagnostic,
                    action: { model.onCheckPort?() }
                )

                diagnosticAction(
                    title: language == .russian ? "Проверить файл" : "Check executable",
                    systemImage: "checkmark.shield",
                    result: model.executableDiagnostic,
                    action: { model.onCheckExecutable?() }
                )

                diagnosticAction(
                    title: testKeysTitle,
                    systemImage: "key.horizontal",
                    result: model.metadataKeysDiagnostic,
                    action: { model.onTestAllMetadataAPIKeys?() }
                )

                diagnosticAction(
                    title: processCleanupTitle,
                    systemImage: "stop.circle",
                    result: processCleanupResult,
                    action: { model.onStopExternalProcesses?() }
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

            if !model.latestDiagnostic.message.isEmpty,
               model.latestDiagnostic.kind != .checking {
                diagnosticResultBanner(model.latestDiagnostic)
            }

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
        }
        .serverSettingsPanel()
    }

    private var primaryDiagnosticAction: some View {
        Button {
            model.onRunFullDiagnostics?()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(fullCheckTitle)
                        .font(.callout.weight(.semibold))
                    Text(language == .russian
                        ? "Порт, процессы и исполняемый файл"
                        : "Port, processes, and executable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Color.accentColor.opacity(0.09),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
    }

    private func diagnosticAction(
        title: String,
        systemImage: String,
        result: DiagnosticResult = .idle,
        tint: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: result.kind == .idle
                    ? systemImage
                    : diagnosticIcon(result.kind))
                    .foregroundStyle(result.kind == .idle ? tint : diagnosticColor(result.kind))
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
            .frame(height: 42)
            .background(
                tint.opacity(0.065),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(tint.opacity(0.1), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
        .help(result.message.isEmpty ? title : result.message)
        .accessibilityLabel(title)
    }

    private func diagnosticResultBanner(_ result: DiagnosticResult) -> some View {
        Label(result.message, systemImage: diagnosticIcon(result.kind))
            .font(.caption)
            .foregroundStyle(diagnosticColor(result.kind))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                diagnosticColor(result.kind).opacity(0.075),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
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
        return language == .russian
            ? "Найти и остановить все копии"
            : "Find and stop all copies"
    }

    private var processCleanupResult: DiagnosticResult {
        model.isStoppingExternalProcesses
            ? DiagnosticResult(kind: .checking, message: "")
            : model.processDiagnostic
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
