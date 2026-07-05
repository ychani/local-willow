// Renders the iOS app icon: full-bleed dark tile + white waveform
// (iOS applies its own corner mask; no transparency allowed).
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let full = NSRect(x: 0, y: 0, width: size, height: size)
let gradient = NSGradient(colors: [
    NSColor(calibratedWhite: 0.17, alpha: 1),
    NSColor(calibratedWhite: 0.09, alpha: 1),
    NSColor(calibratedWhite: 0.03, alpha: 1),
], atLocations: [0.0, 0.55, 1.0], colorSpace: .deviceRGB)!
gradient.draw(in: NSBezierPath(rect: full), angle: -60)

let heights: [CGFloat] = [0.16, 0.30, 0.50, 0.64, 0.44, 0.26, 0.14]
let barWidth = size * 0.05
let gap = size * 0.04
let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = size / 2 - totalWidth / 2
NSColor.white.setFill()
for h in heights {
    let barHeight = size * h * 0.82
    let bar = NSRect(x: x, y: size / 2 - barHeight / 2, width: barWidth, height: barHeight)
    NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    x += barWidth + gap
}

img.unlockFocus()
guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("render failed")
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
