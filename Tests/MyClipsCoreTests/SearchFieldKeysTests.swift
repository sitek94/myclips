import Carbon.HIToolbox
import Testing

@testable import MyClipsCore

// Regression for https://github.com/sitek94/myclips/issues/1: ⌘A, ⌘⌫ and ⌥/⌘ arrows acted on the clips
// while the search field had text.
struct SearchFieldKeysTests {
    typealias Key = SearchFieldKeys.Key

    static let textKeys = [
        Key(code: kVK_ANSI_A, command: true, commandLetter: "a"),
        Key(code: kVK_Delete, command: true),
        Key(code: kVK_LeftArrow, option: true),
        Key(code: kVK_RightArrow, command: true),
    ]

    @Test(arguments: textKeys)
    func textEditingKeysGoToTheFieldWhileItHasText(key: Key) {
        #expect(SearchFieldKeys.ownsKey(key, fieldHasText: true, textSelected: false))
    }

    @Test(arguments: textKeys)
    func theSameKeysActOnClipsWhenTheFieldIsEmpty(key: Key) {
        #expect(!SearchFieldKeys.ownsKey(key, fieldHasText: false, textSelected: false))
    }

    @Test func copyGoesToTheFieldOnlyWithSelectedText() {
        let copy = Key(code: kVK_ANSI_C, command: true, commandLetter: "c")
        #expect(SearchFieldKeys.ownsKey(copy, fieldHasText: true, textSelected: true))
        #expect(!SearchFieldKeys.ownsKey(copy, fieldHasText: true, textSelected: false))
    }

    @Test func listKeysStayWithTheClipsWhileTyping() {
        let keys = [
            Key(code: kVK_RightArrow), Key(code: kVK_Return), Key(code: kVK_ANSI_1, command: true, commandLetter: "1"),
            Key(code: kVK_ANSI_K, command: true, commandLetter: "k"),
        ]
        for key in keys {
            #expect(!SearchFieldKeys.ownsKey(key, fieldHasText: true, textSelected: false))
        }
    }
}
