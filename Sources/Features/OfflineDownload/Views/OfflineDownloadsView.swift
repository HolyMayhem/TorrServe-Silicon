import AppKit
import SwiftUI

struct OfflineDownloadsView: View {
    @ObservedObject var manager: OfflineDownloadManager
    @ObservedObject var preview: OfflineDownloadsPreview
    let catalog: [String: OfflineMediaInfo]
    let language: AppLanguage
    let openLibrary: () -> Void
    let play: (URL) throws -> Void

    @State private var errorMessage: String?
    @State private var pendingDeletion: OfflineDownloadRecord?
    @State var selectedGroupID: String?
    @AppStorage("OfflineLibraryDisplayMode") private var displayMode = LibraryDisplayMode.compact

    private var isRussian: Bool { language == .russian }
    private var records: [OfflineDownloadRecord] {
        (manager.completedDownloads + preview.records).sorted { $0.completedAt > $1.completedAt }
    }
    private var groups: [OfflineMediaGroup] { OfflineMediaLibrary.groups(records: records, catalog: catalog) }
    private var selectedGroup: OfflineMediaGroup? { groups.first { $0.id == selectedGroupID } }

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label(isRussian ? "Пока нет офлайн-материалов" : "No offline downloads yet", systemImage: "arrow.down.circle")
                } description: {
                    Text(isRussian
                         ? "Скачайте фильм или серию из медиатеки, чтобы смотреть без интернета."
                         : "Download a movie or episode from your library to watch without an internet connection.")
                } actions: {
                    Button(isRussian ? "Открыть медиатеку" : "Open Library", action: openLibrary)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            } else {
                downloadedFiles
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: groups.map(\.id)) { _, ids in
            if let selectedGroupID, !ids.contains(selectedGroupID) { self.selectedGroupID = nil }
        }
        .onChange(of: displayMode) { _, _ in selectedGroupID = nil }
        .onAppear { manager.refreshCompletedDownloads() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.refreshCompletedDownloads()
        }
        .alert(isRussian ? "Ошибка" : "Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            isRussian ? "Удалить скачанный файл?" : "Delete downloaded file?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { record in
            Button(isRussian ? "Переместить в Корзину" : "Move to Trash", role: .destructive) {
                pendingDeletion = nil
                do {
                    try manager.moveCompletedDownloadToTrash(sourceURL: record.sourceURL, expectedLength: record.expectedLength)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button(isRussian ? "Отмена" : "Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { record in
            Text(record.destinationURL.lastPathComponent)
        }
    }

    private var downloadedFiles: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if selectedGroup != nil, displayMode != .compact {
                    Button { selectedGroupID = nil } label: {
                        Label(isRussian ? "Все материалы" : "All downloads", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                } else {
                    Label(isRussian ? "Сохранённые материалы" : "Saved Downloads", systemImage: "arrow.down.circle")
                        .font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                LibraryDisplayModePicker(selection: $displayMode, language: language)
                Button(isRussian ? "Открыть медиатеку" : "Open Library", action: openLibrary)
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if displayMode == .compact {
                compactLibrary
            } else if let selectedGroup {
                mediaDetail(selectedGroup)
            } else {
                gallery
            }

            Divider()
            HStack {
                Text(isRussian ? "Материалов: \(groups.count) · Файлов: \(records.count)" : "Items: \(groups.count) · Files: \(records.count)")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: records.reduce(0) { $0 + $1.expectedLength }, countStyle: .file))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var compactLibrary: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(groups) { group in
                        OfflineMediaCard(group: group, mode: .compact, language: language, isSelected: group.id == selectedGroupID) {
                            selectedGroupID = group.id
                        }
                    }
                }
                .padding(12)
            }
            .frame(width: 300)
            Divider()
            if let selectedGroup { mediaDetail(selectedGroup) }
            else {
                ContentUnavailableView(isRussian ? "Выберите материал" : "Select a title", systemImage: "film.stack", description: Text(isRussian ? "Откройте фильм или сериал, чтобы увидеть скачанные файлы." : "Open a movie or series to see its downloaded files."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var gallery: some View {
        ScrollView {
            if displayMode == .posters {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 14)], spacing: 14) {
                    ForEach(groups) { group in
                        OfflineMediaCard(group: group, mode: .posters, language: language) { selectedGroupID = group.id }
                    }
                }
                .padding(14)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(groups) { group in
                        OfflineMediaCard(group: group, mode: .cards, language: language) { selectedGroupID = group.id }
                    }
                }
                .padding(14)
            }
        }
    }

    private func mediaDetail(_ group: OfflineMediaGroup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    OfflineMediaArtwork(group: group)
                        .frame(width: 80, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                        Text(group.isSeries ? (isRussian ? "Сериал" : "Series") : (isRussian ? "Фильм" : "Movie"))
                            .font(.callout).foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: group.totalBytes, countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                ForEach(group.fileSections) { section in
                    Text(section.season.map { isRussian ? "Сезон \($0)" : "Season \($0)" } ?? (isRussian ? "Файлы" : "Files"))
                        .font(.headline)
                    VStack(spacing: 0) {
                        ForEach(section.records, id: \.destinationURL) { record in
                            fileRow(record)
                            if record.destinationURL != section.records.last?.destinationURL { Divider() }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func fileRow(_ record: OfflineDownloadRecord) -> some View {
        let isDemo = preview.contains(record)
        let available = isDemo || manager.completedDestination(sourceURL: record.sourceURL, expectedLength: record.expectedLength) == record.destinationURL
        return HStack(spacing: 14) {
            Image(systemName: "film")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.destinationURL.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Text(available
                     ? (isDemo ? (isRussian ? "Демо · " : "Demo · ") : "") + ByteCountFormatter.string(fromByteCount: record.expectedLength, countStyle: .file)
                     : (isRussian ? "Файл недоступен — проверьте папку или подключение диска" : "File unavailable — check the folder or reconnect the drive"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                do { try play(record.destinationURL) }
                catch { errorMessage = error.localizedDescription }
            } label: {
                Label(isRussian ? "Смотреть" : "Watch", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)
            .disabled(!available || isDemo)
            .help(isDemo ? (isRussian ? "Демо-материал без видеофайла" : "Demo item without a video file") : (isRussian ? "Смотреть" : "Watch"))

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([record.destinationURL])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(isRussian ? "Показать в Finder" : "Show in Finder")
            .accessibilityLabel(isRussian ? "Показать в Finder" : "Show in Finder")
            .disabled(!available || isDemo)

            Button {
                if isDemo { preview.remove(record) }
                else { pendingDeletion = record }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(isRussian ? "Удалить скачанный файл" : "Delete downloaded file")
            .accessibilityLabel(isRussian ? "Удалить скачанный файл" : "Delete downloaded file")
        }
        .padding(.vertical, 16)
        .help(record.destinationURL.path)
    }
}
