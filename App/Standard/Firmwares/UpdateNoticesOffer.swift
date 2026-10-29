import SwiftUI

/// Offers update notifications once, on the page of the first firmware saved.
struct UpdateNoticesOffer: View {
    @Environment(AppModel.self) private var model
    /// The saved firmware the page shows.
    var stored: StoredFirmware

    var body: some View {
        let settings = model.settings
        // The official firmware comes with the app, so it isn't a firmware the person saved.
        if model.library.canRemove(stored), !settings.hasOfferedUpdateNotices, !settings.notifiesFirmwareUpdates {
            VStack(alignment: .leading, spacing: 10) {
                Text(UpdateNoticeWords.toggle).font(.headline)
                Text(UpdateNoticeWords.offerDetail)
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryInk)
                HStack(spacing: 10) {
                    Button(UpdateNoticeWords.notNow) { settings.hasOfferedUpdateNotices = true }
                        .buttonStyle(.secondary)
                    Button(UpdateNoticeWords.turnOn) { Task { await model.setNotifiesFirmwareUpdates(true) } }
                        .buttonStyle(.prominent(Palette.accent))
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
            .transition(.opacity)
        }
    }
}
