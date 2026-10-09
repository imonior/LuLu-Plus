// Draws the Settings toolbar's globe for the Language tab.
//
// The other tabs' icons are two-tone: a monochrome shell plus one green accent. This one is the
// same treatment - the circle and equator in the shell colour, the meridian in the set's green -
// rendered once per appearance, because the toolbar swaps icons when the user switches between
// light and dark. Sizes (22 pt) and colours match the neighbouring PDFs in the asset catalog.
//
// Run through make_brand_assets.sh, not directly.

import CoreGraphics
import Foundation

let usage = "usage: PrefsIconRenderer <out-dir>\n"

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(usage.data(using: .utf8)!)
    exit(2)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    return CGColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
}

let green = rgb(0x93, 0xC1, 0x3D)

// shell colours sampled from the catalog's existing Settings icons
let variants: [(name: String, shell: CGColor)] = [
    ("Any", rgb(0x8B, 0x9D, 0xA4)),
    ("Light", rgb(0x25, 0x25, 0x25)),
    ("Dark", rgb(0xDD, 0xDE, 0xDB)),
]

let size: CGFloat = 22
let line: CGFloat = 1.7

for variant in variants {
    let path = outDir.appendingPathComponent("prefsLanguage \(variant.name).pdf")

    guard let consumer = CGDataConsumer(url: path as CFURL) else {
        FileHandle.standardError.write("cannot write \(path.path)\n".data(using: .utf8)!)
        exit(3)
    }

    var box = CGRect(x: 0, y: 0, width: size, height: size)
    guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        FileHandle.standardError.write("no PDF context for \(path.path)\n".data(using: .utf8)!)
        exit(4)
    }

    ctx.beginPDFPage(nil)

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(line)

    // the globe's outline
    ctx.setStrokeColor(variant.shell)
    ctx.strokeEllipse(in: CGRect(x: 2.4, y: 2.4, width: size - 4.8, height: size - 4.8))

    // the meridian, in the set's green
    ctx.setStrokeColor(green)
    ctx.strokeEllipse(in: CGRect(x: (size - 8.6) / 2.0, y: 2.4, width: 8.6, height: size - 4.8))

    // the equator
    ctx.setStrokeColor(variant.shell)
    ctx.move(to: CGPoint(x: 3.3, y: size / 2.0))
    ctx.addLine(to: CGPoint(x: size - 3.3, y: size / 2.0))
    ctx.strokePath()

    ctx.endPDFPage()
    ctx.closePDF()

    print("prefs icon: \(path.path)")
}
