import Foundation

public enum ClipKind: String, Sendable, CaseIterable {
    case text, link, image, file
}

/// One pasteboard type's bytes. `item` is the index of the pasteboard item it came from.
public struct Representation: Sendable, Hashable {
    public var item: Int
    public var type: String
    public var data: Data

    public init(item: Int, type: String, data: Data) {
        self.item = item
        self.type = type
        self.data = data
    }
}

/// A capture ready to be recorded.
public struct ClipPayload: Sendable {
    public var kind: ClipKind
    /// Searchable text: the string content, or file paths for files.
    public var text: String
    public var representations: [Representation]
    public var sourceBundleID: String?
    public var sourceName: String?

    public init(kind: ClipKind, text: String, representations: [Representation], sourceBundleID: String? = nil, sourceName: String? = nil) {
        self.kind = kind
        self.text = text
        self.representations = representations
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
    }

    public var byteSize: Int { representations.reduce(0) { $0 + $1.data.count } }
}

public struct Clip: Sendable, Identifiable, Hashable {
    public let id: Int64
    public let kind: ClipKind
    /// Up to the first 1,000 characters of the searchable text.
    public let preview: String
    public let sourceBundleID: String?
    public let sourceName: String?
    public let createdAt: Date
    public let usedAt: Date
    public let byteSize: Int
    /// Pinned to the top of history.
    public let isPinned: Bool
}

public struct Pinboard: Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let itemCount: Int
}

extension Clip {
    /// "#4F46E5" or "4F46E5"; such a text clip shows as a swatch.
    public var hexRGB: RGB? {
        guard kind == .text else { return nil }
        let hex = preview.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("#")
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return RGB(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// A light swatch needs dark text on it: white text is hard to read on yellow or light gray.
    public var hexIsLight: Bool {
        guard let rgb = hexRGB else { return false }
        // Perceived brightness (Rec. 601 weights).
        return 0.299 * rgb.red + 0.587 * rgb.green + 0.114 * rgb.blue > 0.65
    }
}

/// A color's red, green and blue, from 0 to 1.
public struct RGB: Sendable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double
}
