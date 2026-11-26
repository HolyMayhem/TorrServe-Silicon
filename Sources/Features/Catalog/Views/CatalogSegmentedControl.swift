import AppKit
import SwiftUI

struct CatalogSegmentedControl<Value: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: options.map { $0.label },
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectSegment(_:))
        )
        control.controlSize = .large
        control.segmentDistribution = .fillEqually
        if #available(macOS 27.0, *) {
            control.borderShape = .capsule
            control.role = .tabs
        } else if #available(macOS 26.0, *) {
            control.borderShape = .capsule
            control.selectedSegmentBezelColor = NSColor.secondaryLabelColor.withAlphaComponent(0.26)
        }
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.setAccessibilityLabel(title)
        control.isEnabled = isEnabled
        for (index, option) in options.enumerated() where control.label(forSegment: index) != option.label {
            control.setLabel(option.label, forSegment: index)
        }
        if let index = options.firstIndex(where: { $0.value == selection }),
           control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: CatalogSegmentedControl

        init(parent: CatalogSegmentedControl) { self.parent = parent }

        @objc func selectSegment(_ sender: NSSegmentedControl) {
            guard parent.options.indices.contains(sender.selectedSegment) else { return }
            parent.selection = parent.options[sender.selectedSegment].value
        }
    }
}
