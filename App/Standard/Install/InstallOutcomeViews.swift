import FM1Kit
import SwiftUI

/// The end of an install that worked.
struct InstallDoneView: View {
    @Environment(AppModel.self) private var model
    var job: DeviceController.FlashJob
    /// What the FM-1 reported once it restarted.
    var reported: String
    @State private var restoresVoices = false

    private var installed: StoredFirmware { job.steps[job.steps.count - 1] }

    var body: some View {
        Image(systemName: "checkmark")
            .font(.title.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(Circle().fill(Palette.good))
            .transition(.scale.combined(with: .opacity))
            .accessibilityHidden(true)
        VStack(spacing: 8) {
            Text("\(installed.name) is ready to play")
                .font(.title.weight(.bold))
            Text("Your FM-1 says it's running \(reported). It's safe to unplug.")
                .foregroundStyle(Palette.secondaryInk)
        }
        .multilineTextAlignment(.center)
        if reported == FM1Identity.officialV15.text {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    """
                    The official firmware can keep the old firmware's sounds in some banks, some of them wrong \
                    or silent. Putting back its 128 factory sounds fixes that.
                    """
                )
                .font(.callout)
                .foregroundStyle(Palette.ink)
                Button("Put back the factory sounds…") { restoresVoices = true }
                    .buttonStyle(.secondary)
            }
            .padding(16)
            .cardBackground()
        }
        Button("Done") { model.device.dismissFlash() }
            .buttonStyle(.prominent)
            .sheet(isPresented: $restoresVoices) {
                FactoryVoicesView().environment(model)
            }
    }
}

/// The end of an install that stopped: what happened in plain words, and one thing to do.
struct InstallProblemView: View {
    @Environment(AppModel.self) private var model
    var job: DeviceController.FlashJob
    var message: String
    /// Whether the FM-1 is waiting in its update loader, so the install can carry on.
    var canResume: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(canResume ? "The install was interrupted" : "The install stopped")
                .font(.title.weight(.bold))
            Text(
                canResume
                    ? "Your FM-1 is waiting to finish installing \(job.current.name), so nothing is lost."
                    : job.needsAStepFirst ? message : Self.tryAgain(mightBeRefused: job.mightBeRefused)
            )
            .foregroundStyle(Palette.secondaryInk)
        }
        .multilineTextAlignment(.center)
        if canResume {
            VStack(alignment: .leading, spacing: 12) {
                step(1, "Plug the FM-1 back in, if it came out.")
                step(2, "Tap Carry on. It picks up where it stopped.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
        if job.needsAStepFirst {
            // Trying again would only be refused again.
            if let wayRound {
                Button("Install \(wayRound.name)") { open(wayRound) }
                    .buttonStyle(.prominent)
                Button("What can I do?") { openHelp() }
                    .buttonStyle(.secondary)
            } else {
                Button("What can I do?") { openHelp() }
                    .buttonStyle(.prominent)
            }
        } else {
            Button(canResume ? "Carry on installing" : "Try again") { model.device.resume() }
                .buttonStyle(.prominent)
        }
        if job.mightBeRefused {
            Button("What can I do?") { openHelp() }
                .buttonStyle(.secondary)
        }
        if !canResume {
            Button("Close") { model.device.dismissFlash() }
                .buttonStyle(.secondary)
        }
        details
    }

    private static func tryAgain(mightBeRefused: Bool) -> String {
        let check = "Check that your FM-1 is plugged in and switched on, then try again."
        return mightBeRefused ? check + " If it stops again, the firmware on it may not accept this one." : check
    }

    /// MIDIMON, to install first, when the list has it.
    private var wayRound: CatalogueEntry? { model.catalogue.entry(id: FeluccaUpdateCode.wayRound) }

    private func open(_ entry: CatalogueEntry) {
        model.device.dismissFlash()
        model.requestedPage = .firmware(entry.id)
    }

    private func openHelp() {
        model.device.dismissFlash()
        model.requestedPage = .help(.wontInstall)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Palette.control))
            Text(text)
        }
    }

    /// The technical message and the log, to copy when asking for help.
    private var details: some View {
        DisclosureGroup("Show the details") {
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                Text(model.device.log.joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.secondaryInk)
                Button("Copy the details") {
                    Pasteboard.copy(([message] + model.device.log).joined(separator: "\n"))
                }
                .foregroundStyle(Palette.accentText)
            }
            .font(.footnote)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
        .font(.subheadline)
        .tint(Palette.secondaryInk)
        .disclosureGroupStyle(.wholeHeader)
    }
}

/// Puts back V15's 128 factory sounds, after asking.
struct FactoryVoicesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var understands = false

    private var device: DeviceController { model.device }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                content
                Spacer()
            }
            .padding(20)
            .background(Palette.ground)
            .navigationTitle("Factory sounds")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(device.voiceRestore.isRunning)
                }
            }
        }
        .interactiveDismissDisabled(device.voiceRestore.isRunning)
        .onDisappear { device.dismissVoiceRestore() }
        .sensoryFeedback(.success, trigger: device.voiceRestore == .succeeded)
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    @ViewBuilder private var content: some View {
        switch device.voiceRestore {
        case .idle:
            question
        case .writing(let fraction):
            Text("Putting back the factory sounds…").font(.headline)
            ProgressBar(fraction: fraction)
            Text("Keep the cable connected. It takes about a second.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        case .succeeded:
            Label("Done: all four banks hold the 128 factory sounds again.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.goodInk)
        case .failed(let reason):
            Notice(reason, systemImage: "exclamationmark.triangle", isWarning: true)
            Button("Run it again") { Task { await device.restoreFactoryVoices() } }
                .buttonStyle(.prominent)
                .disabled(device.isWriting)
        }
    }

    @ViewBuilder private var question: some View {
        Text(
            """
            This replaces every sound in the FM-1's four banks with the official firmware's 128 factory \
            sounds, including any you made. They can't be saved first.
            """
        )
        if device.identity != .officialV15 {
            Notice(
                "Your FM-1 needs to be running the official firmware (V15) for this.",
                systemImage: "info.circle",
                isWarning: true
            )
        }
        Toggle("Replace every sound", isOn: $understands)
            .tint(Palette.accent)
        Button("Put them back") { Task { await device.restoreFactoryVoices() } }
            .buttonStyle(.prominent)
            .disabled(!understands || device.identity != .officialV15 || device.isWriting)
    }
}
