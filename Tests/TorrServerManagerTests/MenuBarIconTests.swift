import AppKit
import XCTest
@testable import TorrServerManager

final class MenuBarIconTests: XCTestCase {
    func testIconIsMonochromeTemplateAndRendersAtRetinaScale() throws {
        let image = MenuBarIcon.makeImage()
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)

        let scale = 8
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 18 * scale,
            pixelsHigh: 18 * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return XCTFail("Could not create the icon bitmap.")
        }
        bitmap.size = image.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        XCTAssertNotNil(bitmap.bitmapData)
        if let path = ProcessInfo.processInfo.environment["MENU_BAR_ICON_PREVIEW_PATH"] {
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: path))
        }
    }
}
