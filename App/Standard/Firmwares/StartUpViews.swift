import SwiftUI

/// Asks what starts the FM-1: M-VAVE's bootloader, m-bootloader, the one Open leaves, or not sure.
struct StartUpQuestion: View {
    @Binding var startUp: StartUp?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(StartUp.question).font(.headline).foregroundStyle(Palette.ink)
                Text(StartUp.questionDetail).font(.subheadline).foregroundStyle(Palette.secondaryInk)
            }
            VStack(spacing: 0) {
                ForEach(Array(StartUp.allCases.enumerated()), id: \.element) { index, choice in
                    if index > 0 { Divider().overlay(Palette.line) }
                    choiceRow(choice)
                }
            }
            .cardBackground()
            Text(StartUp.changeLater).font(.footnote).foregroundStyle(Palette.secondaryInk)
        }
        .sensoryFeedback(.selection, trigger: startUp)
    }

    private func choiceRow(_ choice: StartUp) -> some View {
        let isChosen = startUp == choice
        return Button {
            withAnimation(Motion.press) { startUp = choice }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                    .accessibilityHidden(true)
                    .font(.title2)
                    .foregroundStyle(isChosen ? Palette.firmwaresTint : Palette.secondaryInk)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.name).font(.headline).foregroundStyle(Palette.ink)
                    if let detail = choice.detail {
                        Text(detail).font(.subheadline).foregroundStyle(Palette.secondaryInk)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }
}

/// What switching away from a firmware will take, from its guide, with where to find out more.
struct SwitchingWarningCard: View {
    var warnings: [String]
    /// Opens Help at what to do, closing the sheet the card is on.
    var openHelp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(SwitchingWords.warningTitle, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            ForEach(warnings, id: \.self) { warning in
                Text(warning).font(.callout)
            }
            Button("What can I do?", action: openHelp)
                .font(.callout.weight(.semibold))
                .buttonStyle(.plain)
                .underline()
        }
        .foregroundStyle(Palette.warningInk)
        .tint(Palette.warningInk)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.warningBackground)
        )
    }
}

/// A guide's steps, numbered.
struct StepsText: View {
    var steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 6)
    }
}
