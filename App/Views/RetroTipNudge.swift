import SwiftUI

/// Retro's tip card, at the bottom of the screen after the fifth and fifteenth installs.
struct RetroTipNudge: View {
    @Environment(AppModel.self) private var model
    let nudge: TipNudge

    var body: some View {
        PixelPanel(title: "TIP JAR") {
            HStack(alignment: .top, spacing: 12) {
                MonoText(nudge.title.uppercased(), size: 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("✕") { model.dismissTipNudge() }
                    .buttonStyle(.pixelCompact)
                    .accessibilityLabel("Not now")
            }
            RetroTipJar(tipJar: model.tipJar, message: nudge.message)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: 520)
        .task(id: model.tipJar.status == .thanked) {
            // The thanks stays up a moment, then the card goes for good.
            guard model.tipJar.status == .thanked else { return }
            try? await Task.sleep(for: .seconds(2.5))
            model.dismissTipNudge()
        }
    }
}
