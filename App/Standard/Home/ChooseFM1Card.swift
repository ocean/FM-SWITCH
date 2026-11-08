import FM1Kit
import SwiftUI

/// Lists the devices connected, when there's more than one, to choose the one to work with.
struct ChooseFM1Card: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DeviceChoice.title).font(.headline).foregroundStyle(Palette.ink)
                Text(DeviceChoice.detail).font(.subheadline).foregroundStyle(Palette.secondaryInk)
            }
            VStack(spacing: 0) {
                ForEach(Array(model.device.devices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 { Divider().overlay(Palette.line) }
                    row(device)
                }
            }
            .cardBackground()
        }
        .sensoryFeedback(.selection, trigger: model.device.chosenDevice)
    }

    private func row(_ device: FM1DeviceSummary) -> some View {
        let isChosen = model.device.chosenDevice?.id == device.id
        return Button {
            withAnimation(Motion.press) { model.device.choose(device) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                    .accessibilityHidden(true)
                    .font(.title2)
                    .foregroundStyle(isChosen ? Palette.firmwaresTint : Palette.secondaryInk)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(DeviceChoice.name(of: device, in: model)).font(.headline).foregroundStyle(Palette.ink)
                    Text(DeviceChoice.detail(of: device)).font(.subheadline).foregroundStyle(Palette.secondaryInk)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(model.device.isWriting)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }
}
