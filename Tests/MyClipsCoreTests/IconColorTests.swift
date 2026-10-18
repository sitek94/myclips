import Testing

@testable import MyClipsCore

@Suite struct IconColorTests {
    /// `count` opaque pixels of one color.
    private func pixels(_ red: UInt8, _ green: UInt8, _ blue: UInt8, count: Int, alpha: UInt8 = 255) -> [UInt8] {
        Array(repeating: [red, green, blue, alpha], count: count).flatMap(\.self)
    }

    @Test func picksTheMostCommonColorNotTheMostCommonPixel() throws {
        // A mostly white icon with a large blue mark and a small red one.
        let icon = pixels(255, 255, 255, count: 500) + pixels(30, 90, 220, count: 200) + pixels(220, 30, 30, count: 50)
        let color = try #require(IconColor.pick(rgba: icon))
        #expect(color.blue > color.red && color.blue > color.green)
    }

    @Test func grayAndClearIconsHaveNoColor() {
        let icon = pixels(128, 128, 128, count: 300) + pixels(255, 0, 0, count: 300, alpha: 0)
        #expect(IconColor.pick(rgba: icon) == nil)
    }

    @Test func paleColorsBecomeVividAndBright() throws {
        let color = try #require(IconColor.pick(rgba: pixels(240, 160, 160, count: 10)))
        let hsb = HSB(color)
        #expect(abs(hsb.saturation - 0.85) < 0.01)
        #expect(abs(hsb.brightness - 0.94) < 0.01)
    }

    @Test func darkColorsStayDark() throws {
        let color = try #require(IconColor.pick(rgba: pixels(20, 30, 80, count: 10)))
        #expect(abs(HSB(color).brightness - 80.0 / 255) < 0.01)
    }

    @Test func hsbRoundTrips() {
        for rgb in [RGB(red: 0.2, green: 0.6, blue: 0.9), RGB(red: 0.9, green: 0.1, blue: 0.5), RGB(red: 0.4, green: 0.8, blue: 0.1)] {
            let back = HSB(rgb).rgb
            #expect(abs(back.red - rgb.red) < 0.001 && abs(back.green - rgb.green) < 0.001 && abs(back.blue - rgb.blue) < 0.001)
        }
    }
}
