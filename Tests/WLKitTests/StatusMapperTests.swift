import XCTest
import SwiftUI
@testable import WLKit

/// Mirrors test/status.test.js so the two implementations cannot drift.
final class StatusMapperTests: XCTestCase {

    private func agent(_ status: String, pane: String = "w1:p1") -> HerdrAgent {
        HerdrAgent(status: status, paneID: pane)
    }

    // MARK: - Aggregate

    func testNoAgentsMeansNoState() {
        XCTAssertNil(StatusMapper.aggregate([]))
    }

    func testBlockedOutranksWorkingAndIdle() {
        let state = StatusMapper.aggregate([
            agent("idle", pane: "w1:p1"),
            agent("working", pane: "w1:p2"),
            agent("blocked", pane: "w1:p3"),
        ])
        XCTAssertEqual(state, "blocked")
        XCTAssertEqual(StatusMapper.zone(for: state)?.color, 0xFF2D2D)
    }

    func testWorkingOutranksIdleAndDone() {
        let state = StatusMapper.aggregate([agent("done"), agent("idle"), agent("working")])
        XCTAssertEqual(state, "working")
        XCTAssertEqual(StatusMapper.zone(for: state)?.color, 0xFFA000)
    }

    func testUnrecognisedStatusStillYieldsAState() {
        XCTAssertEqual(StatusMapper.aggregate([agent("wat")]), "unknown")
    }

    func testBlockedBreathesSoItReadsDifferently() {
        XCTAssertEqual(StatusMapper.zone(for: "blocked")?.effect, .breath)
        XCTAssertEqual(StatusMapper.zone(for: "working")?.effect, .solid)
    }

    // MARK: - Per-key

    func testEachAgentGetsItsOwnKeyInReadingOrder() {
        let threads = StatusMapper.threads(for: [
            agent("working"), agent("blocked"), agent("idle"),
        ])
        XCTAssertEqual(threads.count, 6, "one entry per agent key")
        // The pad's top row is wired right to left, so reading order starts
        // at key 1: the first agent lights the top-LEFT key.
        XCTAssertEqual(threads.map(\.id), [1, 0, 2, 3, 4, 5], "keys in reading order")
        XCTAssertEqual(threads[0].color, 0xFFA000)
        XCTAssertEqual(threads[1].color, 0xFF2D2D)
        XCTAssertEqual(threads[2].color, 0x00C853)
    }

    func testKeysWithNoAgentAreSwitchedOffNotLeftStale() {
        let threads = StatusMapper.threads(for: [agent("working")])
        for thread in threads.dropFirst() {
            XCTAssertEqual(thread.effect, .off)
            XCTAssertEqual(thread.brightness, 0)
            XCTAssertNil(thread.color, "no colour on an unused key")
        }
    }

    func testBlockedAgentBreathesOnItsOwnKey() {
        let threads = StatusMapper.threads(for: [agent("idle"), agent("blocked")])
        XCTAssertEqual(threads[0].effect, .solid)
        XCTAssertEqual(threads[1].effect, .breath)
    }

    func testMoreAgentsThanKeysDoesNotOverflow() {
        let many = (0..<9).map { _ in agent("working") }
        XCTAssertEqual(StatusMapper.threads(for: many).count, 6)
    }

    func testConfigOverridesAreHonoured() {
        var cfg = BridgeConfig()
        cfg.colors["working"] = 0x123456
        cfg.brightness = 0.3
        let thread = StatusMapper.threads(for: [agent("working")], cfg)[0]
        XCTAssertEqual(thread.color, 0x123456)
        XCTAssertEqual(thread.brightness, 0.3)
    }

    // MARK: - Wire encoding

