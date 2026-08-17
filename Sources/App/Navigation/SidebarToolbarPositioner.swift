import AppKit
import SwiftUI

struct SidebarToolbarPositioner: NSViewRepresentable {
    let horizontalOffset: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        schedulePositionUpdate(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        schedulePositionUpdate(from: view)
    }

    private func schedulePositionUpdate(from view: NSView) {
        DispatchQueue.main.async {
            applyPosition(from: view)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            applyPosition(from: view)
        }
    }

    private func applyPosition(from view: NSView) {
        guard let window = view.window,
              let toolbarItem = window.toolbar?.items.first(where: {
                  $0.itemIdentifier == .toggleSidebar
              }),
              let toolbarView = toolbarItem.view else {
            return
        }

        toolbarView.wantsLayer = true
        toolbarView.layer?.setAffineTransform(
            CGAffineTransform(translationX: horizontalOffset, y: 0)
        )
    }
}
