import XCTest
@testable import TorrServerManager

final class TorrServerVersionTests: XCTestCase {
    func testParsesVersionFromExecutableOutput() {
        let version = TorrServerVersion("TorrServer MatriX.143")

        XCTAssertEqual(version?.displayName, "MatriX.143")
    }

    func testParsesVersionAfterExecutableWarning() {
        let output = """
        2026/08/22 05:15:17 ffprobe and avprobe not found in $PATH
        TorrServer MatriX.138
        """

        XCTAssertEqual(TorrServerVersion(output)?.displayName, "MatriX.138")
    }

    func testComparesVersionComponentsNumerically() throws {
        let current = try XCTUnwrap(TorrServerVersion("MatriX.142.2"))
        let update = try XCTUnwrap(TorrServerVersion("MatriX.143"))

        XCTAssertLessThan(current, update)
    }

    func testMissingComponentsAreTreatedAsZero() throws {
        let shortVersion = try XCTUnwrap(TorrServerVersion("MatriX.142"))
        let paddedVersion = try XCTUnwrap(TorrServerVersion("MatriX.142.0"))

        XCTAssertEqual(shortVersion, paddedVersion)
    }
}
