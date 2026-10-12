import Carbon.HIToolbox

/// Which keys belong to the shelf's search field. When the field has text, standard text-editing keys act on
/// the text; list keys act on the clips only when the field is empty, or when a text field has no use for the key.
public enum SearchFieldKeys {
    public struct Key: Sendable {
        public var code: Int
        public var command: Bool
        public var option: Bool
        /// The character typed with ⌘, matched by character so shortcuts follow the keyboard layout.
        public var commandLetter: String?

        public init(code: Int, command: Bool = false, option: Bool = false, commandLetter: String? = nil) {
            self.code = code
            self.command = command
            self.option = option
            self.commandLetter = commandLetter
        }
    }

    /// True when the key goes to the search field instead of the clips.
    public static func ownsKey(_ key: Key, fieldHasText: Bool, textSelected: Bool) -> Bool {
        guard fieldHasText else { return false }
        switch key.commandLetter {
        case "a", "x", "v", "z": return true
        case "c": return textSelected
        default: break
        }
        switch key.code {
        case kVK_Delete where key.command: return true
        // Plain arrows move between clips: the shelf is a horizontal row.
        case kVK_LeftArrow, kVK_RightArrow: return key.command || key.option
        default: return false
        }
    }
}
