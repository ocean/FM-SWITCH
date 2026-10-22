import SwiftUI

/// The firmware's screenshots, found in its project's README, as a strip of pixel-framed
/// pictures. Nothing here is written down in the app: the pictures are whatever the project
/// lists today.
struct ScreenshotGallery: View {
    @Environment(AppModel.self) private var model
    @Environment(\.phosphor) private var theme
    let entry: CatalogueEntry

    var body: some View {
        PixelPanel(title: "SCREENSHOTS") {
            Group {
                if let found = model.catalogue.screenshots[entry.id], !found.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(found, id: \.absoluteString) { url in
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                    case .failure:
                                        frame(content: NoteText("Couldn't load"))
                                    default:
                                        frame(content: NoteText("…"))
                                    }
                                }
                                .frame(maxHeight: 200)
                                .overlay(PixelBox().strokeBorder(theme.faint, lineWidth: 2))
                            }
                        }
                        .padding(2)
                    }
                } else if model.catalogue.screenshots[entry.id] == nil {
                    NoteText("Looking for screenshots in the project's README…")
                } else {
                    NoteText("No pictures in the project's README, or none could be fetched.")
                    #if DEBUG
                        if let trace = model.catalogue.screenshotTraces[entry.id] {
                            MonoText(trace, size: 11)
                        }
                    #endif
                }
            }
            .task { await model.catalogue.fetchScreenshots(of: entry.id) }
            .accessibilityLabel("Pictures of \(entry.name)")
        }
    }

    private func frame(content: some View) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.surface)
            .frame(width: 200, height: 120)
    }
}
