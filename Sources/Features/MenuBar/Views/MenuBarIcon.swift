import AppKit

enum MenuBarIcon {
    static func makeImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            NSGraphicsContext.current?.imageInterpolation = .high

            NSColor.black.setStroke()
            let circle = NSBezierPath(
                ovalIn: bounds.insetBy(dx: 2.15, dy: 2.15)
            )
            circle.lineWidth = 1.05
            circle.stroke()

            let configuration = NSImage.SymbolConfiguration(
                pointSize: 12,
                weight: .medium
            )
            guard
                let symbol = NSImage(
                    systemSymbolName: "bolt.fill",
                    accessibilityDescription: "TorrServer"
                )?.withSymbolConfiguration(configuration)
            else {
                return true
            }

            let alignmentRect = symbol.alignmentRect.isEmpty
                ? NSRect(origin: .zero, size: symbol.size)
                : symbol.alignmentRect
            let availableSize = NSSize(width: 7.4, height: 10.8)
            let scale = min(
                availableSize.width / alignmentRect.width,
                availableSize.height / alignmentRect.height
            )
            let symbolSize = NSSize(
                width: symbol.size.width * scale,
                height: symbol.size.height * scale
            )
            let symbolRect = NSRect(
                x: bounds.midX - alignmentRect.midX * scale + 0.5,
                y: bounds.midY - alignmentRect.midY * scale,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbol.draw(
                in: symbolRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}
