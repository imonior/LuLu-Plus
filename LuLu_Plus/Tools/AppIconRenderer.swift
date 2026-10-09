// Renders the macOS app-icon sizes from one square source image.
//
// The source is drawn into a squircle tile on Apple's macOS icon grid (an 824 pt body on a
// 1024 pt canvas) so the result sits next to other Mac icons instead of looking like a
// full-bleed square. Run through make_app_icon.sh, not directly.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let usage = "usage: AppIconRenderer <source.png> <out-dir>\n"

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(usage.data(using: .utf8)!)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let art = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("cannot read \(sourceURL.path)\n".data(using: .utf8)!)
    exit(3)
}

let canvas = 1024
let body = 824

// the macOS icon body is a squircle, not a circular rounded rectangle
func squircle(body: CGFloat, in canvas: CGFloat, exponent: Double) -> CGPath {
    let path = CGMutablePath()
    let rect = CGRect(x: (canvas - body) / 2, y: (canvas - body) / 2, width: body, height: body)
    let cx = rect.midX
    let cy = rect.midY
    let a = rect.width / 2
    let b = rect.height / 2
    let steps = 1440
    for step in 0...steps {
        let t = 2 * Double.pi * Double(step) / Double(steps)
        let ct = cos(t)
        let st = sin(t)
        let x = cx + CGFloat(copysign(pow(abs(ct), 2 / exponent), ct)) * a
        let y = cy + CGFloat(copysign(pow(abs(st), 2 / exponent), st)) * b
        if 0 == step {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

func context(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write("cannot write \(url.path)\n".data(using: .utf8)!)
        exit(4)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        FileHandle.standardError.write("cannot finalize \(url.path)\n".data(using: .utf8)!)
        exit(5)
    }
}

//master
let master = context(canvas)
let tile = squircle(body: CGFloat(body), in: CGFloat(canvas), exponent: 5.0)
let artRect = CGRect(x: (canvas - body) / 2, y: (canvas - body) / 2, width: body, height: body)

// the tile's own shadow, painted under an opaque white backing so the artwork covers it
master.saveGState()
master.setShadow(offset: CGSize(width: 0, height: -14), blur: 26,
                 color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
master.addPath(tile)
master.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
master.fillPath()
master.restoreGState()

master.saveGState()
master.addPath(tile)
master.clip()
master.draw(art, in: artRect)
master.restoreGState()

guard let masterImage = master.makeImage() else { exit(6) }

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for (name, size) in sizes {
    let ctx = context(size)
    ctx.draw(masterImage, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let image = ctx.makeImage() else { exit(7) }
    write(image, to: outDir.appendingPathComponent(name))
    print("\(name) (\(size)px)")
}
