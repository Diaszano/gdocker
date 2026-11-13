// Draws the app icon: three stacked containers on a blue squircle. Usage: swift scripts/make_icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat) in CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

// Background: macOS icon grid (824pt body, 100pt margin) with a vertical gradient and soft shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(squircle)
ctx.setFillColor(rgb(20, 60, 140))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let gradient = CGGradient(colorsSpace: nil, colors: [rgb(64, 156, 255), rgb(22, 72, 170)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

// Three containers, each slightly offset to read as a stack; ribs give the shipping-container look.
func container(_ rect: CGRect, fill: CGColor) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 14, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 26, cornerHeight: 26, transform: nil))
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.setStrokeColor(CGColor(srgbRed: 22 / 255, green: 72 / 255, blue: 170 / 255, alpha: 0.28))
    ctx.setLineWidth(12)
    ctx.setLineCap(.round)
    let ribs = 6
    for i in 1..<ribs {
        let x = rect.minX + rect.width * CGFloat(i) / CGFloat(ribs)
        ctx.move(to: CGPoint(x: x, y: rect.minY + 30))
        ctx.addLine(to: CGPoint(x: x, y: rect.maxY - 30))
    }
    ctx.strokePath()
}
container(CGRect(x: 262, y: 250, width: 500, height: 150), fill: rgb(255, 255, 255))
container(CGRect(x: 232, y: 437, width: 500, height: 150), fill: rgb(232, 242, 255))
container(CGRect(x: 292, y: 624, width: 500, height: 150), fill: rgb(255, 255, 255))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
