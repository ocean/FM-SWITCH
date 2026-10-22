import SwiftUI
import UIKit
import WebKit

/// A link: tapping opens it in the in-app browser, and pressing and holding opens the share
/// sheet, as links do elsewhere on iPhone and iPad.
struct PixelLink<Label: View>: View {
    /// Where the link is in its window, for pointing the iPad's share popover at it.
    @State private var frame = CGRect.zero
    @State private var shares = 0
    @State private var browsing = false
    private let url: URL
    private let label: Label

    init(_ url: URL, @ViewBuilder label: () -> Label) {
        self.url = url
        self.label = label()
    }

    var body: some View {
        label
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { newFrame in
                frame = newFrame
            }
            .onTapGesture { browsing = true }
            .onLongPressGesture { share() }
            .sensoryFeedback(.impact, trigger: shares)
            .sheet(isPresented: $browsing) {
                BrowserSheet(url: url)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isLink)
            .accessibilityAction { browsing = true }
            .accessibilityAction(named: "Share") { share() }
    }

    private func share() {
        shares += 1
        ShareSheet.present(url, from: frame)
    }
}

/// The in-app browser: a half-height sheet that the user can drag up to full height, with a
/// web view inside. SFSafariViewController can't take sheet detents, so this is a plain web
/// view; the sheet's share button offers opening the page in Safari.
@MainActor
struct BrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            BrowserWebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.host ?? url.absoluteString)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// The system share sheet, which SwiftUI's ShareLink can't open from a press and hold.
@MainActor
private enum ShareSheet {
    static func present(_ url: URL, from frame: CGRect) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow,
            var top = window.rootViewController
        else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // On iPad the sheet is a popover, which needs something to point at.
        sheet.popoverPresentationController?.sourceView = window
        sheet.popoverPresentationController?.sourceRect = frame
        top.present(sheet, animated: true)
    }
}
