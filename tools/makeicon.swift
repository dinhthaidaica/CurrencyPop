// Writes CurrencyPop.icns from the same symbol and teal the panel uses.
// Run once after changing the mark:  swift tools/makeicon.swift
// The .icns is committed, so a normal build never needs this.

import AppKit

let deep = NSColor(srgbRed: 0.04, green: 0.31, blue: 0.27, alpha: 1)
let bright = NSColor(srgbRed: 0.11, green: 0.60, blue: 0.50, alpha: 1)

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple leaves the outer ~8.5% clear and rounds at 22.37% of the content box.
    let inset = size * 0.085
    let box = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = box.width * 0.2237
    let plate = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
    NSGradient(starting: bright, ending: deep)!.draw(in: plate, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: box.width * 0.46, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "arrow.left.arrow.right",
                            accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        // Tint in a scratch image: filling .sourceAtop straight onto the canvas
        // would paint the plate white as well.
        let glyph = NSImage(size: symbol.size)
        glyph.lockFocus()
        symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
        glyph.unlockFocus()

        glyph.draw(in: NSRect(x: box.midX - symbol.size.width / 2,
                              y: box.midY - symbol.size.height / 2,
                              width: symbol.size.width, height: symbol.size.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("CurrencyPop.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path,
                      "-o", root.appendingPathComponent("CurrencyPop.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)

print(iconutil.terminationStatus == 0 ? "wrote CurrencyPop.icns" : "iconutil failed")
exit(iconutil.terminationStatus)
