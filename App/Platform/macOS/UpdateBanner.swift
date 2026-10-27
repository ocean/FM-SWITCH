import SwiftUI

/// Says a newer FM-SWITCH is out, at the top of My FM-1.
struct UpdateBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let release = model.updates.available {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .accessibilityHidden(true)
                    .font(.title)
                    .foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FM-SWITCH \(release.version) is out").font(.headline).foregroundStyle(Palette.ink)
                    Text("You have \(model.updates.current).").font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer(minLength: 0)
                Button("Not now") { withAnimation(Motion.fade) { model.updates.notNow() } }
                    .buttonStyle(.secondary)
                Button("Download") { openURL(release.page) }
                    .buttonStyle(.prominent(Palette.accent))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
            .transition(.opacity)
        }
    }
}

/// Says a newer FM-SWITCH is out, at the top of Retro's DEVICE screen.
struct RetroUpdateBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let release = model.updates.available {
            PixelPanel {
                MonoText("FM-SWITCH \(release.version) IS OUT. YOU HAVE \(model.updates.current).", size: 14)
                HStack(spacing: 10) {
                    Button("DOWNLOAD") { openURL(release.page) }
                        .buttonStyle(.pixelProminent)
                    Button("NOT NOW") { model.updates.notNow() }
                        .buttonStyle(.pixelCompact)
                }
            }
        }
    }
}
