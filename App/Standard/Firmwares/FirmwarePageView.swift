import SwiftUI

/// One firmware: what it is, where to read more, and installing it.
struct FirmwarePageView: View {
    @Environment(AppModel.self) private var model
    @State private var errorMessage: String?
    @State private var installing: StoredFirmware?
    let listed: CatalogueEntry

    /// The listed release, or a newer one found at the firmware's source.
    private var entry: CatalogueEntry { model.catalogue.entry(id: listed.id) ?? listed }
    private var stored: StoredFirmware? { model.library.stored(for: entry) }
    private var isDownloading: Bool { model.library.downloading.contains(entry.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let pictures = model.catalogue.screenshots[listed.id], !pictures.isEmpty {
                    FirmwarePictures(pictures: pictures, name: entry.name)
                }
                VStack(alignment: .leading, spacing: 18) {
                    untested
                    newerRelease
                    buildChoice
                    installSection
                    links
                    details
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.ground)
        .navigationTitle(entry.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem { starButton }
        }
        .task { await model.catalogue.checkSource(of: listed.id) }
        .task { await model.catalogue.findScreenshots(of: listed.id) }
        .sheet(item: $installing) { item in
            BeforeYouStartView(target: item, requiresOfficial: entry.requiresOfficialFirmware)
                .environment(model)
        }
    }

    /// Stars it to come back to, without saving it.
    private var starButton: some View {
        let isStarred = model.starred.contains(listed.id)
        return Button {
            model.starred.toggle(listed.id)
        } label: {
            Label(isStarred ? "Remove star" : "Star", systemImage: isStarred ? "star.fill" : "star")
        }
        .sensoryFeedback(.selection, trigger: isStarred)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBand
            VStack(alignment: .leading, spacing: 8) {
                if let author = entry.author ?? stored?.author {
                    Text("By \(author)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.secondaryInk)
                }
                if let what = entry.what {
                    Text(what)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if entry.whatSource == .gitHub {
                        Text("The author's own description, from GitHub.")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// The name and version on one of the firmware's own colours: whichever the name stands out on
    /// more.
    private var titleBand: some View {
        let design = model.catalogue.badge(id: entry.id, name: entry.name)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.name)
                .font(.largeTitle.weight(.heavy))
            Text(entry.version ?? "")
                .font(.headline)
                .opacity(0.8)
        }
        .foregroundStyle(Color(rgb: design.ink))
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: design.strongerHalf))
    }

    /// A warning for firmwares no one has tried on a real FM-1 yet.
    @ViewBuilder private var untested: some View {
        if !entry.isHardwareTested {
            Notice(
                """
                In testing: not yet known to work on a real FM-1. It's only listed in aroum's FM1 Resource \
                Hub, not on the firmware hub or fm1-editor.com.
                """,
                systemImage: "exclamationmark.triangle",
                isWarning: true
            )
        }
    }

    /// A newer release than the lists show, found at the firmware's own source.
    @ViewBuilder private var newerRelease: some View {
        if let source = ReleaseCheck.source(for: model.catalogue.listedEntry(id: listed.id) ?? listed),
            case .newer(let newer) = model.catalogue.sourceChecks[listed.id]?.outcome
        {
            Label(
                "\(newer.version ?? "A newer release") is out on \(source.rawValue). Installing gets the newer one.",
                systemImage: "sparkles"
            )
            .font(.callout)
            .foregroundStyle(Palette.goodInk)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.goodBackground))
        }
    }

