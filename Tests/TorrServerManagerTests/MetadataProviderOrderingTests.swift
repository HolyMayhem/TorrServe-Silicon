import XCTest
@testable import TorrServerManager

final class MetadataProviderOrderingTests: XCTestCase {
    private let defaultOrder: [MetadataProvider] = [.omdb, .kinopoisk, .tmdb]

    func testMovesFirstProviderToTheEnd() {
        let result = MetadataProviderOrdering.moving(
            defaultOrder,
            provider: .omdb,
            to: 2
        )

        XCTAssertEqual(result, [.kinopoisk, .tmdb, .omdb])
    }

    func testMovesLastProviderToTheBeginning() {
        let result = MetadataProviderOrdering.moving(
            defaultOrder,
            provider: .tmdb,
            to: 0
        )

        XCTAssertEqual(result, [.tmdb, .omdb, .kinopoisk])
    }

    func testKeepsAllProvidersWhenMovedToTheMiddle() {
        let result = MetadataProviderOrdering.moving(
            defaultOrder,
            provider: .omdb,
            to: 1
        )

        XCTAssertEqual(result, [.kinopoisk, .omdb, .tmdb])
        XCTAssertEqual(Set(result), Set(MetadataProvider.allCases))
    }
}
