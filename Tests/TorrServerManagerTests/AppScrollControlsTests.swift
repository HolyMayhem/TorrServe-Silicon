import AppKit
import XCTest
@testable import TorrServerManager

@MainActor
final class AppScrollControlsTests: XCTestCase {
    func testHiddenVerticalScrollerDoesNotReserveTrailingGutter() {
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 300, height: 300)
        )
        scrollView.documentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 300, height: 600)
        )
        scrollView.scrollerStyle = .legacy
        scrollView.hasVerticalScroller = true
        scrollView.tile()

        XCTAssertLessThan(scrollView.contentSize.width, scrollView.bounds.width)

        AppNativeScrollIndicatorHider
            .removeReservedVerticalScrollerSpace(from: scrollView)

        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertNil(scrollView.verticalScroller)
        XCTAssertEqual(
            scrollView.contentSize.width,
            scrollView.bounds.width,
            accuracy: 0.5
        )
    }
}
