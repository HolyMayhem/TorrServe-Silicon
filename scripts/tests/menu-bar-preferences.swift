import Foundation

@main
struct MenuBarPreferenceChecks {
    static func main() {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError(message) }
        }
        let suite = "TorrServeMenuBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MenuBarPreferencesStore(defaults: defaults)
        let fresh = store.load()
        expect(fresh == .defaults, "Fresh preferences use defaults")
        expect(MenuBarExtraOption.allCases.allSatisfy { !fresh[keyPath: $0.keyPath] }, "Every extra is opt-in")
        expect(fresh.sectionOrder.filter { fresh.isVisible($0) } == [.recentMaterial, .speed, .quickActions, .qrCode],
               "The existing menu is unchanged until extras are enabled")

        let legacy = ["qrCode", "speed", "future-unknown", "quickActions", "recentMaterial", "speed"]
        defaults.set(legacy, forKey: MenuBarPreferencesStore.Key.sectionOrder)
        defaults.set(false, forKey: MenuBarPreferencesStore.Key.recentMaterial)
        let migrated = store.load()
        expect(Array(migrated.sectionOrder.prefix(4)) == [.qrCode, .speed, .quickActions, .recentMaterial],
               "Keep the user's old order, ignoring unknown and duplicate items")
        expect(!migrated.showsRecentMaterial, "Existing visibility survives migration")
        expect(Set(migrated.sectionOrder) == Set(MenuBarPopoverSection.allCases), "New movable blocks are appended once")
        for option in MenuBarExtraOption.allCases {
            var enabled = migrated
            enabled[keyPath: option.keyPath] = true
            store.save(enabled)
            expect(store.load() == enabled, "Persist independent option: \(option.rawValue)")
            expect(MenuBarExtraOption.allCases.filter { store.load()[keyPath: $0.keyPath] } == [option],
                   "Enabling \(option.rawValue) does not enable other extras")
        }
        var all = fresh
        for option in MenuBarExtraOption.allCases { all[keyPath: option.keyPath] = true }
        all.sectionOrder.reverse()
        store.save(all)
        expect(MenuBarPreferencesStore(defaults: defaults).load() == all, "All options and custom order survive relaunch")
        var independent = fresh
        independent.showsCopyAddress = true
        expect(independent.isVisible(.serverAddress) && !independent.showsServerAddress, "Copy can appear without the address text")
        independent = fresh
        independent.showsUpdateStatus = true
        expect(independent.isVisible(.serverVersion) && !independent.showsServerVersion, "Update status works without the version text")
        let moved = MenuBarSectionOrdering.moving(all.sectionOrder, section: .settings, to: 9)
        expect(moved.last == .settings && Set(moved).count == 10, "Move a new block across the whole menu")
        let clamped = MenuBarSectionOrdering.moving(moved, section: .restart, to: -10)
        expect(clamped.first == .restart && clamped.count == 10, "Clamp order moves without losing sections")
        var reset = all
        reset.sectionOrder = MenuBarPopoverSection.allCases
        expect(MenuBarExtraOption.allCases.allSatisfy { reset[keyPath: $0.keyPath] }, "Resetting order keeps visibility choices")

        expect(MenuBarCacheSnapshot.aggregate([]) == .empty, "An empty active list has no allocated buffer")
        let aggregate = MenuBarCacheSnapshot.aggregate([(640, 2048), (256, 1024)])
        expect(aggregate == MenuBarCacheSnapshot(used: 896, capacity: 3072), "Sum both usage and capacity across active torrents")
        expect(aggregate?.fraction == Double(896) / Double(3072), "Combined progress uses the combined capacity")
        expect(MenuBarCacheSnapshot.aggregate([(-1, 20)]) == nil, "Reject negative cache usage")
        expect(MenuBarCacheSnapshot.aggregate([(21, 20)]) == nil, "Reject inconsistent cache responses")
        expect(MenuBarCacheSnapshot.aggregate([(0, -1)]) == nil, "Reject negative capacity")
        expect(MenuBarCacheSnapshot.aggregate([(0, .max), (0, 1)]) == nil, "Overflow cannot wrap cache capacity")
        expect(MenuBarCacheSnapshot.empty.fraction == 0, "Zero capacity is safe")
        print("Menu bar preferences and cache: \(checks) checks passed")
    }
}
