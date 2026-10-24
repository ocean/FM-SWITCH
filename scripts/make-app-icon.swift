#!/usr/bin/env swift
// Draws the app icon and writes it into the asset catalogue as AppIcon.
//
// The icon is the FM-1, simplified so it reads at small sizes, with the firmware-swap arrows on its
// screen and its keys lit as on the stock firmware: HOME white, PLAY green and REC red. Its
// proportions come from a photo of the real panel; the screen is a little bigger, so the arrows
// stay arrows on the Home Screen.
//
// It writes the light, dark and tinted iPhone and iPad icons, the Mac's sizes in the Mac's
// rounded-square shape, and the launch screen: the icon on a deep violet glow that suits both looks,
// light or dark. Retro's pixel icon is drawn by `make-icon.py`.
//
// Run it after changing the drawing: `scripts/make-app-icon.swift`. Pass `symmetrical` to draw the
// other layout considered, with a smaller screen and evenly spaced arrows.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The screen's size and the arrows on it.
struct Layout {
    /// The panel's width, in pixels of the 1024-pixel icon.
    var bodyWidth: CGFloat
    /// The screen's bezel, as fractions of the panel's width (left and right) and height (bottom).
    var screenLeft: CGFloat
    var screenRight: CGFloat
    var screenBottom: CGFloat
    /// The arrows' thickness, and how far each is from the screen's middle, as fractions of the
    /// screen's height.
    var arrowStroke: CGFloat
    var arrowSpread: CGFloat

    /// The chosen layout: the biggest screen, so the arrows read best when small.
    static let chosen = Self(
        bodyWidth: 960, screenLeft: 0.2, screenRight: 0.54, screenBottom: 0.555, arrowStroke: 0.13,
        arrowSpread: 0.21)
    /// The alternative, kept in case it's wanted: a smaller screen with more even arrows.
    static let symmetrical = Self(
        bodyWidth: 930, screenLeft: 0.225, screenRight: 0.51, screenBottom: 0.54, arrowStroke: 0.12,
        arrowSpread: 0.2)
}

/// The icon's colours, as `0xRRGGBB`.
struct Palette {
    /// The background's top and bottom, or nil for a clear one.
    var background: (top: UInt32, bottom: UInt32)?
    var bodyTop: UInt32 = 0x4F5357
    var bodyBottom: UInt32 = 0x3E4246
    var knob: UInt32 = 0x6A6E72
    var key: UInt32 = 0x33363A
    var well: UInt32 = 0x26292C
    var bezel: UInt32 = 0x1B1E21
    var screen: UInt32 = 0x12171A
    var arrows: UInt32 = 0xFFFFFF
    var play: UInt32 = 0x8FE36B
    var rec: UInt32 = 0xFF5A4F
    var hasShadow = true

    static let light = Self(background: (0x8B4BF0, 0x5B1FC4))
    static let dark = Self(background: (0x2A1A4D, 0x110A21))
    /// Tinted mode keeps only brightness, so the panel is lighter and every light is white.
    static let tinted = Self(
        background: nil, bodyTop: 0xA0A0A0, bodyBottom: 0x868686, knob: 0xBEBEBE, key: 0x5A5A5A,
        well: 0x3C3C3C, bezel: 0x1E1E1E, screen: 0x000000, play: 0xFFFFFF, rec: 0xFFFFFF, hasShadow: false)
}

let iconSize: CGFloat = 1024
let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../App/Assets.xcassets").standardizedFileURL
let catalogue = assets.appendingPathComponent("AppIcon.appiconset")

