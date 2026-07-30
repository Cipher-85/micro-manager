# herdr-worklouder-micro

A [Herdr](https://herdr.dev) plugin that connects a Work Louder **Creator Micro 2**
to your running coding agents:

- the pad's light reflects agent status, so you can tell at a glance whether
  anything needs you
- the top six keys jump straight to agents 1-6 in Herdr

## Status of per-key colours

The stock Input app only ever calls one lighting method, `lights.preview`,
which addresses two **whole-device** surfaces (`backlight`, `underglow`) with a
single colour each. There is no per-key addressing in anything the app does.

However, the Creator Micro hardware genuinely has per-key LEDs (QMK's v1 board
declares an `rgb_matrix` of 12 positioned per-key LEDs plus 8 underglow), and
strings in the cm-v2 firmware (v0.6.0-rc.8) show handlers the app never calls:

| method | evidence |
|---|---|
| `v.oai.rgbcfg` | registered next to `lights.preview` in `wl_lights_controller`; the surrounding key vocabulary is `effect/brightness/speed/magic/color` plus sections `backlight/underglow/`**`keys`**/**`ambient`** |
| `v.oai.thstatus` | `"OAI BRIDGE: init, v.oai.thstatus registered on all variants"` (`src/oai/wl_oai_bridge.cpp`) |
| `v.oai.hid`, `v.oai.rad` | same bridge |

`oai` is OpenAI: this is the Codex Micro's agent-status integration, and the
same firmware image ships to the Creator Micro 2. The OAI default profile even
maps the **top six keys** to `KV_OAI_AG00`..`KV_OAI_AG05`.

Whether `keys` is a genuinely addressable array or just the OAI name for the
key backlight surface is not decidable from the binary. The firmware answers
unknown methods with a JSON-RPC `Method not found`, so:

```bash
npm run probe
```

will say definitively. If per-key addressing works, `bin/leds.js` can be
extended to light one key per agent instead of one aggregate colour.

## Requirements

- Node 18+
- A running Herdr server (`herdr status`)
- **macOS:** Input Monitoring permission for whatever process runs the bridge
  (System Settings → Privacy & Security → Input Monitoring). Without it, opening
  the HID interface fails with `privilege violation`.
- **Linux:** a udev rule granting access to the `303a:` HID device.

## Install

```bash
npm install --omit=dev
herdr plugin link /path/to/herdr-worklouder-micro
```

## The status light

`bin/leds.js` is a long-running bridge. It watches Herdr and pushes a colour:

| condition | colour |
|---|---|
| any agent blocked / waiting on you | red, breathing |
| else any agent working | amber |
| else agents running but idle | green |
| no agents | off |

Worst state wins, because with one light the useful question is "does anything
need me?".

Run it in a pane to watch it work:

```bash
herdr plugin pane open worklouder.micro.leds
```

Or in the background (see `launchd/` for a macOS agent). To develop without the
hardware present:

```bash
WL_FAKE_DEVICE=1 npm run leds
```

### Configuring colours

Drop a `config.json` into the plugin's config dir
(`herdr plugin config-dir worklouder.micro`):

```json
{
  "colors": { "blocked": "#FF0055", "working": "#FFAA00", "idle": "#003311" },
  "brightness": 0.6,
  "drive_backlight": true
}
```

Keys you omit keep their defaults. `priority` reorders which state wins.

## The six keys

Map the pad's top six keys to **F13-F18** in Work Louder's Input app, then bind
them in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "f13"
type = "plugin_action"
command = "worklouder.micro.focus1"
description = "focus agent 1"

# ... f14 -> focus2, through f18 -> focus6
```

Slots are ordered by workspace, then tab, then pane, so a key keeps pointing at
the same agent as long as the set of agents does not change. Check the current
mapping with:

```bash
herdr agent list
```

## Known conflict

Work Louder's Input app drives the underglow from the focused desktop app
("AppSense" colour cues). If it is running it will fight this bridge for the
light. Turn that feature off, or quit Input, while using the bridge.

## Tests

```bash
npm test
```

Covers the status-to-colour mapping, config merging, slot ordering, and colour
encoding — everything that does not need hardware.

## Protocol notes

The device speaks JSON-RPC 2.0 over raw HID on usage page `0xFF00`, usage `1`:

```
byte 0      report id, always 0x06
byte 1      channel: 1 = firmware debug log, 2 = JSON-RPC
byte 2      payload length in this report, <= 61
bytes 3..   UTF-8 fragment of the JSON message
```

Requests are split across as many 64-byte reports as needed; responses are
reassembled by scanning for balanced braces. Colours go on the wire as a
`0xRRGGBB` integer; `brightness`, `speed`, and `magic` are 0..1 floats. Call ids
must be under 1000.
