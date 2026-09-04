# Pad-map customization

Status: **in progress — phase 1**

A real customization layer for the Creator Micro 2. Firmware key ids 0...18
(the 13 keys, dial, and stick) map to a `PadAction`. Today's hardcoded
`handleKeyPress` switch is replaced by that map. The existing `keys` strings
in `config.json` stay as a shim so current files keep working.

This is not a revival of Plan 1 (`PadEngine`, `ActionRunner`,
`ProfileSwitcher`, harness profiles). Those stay gone. The Inspector stays a
HID debugger and is **not** the editor.

## PadMap module

`Sources/WLKit/PadMap.swift`. Public seam: `PadMap.action(for:)` and
`PadMap.parse`. Loaded from the same path as `KeyBindings.configPath()`
(`$XDG_CONFIG_HOME/micromanager/config.json`, else
`~/.config/micromanager/config.json`). Reloaded on every bridge `start()`
next to `KeyBindings`.

`KeyBindings` is left as-is (claude/codex lists and the `keys` reader).
`PadMap` reads the same JSON independently. `StatusMapper` and Inspector are
untouched in phase 1.

Interface: firmware key id → `PadAction`. There is one dispatch path.
`BridgeController.handleKeyPress` switches on `padMap.action(for:)`. No
parallel key-id switch.

## Action catalog

```swift
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
```

Phase 1 dispatch:

| action | runs |
|---|---|
| `gitButlerStatus` | `onStackKey` |
| `herdr("next_tab")` | `cycleTabs` |
| other `herdr` | no-op |
| `gitButlerLand` | `onLandKey` |
| `injectPrompt` | `injectPrompt` |
| `voice` | `onVoiceKey` |
| `effort` | `onDial` |
| `model` | `onJoystick` |
| `focusSlot` | `focusSlot` |
| `unbound` | no-op |

Unknown or empty actions become `unbound`. Never crash.

## Default map

Test these as literals, not via `Pad.*KeyID`. Prompt strings match
`KeyBindings.defaults`.

| id | control | default |
|---|---|---|
| 1 | top-left agent (reading order slot 0) | `focusSlot(0)` |
| 0 | top-right agent (slot 1) | `focusSlot(1)` |
| 2 | row 2 col 1 (slot 2) | `focusSlot(2)` |
| 3 | row 2 col 2 (slot 3) | `focusSlot(3)` |
| 4 | row 2 col 3 (slot 4) | `focusSlot(4)` |
| 5 | row 2 col 4 (slot 5) | `focusSlot(5)` |
| 6 | stack | `gitButlerStatus` |
| 7 | tab cycle | `herdr("next_tab")` |
| 8 | land | `gitButlerLand` |
| 9 | row 3 last | `injectPrompt("Open PRs for all active GitButler branches")` |
| 10 | wide key left half | `voice` |
| 11 | wide key right half | `voice` |
| 12 | bottom-right | `injectPrompt("Run but pull")` |
| 13 | dial clockwise | `effort(step: 1)` |
| 14 | dial counter-clockwise | `effort(step: -1)` |
| 15 | stick north | `model(.north)` |
| 16 | stick west | `model(.west)` |
| 17 | stick south | `model(.south)` |
| 18 | stick east | `model(.east)` |

Firmware top row is wired right to left, so reading-order slot 0 is id 1.

## `config.json` overlay

Order: today's defaults, then the `keys` shim, then the `map` overlay.
**Map wins.** No file, empty file, or malformed JSON → defaults, identical
to current main.

### `keys` shim (unchanged shape)

A bound string becomes `injectPrompt`. An empty string unbinds. `"10+11"`
sets both ids 10 and 11. Keys the file does not mention keep their defaults.

```json
{
  "keys": {
    "9": "Ship it",
    "12": "",
    "10+11": "Summarise what you are working on"
  }
}
```

### `map` overlay

Each entry is an object with `"action"` plus the field that action needs.
Unknown action names, missing fields, and empty names/text unbind that key
only.

| action | extra field |
|---|---|
| `focusSlot` | `slot` (int) |
| `gitButlerStatus` | — |
| `gitButlerLand` | — |
| `herdr` | `name` (string; phase 1 runs `next_tab` only) |
| `injectPrompt` | `text` (string; empty unbinds) |
| `voice` | — |
| `effort` | `step` (int) |
| `model` | `dir`: `north` / `south` / `east` / `west` |

Key names: decimal id `"0"`...`"18"`, or `"10+11"` for both wide-key
halves. Dial and stick may also be named:

- `dial.cw` → id 13, `dial.ccw` → id 14
- `stick.n` → 15, `stick.w` → 16, `stick.s` → 17, `stick.e` → 18

```json
{
  "map": {
    "6": { "action": "voice" },
    "9": { "action": "injectPrompt", "text": "Ship it" },
    "10+11": { "action": "voice" },
    "dial": {
      "cw":  { "action": "effort", "step": 1 },
      "ccw": { "action": "effort", "step": -1 }
    },
    "stick": {
      "n": { "action": "model", "dir": "north" },
      "w": { "action": "model", "dir": "west" },
      "s": { "action": "model", "dir": "south" },
      "e": { "action": "model", "dir": "east" }
    }
  }
}
```

## Phases

1. **PadMap + dispatch (this slice).** Parse overlay, default table, replace
   `handleKeyPress`. v1 herdr name: `next_tab` only. Lighting, Inspector, and
   `KeyBindings` lists unchanged.
2. **Lighting follows the map.** `StatusMapper` still paints by physical
   role (stack key, voice halves, macros). A remapped key should light as
   what it *does*.
3. **Herdr catalog.** Dispatch names besides `next_tab`. Unknown names stay
   no-ops; still never crash.
4. **Editor in Micro Manager.** A map UI in the menu-bar app (panel or
   sheet). Inspector is not the editor — it remains the traffic/keymap
   debugger and must not grow a second copy of this map.
5. **Write-back.** Persist `map` to `config.json` and reload without an
   off/on toggle.

## Out of scope

- Plan 1 `PadEngine` / `ActionRunner` / `ProfileSwitcher` / harness profiles
- Teaching Inspector to edit the map
- Installing the app, resetting TCC, pushing, or merging to `main` as part
  of phase 1