func colour(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws the icon, 1024 pixels square, with y running down.
struct IconDrawing {
    var context: CGContext
    var layout: Layout
    var palette: Palette
    /// How many output pixels each of the icon's pixels is, for shadows, which ignore scaling.
    var pixelScale: CGFloat

    private var body: CGRect {
        let height = layout.bodyWidth * 534 / 880
        return CGRect(
            x: iconSize / 2 - layout.bodyWidth / 2, y: iconSize / 2 - height / 2 + 2, width: layout.bodyWidth,
            height: height)
    }

    private var scale: CGFloat { layout.bodyWidth / 880 }

    func draw() {
        if let background = palette.background {
            fillGradient(CGRect(x: 0, y: 0, width: iconSize, height: iconSize), background.top, background.bottom)
        }
        drawBody()
        drawLeft()
        drawScreen()
        drawRight()
        drawKeyboard()
    }

    // MARK: - Parts.

    private func drawBody() {
        let radius = 70 * scale
        if palette.hasShadow {
            context.saveGState()
            // Shadow offsets ignore the flip, so a negative one falls down the icon.
            context.setShadow(
                offset: CGSize(width: 0, height: -26 * pixelScale), blur: 54 * pixelScale,
                color: colour(0x1A0840, 0.5))
            fillRounded(body, radius: radius, palette.bodyBottom)
            context.restoreGState()
        }
        context.saveGState()
        context.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        fillGradient(body, palette.bodyTop, palette.bodyBottom)
        context.restoreGState()
    }

    /// Four knobs, then OCT− and OCT+ in their well, fitted beside the screen.
    private func drawLeft() {
        let width = layout.screenLeft - 0.04 - 0.045
        func left(_ x: CGFloat) -> CGFloat { 0.045 + width * (x - 0.045) / 0.17 }
        let radius = 32 * scale * min(1, width / 0.17)
        for x in [0.081, 0.181] as [CGFloat] {
            for y in [0.15, 0.315] as [CGFloat] {
                fillCircle(at(left(x), y), radius: radius, palette.knob)
            }
        }
        let octaves = box(left(0.045), 0.415, left(0.215), 0.515)
        fillRounded(octaves, radius: 18, palette.well)
        let keyWidth = (octaves.width - 24) / 2
        for index in 0..<2 {
            drawKey(
                CGRect(
                    x: octaves.minX + 8 + CGFloat(index) * (keyWidth + 8), y: octaves.minY + 8, width: keyWidth,
                    height: octaves.height - 16))
        }
    }

    /// The screen in its bezel, with one arrow pointing each way.
    private func drawScreen() {
        let bezel = box(layout.screenLeft, 0.03, layout.screenRight, layout.screenBottom)
        fillRounded(bezel, radius: 34, palette.bezel)
        let screen = bezel.insetBy(dx: bezel.width * 0.1, dy: bezel.height * 0.07)
        fillRounded(screen, radius: 10, palette.screen)
        let stroke = screen.height * layout.arrowStroke
        let inset = screen.width * 0.14
        let spread = screen.height * layout.arrowSpread
        // Heads clear of the other arrow's shaft, and inside the screen.
        let head = min(
            screen.width * 0.24, 2 * spread - stroke * 1.2,
            screen.height / 2 - spread - stroke / 2 - screen.height * 0.04)
        context.setStrokeColor(colour(palette.arrows))
        context.setLineWidth(stroke)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawArrow(from: screen.maxX - inset, to: screen.minX + inset, y: screen.midY - spread, head: head)
        drawArrow(from: screen.minX + inset, to: screen.maxX - inset, y: screen.midY + spread, head: head)
    }

    /// Four knobs, then six page keys in their well, with HOME, PLAY and REC lit.
    private func drawRight() {
        let edge = layout.screenRight + 0.04
        let width = 0.935 - edge
        func right(_ x: CGFloat) -> CGFloat { edge + width * (x - 0.53) / 0.405 }
        for x in [0.56, 0.673, 0.787, 0.903] as [CGFloat] {
            fillCircle(at(right(x), 0.15), radius: 28 * scale, palette.knob)
        }
        let well = box(right(0.53), 0.27, 0.935, 0.515)
        fillRounded(well, radius: 22, palette.well)
        let gap: CGFloat = 8
        let keyWidth = (well.width - 4 * gap) / 3
        let keyHeight = (well.height - 3 * gap) / 2
        let lights: [(UInt32, CGFloat)?] = [nil, nil, nil, (0xFFFFFF, 1), (palette.play, 1), (palette.rec, 1)]
        for (index, light) in lights.enumerated() {
            let (row, column) = index.quotientAndRemainder(dividingBy: 3)
            let key = CGRect(
                x: well.minX + gap + CGFloat(column) * (keyWidth + gap),
                y: well.minY + gap + CGFloat(row) * (keyHeight + gap), width: keyWidth, height: keyHeight)
            drawKey(key, light: light?.0)
        }
    }

    /// Eight pill-shaped keys, unlit.
    private func drawKeyboard() {
        let keyboard = box(0.035, 0.57, 0.965, 0.94)
        fillRounded(keyboard, radius: 34, palette.well)
        let slot = (keyboard.width - 24 - 7 * 10) / 8
        let height = keyboard.height - 24
        let width = min(slot, height * 0.62)
        for index in 0..<8 {
            let x = keyboard.minX + 12 + CGFloat(index) * (slot + 10) + (slot - width) / 2
            fillRounded(
                CGRect(x: x, y: keyboard.maxY - 12 - height, width: width, height: height), radius: width / 2,
                palette.key)
        }
    }

    /// A key with its label, dim white unless it's lit in `light`.
    private func drawKey(_ rect: CGRect, light: UInt32? = nil) {
        fillRounded(rect, radius: min(rect.width, rect.height) * 0.26, palette.key)
        let label = CGRect(
            x: rect.midX - rect.width * 0.3, y: rect.midY - rect.height * 0.11, width: rect.width * 0.6,
            height: rect.height * 0.22)
        context.saveGState()
        if let light {
            context.setShadow(offset: .zero, blur: 26 * pixelScale, color: colour(light, 0.9))
        }
        fillRounded(label, radius: label.height / 2, light ?? 0xFFFFFF, alpha: light == nil ? 0.45 : 1)
        context.restoreGState()
    }

    private func drawArrow(from start: CGFloat, to tip: CGFloat, y: CGFloat, head: CGFloat) {
        let back = tip > start ? tip - head : tip + head
        context.move(to: CGPoint(x: start, y: y))
        context.addLine(to: CGPoint(x: tip, y: y))
        context.move(to: CGPoint(x: back, y: y - head))
        context.addLine(to: CGPoint(x: tip, y: y))
        context.addLine(to: CGPoint(x: back, y: y + head))
        context.strokePath()
    }

    // MARK: - Helpers.

    /// A point on the panel, from fractions of its width and height.
    private func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: body.minX + x * body.width, y: body.minY + y * body.height)
    }

    private func box(_ left: CGFloat, _ top: CGFloat, _ right: CGFloat, _ bottom: CGFloat) -> CGRect {
        let (start, end) = (at(left, top), at(right, bottom))
        return CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
    }

    private func fillRounded(_ rect: CGRect, radius: CGFloat, _ fill: UInt32, alpha: CGFloat = 1) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(colour(fill, alpha))
        context.fillPath()
    }

    private func fillCircle(_ centre: CGPoint, radius: CGFloat, _ fill: UInt32) {
        context.setFillColor(colour(fill))
        context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
    }

    private func fillGradient(_ rect: CGRect, _ top: UInt32, _ bottom: UInt32) {
        let colours = [colour(top), colour(bottom)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours, locations: [0, 1])
        else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        context.restoreGState()
    }
}

