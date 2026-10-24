import SwiftUI

/// The standard look's motion.
///
/// Springs throughout, because a spring starts from wherever something is on screen, so a change
/// of mind mid-animation carries on smoothly instead of jumping. They're critically damped (no
/// bounce) unless a gesture with momentum came first.
enum Motion {
    /// Transitions and state changes.
    static let standard = Animation.spring(response: 0.35, dampingFraction: 1)
    /// A button or card pressed and let go: quick, so it feels part of the touch.
    static let press = Animation.spring(response: 0.2, dampingFraction: 1)
    /// Text and colour changes, and what replaces movement under Reduce Motion.
    static let fade = Animation.easeInOut(duration: 0.2)

    /// A lit key's glow, about once a second.
    ///
    /// Never slower, as slow loops can make people feel unwell. Don't use it under Reduce Motion.
    static let pulse = Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)

    /// ``standard``, or ``fade`` when the person has asked for less motion.
    static func standard(reducingMotion: Bool) -> Animation {
        reducingMotion ? fade : standard
    }
}

/// Shrinks a little the moment it's touched, and springs back when let go.
///
/// It answers straight away, so the press feels direct. Under Reduce Motion it dims instead.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PressEffect(isPressed: configuration.isPressed))
    }
}

/// The main button on a screen: filled, full width, white text.
struct ProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var colour = Palette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .foregroundStyle(isEnabled ? Color.white : Palette.secondaryInk)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isEnabled ? colour : Palette.control)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .modifier(PressEffect(isPressed: configuration.isPressed))
    }
}

/// A second choice beside the main button: the same shape, quieter.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .foregroundStyle(Palette.ink)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.control))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .modifier(PressEffect(isPressed: configuration.isPressed))
    }
}

/// A disclosure group whose whole header opens and closes it, not just its arrow.
///
/// On the Mac, the system's only answers a click on its small triangle. Here the header is one
/// button, padded by `padding` so a card made of it answers a tap anywhere while it's closed.
struct WholeHeaderDisclosureStyle: DisclosureGroupStyle {
    var padding: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureHeader(configuration: configuration, padding: padding)
            if configuration.isExpanded {
                configuration.content
                    .padding([.horizontal, .bottom], padding)
            }
        }
    }
}

/// The header of ``WholeHeaderDisclosureStyle``: the label, then an arrow that turns down when open.
private struct DisclosureHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    var configuration: DisclosureGroupStyleConfiguration
    var padding: CGFloat

    var body: some View {
        Button {
            withAnimation(Motion.standard(reducingMotion: reducesMotion)) { configuration.isExpanded.toggle() }
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            // In the tint, as the system's header is.
            .foregroundStyle(.tint)
            .padding(padding)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isExpanded ? "Open" : "Closed")
        .accessibilityHint(configuration.isExpanded ? "Hides the details" : "Shows the details")
    }
}

extension DisclosureGroupStyle where Self == WholeHeaderDisclosureStyle {
    /// Opens and closes from anywhere on its header.
    static var wholeHeader: WholeHeaderDisclosureStyle { WholeHeaderDisclosureStyle() }

    /// Opens and closes from anywhere on its header, with `padding` inside it, for a card.
    static func wholeHeader(padding: CGFloat) -> WholeHeaderDisclosureStyle {
        WholeHeaderDisclosureStyle(padding: padding)
    }
}

/// The press feedback the button styles share.
private struct PressEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    var isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reducesMotion ? 0.97 : 1)
            .opacity(isPressed ? 0.85 : 1)
            .animation(Motion.press, value: isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// Cards and rows that act as buttons.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension ButtonStyle where Self == ProminentButtonStyle {
    static var prominent: ProminentButtonStyle { ProminentButtonStyle() }

    static func prominent(_ colour: Color) -> ProminentButtonStyle { ProminentButtonStyle(colour: colour) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension View {
    /// A white (or dark grey) card on the ground.
    func cardBackground(cornerRadius: CGFloat = 16) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Palette.card))
    }
}
