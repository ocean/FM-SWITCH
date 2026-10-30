#!/usr/bin/env swift
// Draws the background of the Mac DMG's window: a pixel arrow from the app to Applications.
//
// Finder labels the icons in black in light mode and white in dark mode, whatever the background,
// so the background is a hot pink that both read on at about 4.5:1, and that sets off the icon's
// purple tile. The arrow and the hint are in Retro's style: square pixels with hard block
// shadows, and the hint in Silkscreen.
//
// It writes scripts/dmg-background.tiff, at 1x and 2x, which `package-mac.sh` puts in the DMG. The
// icons' places there must match `appCentre` and `applicationsCentre`. Run it after changing the
// drawing: `scripts/make-dmg-background.swift`.

import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// The window's content, in points.
let width: CGFloat = 640
let height: CGFloat = 330
/// Where the icons' pictures are centred, in points from the top left.
///
/// The package script places them at y 100, which Finder takes as the middle of the picture and its label together.
let appCentre = CGPoint(x: 160, y: 145)
let applicationsCentre = CGPoint(x: 480, y: 145)

let scripts = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let fonts = scripts.appendingPathComponent("../App/Resources/Fonts").standardizedFileURL

func colour(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// The background's hot pink: white labels read on it at 4.5:1 and black ones at 4.7:1.
let hotPink: UInt32 = 0xDE1E8C
/// The block shadows' deep pink.
let shadow = colour(0x42092A, 0.7)

/// Draws the background with y running down, `scale` pixels to the point.
func drawBackground(scale: Int) -> CGImage {
    guard
        let context = CGContext(
            data: nil, width: Int(width) * scale, height: Int(height) * scale, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fatalError("Couldn't make the drawing context.") }
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .none
    context.setShouldAntialias(false)

    context.setFillColor(colour(hotPink))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    drawDots(in: context)
    drawArrow(in: context)
    drawHint(in: context)

    guard let image = context.makeImage() else { fatalError("Couldn't draw the background.") }
    return image
}

/// A faint grid of pixels, like an unlit screen's.
func drawDots(in context: CGContext) {
    context.setFillColor(colour(0xFFFFFF, 0.07))
    let spacing: CGFloat = 16
    for row in stride(from: spacing / 2, to: height, by: spacing) {
        for column in stride(from: spacing / 2, to: width, by: spacing) {
            context.fill(CGRect(x: column - 1, y: row - 1, width: 2, height: 2))
        }
    }
}

/// The arrow, in blocks: a shaft three blocks thick, then a head eleven blocks tall that narrows by
/// a block on each side per column.
func drawArrow(in context: CGContext) {
    let block: CGFloat = 6
    let shaftLength = 12
    let headLength = 6
    var blocks: [(column: Int, row: Int)] = []
    for column in 0..<shaftLength {
        for row in -1...1 { blocks.append((column, row)) }
    }
    for step in 0..<headLength {
        let reach = headLength - 1 - step
        for row in -reach...reach { blocks.append((shaftLength + step, row)) }
    }

    let length = CGFloat(shaftLength + headLength) * block
    let left = ((appCentre.x + applicationsCentre.x) / 2 - length / 2).rounded()
    let middle = appCentre.y - block / 2
    let size = block
    func rect(_ block: (column: Int, row: Int), offset: CGFloat) -> CGRect {
        CGRect(
            x: left + CGFloat(block.column) * size + offset, y: middle + CGFloat(block.row) * size + offset,
            width: size, height: size)
    }
    context.setFillColor(shadow)
    context.fill(blocks.map { rect($0, offset: block / 2) })
    context.setFillColor(colour(0xFFFFFF))
    context.fill(blocks.map { rect($0, offset: 0) })
}

/// The hint under the icons, in Silkscreen with a block shadow.
func drawHint(in context: CGContext) {
    let url = fonts.appendingPathComponent("Silkscreen-Regular.ttf")
    guard
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
        let descriptor = descriptors.first
    else { fatalError("Couldn't load Silkscreen from \(url.path).") }
    let font = CTFontCreateWithFontDescriptor(descriptor, 16, nil)

    func line(_ fill: CGColor) -> CTLine {
        let text = NSAttributedString(
            string: "Drag FM-SWITCH into Applications",
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill,
            ])
        return CTLineCreateWithAttributedString(text)
    }
    let bounds = CTLineGetImageBounds(line(shadow), context)
    let origin = CGPoint(x: ((width - bounds.width) / 2 - bounds.minX).rounded(), y: 292)

    // Text draws upwards, so it's drawn unflipped about its baseline.
    for (fill, offset) in [(shadow, 2.0), (colour(0xFFFFFF), 0.0)] {
        context.saveGState()
        context.translateBy(x: origin.x + offset, y: origin.y + offset)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line(fill), context)
        context.restoreGState()
    }
}

/// Writes both scales into one TIFF, so Finder picks the sharp one on a Retina display.
func writeTIFF(_ images: [CGImage], to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, images.count, nil)
    else { fatalError("Couldn't write \(url.path).") }
    for (index, image) in images.enumerated() {
        let dpi = 72 * (index + 1)
        CGImageDestinationAddImage(
            destination, image,
            [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(url.path).") }
}

let output = scripts.appendingPathComponent("dmg-background.tiff")
writeTIFF([drawBackground(scale: 1), drawBackground(scale: 2)], to: output)
print("Wrote \(output.lastPathComponent)")
