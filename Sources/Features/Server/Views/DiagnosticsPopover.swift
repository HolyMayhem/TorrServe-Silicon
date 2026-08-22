import SwiftUI

struct DiagnosticsPopover: View {
    @ObservedObject var model: MainWindowModel

    private var isChecking: Bool {
        model.isRunningDiagnostics
            || model.portDiagnostic.kind == .checking
            || model.processDiagnostic.kind == .checking
            || model.executableDiagnostic.kind == .checking
    }

    private var hasNeverRun: Bool {
        model.portDiagnostic.kind == .idle
            && model.processDiagnostic.kind == .idle
            && model.executableDiagnostic.kind == .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.language == .russian ? "Диагностика TorrServer" : "TorrServer diagnostics")
                        .font(.headline)
                    Text(model.language == .russian
                        ? "Проверка порта, экземпляров TorrServer и исполняемого файла."
                        : "Checks the port, TorrServer instances, and executable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isChecking || model.isStoppingExternalProcesses {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Button {
                model.onRunFullDiagnostics?()
            } label: {
                Label(
                    model.language == .russian ? "Запустить полную проверку" : "Run full check",
                    systemImage: "waveform.path.ecg"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isChecking || model.isStoppingExternalProcesses)

            VStack(spacing: 0) {
                DiagnosticCheckRow(
                    title: model.language == .russian ? "Порт 8090" : "Port 8090",
                    fallbackMessage: model.language == .russian ? "Доступность API TorrServer" : "TorrServer API availability",
                    checkTitle: model.language == .russian ? "Проверить" : "Check",
                    systemImage: "network",
                    result: model.portDiagnostic,
                    isDisabled: isChecking,
                    action: { model.onCheckPort?() }
                )

                Divider().padding(.leading, 38)

                DiagnosticCheckRow(
                    title: processTitle,
                    fallbackMessage: model.language == .russian ? "Другие копии приложения и TorrServer" : "Other app and TorrServer copies",
                    checkTitle: model.language == .russian ? "Проверить" : "Check",
                    systemImage: "square.stack.3d.up",
                    result: model.processDiagnostic,
                    isDisabled: isChecking || model.isStoppingExternalProcesses,
                    action: { model.onFindTorrServer?() }
                )

                Divider().padding(.leading, 38)

                DiagnosticCheckRow(
                    title: model.language == .russian ? "Исполняемый файл" : "Executable",
                    fallbackMessage: model.language == .russian ? "Путь, права запуска и архитектура arm64" : "Path, execution permission, and arm64 architecture",
                    checkTitle: model.language == .russian ? "Проверить" : "Check",
                    systemImage: "checkmark.shield",
                    result: model.executableDiagnostic,
                    isDisabled: isChecking,
                    action: { model.onCheckExecutable?() }
                )
            }
            .padding(.horizontal, 11)
            .background(Color.secondary.opacity(0.075), in: RoundedRectangle(cornerRadius: 13))

            Button {
                model.onStopExternalProcesses?()
            } label: {
                Label(stopAllTitle, systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isChecking || model.isStoppingExternalProcesses)

            HStack(spacing: 8) {
                Button {
                    model.onCopyDiagnosticReport?()
                } label: {
                    Label(
                        model.language == .russian ? "Скопировать отчёт" : "Copy report",
                        systemImage: "doc.on.doc"
                    )
                    .frame(maxWidth: .infinity)
                }

                Button {
                    model.onSaveDiagnosticReport?()
                } label: {
                    Label(
                        model.language == .russian ? "Сохранить…" : "Save…",
                        systemImage: "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isChecking || model.isStoppingExternalProcesses)

            HStack {
                Button {
                    model.onDownload?()
                } label: {
                    Label(
                        model.language == .russian ? "Скачать свежий TorrServer" : "Download latest TorrServer",
                        systemImage: "arrow.down.circle"
                    )
                }
                .buttonStyle(.link)

                Spacer()
            }

            if !model.latestDiagnostic.message.isEmpty,
               model.latestDiagnostic.kind != .checking {
                Label(
                    model.latestDiagnostic.message,
                    systemImage: resultIcon(model.latestDiagnostic.kind)
                )
                .font(.caption)
                .foregroundStyle(resultColor(model.latestDiagnostic.kind))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    resultColor(model.latestDiagnostic.kind).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 11)
                )
            }
        }
        .padding(16)
        .frame(width: 480)
        .onAppear {
            if hasNeverRun {
                model.onRunFullDiagnostics?()
            }
        }
    }

    private var processTitle: String {
        let count = model.processScan.processes.count
        guard count > 0 else {
            return model.language == .russian ? "Другие копии" : "Other copies"
        }
        return model.language == .russian
            ? "Другие копии · \(count)"
            : "Other copies · \(count)"
    }

    private var stopAllTitle: String {
        return model.language == .russian
            ? "Найти и остановить все копии"
            : "Find and stop all copies"
    }

    private func resultColor(_ kind: DiagnosticResultKind) -> Color {
        switch kind {
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        default: return .secondary
        }
    }

    private func resultIcon(_ kind: DiagnosticResultKind) -> String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        case .checking: return "hourglass"
        case .idle: return "circle"
        }
    }
}

struct DiagnosticCheckRow: View {
    let title: String
    let fallbackMessage: String
    let checkTitle: String
    let systemImage: String
    let result: DiagnosticResult
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: resultIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(resultColor)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(result.message.isEmpty ? fallbackMessage : result.message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isDisabled || result.kind == .checking)
            .help(checkTitle)
            .accessibilityLabel(checkTitle)
        }
        .padding(.vertical, 9)
    }

    private var resultIcon: String {
        switch result.kind {
        case .idle: return systemImage
        case .checking: return "hourglass"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    private var resultColor: Color {
        switch result.kind {
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        default: return .secondary
        }
    }
}
