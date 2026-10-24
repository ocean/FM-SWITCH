import SwiftUI

/// The pictures in a firmware's README, in a strip that scrolls sideways.
///
/// Tapping one opens it larger.
struct FirmwarePictures: View {
    @Environment(\.openURL) private var openURL
    var pictures: [URL]
    var name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(pictures.enumerated()), id: \.element) { index, url in
                        Button {
                            openURL(url)
                        } label: {
                            picture(url)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Picture \(index + 1) of \(pictures.count) of \(name)")
                        .accessibilityHint("Opens it larger.")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            Text("From the project's README.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .padding(.horizontal, 20)
        }
    }

    private func picture(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                // Loading, or it couldn't be loaded.
                Palette.control
                    .frame(width: 150)
                    .overlay {
                        if phase.error == nil { ProgressView() }
                    }
            }
        }
        .frame(height: 200)
        .frame(maxWidth: 340)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line))
    }
}
