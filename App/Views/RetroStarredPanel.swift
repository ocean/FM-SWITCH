import SwiftUI

/// SAVED's starred firmwares that aren't saved, each opening its page.
struct RetroStarredPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.phosphor) private var theme
    @Environment(\.isWideLayout) private var isWide
    var starred: [CatalogueEntry]
    /// The starred firmware showing beside the list, or opened on a page of its own.
    @Binding var openedStar: CatalogueEntry?

    var body: some View {
        PixelPanel(title: "STARRED") {
            if starred.isEmpty {
                MonoText("Nothing starred. Star a firmware in the FIRMWARE list to keep it here.", size: 14, dim: true)
            }
            ForEach(starred) { entry in
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        openedStar = entry
                    } label: {
                        title(entry)
                            // As wide as the row allows, so a click anywhere beside the button opens it.
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(openedStar?.id == entry.id ? .isSelected : [])
                    Button("★") { model.starred.toggle(entry.id) }
                        .buttonStyle(.pixelCompact)
                        .accessibilityLabel("Remove star from \(entry.name)")
                }
                .rowBox(isPicked: isWide && openedStar?.id == entry.id, theme: theme)
            }
        }
    }

    private func title(_ entry: CatalogueEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name.uppercased())
                .font(.pixel(12, bold: true, relativeTo: .headline))
                .foregroundStyle(theme.bright)
                .phosphorGlow(0.7)
            MonoText([entry.version, entry.author].compactMap(\.self).joined(separator: " · "), size: 14, dim: true)
        }
    }
}
