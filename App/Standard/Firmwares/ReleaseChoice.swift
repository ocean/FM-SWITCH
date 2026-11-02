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
                    label("Stable", version: entry.beta ? other.version : entry.version, test: false).tag(false)
                    label("Test", version: entry.beta ? entry.version : other.version, test: true).tag(true)
                }
                .pickerStyle(.segmented)
                Text("A test release has the newest changes, and may still have problems.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    /// The release's name, with a tick when it's saved here.
    private func label(_ track: String, version: String?, test: Bool) -> some View {
        let isSaved = model.library.isSaved(test: test, of: entry)
        let name = "\(track) \(version ?? "")"
        return Text(isSaved ? "\(name) ✓" : name)
            .accessibilityLabel(isSaved ? "\(name), saved" : name)
    }
}
