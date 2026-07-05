// Renders the LocalWillow app icon: willow-green rounded square + white mic glyph.
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let inset: CGFloat = size * 0.09  // macOS icon grid margin
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.2, yRadius: size * 0.2)
let gradient = NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.42, blue: 0.30, alpha: 1),
                          ending: NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.16, alpha: 1))!
gradient.draw(in: path, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .medium)
if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: mic.size)
    tinted.lockFocus()
    mic.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: mic.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    let s = mic.size
    let scale = (size * 0.45) / max(s.width, s.height)
    let w = s.width * scale, h = s.height * scale
    tinted.draw(in: NSRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h))
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("render failed")
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
