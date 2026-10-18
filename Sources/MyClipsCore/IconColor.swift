/// The color of a card's header, picked from the source app's icon: the most common clearly colored pixel, made
/// vivid enough to carry white text. Gray icons have no such pixel; the caller falls back to gray.
public enum IconColor {
    /// For apps without an icon or a clear color.
    public static let gray = RGB(red: 0.5, green: 0.5, blue: 0.5)

    /// `rgba`: 8-bit red, green, blue, alpha per pixel. Only opaque pixels count.
    public static func pick(rgba: [UInt8]) -> RGB? {
        // Pixels counted in 32 levels per channel, so antialiasing and gradients of one color count together.
        var buckets: [Int: Bucket] = [:]
        for offset in stride(from: 0, to: rgba.count - 3, by: 4) where rgba[offset + 3] == 255 {
            let red = Int(rgba[offset]), green = Int(rgba[offset + 1]), blue = Int(rgba[offset + 2])
            guard HSB(RGB(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)).saturation >= 0.25
            else { continue }
            let key = (red >> 3) << 10 | (green >> 3) << 5 | blue >> 3
            buckets[key, default: Bucket()].add(red, green, blue)
        }
        guard let top = buckets.values.max(by: { $0.count < $1.count }) else { return nil }
        var hsb = HSB(top.average)
        hsb.saturation = max(hsb.saturation, 0.85)
        // Dark colors stay dark; the rest become bright, but not glaring.
        if hsb.brightness > 0.4 { hsb.brightness = min(max(hsb.brightness, 0.75), 0.96) }
        return hsb.rgb
    }

    /// Pixels of nearly one color: how many, and their sums for the average.
    private struct Bucket {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0

        mutating func add(_ red: Int, _ green: Int, _ blue: Int) {
            count += 1
            self.red += red
            self.green += green
            self.blue += blue
        }

        var average: RGB {
            let total = Double(count) * 255
            return RGB(red: Double(red) / total, green: Double(green) / total, blue: Double(blue) / total)
        }
    }
}

/// Hue, saturation and brightness, from 0 to 1.
struct HSB {
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(_ rgb: RGB) {
        let high = max(rgb.red, rgb.green, rgb.blue)
        let low = min(rgb.red, rgb.green, rgb.blue)
        let range = high - low
        brightness = high
        saturation = high == 0 ? 0 : range / high
        guard range > 0 else {
            hue = 0
            return
        }
        let sector: Double
        switch high {
        case rgb.red: sector = (rgb.green - rgb.blue) / range
        case rgb.green: sector = (rgb.blue - rgb.red) / range + 2
        default: sector = (rgb.red - rgb.green) / range + 4
        }
        hue = (sector / 6).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
    }

    var rgb: RGB {
        let sector = hue * 6
        let chroma = brightness * saturation
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        // Red, green and blue before the lift, per sixth of the hue circle.
        let channels: [Double] =
            switch Int(sector) % 6 {
            case 0: [chroma, second, 0]
            case 1: [second, chroma, 0]
            case 2: [0, chroma, second]
            case 3: [0, second, chroma]
            case 4: [second, 0, chroma]
            default: [chroma, 0, second]
            }
        let lift = brightness - chroma
        return RGB(red: channels[0] + lift, green: channels[1] + lift, blue: channels[2] + lift)
    }
}
