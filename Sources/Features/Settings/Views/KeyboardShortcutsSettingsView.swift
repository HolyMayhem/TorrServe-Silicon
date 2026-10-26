import SwiftUI

struct KeyboardShortcutsSettingsView: View {
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.sectionSpacing) {
            Text(language == .russian
                ? "Сочетания медиатеки работают в главном окне. При вводе текста сохраняются обычные команды редактирования macOS. ⌘A и Ctrl+A выделяют фильмы, видимые с учётом поиска."
                : "Library shortcuts work in the main window. Standard macOS editing commands apply while typing. ⌘A and Ctrl+A select the items visible in the current search.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            ForEach(AppKeyboardShortcut.Group.allCases, id: \.self) { group in
                ServerSettingsGroup(title: group.title(language: language)) {
                    let shortcuts = AppKeyboardShortcut.allCases.filter { $0.group == group }
                    ForEach(shortcuts) { shortcut in
                        if shortcut != shortcuts.first { Divider() }
                        HStack(spacing: 12) {
                            Text(shortcut.title(language: language))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            HStack(spacing: 5) {
                                ForEach(shortcut.displayKeys, id: \.self) { keys in
                                    Text(keys)
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
                                }
                            }
                            .fixedSize()
                        }
                        .frame(minHeight: 42)
                        .searchableSetting(shortcut.title(language: language))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Text(language == .russian
                ? "⌘ Command   ⌥ Option   ⌃ Control   ⇧ Shift\nРаздел поиска доступен, когда он включён в настройках. Удаление всегда требует подтверждения."
                : "⌘ Command   ⌥ Option   ⌃ Control   ⇧ Shift\nThe Search page is available when enabled in Settings. Removing items always requires confirmation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }
}
