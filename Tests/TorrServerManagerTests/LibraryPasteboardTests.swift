import AppKit
import XCTest
@testable import TorrServerManager

final class LibraryPasteboardTests: XCTestCase {
    func testAcceptsMagnetLinkFromClipboardText() {
        let magnetLink = "magnet:?xt=urn:btih:0123456789ABCDEF"

        XCTAssertEqual(
            LibraryPasteboard.magnetLink(from: magnetLink),
            magnetLink
        )
    }

    func testTrimsWhitespaceAroundMagnetLink() {
        XCTAssertEqual(
            LibraryPasteboard.magnetLink(from: "  \nMAGNET:?xt=urn:btih:ABCDEF\t"),
            "MAGNET:?xt=urn:btih:ABCDEF"
        )
    }

    func testRejectsNonMagnetClipboardText() {
        XCTAssertNil(LibraryPasteboard.magnetLink(from: "https://example.com"))
        XCTAssertNil(LibraryPasteboard.magnetLink(from: nil))
    }

    func testRecognizesCommandVShortcut() {
        XCTAssertTrue(
            LibraryKeyboardShortcutMonitor.Coordinator.isPasteShortcut(
                keyCode: 9,
                modifierFlags: .command
            )
        )
    }

    func testRejectsModifiedPasteShortcutAndOtherKeys() {
        XCTAssertFalse(
            LibraryKeyboardShortcutMonitor.Coordinator.isPasteShortcut(
                keyCode: 9,
                modifierFlags: [.command, .shift]
            )
        )
        XCTAssertFalse(
            LibraryKeyboardShortcutMonitor.Coordinator.isPasteShortcut(
                keyCode: 8,
                modifierFlags: .command
            )
        )
    }
}
