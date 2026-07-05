// Renders the LocalWillow app icon: deep-green gradient squircle with a white
// voice-waveform mark. Original design (not the Willow Voice trademark).
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// --- Background squircle -------------------------------------------------
let inset: CGFloat = size * 0.09  // macOS icon grid margin
let box = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = box.width * 0.235    // Big Sur-style corner ratio
let squircle = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

// Soft drop shadow behind the tile
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
shadow.shadowBlurRadius = size * 0.02
shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.withAlphaComponent(0.001).setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

// Diagonal emerald gradient
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.22, green: 0.78, blue: 0.55, alpha: 1),  // spring green
    NSColor(calibratedRed: 0.10, green: 0.47, blue: 0.34, alpha: 1),  // emerald
    NSColor(calibratedRed: 0.04, green: 0.24, blue: 0.18, alpha: 1),  // deep forest
], atLocations: [0.0, 0.55, 1.0], colorSpace: .deviceRGB)!
gradient.draw(in: squircle, angle: -60)

// Subtle top sheen for depth
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
let sheen = NSGradient(starting: NSColor.white.withAlphaComponent(0.18),
                       ending: NSColor.white.withAlphaComponent(0.0))!
sheen.draw(in: NSRect(x: box.minX, y: box.midY + box.height * 0.18,
                      width: box.width, height: box.height * 0.32), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// --- Waveform mark --------------------------------------------------------
// Seven capsules, heights arced like a spoken word's energy envelope.
let heights: [CGFloat] = [0.16, 0.30, 0.50, 0.64, 0.44, 0.26, 0.14]
let barWidth = box.width * 0.055
let gap = box.width * 0.045
let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = box.midX - totalWidth / 2

NSGraphicsContext.saveGraphicsState()
let barShadow = NSShadow()
barShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
barShadow.shadowBlurRadius = size * 0.012
barShadow.shadowOffset = NSSize(width: 0, height: -size * 0.006)
barShadow.set()
NSColor.white.setFill()
for h in heights {
    let barHeight = box.height * h
    let bar = NSRect(x: x, y: box.midY - barHeight / 2, width: barWidth, height: barHeight)
    NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    x += barWidth + gap
}
NSGraphicsContext.restoreGraphicsState()

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("render failed")
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
