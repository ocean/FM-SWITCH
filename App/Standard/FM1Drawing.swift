import SwiftUI

/// The FM-1, drawn: the app's character.
///
/// Its screen says what's happening, and it lights the key to hold when a step needs one.
///
/// It follows the real panel, simplified so its buttons' labels are big enough to read: plain
/// knobs, the octave buttons, the screen, the twelve page buttons and the keys, closer together
/// than on the real panel. It's laid out at 372 × 200 points, about the real panel's
/// proportions, and scaled to fill the width it's given, so it matches the cards under it.
struct FM1Drawing: View {
    /// The FM-1's keys that can be lit.
    enum Key: String {
        case play = "PLAY"
        case rec = "REC"
        case octaveDown = "OCT−"
    }

    var line1: String
    var line2 = ""
    var litKey: Key?
    /// Progress shown under the screen's text, from 0 to 1, or nil for none.
    var progress: Double?
    var screenTint = Color(rgb: 0x9BE7B4)
    /// Called when the screen is tapped.
    var onScreenTap: (() -> Void)?

    private static let size = CGSize(width: 372, height: 200)

    private static let pageKeys = [
        "FX", "SEL", "ENV", "LFO", "EDIT", "GLO", "HOME", "SAVE", "ARP", "SEQ", "PLAY", "REC",
    ]

    #if DEBUG
        /// The lit key, or with `-drawingLitKey PLAY`, that one, for screenshots.
        private var shownLitKey: Key? {
            litKey ?? UserDefaults.standard.string(forKey: "drawingLitKey").flatMap(Key.init(rawValue:))
        }
    #else
        private var shownLitKey: Key? { litKey }
    #endif

    var body: some View {
        let size = Self.size
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    panel
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(geometry.size.width / size.width, anchor: .topLeading)
                }
            }
            // Its labels are part of the picture, so it's one image to VoiceOver, described by
            // what its screen says and which key is lit.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isImage)
            // For the accessibility audit, which skips illustrations.
            .accessibilityIdentifier("decorative")
    }

    private var accessibilityText: String {
        var parts = ["FM-1"]
        let screen = [line1, line2].filter { !$0.isEmpty }.joined(separator: " ")
        if !screen.isEmpty { parts.append("its screen says \(screen)") }
        if let litKey = shownLitKey { parts.append("with its \(litKey.rawValue) key lit") }
        return parts.joined(separator: ", ")
    }

    private var panel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                VStack(spacing: 10) {
                    Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                        GridRow {
                            Knob(size: 18)
                            Knob(size: 18)
                        }
                        GridRow {
                            Knob(size: 18)
                            Knob(size: 18)
                        }
                    }
                    octaveKeys(height: 22, labelSize: 9)
                }
                .frame(width: 58)
                screen(width: 98, titleSize: 13)
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in
                            Knob(size: 18)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    pageButtons(height: 24, labelSize: 9.5)
                }
            }
            .frame(height: 112)
            keyboard
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(rgb: 0x4A4E52))
                .shadow(color: .black.opacity(0.22), radius: 12, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    // MARK: - Parts.

    private func screen(width: CGFloat?, titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(line1)
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .contentTransition(.opacity)
            if !line2.isEmpty {
                Text(line2)
                    .font(.system(size: titleSize - 1.5, design: .rounded))
                    .opacity(0.8)
                    .contentTransition(.opacity)
            }
            if let progress {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(screenTint)
                                .frame(width: geometry.size.width * min(max(progress, 0), 1))
                        }
                    }
            }
        }
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .foregroundStyle(screenTint)
        .padding(.horizontal, 10)
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(rgb: 0x12171A)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(rgb: 0x2B2F33), lineWidth: 3)
        )
        .animation(Motion.fade, value: line1)
        .animation(Motion.fade, value: line2)
        .contentShape(Rectangle())
        .onTapGesture { onScreenTap?() }
        // The drawing is hidden from VoiceOver, so this only satisfies the lint; the easter egg
        // isn't announced.
        .accessibilityAddTraits(.isButton)
    }

    private func octaveKeys(height: CGFloat, labelSize: CGFloat) -> some View {
        HStack(spacing: 3) {
            PanelKey(name: "OCT−", isLit: shownLitKey == .octaveDown, height: height, labelSize: labelSize)
            PanelKey(name: "OCT+", isLit: false, height: height, labelSize: labelSize)
        }
    }

    /// The twelve page buttons, in two rows of six.
    private func pageButtons(height: CGFloat, labelSize: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 6), spacing: 4) {
            ForEach(Self.pageKeys, id: \.self) { name in
                PanelKey(name: name, isLit: shownLitKey?.rawValue == name, height: height, labelSize: labelSize)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(rgb: 0x26292C)))
    }

    private var keyboard: some View {
        HStack(spacing: 4) {
            ForEach(0..<16, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(rgb: 0x33363A))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(rgb: 0x26292C)))
    }
}

/// A plain knob: just enough to say "knob".
private struct Knob: View {
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(rgb: 0x6E7276))
            .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .frame(width: size, height: size)
    }
}

/// One of the panel's buttons, its label lit as on the stock firmware.
///
/// Labels are dim white, with HOME bright white, PLAY green and REC red. The key to hold glows white.
private struct PanelKey: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @State private var isBright = false
    var name: String
    var isLit: Bool
    var height: CGFloat
    var labelSize: CGFloat

    /// The label's colour, each at least 4.5:1 on the key.
    private var labelColour: Color {
        switch name {
        case "PLAY": Color(rgb: 0x8FE36B)
        case "REC": Color(rgb: 0xFF7A6E)
        case "HOME": .white
        default: isLit ? .white : Color(rgb: 0xC8CBCE)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(rgb: isLit ? 0x4A4E53 : 0x33363A))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white.opacity(isLit ? 0.9 : 0), lineWidth: 1.5)
            }
            .frame(height: height)
            .overlay {
                Text(name)
                    .font(.system(size: labelSize, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 1)
                    .foregroundStyle(labelColour)
            }
            .shadow(color: isLit ? .white.opacity(isBright ? 0.8 : 0.4) : .clear, radius: isBright ? 9 : 5)
            .animation(Motion.standard, value: isLit)
            .onChange(of: isLit, initial: true) { _, lit in pulse(lit) }
            .onChange(of: reducesMotion) { _, _ in pulse(isLit) }
    }

    /// A gentle glow about once a second while lit; steady under Reduce Motion.
    private func pulse(_ lit: Bool) {
        guard lit, !reducesMotion else {
            withAnimation(Motion.fade) { isBright = lit }
            return
        }
        withAnimation(Motion.pulse) { isBright = true }
    }
}
