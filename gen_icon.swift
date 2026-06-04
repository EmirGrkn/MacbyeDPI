#!/usr/bin/swift
import Cocoa

let outputPath = CommandLine.arguments[1]
let canvasSize = 512

let symbolConfig = NSImage.SymbolConfiguration(pointSize: CGFloat(canvasSize) * 0.72, weight: .medium)
guard let symbol = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: nil),
      let configured = symbol.withSymbolConfiguration(symbolConfig) else {
    fputs("Error: could not load SF Symbol shield.fill\n", stderr)
    exit(1)
}

let canvas = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
canvas.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()
let sx = (CGFloat(canvasSize) - configured.size.width)  / 2
let sy = (CGFloat(canvasSize) - configured.size.height) / 2
configured.draw(in: NSRect(x: sx, y: sy, width: configured.size.width, height: configured.size.height))
canvas.unlockFocus()

guard let tiff   = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png    = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Error: failed to render PNG\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
