import SwiftUI

/// The pictures in a firmware's README, in pixel frames, in a strip that scrolls sideways.
///
/// Tapping one opens it larger.
struct RetroPictures: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.phosphor) private var theme
    var pictures: [URL]
    var name: String

    var body: some View {
        PixelPanel(title: "PICTURES") {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(pictures.enumerated()), id: \.element) { index, url in
                        Button {
                            openURL(url)
                        } label: {
                            picture(url)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Picture \(index + 1) of \(pictures.count) of \(name)")
                        .accessibilityHint("Opens it larger.")
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.hidden)
            NoteText("From the project's README.")
        }
    }

    private func picture(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                theme.surface
                    .frame(width: 150)
                    .overlay {
                        if phase.error == nil { BlinkingCursor() }
                    }
            }
        }
        .frame(height: 180)
        .frame(maxWidth: 320)
        .overlay(PixelBox().strokeBorder(theme.faint, lineWidth: 2))
    }
}