    func testThreadWireUsesAbbreviatedKeysAndNumericEffect() {
        let wire = OAI.Thread(id: 0, color: 0xFF0000, brightness: 1, effect: .solid, speed: 0.5).wire
        XCTAssertEqual(wire["id"] as? Int, 0)
        XCTAssertEqual(wire["c"] as? Int, 0xFF0000)
        XCTAssertEqual(wire["b"] as? Double, 1)
        XCTAssertEqual(wire["e"] as? Int, 1, "effect is a NUMBER, not a string")
        XCTAssertEqual(wire["s"] as? Double, 0.5)
        XCTAssertNil(wire["color"], "full field names are ignored by the firmware")
    }

    func testUnsetThreadFieldsAreOmittedSoTheyStayUnchanged() {
        let wire = OAI.Thread(id: 3, brightness: 0, effect: .off).wire
        XCTAssertNil(wire["c"])
        XCTAssertNil(wire["s"])
    }

    func testColourRoundTrip() {
        XCTAssertEqual(packedRGB(fromHex: "#FF2D2D"), 0xFF2D2D)
        XCTAssertEqual(packedRGB(fromHex: "00C853"), 0x00C853)
        XCTAssertEqual(packedRGB(fromHex: "#0f0"), 0x00FF00)
        XCTAssertEqual(hexString(0xFF2D2D), "#FF2D2D")
    }

    /// Slots follow the pad's reading order, so a slot must always resolve to
    /// the key that lights it and back.
    func testAgentSlotAndKeyAreInverses() {
        for (slot, key) in Pad.agentKeyIDs.enumerated() {
            XCTAssertEqual(Pad.agentSlot(for: key), slot)
        }
        XCTAssertNil(Pad.agentSlot(for: Pad.stackKeyID))
        XCTAssertNil(Pad.agentSlot(for: Pad.landKeyID))
    }

    // MARK: - AG key names

    func testAGNamesMapToKeyIndices() {
        XCTAssertEqual(OAI.agIndex("AG00"), 0)
        XCTAssertEqual(OAI.agIndex("AG05"), 5)
        XCTAssertEqual(OAI.agIndex("AG12"), 12)
        XCTAssertNil(OAI.agIndex("KC_F13"))
        XCTAssertNil(OAI.agIndex(nil))
    }

    // MARK: - Map lighting

    private func padMap(_ json: String) -> PadMap {
        PadMap.parse(Data(json.utf8))
    }

    private func thread(_ threads: [OAI.Thread], id: Int) -> OAI.Thread {
        threads.first { $0.id == id }!
    }

    func testDefaultMapPaintsEachKeyFromItsAction() {
        let threads = StatusMapper.threads(
            for: [agent("working"), agent("blocked"), agent("idle")],
            map: PadMap()
        )
        XCTAssertEqual(threads.count, 13)
        XCTAssertEqual(threads.map(\.id), Array(0...12))
        XCTAssertEqual(thread(threads, id: 1).color, 0xFFA000)
        XCTAssertEqual(thread(threads, id: 0).color, 0xFF2D2D)
        XCTAssertEqual(thread(threads, id: 2).color, 0x00C853)
        XCTAssertEqual(thread(threads, id: 6).color, 0x7C4DFF)
        XCTAssertEqual(thread(threads, id: 7).color, 0x00BFA5)
        XCTAssertEqual(thread(threads, id: 8).color, 0xE91E63)
        XCTAssertEqual(thread(threads, id: 9).color, 0x90A4AE)
        XCTAssertEqual(thread(threads, id: 12).color, 0x90A4AE)
        XCTAssertEqual(thread(threads, id: 10).color, 0xECEFF1)
        XCTAssertEqual(thread(threads, id: 11).color, 0xECEFF1)
        for id in [3, 4, 5] {
            XCTAssertEqual(thread(threads, id: id).effect, .off)
            XCTAssertEqual(thread(threads, id: id).brightness, 0)
            XCTAssertNil(thread(threads, id: id).color)
        }
    }

