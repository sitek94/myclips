import AudioToolbox
import Foundation

/// A short sound when a clip is saved and when clips are pasted. The user picks each sound by name from the sound
/// folders, their own `~/Library/Sounds` first; the defaults are built-in macOS sounds.
@MainActor
final class Sounds {
    enum Event: String, CaseIterable {
        case save, paste

        var defaultName: String {
            switch self {
            case .save: "Pop"
            case .paste: "Tink"
            }
        }
    }

    static let folders = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Sounds"),
        URL(filePath: "/Library/Sounds"),
        URL(filePath: "/System/Library/Sounds"),
    ]
    static let fileTypes: Set<String> = ["aiff", "aif", "caf", "wav", "mp3", "m4a"]

    /// System sounds, created once per file.
    private var ids: [URL: SystemSoundID] = [:]

    func play(named name: String) {
        guard let url = Self.url(named: name) else { return }
        if ids[url] == nil {
            var id: SystemSoundID = 0
            guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr else { return }
            ids[url] = id
        }
        if let id = ids[url] { AudioServicesPlaySystemSound(id) }
    }

    /// Every sound name in the folders, sorted; a name in more than one folder is listed once.
    static func names() -> [String] {
        Array(Set(folders.flatMap(files).map { $0.deletingPathExtension().lastPathComponent }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The first folder's file with this name wins.
    static func url(named name: String) -> URL? {
        folders.lazy.flatMap(files).first { $0.deletingPathExtension().lastPathComponent == name }
    }

    private static func files(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { fileTypes.contains($0.pathExtension.lowercased()) }
    }
}
