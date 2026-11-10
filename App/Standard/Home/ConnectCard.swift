import FM1Kit
import SwiftUI

/// How to connect the FM-1, and when it still isn't found, what might be wrong.
///
/// Testers can't be asked questions, so the card answers them: a screenshot sent as feedback shows
/// every MIDI port, whether FM-SWITCH talked to it, when it last looked, and the app's version.
struct ConnectCard: View {
    @Environment(AppModel.self) private var model
    /// The port the person asked to try, until they say they're sure.
    @State private var trying: MIDIPortDescriptor?

    var body: some View {
        let device = model.device
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
            Divider().overlay(Palette.line).padding(.vertical, 4)
            Text("Still not found?").font(.subheadline.weight(.semibold))
            Text(
                """
                If the FM-1's screen shows BAD CONFIG or a bootloader, no firmware is running, so \
                there's nothing for FM-SWITCH to talk to. Some USB cables only charge: try another.
                """
            )
            .font(.subheadline)
            .foregroundStyle(Palette.secondaryInk)
            ports(device.ports)
            footer(lastScan: device.lastScan)
        }
        .foregroundStyle(Palette.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .confirmingTryPort($trying)
    }

    @ViewBuilder private func ports(_ ports: [MIDIPortDescriptor]) -> some View {
        Text("MIDI devices this \(ThisDevice.name) can see").font(.subheadline.weight(.semibold))
            .padding(.top, 4)
        if ports.isEmpty {
            Text("None. A cable that only charges, or an FM-1 with no firmware running, shows nothing here.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
        }
        ForEach(ports) { port in
            portRow(port)
        }
        if ports.contains(where: { !FM1Updater.isProbeable($0) }) {
            Text(
                """
                FM-SWITCH only talks to devices named like an FM-1, so it never sends anything to \
                other gear. If your FM-1's firmware names it differently, try it.
                """
            )
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        }
    }

    private func portRow(_ port: MIDIPortDescriptor) -> some View {
        let device = model.device
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(port.name).font(.subheadline)
                if device.asks(port) {
                    let label = device.isTried(port) ? "Asked, as you chose" : "Asked"
                    Tag(text: label, ink: Palette.ink, fill: Palette.control)
                } else {
                    Tag(text: "Left alone", ink: Palette.warningInk, fill: Palette.warningBackground)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if device.isTried(port) {
                Button("Stop Trying") { Task { await device.stopTrying(port) } }
                    .buttonStyle(.secondary)
            } else if !device.asks(port) {
                Button("Try This Port") { trying = port }
                    // For UI tests, as the dialog it opens has a button of the same name.
                    .accessibilityIdentifier("tryPort")
                    .buttonStyle(.secondary)
            }
        }
        .disabled(device.isWriting)
    }

    private func footer(lastScan: Date?) -> some View {
        let looked = lastScan.map { "Last looked at \($0.formatted(date: .omitted, time: .standard)). " } ?? ""
        return Text("\(looked)FM-SWITCH \(AppVersion.text).")
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            .padding(.top, 4)
    }
}
