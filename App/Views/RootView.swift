import SwiftUI

/// The app's root: the standard look, or Retro once it's been found and picked.
///
/// What both looks share (the firmware list's download, MIDI coming back) starts here.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.settings.look {
            case .standard: StandardRootView()
            case .retro: RetroRootView()
            }
        }
        // The firmware list downloads in the background as the app opens, not when it's first
        // shown; the saved copy shows meanwhile.
        .task { await model.catalogue.refresh() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.device.scenePhaseChanged(to: phase)
            if phase == .active { model.retryConnectionIfUnavailable() }
            #if os(iOS)
                if phase == .background && model.settings.notifiesFirmwareUpdates {
                    FirmwareUpdateNotices.scheduleCheck()
                }
            #endif
        }
    }
}