    func testMapOverlayPromptPaintsMacroNotStack() {
        let map = padMap(#"{"map": {"6": {"action": "injectPrompt", "text": "hi"}}}"#)
        let threads = StatusMapper.threads(for: [agent("working")], map: map)
        XCTAssertEqual(thread(threads, id: 6).color, 0x90A4AE)
        XCTAssertNotEqual(thread(threads, id: 6).color, 0x7C4DFF)
    }

    func testMapMovesAgentColourWithFocusSlot() {
        let map = padMap(#"{"map": {"6": {"action": "focusSlot", "slot": 0}, "1": {"action": "voice"}}}"#)
        let threads = StatusMapper.threads(for: [agent("working")], map: map)
        XCTAssertEqual(thread(threads, id: 6).color, 0xFFA000)
        XCTAssertEqual(thread(threads, id: 1).color, 0xECEFF1)
    }

    func testOpenStackBreathesOnGitButlerStatusKey() {
        let map = padMap(#"{"map": {"6": {"action": "voice"}, "9": {"action": "gitButlerStatus"}}}"#)
        let threads = StatusMapper.threads(for: [], map: map, stackOpen: true)
        XCTAssertEqual(thread(threads, id: 9).color, 0x7C4DFF)
        XCTAssertEqual(thread(threads, id: 9).effect, .breath)
        XCTAssertEqual(thread(threads, id: 6).color, 0xECEFF1)
        XCTAssertEqual(thread(threads, id: 6).effect, .solid)
    }

    func testUnboundKeyIsOff() {
        let map = padMap(#"{"map": {"6": {"action": "explode"}}}"#)
        let key = thread(StatusMapper.threads(for: [], map: map), id: 6)
        XCTAssertEqual(key.effect, .off)
        XCTAssertEqual(key.brightness, 0)
        XCTAssertNil(key.color)
    }
}

// MARK: - Status colours must stay distinguishable

extension StatusMapperTests {

    func testDoneAndIdleAreToldApartByColour() {
        // "done" means finished and not yet looked at; "idle" means finished
        // and seen. Different signals, so they must not share a colour.
        let cfg = BridgeConfig()
        XCTAssertNotEqual(
            cfg.color(for: "done"),
            cfg.color(for: "idle"),
            "a finished-but-unread agent must be distinguishable from a quiet one"
        )
        XCTAssertEqual(cfg.color(for: "idle"), 0x00C853)
        XCTAssertEqual(cfg.color(for: "done"), 0x00B0FF)
    }

    func testAttentionStatesAllHaveDistinctColours() {
        let cfg = BridgeConfig()
        var seen: [Int: String] = [:]
        for state in ["blocked", "working", "done", "idle"] {
            let color = cfg.color(for: state)
            XCTAssertNil(seen[color], "\(state) reuses the colour of \(seen[color] ?? "")")
            seen[color] = state
        }
    }

    func testDoneAndIdleAgentsGetDifferentKeys() {
        let threads = StatusMapper.threads(for: [
            HerdrAgent(status: "done", paneID: "w1:p1"),
            HerdrAgent(status: "idle", paneID: "w1:p2"),
        ])
        XCTAssertEqual(threads[0].color, 0x00B0FF)
        XCTAssertEqual(threads[1].color, 0x00C853)
    }

    /// Pins every status colour. These are the whole point of the pad — a
    /// silent change to one is a bug you find by looking at hardware, which is
    /// the slowest possible way to find it.
    func testEveryStatusColourIsPinned() {
        let cfg = BridgeConfig()
        XCTAssertEqual(cfg.color(for: "blocked"), 0xFF2D2D)
        XCTAssertEqual(cfg.color(for: "working"), 0xFFA000)
        XCTAssertEqual(cfg.color(for: "done"), 0x00B0FF)
        XCTAssertEqual(cfg.color(for: "idle"), 0x00C853)
        XCTAssertEqual(cfg.color(for: "unknown"), 0x00C853)
    }
}
