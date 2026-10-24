import SwiftUI

/// The first-run notice in the standard look, with the same words as Retro's.
///
/// It has to be acknowledged before the app can be used. OK unlocks after a few seconds, so it
/// isn't tapped away unread.
struct WelcomeNoticeView: View {
    @Environment(AppModel.self) private var model
    @State private var secondsLeft = 4

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FM1Drawing(line1: "HELLO", line2: "Nice to meet you")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    Text("Welcome to FM-SWITCH")
                        .font(.largeTitle.weight(.bold))
                    Text("Before you start")
                        .font(.headline)
                    Text(SafetyNotice.text)
                    Text(SafetyNotice.recovery)
                    Text("You'll find this again in Settings.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .foregroundStyle(Palette.ink)
                .padding(24)
            }
            Button(secondsLeft > 0 ? "OK (\(secondsLeft))" : "OK") {
                withAnimation(Motion.fade) {
                    model.settings.acknowledgedNoticeVersion = SafetyNotice.version
                }
            }
            .buttonStyle(.prominent)
            .disabled(secondsLeft > 0)
            .contentTransition(.numericText(countsDown: true))
            .animation(Motion.fade, value: secondsLeft)
            .padding(24)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
        .task {
            while secondsLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                secondsLeft -= 1
            }
        }
    }
}
