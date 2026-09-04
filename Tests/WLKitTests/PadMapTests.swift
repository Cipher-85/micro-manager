import XCTest
@testable import WLKit

final class PadMapTests: XCTestCase {

    private func parse(_ json: String) -> PadMap {
        PadMap.parse(Data(json.utf8))
    }

    func testMissingFileMeansDefaults() {
        let map = PadMap()
        XCTAssertEqual(map.action(for: 1), .focusSlot(0))
        XCTAssertEqual(map.action(for: 0), .focusSlot(1))
        XCTAssertEqual(map.action(for: 2), .focusSlot(2))
        XCTAssertEqual(map.action(for: 3), .focusSlot(3))
        XCTAssertEqual(map.action(for: 4), .focusSlot(4))
        XCTAssertEqual(map.action(for: 5), .focusSlot(5))
        XCTAssertEqual(map.action(for: 6), .gitButlerStatus)
        XCTAssertEqual(map.action(for: 7), .herdr("next_tab"))
        XCTAssertEqual(map.action(for: 8), .gitButlerLand)
        XCTAssertEqual(map.action(for: 9), .injectPrompt("Open PRs for all active GitButler branches"))
        XCTAssertEqual(map.action(for: 10), .voice)
        XCTAssertEqual(map.action(for: 11), .voice)
        XCTAssertEqual(map.action(for: 12), .injectPrompt("Run but pull"))
        XCTAssertEqual(map.action(for: 13), .effort(step: 1))
        XCTAssertEqual(map.action(for: 14), .effort(step: -1))
        XCTAssertEqual(map.action(for: 15), .model(.north))
        XCTAssertEqual(map.action(for: 16), .model(.west))
        XCTAssertEqual(map.action(for: 17), .model(.south))
        XCTAssertEqual(map.action(for: 18), .model(.east))
        XCTAssertEqual(map.action(for: 9), .injectPrompt(KeyBindings.defaults[9]!))
        XCTAssertEqual(map.action(for: 12), .injectPrompt(KeyBindings.defaults[12]!))
    }

    func testEmptyAndMalformedFileFallBackToDefaults() {
        XCTAssertEqual(parse(""), PadMap())
        XCTAssertEqual(parse("not json"), PadMap())
        XCTAssertEqual(parse(#"{"map": "nope"}"#), PadMap())
        XCTAssertEqual(parse("{}"), PadMap())
    }

    func testKeysOverrideAKeyAndKeepTheOtherDefault() {
        let map = parse(#"{"keys": {"9": "Ship it"}}"#)
        XCTAssertEqual(map.action(for: 9), .injectPrompt("Ship it"))
        XCTAssertEqual(map.action(for: 12), .injectPrompt("Run but pull"))
    }

    /// "10+11" is the wide key spoken of as one: both halves get the action.
    func testKeysWideKeyBindsBothHalves() {
        let map = parse(#"{"keys": {"10+11": "Summarise your progress"}}"#)
        XCTAssertEqual(map.action(for: 10), .injectPrompt("Summarise your progress"))
        XCTAssertEqual(map.action(for: 11), .injectPrompt("Summarise your progress"))
    }

    /// An empty string unbinds: the key goes dark rather than typing nothing.
    func testEmptyKeysStringUnbindsADefault() {
        let map = parse(#"{"keys": {"12": ""}}"#)
        XCTAssertEqual(map.action(for: 12), .unbound)
        XCTAssertEqual(map.action(for: 9), .injectPrompt("Open PRs for all active GitButler branches"))
    }

    func testMapOverlayReplacesOneKeyAndKeepsTheNeighbour() {
        let map = parse(#"{"map": {"6": {"action": "voice"}}}"#)
        XCTAssertEqual(map.action(for: 6), .voice)
        XCTAssertEqual(map.action(for: 7), .herdr("next_tab"))
    }

    func testMapWinsOverKeysOnTheSameId() {
        let map = parse(#"{"keys": {"9": "from keys"}, "map": {"9": {"action": "voice"}}}"#)
        XCTAssertEqual(map.action(for: 9), .voice)
    }

    func testUnknownActionUnbindsThatKeyOnly() {
        let map = parse(#"{"map": {"6": {"action": "explode"}}}"#)
        XCTAssertEqual(map.action(for: 6), .unbound)
        XCTAssertEqual(map.action(for: 7), .herdr("next_tab"))
    }

    func testMapWideKeyBindsBothHalves() {
        let map = parse(#"{"map": {"10+11": {"action": "gitButlerStatus"}}}"#)
        XCTAssertEqual(map.action(for: 10), .gitButlerStatus)
        XCTAssertEqual(map.action(for: 11), .gitButlerStatus)
    }

    func testDialAndStickOverlay() {
        let map = parse(#"""
        {"map": {
          "dial": {
            "cw":  {"action": "effort", "step": 2},
            "ccw": {"action": "effort", "step": -2}
          },
          "stick": {
            "n": {"action": "voice"},
            "w": {"action": "gitButlerStatus"},
            "s": {"action": "gitButlerLand"},
            "e": {"action": "injectPrompt", "text": "stick east"}
          }
        }}
        """#)
        XCTAssertEqual(map.action(for: 13), .effort(step: 2))
        XCTAssertEqual(map.action(for: 14), .effort(step: -2))
        XCTAssertEqual(map.action(for: 15), .voice)
        XCTAssertEqual(map.action(for: 16), .gitButlerStatus)
        XCTAssertEqual(map.action(for: 17), .gitButlerLand)
        XCTAssertEqual(map.action(for: 18), .injectPrompt("stick east"))
        XCTAssertEqual(map.action(for: 7), .herdr("next_tab"))
    }
}
