import SwiftUI

struct PlayerSetupView: View {
    @ObservedObject var model: LibraryViewModel
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(language == .russian ? "Выберите основной плеер" : "Choose your default player")
                        .font(.title3.weight(.semibold))
                    Text(language == .russian
                        ? "Его можно изменить в библиотеке в любое время."
                        : "You can change it from the library at any time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                setupPlayerRow(
                    choice: .quickTime,
                    installed: true
                )
                ForEach(model.detectedPlayers) { player in
                    setupPlayerRow(
                        choice: player.choice,
                        installed: player.isInstalled
                    )
                }
            }

            HStack {
                Spacer()
                Button(language == .russian ? "Позже" : "Later") {
                    model.dismissPlayerSetup()
                }
            }
        }
        .padding(24)
        .frame(width: 470)
    }

    private func setupPlayerRow(
        choice: ExternalPlayerChoice,
        installed: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: choice == .quickTime ? "play.rectangle" : "play.square")
                .frame(width: 28)
                .foregroundStyle(installed ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.title(language: language)).font(.headline)
                Text(installed
                    ? (language == .russian ? "Установлен" : "Installed")
                    : (language == .russian ? "Не установлен" : "Not installed"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if installed {
                Button(language == .russian ? "Выбрать" : "Select") {
                    model.setPlayer(choice, language: language)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(language == .russian ? "Скачать" : "Download") {
                    model.download(choice)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
