import SwiftUI

/// What the up and down arrow keys step through in a firmware list, on the Mac and on iPad with a
/// keyboard, when picked firmwares show beside it.
struct ArrowKeySteps {
    /// The firmwares in the order they're listed.
    var entries: [CatalogueEntry]
    /// The firmware showing beside the list.
    var selectedID: String?
    /// Shows a firmware beside the list.
    var select: (CatalogueEntry) -> Void

    /// Picks the firmware `offset` places from the one picked, if there is one there.
    ///
    /// With none picked, down picks the first.
    func step(by offset: Int) -> Bool {
        let index = entries.firstIndex { $0.id == selectedID }
        let next = index.map { $0 + offset } ?? (offset > 0 ? 0 : entries.count - 1)
        guard entries.indices.contains(next) else { return false }
        select(entries[next])
        return true
    }
}

extension View {
    /// Lets the up and down arrow keys pick the firmware above or below the one picked.
    ///
    /// - Parameter steps: What they step through, or nothing to leave the keys alone.
    /// - Returns: The list, stepping with the arrow keys while it has the keyboard's focus.
    func steppingWithArrowKeys(_ steps: ArrowKeySteps?) -> some View {
        modifier(ArrowKeyStepping(steps: steps))
    }
}

private struct ArrowKeyStepping: ViewModifier {
    var steps: ArrowKeySteps?
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            // Focusable by clicking, as an editing view is: otherwise the Mac only gives it the
            // focus with keyboard navigation turned on.
            .focusable(steps != nil, interactions: .edit)
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                // With ⌘, they step through the sidebar instead. The Mac marks arrow keys as on the
                // number pad or function keys, so only these modifiers count.
                guard press.modifiers.isDisjoint(with: [.command, .option, .control, .shift]), let steps
                else { return .ignored }
                return steps.step(by: press.key == .upArrow ? -1 : 1) ? .handled : .ignored
            }
            // Ready for the arrows as the list opens, and after picking one with a click or a tap.
            // A moment after it appears: focus asked for straight away, as the sidebar changes to
            // the list, is lost.
            .task {
                try? await Task.sleep(for: .milliseconds(100))
                isFocused = steps != nil
            }
            .onChange(of: steps?.selectedID) { isFocused = steps != nil }
    }
}
