import Foundation
import Testing

@testable import FMSwitch

struct ScreenshotsTests {
    @Test func markdownImages() {
        let urls = Screenshots.imageURLs(
            in: """
            # zp12
            ![home](web/img/home.png)
            Text between.
            <img src="https://example.com/shot.jpg">
            """,
            repo: "zvenson/zp12"
        )
        #expect(urls.count == 2)
        #expect(urls[0].absoluteString == "https://raw.githubusercontent.com/zvenson/zp12/HEAD/web/img/home.png")
        #expect(urls[1].absoluteString == "https://example.com/shot.jpg")
    }

    @Test func ornaments() {
        let urls = Screenshots.imageURLs(
            in: """
            ![logo](assets/logo.png)
            ![build](https://img.shields.io/badge/build-passing.svg)
            ![screen](docs/screen.png)
            """,
            repo: "a/b"
        )
        #expect(urls.map(\.lastPathComponent) == ["screen.png"])
    }

    @Test func singleQuotes() {
        let urls = Screenshots.imageURLs(in: #"<img src='docs/pic.jpeg'>"#, repo: "a/b")
        #expect(urls.count == 1)
        #expect(urls[0].lastPathComponent == "pic.jpeg")
    }

    @Test func noImages() {
        #expect(Screenshots.imageURLs(in: "Just words.\n", repo: "a/b").isEmpty)
    }
}
