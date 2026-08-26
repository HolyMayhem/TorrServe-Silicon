import XCTest
@testable import TorrServerManager

final class MenuBarPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MenuBarPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testUsesExistingVisualLayoutAsDefault() {
        let preferences = MenuBarPreferencesStore(defaults: defaults).load()

        XCTAssertTrue(preferences.isIconVisible)
        XCTAssertTrue(preferences.showsSpeed)
        XCTAssertTrue(preferences.showsRecentMaterial)
        XCTAssertTrue(preferences.showsQuickActions)
        XCTAssertTrue(preferences.showsQRCode)
        XCTAssertFalse(preferences.expandsQRCodeOnOpen)
        XCTAssertEqual(preferences.sectionOrder, MenuBarPopoverSection.allCases)
    }

    func testPersistsVisibilityAndCustomOrder() {
        let store = MenuBarPreferencesStore(defaults: defaults)
        var preferences = MenuBarPreferences.defaults
        preferences.showsRecentMaterial = false
        preferences.showsQRCode = false
        preferences.expandsQRCodeOnOpen = true
        preferences.sectionOrder = [.quickActions, .qrCode, .speed, .recentMaterial]

        store.save(preferences)

        XCTAssertEqual(store.load(), preferences)
    }

    func testNormalizesMissingDuplicateAndUnknownSections() {
        defaults.set(
            ["qrCode", "unknown", "qrCode", "speed"],
            forKey: MenuBarPreferencesStore.Key.sectionOrder
        )

        XCTAssertEqual(
            MenuBarPreferencesStore(defaults: defaults).load().sectionOrder,
            [.qrCode, .speed, .recentMaterial, .quickActions]
        )
    }

    func testMovesSectionBeforeDropTarget() {
        XCTAssertEqual(
            MenuBarSectionOrdering.moving(
                MenuBarPopoverSection.allCases,
                section: .qrCode,
                before: .recentMaterial
            ),
            [.qrCode, .recentMaterial, .speed, .quickActions]
        )
        XCTAssertEqual(
            MenuBarSectionOrdering.moving(
                MenuBarPopoverSection.allCases,
                section: .recentMaterial,
                before: .qrCode
            ),
            [.speed, .quickActions, .recentMaterial, .qrCode]
        )
    }
}
