import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import FMSwitch

/// Finding the pictures in a firmware project's README.
struct ScreenshotsTests {
    /// zp12's README on GitHub's file server, where it's looked for first.
    private let readme = Screenshots.readmeAddresses(repo: "zvenson/zp12")[0]

    @Test func findsMarkdownAndHTMLPictures() {
        let pictures = Screenshots.pictures(
            in: """
                # zp12
                ![home](web/img/home.png)
                Text between.
                <img width="400" src="https://example.com/shot.jpg">
                <img src='./docs/pic.jpeg'>
                """,
            readme: readme)
        #expect(
            pictures.map(\.absoluteString) == [
                "https://raw.githubusercontent.com/zvenson/zp12/HEAD/web/img/home.png",
                "https://example.com/shot.jpg",
                "https://raw.githubusercontent.com/zvenson/zp12/HEAD/docs/pic.jpeg",
            ])
    }

    @Test func leavesOutBadgesAndLogos() {
        let pictures = Screenshots.pictures(
            in: """
                ![logo](assets/logo.png)
                ![build](https://img.shields.io/badge/build-passing.png)
                ![diagram](docs/screens.svg)
                ![screen](docs/screen.png)
                """,
            readme: readme)
        #expect(pictures.map(\.lastPathComponent) == ["screens.svg", "screen.png"])
    }

    @Test func takesPicturesOnGitHubPagesRaw() {
        let pictures = Screenshots.pictures(
            in: """
                ![photo](https://github.com/zvenson/zp12/blob/main/photo.jpg)
                <img src="https://github.com/user-attachments/assets/0d6f2c1e-1234">
                ![root](/docs/root.png)
                """,
            readme: readme)
        #expect(
            pictures.map(\.absoluteString) == [
                "https://github.com/zvenson/zp12/blob/main/photo.jpg?raw=true",
                "https://github.com/user-attachments/assets/0d6f2c1e-1234",
                "https://raw.githubusercontent.com/zvenson/zp12/HEAD/docs/root.png",
            ])
    }

    @Test func showsEachPictureOnce() {
        let pictures = Screenshots.pictures(in: "![a](a.png) ![again](a.png)", readme: readme)
        #expect(pictures.count == 1)
    }

    @Test func triesTheOtherREADMEsWhenOneIsMissing() async {
        let pictures = await Screenshots.find(repo: "zvenson/zp12") { url in
            guard url.absoluteString.hasSuffix("readme.md") else { throw URLError(.fileDoesNotExist) }
            return Data("![screen](screen.png)".utf8)
        }
        #expect(
            pictures.map(\.image.absoluteString) == ["https://raw.githubusercontent.com/zvenson/zp12/HEAD/screen.png"])
    }

    @Test func findsNothingWithoutAREADME() async {
        let pictures = await Screenshots.find(repo: "a/b") { _ in throw URLError(.notConnectedToInternet) }
        #expect(pictures.isEmpty)
    }

    @Test func takesTheScreensKeptInADrawing() async {
        let home = Self.png(width: 240, height: 240)
        let song = Self.png(width: 240, height: 200)
        let drawings = [
            // Split over lines, as some tools write it.
            "screens.svg": Self.drawing(holding: [home, song], splittingLines: true),
            // The same screen again, and an icon.
            "controls.svg": Self.drawing(holding: [home, Self.png(width: 24, height: 24)]),
        ]
        let pictures = await Screenshots.find(repo: "keremimo/melodee") { url in
            if let drawing = drawings[url.lastPathComponent] { return Data(drawing.utf8) }
            return Data("![screens](docs/screens.svg) ![photo](photo.png) ![controls](docs/controls.svg)".utf8)
        }
        let homeAddress = "data:image/png;base64,\(home.base64EncodedString())"
        #expect(
            pictures.map(\.image.absoluteString) == [
                homeAddress,
                "data:image/png;base64,\(song.base64EncodedString())",
                "https://raw.githubusercontent.com/keremimo/melodee/HEAD/photo.png",
            ])
        // GitHub's file server gives drawings as text, so they open on GitHub's page instead.
        #expect(pictures.first?.page.absoluteString == "https://github.com/keremimo/melodee/blob/HEAD/docs/screens.svg")
    }

    @Test func skipsADrawingThatCantBeRead() async {
        let pictures = await Screenshots.find(repo: "a/b") { url in
            guard url.pathExtension == "md" else { throw URLError(.fileDoesNotExist) }
            return Data("![screens](screens.svg)".utf8)
        }
        #expect(pictures.isEmpty)
    }

    /// An SVG drawing with `images` inside it.
    private static func drawing(holding images: [Data], splittingLines: Bool = false) -> String {
        let tags = images.map { image in
            var text = image.base64EncodedString()
            if splittingLines {
                text = text.enumerated().map { $0.offset % 60 == 59 ? "\($0.element)\n" : "\($0.element)" }.joined()
            }
            return #"<image x="0" y="0" width="240" height="240" href="data:image/png;base64,\#(text)"/>"#
        }
        return #"<svg xmlns="http://www.w3.org/2000/svg">\#(tags.joined())</svg>"#
    }

    /// A plain PNG of this size.
    private static func png(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let data = NSMutableData()
        guard let image = context?.makeImage(),
            let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test func takesTheHubsPictureFromItsFeed() throws {
        let json = """
            {"firmwares": [{"id": "tuna", "name": "Tuna", "kind": "groove", "version": "1.2", "pkg": "fw/tuna.fwsc",
            "product": "FM-1_47886200", "size": 1, "sha256": "\(String(repeating: "ab", count: 32))",
            "card": "fw/cards/tuna.png"}]}
            """
        let entry = try #require(HubFeed.decode(Data(json.utf8)).entries().first)
        #expect(entry.hubCard?.absoluteString == "https://thefirmwarehub.com/fw/cards/tuna.png")
        let saved = try JSONDecoder().decode(CatalogueEntry.self, from: JSONEncoder().encode(entry))
        #expect(saved.hubCard == entry.hubCard)
    }

    @Test func showsTheHubsPictureOnlyWhenTheREADMEHasNone() async throws {
        let card = try #require(URL(string: "https://thefirmwarehub.com/fw/cards/tuna.png"))
        var entry = CatalogueEntry(id: "tuna", name: "Tuna", repo: "delirioux/tuna", listing: .hub)
        entry.hubCard = card
        let withPictures = await Screenshots.find(for: entry) { _ in Data("![screen](screen.png)".utf8) }
        #expect(withPictures.map(\.source) == [.readme])
        let without = await Screenshots.find(for: entry) { _ in Data("No pictures.".utf8) }
        #expect(without == [Screenshot(image: card, page: card, source: .hub)])
        entry.repo = nil
        #expect(await Screenshots.find(for: entry) { _ in Data() }.map(\.image) == [card])
    }
}
