import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError(message) }
}

let sound = SettingsSearchEntry(category: "general", group: "Уведомления", title: "Звук уведомлений")
let cache = SettingsSearchEntry(category: "server", group: "Настройки кеша", title: "Размер кеша")
let report = SettingsSearchEntry(category: "server", group: "Диагностика", title: "Сохранить отчёт", revealSection: "diagnostics")
let entries = [sound, cache, report]
func find(_ query: String) -> [SettingsSearchEntry] {
    SettingsSearchIndex.results(for: query, in: entries)
}
expect(find("").isEmpty, "Empty search must not list every setting")
expect(find(" \n\t ").isEmpty, "Whitespace-only search")
expect(find("  ЗВУК  ") == [sound], "Case and surrounding whitespace")
expect(find("уведомлений звук") == [sound], "Words can be in a different order")
expect(find("размер\n\tкеша") == [cache], "Whitespace between words")
expect(find("отчет") == [report], "ё and е must match")
expect(find("несуществующая настройка").isEmpty, "Unknown setting")
expect(find("Уведомления").isEmpty, "Match setting titles, not parent paths")
expect(SettingsSearchIndex.results(for: "звук", in: [sound, sound]) == [sound], "Deduplicate merged preferences")
let otherGroup = SettingsSearchEntry(category: "general", group: "События", title: sound.title)
let otherPage = SettingsSearchEntry(category: "server", group: sound.group, title: sound.title)
expect(SettingsSearchIndex.results(for: "звук", in: [sound, otherGroup, otherPage]).count == 3, "Same title in different locations must remain selectable")
let exact = SettingsSearchEntry(category: "server", group: "", title: "Кеш")
let prefix = SettingsSearchEntry(category: "server", group: "", title: "Кеш на диске")
let substring = SettingsSearchEntry(category: "server", group: "", title: "Опережающий кеш")
expect(SettingsSearchIndex.results(for: "кеш", in: [substring, prefix, exact]) == [exact, prefix, substring], "Exact/prefix ranking")
let groupHeading = SettingsSearchEntry(category: "menuBar", group: "", title: "Порядок элементов")
let repeatedRow = SettingsSearchEntry(category: "menuBar", group: groupHeading.title, title: groupHeading.title)
expect(SettingsSearchIndex.results(for: "порядок", in: [groupHeading, repeatedRow]) == [groupHeading], "One-row groups must not duplicate their heading")
let newSetting = SettingsSearchEntry(category: "general", group: "Новая группа", title: "Совершенно новая настройка")
expect(SettingsSearchIndex.results(for: "новая настройка", in: entries + [newSetting]) == [newSetting], "Newly registered titles need no keyword catalogue")
expect(find("сохранить").first?.revealSection == "diagnostics", "Navigation must preserve disclosure metadata")
let firstClick = SettingsSearchRequest(entry: sound)
let secondClick = SettingsSearchRequest(entry: sound)
expect(firstClick.revision != secondClick.revision, "Clicking the same result must trigger scrolling again")
let english = SettingsSearchEntry(category: "general", group: "Notifications", title: "Notification sound")
expect(SettingsSearchIndex.results(for: "SOUND notification", in: [english]) == [english], "English word matching")
print("Settings search: \(checks) checks passed")
