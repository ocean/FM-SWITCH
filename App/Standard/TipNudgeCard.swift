import StoreKit
import SwiftUI

/// A small card at the bottom of the screen after the fifth and fifteenth installs, with the tips
/// right on it.
struct TipNudgeCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.purchase) private var purchase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let nudge: TipNudge

    private var tipJar: TipJar { model.tipJar }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(nudge.title)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    model.dismissTipNudge()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-12)
                .accessibilityLabel("Not now")
            }
            Text(tipJar.status == .thanked ? Tips.thanks : nudge.message)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if tipJar.status != .thanked { tips }
        }
        .padding(16)
        // The shadow is the card's alone: on the whole card it would blur the text too.
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.card)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tipNudge")
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: 520)
        .task { await tipJar.load() }
        .task(id: tipJar.status == .thanked) {
            // The thanks stays up a moment, then the card goes for good.
            guard tipJar.status == .thanked else { return }
            try? await Task.sleep(for: .seconds(2.5))
            model.dismissTipNudge()
        }
        .sensoryFeedback(.success, trigger: tipJar.status == .thanked)
    }

    /// Buys with SwiftUI's purchase action, which shows the App Store's sheet in this window.
    private func buy(_ tip: Tip) async {
        await tipJar.buy(tip) { try await purchase($0) }
    }

    @ViewBuilder private var tips: some View {
        if TipJar.isInApp {
            // Side by side, unless the text is too large for three across.
            let layout =
                dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                ForEach(tipJar.tips) { tip in
                    Button {
                        Task { await buy(tip) }
                    } label: {
                        if tipJar.status == .buying(tip.id) {
                            ProgressView()
                        } else {
                            VStack(spacing: 2) {
                                Text(tip.name).font(.caption.weight(.semibold)).foregroundStyle(Palette.secondaryInk)
                                Text(tip.price)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 6)
                        }
                    }
                    .buttonStyle(.secondary)
                    .accessibilityLabel("\(tip.name), \(tip.price)")
                    .disabled(tipJar.status == .buying(tip.id))
                }
            }
        } else {
            Link("Leave a tip on Ko-fi", destination: Tips.koFi)
                .buttonStyle(.secondary)
        }
    }
}
