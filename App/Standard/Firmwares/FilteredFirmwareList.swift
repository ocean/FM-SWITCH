import SwiftUI

/// A scrolling list of firmwares with the order menu and the filters at its top, wrapping onto more
/// rows rather than scrolling sideways.
///
/// Once the filters scroll away, the order and the filter picked pin under the title, unless the
/// filter is All. Tapping the pinned filter goes back up to the filters, to pick another.
struct FilteredFirmwareList<Content: View>: View {
    @Binding var order: FirmwareOrder
    /// The filter picked, which may be one `scopes` no longer offers.
    @Binding var scope: FirmwareScope
    var scopes: [FirmwareScope]
    /// The firmwares the arrow keys step through, and the one picked, when they show beside the
    /// list.
    var stepping: ArrowKeySteps?
    /// The list under the filters, given the filter that applies.
    @ViewBuilder var content: (FirmwareScope) -> Content

    /// Whether the filters have scrolled up out of sight.
    @State private var areFiltersHidden = false
    /// How tall the filters are, to know when they've scrolled away.
    @State private var filtersHeight: CGFloat = 0

    private static var filtersID: String { "filters" }

    var body: some View {
        let picked = scope.offered(in: scopes)
        ScrollViewReader { proxy in
            ScrollView { stack(picked: picked) }
                .modifier(ScrolledPast(offset: filtersHeight, isPast: $areFiltersHidden))
                // Only as far as it takes to show it, so one already in sight stays put.
                .onChange(of: stepping?.selectedID) { _, id in
                    if let id { withAnimation(Motion.standard) { proxy.scrollTo(id) } }
                }
                .overlay(alignment: .top) {
                    // Always there, only faded out, as adding the order menu while the list scrolls
                    // stalls the Mac's layout.
                    let isPinned = areFiltersHidden && picked != .all
                    pinned(picked: picked) {
                        withAnimation(Motion.standard) { proxy.scrollTo(Self.filtersID, anchor: .top) }
                    }
                    .opacity(isPinned ? 1 : 0)
                    .allowsHitTesting(isPinned)
                    .accessibilityHidden(!isPinned)
                    .animation(Motion.fade, value: isPinned)
                }
        }
    }

    /// The filters, then the list.
    private func stack(picked: FirmwareScope) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            filters(picked: picked)
                .id(Self.filtersID)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    filtersHeight = height
                }
            content(picked)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .animation(Motion.standard, value: picked)
        .animation(Motion.standard, value: order)
        // Inside the scroll view, so the arrow keys reach it before the scroll view.
        .steppingWithArrowKeys(stepping)
    }

    private func filters(picked: FirmwareScope) -> some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            orderMenu
            ForEach(scopes, id: \.self) { option in
                pill(option, isPicked: option == picked) {
                    withAnimation(Motion.standard) { scope = option }
                }
            }
        }
        .padding(.top, 4)
    }

    private func pinned(picked: FirmwareScope, showFilters: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            orderMenu
            pill(picked, isPicked: true, action: showFilters)
                .accessibilityHint("Shows the filters")
                // For UI tests, as the filters further up have a pill of the same name.
                .accessibilityIdentifier("pinnedFilter")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Palette.ground)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.line) }
    }

    private func pill(_ option: FirmwareScope, isPicked: Bool, action: @escaping () -> Void) -> some View {
        Button(option.name, action: action)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .foregroundStyle(isPicked ? Palette.card : Palette.ink)
            .background(Capsule().fill(isPicked ? Palette.ink : Palette.control))
            .buttonStyle(.pressable)
            .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private var orderMenu: some View {
        Menu {
            Picker("Sort by", selection: $order) {
                ForEach(FirmwareOrder.allCases) { Text($0.name).tag($0) }
            }
        } label: {
            Label(order.name, systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .foregroundStyle(Palette.ink)
                .background(Capsule().strokeBorder(Palette.control, lineWidth: 2))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Sort by \(order.name)")
    }
}
