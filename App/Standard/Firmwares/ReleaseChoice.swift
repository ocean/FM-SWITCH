import SwiftUI

/// The stable release or the test one, for a firmware that has both.
struct ReleaseChoice: View {
    @Environment(AppModel.self) private var model
    var entry: CatalogueEntry

    var body: some View {
        if let other = entry.otherRelease {
            VStack(alignment: .leading, spacing: 8) {
                Text("Two releases to choose from")
                    .font(.headline)
                Picker(
                    "Release",
                    selection: Binding(
                        get: { entry.beta },
                        set: { model.catalogue.choose(test: $0, for: entry.id) }
                    )
                ) {
                    Text("Stable \((entry.beta ? other.version : entry.version) ?? "")").tag(false)
                    Text("Test \((entry.beta ? entry.version : other.version) ?? "")").tag(true)
                }
                .pickerStyle(.segmented)
                Text("A test release has the newest changes, and may still have problems.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}