/// Renders `pixels` square, flipped so y runs down and scaled so the icon's 1024 pixels fill it.
func render(pixels: Int, opaque: Bool, draw: (CGContext, CGFloat) -> Void) -> CGImage {
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: alpha.rawValue)
    else { fatalError("Couldn't make a \(pixels)-pixel drawing context.") }
    let scale = CGFloat(pixels) / iconSize
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: scale, y: -scale)
    draw(context, scale)
    guard let image = context.makeImage() else { fatalError("Couldn't render the \(pixels)-pixel icon.") }
    return image
}

func write(_ image: CGImage, to name: String, in folder: URL = catalogue) {
    let url = folder.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("Couldn't write \(url.path).") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(url.path).") }
}

/// The iPhone and iPad icon, full-bleed: iOS rounds the corners.
func phoneIcon(_ layout: Layout, _ palette: Palette) -> CGImage {
    render(pixels: Int(iconSize), opaque: palette.background != nil) { context, scale in
        IconDrawing(context: context, layout: layout, palette: palette, pixelScale: scale).draw()
    }
}

/// The Mac icon: the drawing in the Mac's rounded square, 824 of 1024 pixels, with its shadow.
func macIcon(_ layout: Layout, pixels: Int) -> CGImage {
    render(pixels: pixels, opaque: false) { context, scale in
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale, color: colour(0, 0.3))
        context.addPath(shape)
        context.setFillColor(colour(0x5B1FC4))
        context.fillPath()
        context.restoreGState()
        context.addPath(shape)
        context.clip()
        context.translateBy(x: tile.minX, y: tile.minY)
        context.scaleBy(x: tile.width / iconSize, y: tile.height / iconSize)
        IconDrawing(context: context, layout: layout, palette: .light, pixelScale: scale * tile.width / iconSize).draw()
    }
}

/// The launch screen's icon: the light icon with the Home Screen's rounded corners, 120 points.
func launchIcon(_ layout: Layout, pixels: Int) -> CGImage {
    render(pixels: pixels, opaque: false) { context, scale in
        let radius = iconSize * 0.2237
        context.addPath(
            CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: iconSize, height: iconSize), cornerWidth: radius,
                cornerHeight: radius, transform: nil))
        context.clip()
        IconDrawing(context: context, layout: layout, palette: .light, pixelScale: scale).draw()
    }
}

let layout = CommandLine.arguments.dropFirst().first == "symmetrical" ? Layout.symmetrical : .chosen
write(phoneIcon(layout, .light), to: "AppIcon.png")
write(phoneIcon(layout, .dark), to: "AppIcon-Dark.png")
write(phoneIcon(layout, .tinted), to: "AppIcon-Tinted.png")
let macSizes = [16, 32, 128, 256, 512]
for points in macSizes {
    for scale in [1, 2] {
        write(macIcon(layout, pixels: points * scale), to: "AppIcon-mac-\(points)@\(scale)x.png")
    }
}

