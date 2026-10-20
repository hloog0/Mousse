// Draws the Mousse app icon with Core Graphics and writes:
//   Resources/AppIcon.icns   bundled into the app by build.sh
//   docs/icon.png            256 px copy for the README
// Run from the repo root:  swift scripts/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)

func hex(_ v: UInt32) -> RGB {
    (CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
}

func color(_ c: RGB, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
}

// "Mint": teal-green tile, teal scroll wheel.
let tileTop = hex(0x4FE3BC), tileBottom = hex(0x0E8F86), wheelColor = hex(0x10A596)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// macOS-style continuous-corner tile: a superellipse filling the standard 824 pt icon body.
func squircle(center: CGPoint, half: CGFloat, n: CGFloat = 4) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let point = CGPoint(x: center.x + half * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n),
                            y: center.y + half * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func fillGradient(_ ctx: CGContext, _ colors: [CGColor], locations: [CGFloat]? = nil, from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [])
}

/// Draws the icon in a 1024×1024 space (origin bottom-left).
func drawIcon(_ ctx: CGContext) {
    let tile = squircle(center: CGPoint(x: 512, y: 512), half: 412)

    // Tile with a soft drop shadow, then its gradient and a sheen across the top.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(tile)
    ctx.setFillColor(color(tileBottom))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    fillGradient(ctx, [color(tileTop), color(tileBottom)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    fillGradient(ctx, [CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0)],
                 from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 560))

    // Motion streaks either side of the mouse, fading at both ends: the page gliding past.
    let streaks: [(dx: CGFloat, y: CGFloat, length: CGFloat, alpha: CGFloat, width: CGFloat)] = [
        (250, 300, 380, 0.6, 30), (330, 360, 250, 0.35, 26),
    ]
    for streak in streaks {
        for side in [-1.0, 1.0] as [CGFloat] {
            let rect = CGRect(x: 512 + side * streak.dx - streak.width / 2, y: streak.y,
                              width: streak.width, height: streak.length)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: streak.width / 2, cornerHeight: streak.width / 2, transform: nil))
            ctx.clip()
            fillGradient(ctx, [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: streak.alpha), CGColor(gray: 1, alpha: 0)],
                         locations: [0, 0.5, 1],
                         from: CGPoint(x: rect.midX, y: rect.minY), to: CGPoint(x: rect.midX, y: rect.maxY))
            ctx.restoreGState()
        }
    }

    // The mouse: a white pill with a soft shadow and a seam between the buttons.
    let body = CGPath(roundedRect: CGRect(x: 357, y: 215, width: 310, height: 510),
                      cornerWidth: 155, cornerHeight: 155, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(body)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    fillGradient(ctx, [CGColor(gray: 1, alpha: 1), color((0.90, 0.92, 0.95))],
                 from: CGPoint(x: 512, y: 725), to: CGPoint(x: 512, y: 215))
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.12))
    ctx.setLineWidth(7)
    ctx.move(to: CGPoint(x: 512, y: 725))
    ctx.addLine(to: CGPoint(x: 512, y: 530))
    ctx.strokePath()
    ctx.restoreGState()

    // Scroll wheel.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 487, y: 560, width: 50, height: 112),
                       cornerWidth: 25, cornerHeight: 25, transform: nil))
    ctx.clip()
    fillGradient(ctx, [color(wheelColor), color(wheelColor, 0.75)], from: CGPoint(x: 512, y: 672), to: CGPoint(x: 512, y: 560))
    ctx.restoreGState()

    ctx.restoreGState()
}

func render(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "couldn't write \(url.path)")
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

// Each size is drawn from the vectors, not scaled down, so small sizes stay crisp.
for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")

try fm.createDirectory(atPath: "docs", withIntermediateDirectories: true)
writePNG(render(size: 256), to: URL(fileURLWithPath: "docs/icon.png"))
print("Wrote Resources/AppIcon.icns and docs/icon.png")
