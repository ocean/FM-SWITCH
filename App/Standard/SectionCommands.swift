import SwiftUI

/// Steps through the sidebar's sections, for the menu commands below.
struct SectionSteps {
    /// Picks the section `offset` places from the one picked, if there is one there.
    var step: (_ offset: Int) -> Void
}

extension FocusedValues {
    /// Set while the window shows the sidebar and its sections can be changed.
    @Entry var sectionSteps: SectionSteps?
}

/// View ▸ Previous Section (⌘↑) and Next Section (⌘↓), to move through the sidebar from anywhere
/// in the window.
struct SectionCommands: Commands {
    @FocusedValue(\.sectionSteps) private var steps

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Previous Section") { steps?.step(-1) }
                .keyboardShortcut(.upArrow)
                .disabled(steps == nil)
            Button("Next Section") { steps?.step(1) }
                .keyboardShortcut(.downArrow)
                .disabled(steps == nil)
        }
    }
}
