// Renders the app icon's glyph (a 1024 × 1024 PNG on a transparent background) from our own drawing in
// scripts/Glyph.swift: a white clipboard, its lines in the icon's 600 shade.
// usage: scripts/make-icon.sh (renders the glyph, then builds the icon)
import AppKit
import SwiftUI

@main
struct MakeGlyph {
    @MainActor static func main() throws {
        let shade600 = Color(red: 0xEA / 255, green: 0x58 / 255, blue: 0x0C / 255)
        let glyph = ClipboardGlyph(detail: shade600).frame(width: 700, height: 700).frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: glyph)
        renderer.scale = 1
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: URL(filePath: CommandLine.arguments[1]))
    }
}
