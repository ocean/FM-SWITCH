import SwiftUI

/// The rounded square with a firmware's initials.
///
/// In dark mode, a badge with a half nearly as dark as the card it sits on gets a thin light
/// outline, so it still shows up.
struct FirmwareBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    var design: FirmwareBadgeDesign
    var size: CGFloat = 48

    private var needsOutline: Bool {
        colorScheme == .dark
            && [design.first, design.second].contains { Contrast.ratio($0, Palette.Shades.card.dark) < 1.6 }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size / 4, style: .continuous)
        // Two letters can be larger than the official badge's version, such as "V15".
        Text(design.letters)
            .font(.system(size: size * (design.letters.count <= 2 ? 0.46 : 0.36), weight: .heavy, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, size * 0.08)
            .foregroundStyle(Color(rgb: design.ink))
            .frame(width: size, height: size)
            .background(BadgeColours(design: design).clipShape(shape))
            .overlay {
                if needsOutline {
                    shape.strokeBorder(.white.opacity(0.35), lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
            // For the accessibility audit, which skips illustrations.
            .accessibilityIdentifier("decorative")
    }
}

/// A badge's two colours, split across or corner to corner, filling whatever space they're given.
struct BadgeColours: View {
    var design: FirmwareBadgeDesign

    var body: some View {
        Color(rgb: design.second)
            .overlay { Color(rgb: design.first).clipShape(FirstHalf(split: design.split)) }
    }
}

/// The top half, or the half on the top-left corner's side of the diagonal.
private struct FirstHalf: Shape {
    var split: FirmwareBadgeDesign.Split

    func path(in rect: CGRect) -> Path {
        switch split {
        case .across:
            Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2))
        case .diagonal:
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}
