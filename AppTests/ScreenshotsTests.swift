import Foundation
import Testing

@testable import FMSwitch

/// Finding the pictures in a firmware project's README.
struct ScreenshotsTests {
    private let readme = URL(string: "https://raw.githubusercontent.com/zvenson/zp12/HEAD/README.md")!

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

    @Test func leavesOutBadgesLogosAndSVGs() {
        let pictures = Screenshots.pictures(
            in: """
                ![logo](assets/logo.png)
                ![build](https://img.shields.io/badge/build-passing.png)
                ![diagram](docs/screens.svg)
                ![screen](docs/screen.png)
                """,
            readme: readme)
        #expect(pictures.map(\.lastPathComponent) == ["screen.png"])
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
        #expect(pictures.map(\.absoluteString) == ["https://raw.githubusercontent.com/zvenson/zp12/HEAD/screen.png"])
    }

    @Test func findsNothingWithoutAREADME() async {
        let pictures = await Screenshots.find(repo: "a/b") { _ in throw URLError(.notConnectedToInternet) }
        #expect(pictures.isEmpty)
    }
}
