import SwiftUI

/// The launch screen, drawn again over the app as it opens, then faded away to show whichever
/// look is on.
///
/// iOS shows the launch screen before the app knows which look is on, so it's the same violet for
/// both, and this takes over from it seamlessly. The icon lifts a little as it goes, unless the
/// person has asked for less motion.
struct LaunchHandOff: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @State private var isLeaving = false
    var finished: () -> Void

    var body: some View {
        ZStack {
            Image("LaunchGradient")
                .resizable()
            Image("LaunchIcon")
                .scaleEffect(isLeaving && !reducesMotion ? 1.12 : 1)
        }
        .ignoresSafeArea()
        .opacity(isLeaving ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            // A beat for the first screen to draw underneath.
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.45)) {
                isLeaving = true
            } completion: {
                finished()
            }
        }
    }
}
