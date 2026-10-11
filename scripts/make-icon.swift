// Writes an app icon as an Icon Composer document (.icon): a vertical gradient fill and one
// white SF Symbol glass layer. macOS 26 renders .icon icons natively; old .icns icons get shrunk into
// a grey frame. bundle.sh compiles the document with actool.
// usage: xcrun swift scripts/make-icon.swift <out.icon> <top hex> <bottom hex> <sf symbol>
// myClips: xcrun swift scripts/make-icon.swift Resources/AppIcon.icon FB923C EA580C list.clipboard.fill
import AppKit
import SwiftUI

let args = CommandLine.arguments
guard args.count == 5 else {
    print("usage: make-icon.swift <out.icon> <top hex> <bottom hex> <sf symbol>")
    exit(2)
}

func components(_ hex: String) -> String {
    let value = UInt32(hex, radix: 16) ?? 0
    let parts = [value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF].map { String(format: "%.5f", Double($0) / 255) }
    return "srgb:" + parts.joined(separator: ",") + ",1.00000"
}

let symbol = args[4]
guard NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else {
    print("unknown SF Symbol \(symbol)")
    exit(1)
}

func color(_ hex: String) -> Color {
    let value = UInt32(hex, radix: 16) ?? 0
    return Color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
}

/// The glyph on a transparent 1024 canvas: white, with secondary details (e.g. a clipboard's lines)
/// in the bottom gradient colour.
struct Glyph: View {
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 500, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(color(args[3]), .white)
            .frame(width: 1024, height: 1024)
    }
}

let iconJSON = """
{
  "fill" : {
    "linear-gradient" : [
      "\(components(args[2]))",
      "\(components(args[3]))"
    ]
  },
  "groups" : [
    {
      "layers" : [
        {
          "glass" : true,
          "image-name" : "glyph.png",
          "name" : "glyph"
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : true,
        "value" : 0.4
      }
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}

"""

// Script top level runs on the main thread; ImageRenderer needs the main actor.
try MainActor.assumeIsolated {
    let out = URL(filePath: args[1])
    let assets = out.appending(path: "Assets")
    try? FileManager.default.removeItem(at: out)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    let renderer = ImageRenderer(content: Glyph())
    renderer.scale = 1
    let png = NSBitmapImageRep(cgImage: renderer.cgImage!).representation(using: .png, properties: [:])!
    try png.write(to: assets.appending(path: "glyph.png"))
    try iconJSON.write(to: out.appending(path: "icon.json"), atomically: true, encoding: .utf8)
    print("wrote \(out.path)")
}
