import SwiftUI

struct SearchSourcesSettingsView: View {
    @ObservedObject var model: SearchViewModel
    let language: AppLanguage
    private var ru: Bool { language == .russian }
    private var texts: SearchTexts { SearchTexts(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(ru ? "Источники поиска" : "Search Sources", systemImage: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            Picker(ru ? "Режим поиска" : "Search mode", selection: Binding(get: { model.mode }, set: model.setMode)) {
                ForEach(TorrentSearchMode.allCases) { mode in Text(mode.title(language: language)).tag(mode) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(model.mode.detail(language: language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.mode.usesTorrentSearch { nativeSources }
                    if model.mode.usesJackett { jackettSettings }
                }
                .padding(1)
            }
            .frame(maxHeight: 390)
            .scrollIndicators(.automatic)

            HStack {
                Link(ru ? "О TorrentSearch" : "About TorrentSearch", destination: URL(string: "https://github.com/prajwalch/TorrentSearch")!)
                    .font(.caption)
                Spacer()
                Button(ru ? "Готово" : "Done") { model.showsSettings = false }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private var nativeSources: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(TorrentSearchProvider.allCases) { provider in
                    if provider != TorrentSearchProvider.allCases.first { Divider() }
                    Toggle(isOn: Binding(get: { model.enabledProviders.contains(provider) }, set: { model.setProvider(provider, enabled: $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.title).font(.callout.weight(.medium))
                            Text(provider.detail(language: language)).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 8)
                }
                if model.enabledProviders.isEmpty {
                    Text(ru ? "Включите хотя бы один источник для TorrentSearch." : "Enable at least one TorrentSearch source.")
                        .font(.caption).foregroundStyle(.orange).padding(.top, 8)
                }
            }
            .padding(.horizontal, 6)
        } label: { Text("TorrentSearch").font(.headline) }
    }

    private var jackettSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if model.mode == .combined, !model.jackettIsConfigured {
                    Text(ru ? "Jackett пока не подключён. Встроенный поиск уже доступен." : "Jackett is not connected yet. Built-in search is already available.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField(texts.jackettAddress, text: $model.serverURL)
                    .textFieldStyle(.roundedBorder)
                SecureField(texts.apiKeyPlaceholder, text: $model.apiKey)
                    .textFieldStyle(.roundedBorder)
                Text(ru ? "Адрес и ключ сохраняются после успешной проверки." : "The address and key are saved after a successful connection test.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button(texts.openJackett) { model.openJackett() }
                        .disabled(model.configuration.normalizedServerURL == nil)
                    Spacer()
                    if model.isTesting { ProgressView().controlSize(.small) }
                    Button(texts.saveAndCheck) { model.testConnection(language: language) }
                        .disabled(model.isTesting || !model.configuration.isComplete)
                }
                if !model.connectionMessage.isEmpty {
                    Label(model.connectionMessage, systemImage: model.jackettConnectionIsHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(model.jackettConnectionIsHealthy ? Color.green : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(6)
        } label: { Text("Jackett").font(.headline) }
    }
}
