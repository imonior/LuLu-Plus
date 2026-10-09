// Draws the "LuLu_Plus" wordmark the About window shows next to the app icon.
//
// Vector output (PDF), so the mark stays sharp at any size; the colour split follows the app
// icon: "LuLu" in its blue, "_Plus" in its red. Run through make_brand_assets.sh.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import UniformTypeIdentifiers

let usage = "usage: WordmarkRenderer <out.pdf>\n"

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(usage.data(using: .utf8)!)
    exit(2)
}

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])

// the size the About window's image view was laid out for
let width: CGFloat = 1268
let height: CGFloat = 385
let padding: CGFloat = 24

let blue = CGColor(red: 0x1B / 255.0, green: 0x7E / 255.0, blue: 0xFE / 255.0, alpha: 1)
let red = CGColor(red: 0xFE / 255.0, green: 0x0C / 255.0, blue: 0x13 / 255.0, alpha: 1)

let mark = NSMutableAttributedString(string: "LuLu_Plus")
mark.addAttribute(kCTForegroundColorAttributeName as NSAttributedString.Key, value: blue,
                  range: NSRange(location: 0, length: 4))
mark.addAttribute(kCTForegroundColorAttributeName as NSAttributedString.Key, value: red,
                  range: NSRange(location: 4, length: 5))

func makeLine(size: CGFloat) -> CTLine {
    // the original mark's letterforms are rounded; the system rounded design is the closest
    let system = NSFont.systemFont(ofSize: size, weight: .bold)
    let rounded = system.fontDescriptor.withDesign(.rounded) ?? system.fontDescriptor
    let font = CTFontCreateWithFontDescriptor(rounded as CTFontDescriptor, size, nil)
    mark.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value: font,
                      range: NSRange(location: 0, length: mark.length))
    return CTLineCreateWithAttributedString(mark)
}

//fit the mark to the width the About window gives it
let probe = makeLine(size: 200)
let probeWidth = CTLineGetBoundsWithOptions(probe, .useOpticalBounds).width
let line = makeLine(size: 200 * (width - 2 * padding) / probeWidth)

let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
guard let ctx = CGContext(outURL as CFURL, mediaBox: &mediaBox, nil) else {
    FileHandle.standardError.write("cannot write \(outURL.path)\n".data(using: .utf8)!)
    exit(3)
}

ctx.beginPDFPage(nil)
ctx.textPosition = CGPoint(x: (width - bounds.width) / 2 - bounds.minX,
                           y: (height - bounds.height) / 2 - bounds.minY)
CTLineDraw(line, ctx)
ctx.endPDFPage()
ctx.closePDF()

print("wordmark: \(outURL.path)")
