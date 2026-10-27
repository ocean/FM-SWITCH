import SwiftUI

/// Help: what can go wrong with an FM-1 and what to do, one topic at a time.
struct HelpView: View {
    @State private var opened: Set<HelpTopic>
    private let openBackupAndRescue: () -> Void

    /// Opens with `topic` showing, and `openBackupAndRescue` for the Mac's button to it.
    init(opening topic: HelpTopic? = nil, openBackupAndRescue: @escaping () -> Void = {}) {
        _opened = State(initialValue: topic.map { [$0] } ?? [])
        self.openBackupAndRescue = openBackupAndRescue
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(HelpTopic.intro)
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.vertical, 4)
                    ForEach(HelpTopic.allCases) { topic in
                        card(topic).id(topic)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                if let topic = opened.first { proxy.scrollTo(topic, anchor: .top) }
            }
        }
        .background(Palette.ground)
        .navigationTitle("Help")
    }

    private func card(_ topic: HelpTopic) -> some View {
        DisclosureGroup(isExpanded: isOpen(topic)) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(topic.paragraphs, id: \.self) { Text($0) }
                if topic.opensBackupAndRescue {
                    Button("Open Backup & rescue", action: openBackupAndRescue)
                        .buttonStyle(.secondary)
                }
                ForEach(topic.links, id: \.url) { link in
                    Link(link.label, destination: link.url)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                }
            }
            .font(.callout)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(topic.title)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
        }
        .tint(Palette.secondaryInk)
        .disclosureGroupStyle(.wholeHeader(padding: 16))
        .cardBackground()
    }

    private func isOpen(_ topic: HelpTopic) -> Binding<Bool> {
        Binding {
            opened.contains(topic)
        } set: { isOpen in
            if isOpen { opened.insert(topic) } else { opened.remove(topic) }
        }
    }
}
