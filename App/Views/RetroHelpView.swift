import SwiftUI

/// HELP: what can go wrong with an FM-1 and what to do, one topic at a time.
struct RetroHelpView: View {
    @Environment(\.phosphor) private var theme
    @State private var opened: Set<HelpTopic>
    private let openRescue: () -> Void

    /// Opens with `topic` showing, and `openRescue` for the Mac's button to Backup & rescue.
    init(opening topic: HelpTopic? = nil, openRescue: @escaping () -> Void = {}) {
        _opened = State(initialValue: topic.map { [$0] } ?? [])
        self.openRescue = openRescue
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenHeader(title: "HELP")
                    MonoText(HelpTopic.intro, size: 14)
                    ForEach(HelpTopic.allCases) { topic in
                        panel(topic).id(topic)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let topic = opened.first { proxy.scrollTo(topic, anchor: .top) }
            }
        }
    }

    private func panel(_ topic: HelpTopic) -> some View {
        let isOpen = opened.contains(topic)
        return PixelPanel {
            Button {
                if isOpen { opened.remove(topic) } else { opened.insert(topic) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(isOpen ? "▾" : "▸").font(.mono(16))
                    Text(topic.title.uppercased())
                        .font(.pixel(11, bold: true, relativeTo: .callout))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.bright)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Open" : "Closed")
            if isOpen { details(topic) }
        }
    }

    @ViewBuilder private func details(_ topic: HelpTopic) -> some View {
        ForEach(topic.paragraphs, id: \.self) { MonoText($0, size: 14) }
        if topic.opensBackupAndRescue {
            Button("OPEN BACKUP & RESCUE", action: openRescue)
                .buttonStyle(.pixelCompact)
        }
        ForEach(topic.links, id: \.url) { link in
            PixelLink(link.url) {
                Text("▸ \(link.label.uppercased())")
                    .font(.pixel(11, bold: true, relativeTo: .callout))
                    .foregroundStyle(theme.bright)
            }
        }
    }
}
