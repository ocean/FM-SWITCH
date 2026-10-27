import SwiftUI

/// What's known about a saved firmware that isn't in the catalogue (an import, or the official
/// firmware), shown beside the list in the wide layout.
struct SavedFirmwareDetail: View {
    @Environment(\.phosphor) private var theme
    let item: StoredFirmware
    let onFlash: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name.uppercased())
                        .font(.pixel(24, bold: true, relativeTo: .largeTitle))
                        .foregroundStyle(theme.bright)
                        .phosphorGlow()
                    if let author = item.author {
                        MonoText("by \(author)", size: 15, dim: true)
                    }
                }
                Button("FLASH") { onFlash() }
                    .buttonStyle(.pixelProminent)
                PixelPanel(title: "DETAILS") {
                    row("REPORTS", item.product)
                    row("VERSION", item.version)
                    row("SIZE", formattedBytes(item.size))
                    row("SAVED", item.savedAt.formatted(date: .abbreviated, time: .shortened))
                    row("SHA-256", String(item.sha256.prefix(16)) + "…")
                }
                if item.source == .imported {
                    NoteText("Imported from Files, and not in the catalogue, so check where it came from.")
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            MonoText(label, size: 13, dim: true)
                .frame(width: 90, alignment: .leading)
            MonoText(value, size: 15)
        }
    }
}

extension View {
    /// Boxes a row as the FIRMWARE list does, outlined brightly while it's the one showing beside
    /// the list.
    func rowBox(isPicked: Bool, theme: PhosphorTheme) -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PixelBox().fill(theme.surface))
            .overlay(PixelBox().strokeBorder(isPicked ? theme.bright : theme.faint, lineWidth: 2))
            .contentShape(Rectangle())
    }
}
