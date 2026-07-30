#!/usr/bin/env node
"use strict";
// Capability probe for Work Louder firmware.
//
// The stock Input app only ever calls `lights.preview`, which addresses two
// whole-device surfaces. But strings in the cm-v2 firmware (v0.6.0-rc.8) show
// additional handlers registered next to it:
//
//   v.oai.rgbcfg    alongside `lights.preview` in wl_lights_controller, with a
//                   key vocabulary of effect/brightness/speed/magic/color and
//                   sections backlight/underglow/keys/ambient
//   v.oai.thstatus  "registered on all variants" (src/oai/wl_oai_bridge.cpp)
//   v.oai.hid, v.oai.rad
//
// The firmware answers unknown methods with a JSON-RPC "Method not found", so
// this probe can tell "not supported on this variant" apart from "supported but
// I sent the wrong shape". Everything here is read-only or transient lighting.

const { WLDevice, PermissionError } = require("../lib/wl-device.js");

const GREEN = 0x00c853;
const RED = 0xff2d2d;

async function attempt(dev, label, method, params) {
  try {
    const result = await dev.call(method, params);
    console.log(`  OK       ${label}`);
    if (result !== undefined && result !== null)
      console.log(`           -> ${JSON.stringify(result).slice(0, 300)}`);
    return { ok: true, result };
  } catch (err) {
    const msg = String(err.message || err);
    const unknown = /method not found/i.test(msg);
    console.log(`  ${unknown ? "NOMETHOD" : "ERROR   "} ${label}: ${msg}`);
    return { ok: false, unknown, message: msg };
  }
}

async function main() {
  let dev;
  try {
    dev = WLDevice.open();
  } catch (err) {
    if (err instanceof PermissionError) {
      console.error("\n" + err.message + "\n");
      process.exit(2);
    }
    throw err;
  }
  if (!dev) {
    console.error(
      "No Work Louder device on the HID bus.\n" +
        "If it is a Bluetooth pad it may have gone to sleep - press a key to wake it,\n" +
        "or plug it in over USB-C, then re-run.",
    );
    process.exit(1);
  }
  console.log(`device: ${dev.info.product} (${dev.model})\n`);

  console.log("baseline:");
  await attempt(dev, "sys.version", "sys.version", null);
  await attempt(dev, "device.status", "device.status", null);

  console.log("\ndoes this variant register the OAI bridge?");
  const th = await attempt(dev, "v.oai.thstatus {}", "v.oai.thstatus", {});
  const rgb = await attempt(dev, "v.oai.rgbcfg {}", "v.oai.rgbcfg", {});
  await attempt(dev, "v.oai.hid {}", "v.oai.hid", {});
  await attempt(dev, "v.oai.rad {}", "v.oai.rad", {});

  if (rgb.ok || !rgb.unknown) {
    console.log("\nv.oai.rgbcfg payload shapes (looking for per-key addressing):");
    // Surface-style, mirroring lights.preview but with the OAI section names.
    await attempt(dev, "sections keys+ambient (solid)", "v.oai.rgbcfg", {
      keys: { effect: "solid", brightness: 1, speed: 0.5, magic: 1, color: GREEN },
      ambient: { effect: "solid", brightness: 1, speed: 0.5, magic: 1, color: GREEN },
    });
    // Per-key candidates: if any of these is accepted, individual keys are
    // addressable and the whole per-agent plan is back on.
    await attempt(dev, "keys as color array", "v.oai.rgbcfg", {
      keys: [RED, GREEN, RED, GREEN, RED, GREEN, 0, 0, 0, 0, 0, 0, 0],
    });
    await attempt(dev, "keys.colors array", "v.oai.rgbcfg", {
      keys: { colors: [RED, GREEN, RED, GREEN, RED, GREEN, 0, 0, 0, 0, 0, 0, 0] },
    });
    await attempt(dev, "keys as index/color objects", "v.oai.rgbcfg", {
      keys: [
        { index: 0, color: RED },
        { index: 1, color: GREEN },
      ],
    });
    await attempt(dev, "keys.leds index/color", "v.oai.rgbcfg", {
      keys: { leds: [{ index: 0, color: RED }, { index: 1, color: GREEN }] },
    });
  }

  if (th.ok || !th.unknown) {
    console.log("\nv.oai.thstatus payload shapes:");
    for (const p of [
      { status: "thinking" },
      { status: 1 },
      { state: "thinking" },
      { thinking: true },
      { status: "idle" },
    ]) {
      await attempt(dev, JSON.stringify(p), "v.oai.thstatus", p);
    }
  }

  console.log("\ndoes lights.preview itself accept keys/ambient sections?");
  await attempt(dev, "lights.preview keys+ambient", "lights.preview", {
    keys: { effect: "solid", brightness: 1, speed: 0.5, magic: 1, color: GREEN },
    ambient: { effect: "solid", brightness: 1, speed: 0.5, magic: 1, color: GREEN },
  });

  console.log("\nrestoring: underglow off");
  await attempt(dev, "lights.preview off", "lights.preview", {
    underglow: { effect: "off", brightness: 0, speed: 0.5, magic: 1, color: 0 },
  });

  dev.close();
  process.exit(0);
}

main().catch((err) => {
  console.error("probe failed:", err.message);
  process.exit(1);
});
