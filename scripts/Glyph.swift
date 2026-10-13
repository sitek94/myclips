import SwiftUI

// The myClips glyph: a clipboard with lines of text. Our own drawing (SF Symbols may not be used in app icons),
// rendered by `scripts/make-icon.sh`, which compiles this file with `make-glyph.swift`.

/// The clipboard on a unit square: a white board and clip, the text lines and the clip's outline in `detail`.
struct ClipboardGlyph: View {
    let detail: Color

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: side * 0.1, style: .continuous)
                    .fill(.white)
                    .frame(width: side * 0.62, height: side * 0.76)
                    .offset(x: side * 0.19, y: side * 0.18)
                // The clip: white, outlined in the detail color where it overlaps the board.
                Circle()
                    .strokeBorder(.white, lineWidth: side * 0.035)
                    .frame(width: side * 0.13, height: side * 0.13)
                    .offset(x: side * 0.435, y: side * 0.04)
                RoundedRectangle(cornerRadius: side * 0.05, style: .continuous)
                    .fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: side * 0.05, style: .continuous).strokeBorder(detail, lineWidth: side * 0.025))
                    .frame(width: side * 0.34, height: side * 0.13)
                    .offset(x: side * 0.33, y: side * 0.13)
                ForEach(0..<3) { line in
                    Capsule()
                        .fill(detail)
                        .frame(width: side * (line == 2 ? 0.2 : 0.36), height: side * 0.055)
                        .offset(x: side * 0.32, y: side * (0.45 + Double(line) * 0.13))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
