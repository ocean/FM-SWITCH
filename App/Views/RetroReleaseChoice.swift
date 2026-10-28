import SwiftUI

/// The stable release or the test one, for a firmware that has both, in the Retro look.
struct RetroReleaseChoice: View {
    @Environment(AppModel.self) private var model
    var entry: CatalogueEntry

    var body: some View {
        if let other = entry.otherRelease {
            PixelPanel(title: "RELEASE") {
                button(test: false, version: entry.beta ? other.version : entry.version)
                button(test: true, version: entry.beta ? entry.version : other.version)
                NoteText("A test release has the newest changes, and may still have problems.")
            }
        }
    }

    private func button(test: Bool, version: String?) -> some View {
        let isChosen = entry.beta == test
        return Button {
            model.catalogue.choose(test: test, for: entry.id)
        } label: {
            HStack {
                Text(isChosen ? "◆" : "◇")
                Text("\(test ? "TEST" : "STABLE") \(version?.uppercased() ?? "")")
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(isChosen ? .pixelProminent : .pixel)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
