import SwiftUI
import UniformTypeIdentifiers

struct MenuBarSectionOrderView: View {
    let sections: [MenuBarPopoverSection]
    let preferences: MenuBarPreferences
    let language: AppLanguage
    let onChange: ([MenuBarPopoverSection]) -> Void

    @State private var draggedSection: MenuBarPopoverSection?

    var body: some View {
        HStack(spacing: 7) {
            ForEach(sections) { section in
                HStack(spacing: 6) {
                    Image(systemName: section.systemImage)
                    Text(section.title(language: language))
                        .lineLimit(1)
                    Image(systemName: "line.3.horizontal")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(preferences.isVisible(section) ? .primary : .tertiary)
                .padding(.horizontal, 10)
                .frame(height: 29)
                .background(
                    Color.primary.opacity(preferences.isVisible(section) ? 0.08 : 0.035),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .opacity(draggedSection == section ? 0.55 : 1)
                .onDrag {
                    draggedSection = section
                    return NSItemProvider(object: section.rawValue as NSString)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: MenuBarSectionDropDelegate(
                        target: section,
                        sections: sections,
                        draggedSection: $draggedSection,
                        onChange: onChange
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(language == .russian
            ? "Порядок элементов меню-бара"
            : "Menu bar item order")
    }
}

enum MenuBarSectionOrdering {
    static func moving(
        _ sections: [MenuBarPopoverSection],
        section: MenuBarPopoverSection,
        before target: MenuBarPopoverSection
    ) -> [MenuBarPopoverSection] {
        guard
            section != target,
            let sourceIndex = sections.firstIndex(of: section),
            let targetIndex = sections.firstIndex(of: target)
        else {
            return MenuBarPreferences.normalizedOrder(sections)
        }

        var result = sections
        result.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        result.insert(section, at: max(insertionIndex, 0))
        return MenuBarPreferences.normalizedOrder(result)
    }
}

private struct MenuBarSectionDropDelegate: DropDelegate {
    let target: MenuBarPopoverSection
    let sections: [MenuBarPopoverSection]
    @Binding var draggedSection: MenuBarPopoverSection?
    let onChange: ([MenuBarPopoverSection]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedSection, draggedSection != target else { return }
        onChange(MenuBarSectionOrdering.moving(
            sections,
            section: draggedSection,
            before: target
        ))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedSection = nil
        return true
    }
}
