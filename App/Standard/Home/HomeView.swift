import FM1Kit
import SwiftUI

/// "My FM-1": the FM-1 itself, what it's running, and the ways into the firmware list and Save my
/// FM-1.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var screenTaps: [Date] = []
    @State private var finishing: StoredFirmware?
    @State private var restoresVoices = false
    @State private var showsRetroNote = false
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    var openFirmwares: () -> Void
    var openSave: () -> Void
    var openSettings: () -> Void

    private var device: DeviceController { model.device }
    private var summary: DeviceSummary { DeviceSummary(model: model) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    FM1Drawing(
                        line1: summary.screenTitle,
                        line2: summary.screenLine,
                        onScreenTap: tapScreen
                    )
                    StatusPill(summary: summary)
                }
                .padding(.top, 8)
                firmwaresCard
                if model.offersSaveMyFM1 { saveCard }
                if case .waiting(let loader) = summary.state { finishCard(loader) }
                if device.identity == .officialV15 { factorySoundsCard }
                if summary.state == .notConnected { connectCard }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.ground)
        .navigationTitle("My FM-1")
        .refreshable { await device.scan() }
        // Plug and unplug events can be missed, so it checks again each time it's shown.
        .task { await device.scan() }
        .sheet(item: $finishing) { item in
            BeforeYouStartView(target: item).environment(model)
        }
        .sheet(isPresented: $restoresVoices) {
            FactoryVoicesView().environment(model)
        }
        .overlay(alignment: .bottom) {
            if showsRetroNote {
                RetroFoundNote(
                    open: {
                        hideRetroNote()
                        openSettings()
                    },
                    switchNow: {
                        hideRetroNote()
                        withAnimation(Motion.fade) { model.settings.look = .retro }
                    },
                    later: hideRetroNote
                )
                .padding(16)
                .transition(reducesMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: screenTaps.count) { _, count in count >= 3 }
        .sensoryFeedback(.success, trigger: showsRetroNote) { _, shows in shows }
    }

    private var firmwaresCard: some View {
        Button(action: openFirmwares) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.left.arrow.right")
                    .accessibilityHidden(true)
                    .font(.title2.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Change firmware").font(.title3.weight(.bold))
                    Text(firmwaresLine).font(.subheadline).opacity(0.9)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.headline).opacity(0.8).accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.firmwares)
                    .shadow(color: Palette.firmwares.opacity(0.28), radius: 12, y: 6)
            )
        }
        .buttonStyle(.pressable)
    }

    private var firmwaresLine: String {
        let count = FirmwareFilter().visible(in: model).count
        guard count > 0 else { return "Synths, grooveboxes and games, or the official one." }
        return "\(count) firmwares to try: synths, grooveboxes and games, or the official one."
    }

    private func finishCard(_ loader: FM1Identity) -> some View {
        let finishers = model.library.packages(thatCanFinish: loader)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Your FM-1 is waiting to finish an install", systemImage: "arrow.clockwise")
                .font(.headline)
            if let first = finishers.first {
                Text("Carry on with \(first.name), and it picks up where it stopped.")
                    .foregroundStyle(Palette.secondaryInk)
                Button("Finish installing \(first.name)") { finishing = first }
                    .buttonStyle(.prominent)
            } else {
                Text("Install the firmware you were installing again, from the firmware list.")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var saveCard: some View {
        Button(action: openSave) {
            TaskRow(
                title: "Save my FM-1",
                detail: device.identity?.isOpenFirmware == true
                    ? "Keep a copy of your projects and samples on this \(ThisDevice.name)."
                    : "Keep a copy of your projects and samples, on M-VAVE's open firmware.",
                systemImage: "square.and.arrow.down",
                tint: Palette.save)
        }
        .buttonStyle(.pressable)
    }

    private var factorySoundsCard: some View {
        Button {
            restoresVoices = true
        } label: {
            TaskRow(
                title: "Factory sounds",
                detail: "Put back the official firmware's 128 sounds, if some are wrong or silent.",
                systemImage: "music.note.list",
                tint: Palette.save)
        }
        .buttonStyle(.pressable)
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect your FM-1").font(.headline)
            Text("1. Switch it on.")
            Text("2. Plug it into this \(ThisDevice.name) with a USB data cable.")
            Text("3. Close any other music app that's using it.")
            if let error = device.transportError {
                Text(error).font(.footnote).foregroundStyle(Palette.warningInk)
                Button("Try again") { model.retryConnectionIfUnavailable() }
                    .buttonStyle(.secondary)
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    /// Five quick taps on the drawing's screen find the Retro look, which goes into Settings, and
    /// say so in a note offering to switch to it.
    private func tapScreen() {
        let now = Date.now
        screenTaps = screenTaps.filter { now.timeIntervalSince($0) < 2 } + [now]
        guard screenTaps.count >= 5 else { return }
        screenTaps = []
        model.settings.isRetroFound = true
        withAnimation(Motion.standard(reducingMotion: reducesMotion)) { showsRetroNote = true }
    }

    private func hideRetroNote() {
        withAnimation(Motion.standard(reducingMotion: reducesMotion)) { showsRetroNote = false }
    }
}

/// "You found Retro!": tapping it opens Settings, where Retro now is, or it can switch straight
/// away, or wait.
private struct RetroFoundNote: View {
    var open: () -> Void
    var switchNow: () -> Void
    var later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .accessibilityHidden(true)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Palette.firmwaresTint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("You found Retro!").font(.headline)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    // As tall as the words need, so neither line is cut short.
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Opens Settings")
            .accessibilityIdentifier("retroNote")
            HStack(spacing: 10) {
                Button("Later", action: later).buttonStyle(.secondary)
                Button("Switch now", action: switchNow).buttonStyle(.prominent(Palette.firmwares))
            }
        }
        .padding(16)
        .frame(maxWidth: 520)
        // The shadow is on the card's shape alone: on the whole note, it would blur its text too.
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.card)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        )
    }

    private var detail: String {
        AlternateIcon.isAvailable
            ? "An 8-bit look for the app, with a pixel app icon to match. It's in Settings now."
            : "An 8-bit look for the app. It's in Settings now."
    }
}

/// A row on Home that leads somewhere: an icon, a title and a line about it.
struct TaskRow: View {
    var title: String
    var detail: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(detail).font(.subheadline).foregroundStyle(Palette.secondaryInk)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .accessibilityHidden(true)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.secondaryInk)
        }
        .padding(16)
        .cardBackground()
    }
}

/// The line under the drawing: connected or not, and what it's running.
private struct StatusPill: View {
    var summary: DeviceSummary

    var body: some View {
        let isGood = summary.state != .notConnected
        HStack(spacing: 8) {
            Circle()
                .fill(isGood ? Palette.good : Palette.secondaryInk)
                .frame(width: 8, height: 8)
            Text(summary.statusLine)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isGood ? Palette.goodInk : Palette.secondaryInk)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(isGood ? Palette.goodBackground : Palette.control))
        .animation(Motion.fade, value: summary.statusLine)
    }
}
