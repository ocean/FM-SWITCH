import SwiftUI

/// The warning about firmwares that only know the older flash chip, and when the FM-1 hasn't said
/// which chip it has, how to tell.
struct FlashChipNotice: View {
    var names: [String]
    var hasNewerFlashChip = false
    var refuses = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Notice(
                FlashChipWords.warning(names, hasNewerFlashChip: hasNewerFlashChip, refuses: refuses),
                systemImage: "exclamationmark.triangle",
                isWarning: true
            )
            if !hasNewerFlashChip {
                DisclosureGroup(FlashChipWords.howToTellQuestion) {
                    Text(FlashChipWords.howToTell)
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.callout.weight(.semibold))
            }
        }
    }
}
