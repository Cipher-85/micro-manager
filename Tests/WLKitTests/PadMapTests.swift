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

    func testLandConfirmPassesOnlyTheLandAction() {
        XCTAssertTrue(PadMap.passesLandConfirm(.gitButlerLand))
        XCTAssertFalse(PadMap.passesLandConfirm(.gitButlerStatus))
        XCTAssertFalse(PadMap.passesLandConfirm(.unbound))
        XCTAssertFalse(PadMap.passesLandConfirm(.focusSlot(0)))
        XCTAssertFalse(PadMap.passesLandConfirm(.herdr("next_tab")))
    }

    func testCloseConfirmPassesOnlyTheArmedCloseAction() {
        XCTAssertTrue(PadMap.passesCloseConfirm(.herdr("close_pane"), armed: "close_pane"))
        XCTAssertTrue(PadMap.passesCloseConfirm(.herdr("close_tab"), armed: "close_tab"))
        XCTAssertFalse(PadMap.passesCloseConfirm(.herdr("close_tab"), armed: "close_pane"))
        XCTAssertFalse(PadMap.passesCloseConfirm(.herdr("next_tab"), armed: "close_pane"))
        XCTAssertFalse(PadMap.passesCloseConfirm(.gitButlerLand, armed: "close_pane"))
        XCTAssertFalse(PadMap.passesCloseConfirm(.herdr("close_pane"), armed: nil))
        XCTAssertFalse(PadMap.passesCloseConfirm(.herdr("next_tab"), armed: "next_tab"))
    }

    func testCloseNamesAreInTheHerdrCatalog() {
        for name in PadCatalog.closeNames {
            XCTAssertTrue(PadCatalog.herdrNames.contains(name), name)
        }
    }

    // MARK: - Encode and save

    private func roundTrip(_ map: PadMap) throws -> PadMap {
        let data = try JSONSerialization.data(withJSONObject: ["map": map.encodedMap()])
        return PadMap.parse(data)
    }

    /// Never the live micromanager config — a unique temp path per call.
    private func tempConfigPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("padmap-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
            .path
    }

    func testDefaultsEncodeRoundTrips() throws {
        XCTAssertEqual(try roundTrip(PadMap()), PadMap())
    }

    func testHerdrAndMacroEncodeRoundTrip() throws {
        var map = PadMap()
        map.set(.herdr("zoom"), for: 7)
        map.set(.injectPrompt("Ship it"), for: 9)
        let loaded = try roundTrip(map)
        XCTAssertEqual(loaded.action(for: 7), .herdr("zoom"))
        XCTAssertEqual(loaded.action(for: 9), .injectPrompt("Ship it"))
    }

    func testWideKeyEncodesAsCombinedId() {
        let encoded = PadMap().encodedMap()
        XCTAssertNotNil(encoded["10+11"])
        XCTAssertNil(encoded["10"])
        XCTAssertNil(encoded["11"])
    }

    func testSetOnWideKeySetsBothHalves() {
        var map = PadMap()
        map.set(.gitButlerLand, for: 10)
        XCTAssertEqual(map.action(for: 10), .gitButlerLand)
        XCTAssertEqual(map.action(for: 11), .gitButlerLand)
    }

    func testSaveMergesPreservingOtherKeys() throws {
        let path = tempConfigPath()
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try #"{"claude":{"x":1},"keys":{"9":"old"},"codex":{"y":true}}"#
            .write(toFile: path, atomically: true, encoding: .utf8)

        var map = PadMap()
        map.set(.voice, for: 9)
        try PadMap.save(map, to: path)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((json["claude"] as? [String: Any])?["x"] as? Int, 1)
        XCTAssertEqual((json["keys"] as? [String: Any])?["9"] as? String, "old")
        XCTAssertEqual((json["codex"] as? [String: Any])?["y"] as? Bool, true)
        XCTAssertEqual(PadMap.parse(data).action(for: 9), .voice)
    }

    func testSaveCreatesMissingParentDirectory() throws {
        let path = tempConfigPath()
        try PadMap.save(PadMap(), to: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testSaveUnboundKeyRoundTrips() throws {
        let path = tempConfigPath()
        var map = PadMap()
        map.set(.unbound, for: 6)
        try PadMap.save(map, to: path)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(PadMap.parse(data).action(for: 6), .unbound)
    }
}
