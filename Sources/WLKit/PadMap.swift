import Foundation

/// Firmware key id 0...18 to the action the bridge should run.
///
/// Read from the same `$XDG_CONFIG_HOME/micromanager/config.json` as
/// `KeyBindings`. Overlay order is today's defaults, then the `keys` shim
/// (a bound string becomes `injectPrompt`, an empty string unbinds), then
/// the `map` overlay — map wins. No file or a malformed file leaves the
/// defaults, which match the pad as of this writing.
///
/// `"10+11"` addresses the wide key as one. Dial and stick may be named
/// (`dial.cw` / `dial.ccw`, `stick.n/w/s/e`) or addressed by id 13...18.
public enum PadAction: Equatable, Sendable {
    case focusSlot(Int)
    case herdr(String)
    case injectPrompt(String)
    case gitButlerStatus
    case gitButlerLand
    case voice
    case effort(step: Int)
    case model(Pad.JoystickDirection)
    case unbound
}

public struct PadMap: Sendable, Equatable {

    public private(set) var actions: [Int: PadAction]

    public static let defaults: [Int: PadAction] = [
        1: .focusSlot(0),
        0: .focusSlot(1),
        2: .focusSlot(2),
        3: .focusSlot(3),
        4: .focusSlot(4),
        5: .focusSlot(5),
        6: .gitButlerStatus,
        7: .herdr("next_tab"),
        8: .gitButlerLand,
        9: .injectPrompt("Open PRs for all active GitButler branches"),
        10: .voice,
        11: .voice,
        12: .injectPrompt("Run but pull"),
        13: .effort(step: 1),
        14: .effort(step: -1),
        15: .model(.north),
        16: .model(.west),
        17: .model(.south),
        18: .model(.east),
    ]

    public init(actions: [Int: PadAction] = PadMap.defaults) {
        self.actions = actions
    }

    public func action(for key: Int) -> PadAction {
        actions[key] ?? .unbound
    }

    /// Assigning either half of the wide key sets both.
    public mutating func set(_ action: PadAction, for key: Int) {
        if key == 10 || key == 11 {
            actions[10] = action
            actions[11] = action
            return
        }
        actions[key] = action
    }

    public func encodedMap() -> [String: Any] {
        var result: [String: Any] = [:]
        for id in 0...12 where id != 10 && id != 11 {
            result["\(id)"] = Self.encode(action(for: id))
        }
        if action(for: 10) == action(for: 11) {
            result["10+11"] = Self.encode(action(for: 10))
        } else {
            result["10"] = Self.encode(action(for: 10))
            result["11"] = Self.encode(action(for: 11))
        }
        result["dial"] = [
            "cw": Self.encode(action(for: 13)),
            "ccw": Self.encode(action(for: 14)),
        ]
        result["stick"] = [
            "n": Self.encode(action(for: 15)),
            "w": Self.encode(action(for: 16)),
            "s": Self.encode(action(for: 17)),
            "e": Self.encode(action(for: 18)),
        ]
        return result
    }

    public static func encode(_ action: PadAction) -> [String: Any] {
        switch action {
        case .focusSlot(let slot):
            return ["action": "focusSlot", "slot": slot]
        case .herdr(let name):
            return ["action": "herdr", "name": name]
        case .injectPrompt(let text):
            return ["action": "injectPrompt", "text": text]
        case .gitButlerStatus:
            return ["action": "gitButlerStatus"]
        case .gitButlerLand:
            return ["action": "gitButlerLand"]
        case .voice:
            return ["action": "voice"]
        case .effort(let step):
            return ["action": "effort", "step": step]
        case .model(let direction):
            let dir: String
            switch direction {
            case .north: dir = "north"
            case .south: dir = "south"
            case .east: dir = "east"
            case .west: dir = "west"
            }
            return ["action": "model", "dir": dir]
        case .unbound:
            return ["action": "unbound"]
        }
    }

    public static func save(_ map: PadMap) throws {
        try save(map, to: KeyBindings.configPath())
    }

    /// Replaces only the `map` key. Other fields in an existing object are
    /// left alone. A missing or malformed file becomes `{ "map": ... }`.
    public static func save(_ map: PadMap, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var root: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: path),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = json
        }
        root["map"] = map.encodedMap()
        let out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try out.write(to: url, options: .atomic)
    }

    public static func load() -> PadMap {
        guard let data = FileManager.default.contents(atPath: KeyBindings.configPath()) else {
            return PadMap()
        }
        return parse(data)
    }

    /// A malformed file falls back to the defaults rather than a dead pad.
    static func parse(_ data: Data) -> PadMap {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return PadMap() }

        var actions = defaults
        applyKeysShim(&actions, json["keys"])
        applyMap(&actions, json["map"])
        return PadMap(actions: actions)
    }

    private static func applyKeysShim(_ actions: inout [Int: PadAction], _ raw: Any?) {
        guard let keys = raw as? [String: Any] else { return }
        for (name, value) in keys {
            guard let text = value as? String else { continue }
            for key in keyIDs(for: name) {
                actions[key] = text.isEmpty ? .unbound : .injectPrompt(text)
            }
        }
    }

    private static func applyMap(_ actions: inout [Int: PadAction], _ raw: Any?) {
        guard let map = raw as? [String: Any] else { return }
        for (name, value) in map where name != "dial" && name != "stick" {
            for key in keyIDs(for: name) {
                actions[key] = parseAction(value)
            }
        }
        if let dial = map["dial"] as? [String: Any] {
            if let cw = dial["cw"] { actions[13] = parseAction(cw) }
            if let ccw = dial["ccw"] { actions[14] = parseAction(ccw) }
        }
        if let stick = map["stick"] as? [String: Any] {
            if let n = stick["n"] { actions[15] = parseAction(n) }
            if let w = stick["w"] { actions[16] = parseAction(w) }
            if let s = stick["s"] { actions[17] = parseAction(s) }
            if let e = stick["e"] { actions[18] = parseAction(e) }
        }
    }

    private static func parseAction(_ value: Any) -> PadAction {
        guard let obj = value as? [String: Any] else { return .unbound }
        guard let name = obj["action"] as? String, !name.isEmpty else { return .unbound }
        switch name {
        case "focusSlot":
            guard let slot = obj["slot"] as? Int else { return .unbound }
            return .focusSlot(slot)
        case "gitButlerStatus":
            return .gitButlerStatus
        case "gitButlerLand":
            return .gitButlerLand
        case "herdr":
            guard let herdrName = obj["name"] as? String, !herdrName.isEmpty else { return .unbound }
            return .herdr(herdrName)
        case "injectPrompt":
            guard let text = obj["text"] as? String, !text.isEmpty else { return .unbound }
            return .injectPrompt(text)
        case "voice":
            return .voice
        case "effort":
            guard let step = obj["step"] as? Int else { return .unbound }
            return .effort(step: step)
        case "model":
            switch obj["dir"] as? String {
            case "north": return .model(.north)
            case "south": return .model(.south)
            case "east": return .model(.east)
            case "west": return .model(.west)
            default: return .unbound
            }
        default:
            return .unbound
        }
    }

    private static func keyIDs(for name: String) -> [Int] {
        if name == "10+11" { return [10, 11] }
        guard let id = Int(name), (0...18).contains(id) else { return [] }
        return [id]
    }
}