/// One entry in the icon set's Contents.json.
struct Entry: Encodable {
    struct Appearance: Encodable {
        var appearance = "luminosity"
        var value: String
    }

    var idiom: String
    var platform: String?
    var size: String?
    var scale: String?
    var filename: String
    var appearances: [Appearance]?
}

struct Contents: Encodable {
    struct Info: Encodable {
        var author = "xcode"
        var version = 1
    }

    var images: [Entry]
    var info = Info()
}

let phone = [
    Entry(idiom: "universal", platform: "ios", size: "1024x1024", filename: "AppIcon.png"),
    Entry(
        idiom: "universal", platform: "ios", size: "1024x1024", filename: "AppIcon-Dark.png",
        appearances: [.init(value: "dark")]),
    Entry(
        idiom: "universal", platform: "ios", size: "1024x1024", filename: "AppIcon-Tinted.png",
        appearances: [.init(value: "tinted")]),
]
let mac = macSizes.flatMap { points in
    [1, 2].map { scale in
        Entry(idiom: "mac", size: "\(points)x\(points)", scale: "\(scale)x", filename: "AppIcon-mac-\(points)@\(scale)x.png")
    }
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

func writeJSON(_ value: some Encodable, in folder: URL) throws {
    let json = try encoder.encode(value)
    try (String(decoding: json, as: UTF8.self) + "\n").write(
        to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

try writeJSON(Contents(images: phone + mac), in: catalogue)

// The launch screen: the icon, over its violet background.
let launchImages = assets.appendingPathComponent("LaunchIcon.imageset")
try FileManager.default.createDirectory(at: launchImages, withIntermediateDirectories: true)
for scale in [1, 2, 3] {
    write(launchIcon(layout, pixels: 120 * scale), to: "LaunchIcon@\(scale)x.png", in: launchImages)
}
try writeJSON(
    Contents(images: [1, 2, 3].map { scale in
        Entry(idiom: "universal", scale: "\(scale)x", filename: "LaunchIcon@\(scale)x.png")
    }),
    in: launchImages)

/// The same noise on every run, so the image only changes when the drawing does.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64 = 0x464D_2D31

    mutating func next() -> UInt64 {
        // SplitMix64.
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// The launch screen's background: deep violet, darker towards the bottom, glowing behind the icon.
///
/// It's the same in light and dark mode, and for both looks, since iOS shows it before the app
/// knows which look is on. The launch storyboard stretches it to fill the screen, so it's drawn at
/// about a phone's shape, with a little noise so the gradient doesn't band.
func launchGradient(width: Int, height: Int) -> CGImage {
    let top: (CGFloat, CGFloat, CGFloat) = (0x2B, 0x12, 0x60)
    let bottom: (CGFloat, CGFloat, CGFloat) = (0x0C, 0x06, 0x18)
    let glow: (CGFloat, CGFloat, CGFloat) = (0x6D, 0x28, 0xD9)
    var generator = SeededGenerator()
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        let down = CGFloat(y) / CGFloat(height - 1)
        for x in 0..<width {
            // How far from the middle, in widths, so the glow is round on a phone.
            let across = (CGFloat(x) / CGFloat(width - 1) - 0.5)
            let along = (down - 0.5) * CGFloat(height) / CGFloat(width)
            let distance = (across * across + along * along).squareRoot()
            let fade = max(0, 1 - distance / 0.62)
            let strength = 0.42 * fade * fade * (3 - 2 * fade)
            let channels = [
                (top.0, bottom.0, glow.0), (top.1, bottom.1, glow.1), (top.2, bottom.2, glow.2),
            ]
            for (index, (from, to, lit)) in channels.enumerated() {
                let ground = from + (to - from) * down
                let value = ground + (lit - ground) * strength + CGFloat.random(in: -0.5...0.5, using: &generator)
                pixels[(y * width + x) * 4 + index] = UInt8(max(0, min(255, value.rounded())))
            }
        }
    }
    guard
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let provider = CGDataProvider(data: Data(pixels) as CFData),
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { fatalError("Couldn't draw the launch screen's background.") }
    return image
}

let launchBackground = assets.appendingPathComponent("LaunchGradient.imageset")
try FileManager.default.createDirectory(at: launchBackground, withIntermediateDirectories: true)
write(launchGradient(width: 600, height: 1300), to: "LaunchGradient.png", in: launchBackground)
try writeJSON(
    Contents(images: [Entry(idiom: "universal", filename: "LaunchGradient.png")]), in: launchBackground)
print("Wrote AppIcon and the launch screen (\(layout.bodyWidth == Layout.chosen.bodyWidth ? "chosen" : "symmetrical") layout)")