    /// The release's builds, when it comes in several (e.g. standard and single-core).
    @ViewBuilder private var buildChoice: some View {
        if let builds = entry.builds, builds.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("This release comes in \(builds.count) versions")
                    .font(.headline)
                Picker(
                    "Version",
                    selection: Binding(
                        get: { entry.build ?? "" },
                        set: { model.catalogue.choose(build: $0, for: listed.id) }
                    )
                ) {
                    if entry.build == nil { Text("Choose one").tag("") }
                    ForEach(builds, id: \.name) { build in
                        Text(build.name.capitalized).tag(build.name)
                    }
                }
                .pickerStyle(.segmented)
                Text("Pick another than the usual one only if its release notes say it suits you.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    @ViewBuilder private var installSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stored != nil || entry.isDownloadable {
                installButton
                if stored == nil { saveButton }
                installNote
            } else {
                Text(
                    """
                    There's no file to download for this one. Its links below say how to get it; if you get a \
                    .fwsc file, add it with + in the firmware list.
                    """
                )
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(Palette.warningInk)
            }
        }
    }

    private var installButton: some View {
        Button {
            Task { await install() }
        } label: {
            if isDownloading {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Downloading…")
                }
            } else {
                Text("Install \(entry.name)")
            }
        }
        .buttonStyle(.prominent(Palette.firmwares))
        .disabled(isDownloading || (stored == nil && entry.needsBuildChoice))
    }

    /// Saves it here without installing, to install later, even offline.
    private var saveButton: some View {
        Button("Save to this \(ThisDevice.name) for later") {
            Task { await save() }
        }
        .buttonStyle(.secondary)
        .disabled(isDownloading || entry.needsBuildChoice)
    }

    @ViewBuilder private var installNote: some View {
        if let stored, !model.library.canRemove(stored) {
            Text("Comes with the app, so it installs even offline.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        } else if let stored {
            HStack {
                Text("Saved on this \(ThisDevice.name), so it installs even offline.")
                Spacer()
                Button("Remove") { model.library.remove(stored) }
                    .foregroundStyle(Palette.accentText)
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        } else if model.device.identity == nil {
            Text("Downloads now. Plug in your FM-1 when you're ready to install.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
    }

    @ViewBuilder private var links: some View {
        if !entry.pageLinks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entry.pageLinks.enumerated()), id: \.offset) { index, link in
                    if index > 0 { Divider().overlay(Palette.line) }
                    PixelLink(link.url) {
                        HStack {
                            Text(link.label)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .accessibilityHidden(true)
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(Palette.accentText)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                    }
                }
            }
            .cardBackground()
        }
    }

    private var details: some View {
        DisclosureGroup("Details") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                detailRow("Reports", entry.product ?? stored?.product ?? "Known once downloaded")
                if let size = entry.size ?? stored?.size { detailRow("Size", formattedBytes(size)) }
                if let date = entry.date { detailRow("Released", date) }
                if let stored { detailRow("Saved", stored.savedAt.formatted(date: .abbreviated, time: .shortened)) }
                if !entry.kinds.isEmpty { detailRow("Kind", entry.kinds.joined(separator: ", ")) }
                if let licence = entry.licence { detailRow("Licence", licence) }
                if let stars = entry.stars { detailRow("GitHub stars", "\(stars)") }
                detailRow("Recovery", entry.rescueMode?.summary ?? "Not known")
                detailRow("Listed on", entry.listedOn)
                detailRow("Tested on an FM-1", entry.isHardwareTested ? "Yes" : "In testing")
                detailRow("Built from source", entry.sourceBuildSummary)
                detailRow("File from", entry.packageSource)
                detailRow("SHA-256", entry.sha256.map { String($0.prefix(16)) + "…" } ?? "Not published")
                if entry.requiresOfficialFirmware {
                    detailRow("Installs", "From the official firmware, which goes on first")
                }
            }
            .font(.footnote)
            .padding(.top, 8)
        }
        .font(.headline)
        .tint(Palette.ink)
        .disclosureGroupStyle(.wholeHeader(padding: 16))
        .cardBackground()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Palette.secondaryInk)
            Text(value).foregroundStyle(Palette.ink).textSelection(.enabled)
        }
    }

    /// Downloads the firmware and keeps it here, without installing it.
    private func save() async {
        errorMessage = nil
        do {
            try await model.library.download(entry)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Downloads the firmware if it isn't saved yet, then asks the questions before installing.
    private func install() async {
        errorMessage = nil
        if let stored {
            installing = stored
            return
        }
        do {
            installing = try await model.library.download(entry)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
