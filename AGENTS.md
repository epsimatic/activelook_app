# AGENTS.md

Guidance for agents and humans working in this repository.

## 1. What this project is

A Flutter **demo application for ActiveLook®** — the MICROOLED "Light AR" head-up display
technology used in sports/safety glasses. The app is meant to be a reference showcase for
developers evaluating ActiveLook: connect to a pair of glasses over BLE, preload a small set of
graphical resources, and drive the display with layouts/pages.

**Target device: engo3 (Engo Eyewear / ActiveLook) — color display.** The app is developed and
tested against engo3 specifically, not against the monochrome `MDP05` glasses even though the
protocol layer must stay generic enough not to crash on them. See §1.1 for the hardware facts
that matter and §7 for the color-first UX rules.

Official reference material (read these before touching the BLE layer):

- API / protocol spec: <https://github.com/ActiveLook/Activelook-API-Documentation>
  (raw: `ActiveLook_API.md`)
- Getting-started guide: <https://www.activelook.net/news-blog/developing-with-activelook-getting-started>
- Official SDKs to mirror behaviour from (Android/Kotlin, iOS/Swift — **no Dart SDK exists**):
  <https://github.com/ActiveLook/android-sdk>, <https://github.com/ActiveLook/ios-sdk>

### 1.1 Target hardware: engo3 (color)

| Property        | Value                                                                     |
| --------------- | ------------------------------------------------------------------------- |
| Product         | engo3 / engo3 Cyclist / engo3 Titanium (same electronics, different frames) |
| Display         | 304×256 micro-OLED, **color: 81 RG colors** (red–green palette, no blue)   |
| Expected hw id  | `ALKxx-MDP08…` — color display module (`MDP08` = color, `MDP05` = 16 greys) |
| Protocol        | Stock ActiveLook BLE protocol, fw 4.x — no vendor-specific commands        |
| Firmware/HW     | Read `0x2A26` / `0x2A27` on service `0x180A`; do not hard-code a version   |
| Input           | Capacitive double-tap on the temple (touch event `0x1CBC`), no buttons     |
| Sensors         | Gesture, ambient light, battery `0x2A19`                                   |

Practical consequences for this app:

- **Color is the default path, not an optional extra.** Use `color` (0x3D), `txtColor` (0x3E),
  `layoutSaveInColor` (0x6B) and the RG image formats (0x0A / 0x0C) as the primary rendering
  route. Keep a grayscale fallback only behind an explicit capability check.
- Still gate every color command on the hardware string (`MDP08`), because the same codebase
  may be pointed at older engo2 (`MDP05`) glasses during development. On non-color hardware the
  device answers `0xE2 error`; do not silently ignore that.
- The palette is **81 discrete colors, not RGB565/24-bit**. Convert host-side images to the
  nearest palette entry; there is no true blue, so blue-ish designs will look wrong.
- Double-tap arrives as a plain touch notification — the glasses do not tell you "double tap",
  so debounce in the app (~400 ms window) if you want a distinct gesture.

## 2. Current state (be honest about this)

A working "connect and say hi" demo, no longer a template:

- Flow: `lib/main.dart` → `lib/app/app.dart` → `lib/features/scan/scan_screen.dart` →
  `lib/features/glasses/glasses_screen.dart`.
- BLE: `lib/ble/` (scanner, transport with GATT discovery, notifications, flow control,
  chunked write queue, Device Information + battery reads). `flutter_blue_plus` 2.3.x is the
  only plugin and is confined to that directory.
- Protocol: `lib/protocol/` (frame encoder/parser, command builders, engo3 palette preview).
- Implemented commands: `displayPower`, `clear`, `demo`, `battery`, `vers`, `luma`, `holdFlush`,
  `color`, `rectf`, `circf`, `arc`, `txt`, `txtColor`. Text is sent as hold → clear →
  `txtColor`/`txt` → flush.
- Animated full-screen color demo (`lib/models/color_show.dart`), three modes:
  - **pulse** — 7 concentric full rings, full-screen redraw: hold/clear + 7×(color+circf) +
    flush, ~130 B per frame.
  - **sweep** — low-BLE smooth mode: appends one `color`+`arc` segment per frame (~21 B) and
    only clears once per revolution; the panel keeps earlier segments, no full redraw.
  - **counter** — fastest text demo: incrementing number in an alternating palette color, one
    `txtColor` per frame inside hold/clear/flush, ~31 B, no graphics commands. Preview uses
    `displayColor` so it matches the on-glasses color.
  Speed 2–30 fps (15 default); the UI shows measured bytes/frame and KB/s (`lastFrameBytes`,
  `colorShowBytesPerSecond`). Frames are plain shape lists, so the phone preview paints exactly
  what the glasses get. Gated on `MDP08`; `stopColorShow` resets the hold counter with
  `holdFlush 0xFF`.
- **Compass ribbon** (mobile only): `lib/models/compass.dart` (8-point labels, heading
  normalisation), `lib/features/compass/` (`DeviceCompassSource` over `flutter_compass`, the
  HUD ribbon widget/painter) and `lib/protocol/active_look_compass.dart` (on-glasses frame:
  `hold → clear → baseline/ticks/labels/caret → flush`, 1 Hz). The phone ribbon follows the
  sensor at full rate; the glasses copy is throttled by `GlassesController`. The compass card is
  only built when `controller.compassSupported` (Android/iOS); desktop builds never touch the
  plugin channel and show no compass section at all.
- A simulated transport/scanner (`lib/ble/mock_glasses.dart`) lets the app run without hardware.
- Not implemented yet: `cfgWrite` + resource upload (images/fonts/layouts/pages/gauges),
  layouts/pages rendering, touch double-tap debounce, firmware-update prompting.
- Platforms: **android** and **macos** only (`ios/`, `web/`, `linux/`, `windows/` do not exist).
  BLE permissions (Android manifest) and entitlements (macOS) are already configured.
- `README.md` explains how to run the demo; keep it in sync with behaviour changes.

When you add real functionality, keep this section in sync (or drop stale claims).

## 3. Commands

```bash
flutter pub get
flutter analyze                 # must stay clean; analyzer excludes build/, android/, macos/
dart format lib test            # formatting is not enforced by CI, but match existing style
flutter test
flutter run -d macos            # fastest iteration loop for UI work
flutter run -d <android-device> # real BLE testing
contrib/install-hooks.sh        # optional: git pre-commit format/analyze/test hook
```

No Makefile, no `justfile`, no build_runner setup, no codegen. CI lives in
`.github/workflows/flutter-workflow.yaml` (analyze + test + release APK artifact); the same
checks run locally via the git pre-commit hook, installed with `contrib/install-hooks.sh`.
Prerequisites and SDK setup are described in `INSTALL.md`. Do not introduce
`build_runner`/`freezed`/`json_serializable` unless the task actually needs it.

## 4. Dart & Flutter conventions

- SDK is `^3.13.2`, Flutter 3.47.x. The template already uses **dot shorthands**
  (`colorScheme: .fromSeed(...)`, `mainAxisAlignment: .center`). Prefer that modern style where
  it reads clearly; don't rewrite existing files just to use it.
- Lints: `package:flutter_lints/flutter.yaml` with no custom rules. Fix lints rather than adding
  ignores. `avoid_print` is active — use a small logger or `debugPrint`, not `print`.
- `const` constructors everywhere they apply; `final` fields; no `dynamic`.
- Prefer small, single-responsibility widgets. Extract widgets into their own files once they
  exceed roughly a screenful or are reused.
- Public APIs (anything consumed outside its file) get doc comments (`///`). Protocol code in
  particular should document byte layouts and cite the spec command name/ID.

### Target source layout (follow it once real code lands)

```
lib/
  main.dart                # runApp + top-level wiring only
  app/                     # MaterialApp, theme, routing
  ble/                     # scanning, connection, GATT, flow control, reconnect
  protocol/                # frame encoder/decoder, command builders, responses
  resources/               # bundled icons/fonts + upload/config management
  features/                # screens: scan, connect, dashboard/demo, settings
    compass/               # compass source + HUD ribbon widget/painter
  models/                  # plain data classes
test/                      # unit tests for protocol/resource logic, widget tests for screens
```

Keep BLE I/O out of widgets. Screens talk to a controller/state object; the controller talks to
the protocol layer; only the BLE layer touches the plugin.

## 5. BLE plugin

There is **no ActiveLook package on pub.dev**. Use a maintained BLE plugin —
`flutter_blue_plus` is the default choice; `flutter_reactive_ble` is acceptable if the task
requires it. Pick one and keep all plugin usage isolated in `lib/ble/`.

Compass support uses `flutter_compass` (`DeviceCompassSource`, Android/iOS only). It reads the
rotation-vector/magnetometer sensor and needs no manifest permissions on modern Android; guard
it behind `Platform.isAndroid || Platform.isIOS` so desktop builds never subscribe to a channel
that does not exist there.

⚠ `flutter_blue_plus` 2.x requires passing a `License` to `connect()`. The code uses
`License.nonprofit` (personal/educational/non-profit). **Commercial use requires a paid license** —
check the package LICENSE before shipping.

Platform requirements you will hit:

- **Android**: `BLUETOOTH_SCAN` (with `neverForLocation` if applicable) + `BLUETOOTH_CONNECT` for
  API 31+, legacy `BLUETOOTH`/`BLUETOOTH_ADMIN` + `ACCESS_FINE_LOCATION` below that, in
  `android/app/src/main/AndroidManifest.xml`. `minSdk` comes from `flutter.minSdkVersion` —
  raise it explicitly if the plugin requires it.
- **macOS**: add `NSBluetoothAlwaysUsageDescription` to `macos/Runner/Info.plist`, and enable
  `com.apple.security.device.bluetooth` in **both** `macos/Runner/DebugProfile.entitlements` and
  `macos/Runner/Release.entitlements` (the sandbox blocks BLE otherwise).
- Device discovery: filter on manufacturer data ending in `0x08F2` (or name prefix `A.Look`),
  not on a hard-coded name.

## 6. ActiveLook protocol cheat-sheet

Condensed from the spec. Full details, response formats and layout/image encodings live in
`ActiveLook_API.md` — always verify there instead of guessing.

### GATT

ActiveLook command service: `0783B03E-8535-B5A0-7140-A304D2495CB7`

| Role                  | UUID                                     | Property            |
| --------------------- | ---------------------------------------- | ------------------- |
| RX (host → glasses)   | `0783B03E-8535-B5A0-7140-A304D2495CBA`   | Write, Write w/o rsp |
| TX (glasses → host)   | `0783B03E-8535-B5A0-7140-A304D2495CB8`   | Notify              |
| Control               | `0783B03E-8535-B5A0-7140-A304D2495CB9`   | Notify              |
| Touch event (user)    | `0783B03E-8535-B5A0-7140-A304D2495CBC`   | Notify (value `0x01`)|
| Gesture event (sensor)| `0783B03E-8535-B5A0-7140-A304D2495CBB`   | Notify (value `0x01`)|

Battery level: standard `0x2A19` (read + notify every 30 s).
Firmware/hardware info: Device Information service `0x180A` (`0x2A26` fw, `0x2A27` hw — `MDP08` =
color display, `MDP05` = 16 grey levels).

Enable notifications on TX, Control and (for interactivity) Touch/Gesture. **Use Write-with-response
by default.**

### Frame format

```
0xFF | cmdId | format | length | [queryId] | [data] | 0xAA
```

- All multi-byte values are **big-endian**.
- `format` bit 5 = length size (0 → 1 byte, 1 → 2 bytes); bits 4..1 = queryId byte count (0–15).
- `length` counts the whole frame **including** header and footer. Max 533 bytes total (512 data).
- Frames may be split across BLE chunks: reassemble using `length` and the `0xAA` footer.
  Negotiate a large MTU (e.g. 185/247) before the first write.
- `queryId` is echoed in the response so replies can be matched to commands. Use it for anything
  you read back (`battery`, `vers`, `imgList`, `layoutList`, `rdDevInfo`, …).

### Control notifications (must be honoured)

| Value | Meaning                                                          |
| ----- | ---------------------------------------------------------------- |
| 0x01  | flow ON — safe to send                                           |
| 0x02  | buffer 75% full — **stop sending**, wait for 0x01                |
| 0x03  | error: malformed/incomplete command (ignored)                    |
| 0x04  | receive queue overflow                                           |
| 0x06  | missing `cfgWrite` before configuration modification             |

Also handle asynchronous `0xE2 error` notifications (`cmdId`, `error`, `subError`) on TX.

### Commands you will use most

| ID   | Command        | Notes                                                                |
| ---- | -------------- | -------------------------------------------------------------------- |
| 0x00 | `displayPower` | bool                                                                 |
| 0x01 | `clear`        | black screen (held by graphic engine since fw 4.12)                  |
| 0x03 | `demo`         | built-in demo patterns — useful as a "does it work" smoke test       |
| 0x05 | `battery`      | read, response = level %                                             |
| 0x06 | `vers`         | read, 9-byte response                                                |
| 0x09 | `shift`        | s16 x, s16 y                                                         |
| 0x10 | `luma`         | 0–15, persisted                                                      |
| 0x20/0x21/0x22 | `sensor`/`gesture`/`als` | bool, persisted                                       |
| 0x30 | `grayscale`    | 0–15 for next graphical element                                      |
| 0x3D | `color`        | 0–255 RG, **color glasses only**                                     |
| 0x31–0x3C | `point`/`line`/`rect`/`rectf`/`circ`/`circf`/`txt`/`polyline`/`arc` | one-shot drawing |
| 0x39 | `holdFlush`    | 0 hold, 1 flush, 0xFF reset+flush — nested, must be balanced          |
| 0x60–0x6B | `layout*`  | `layoutSave`/`layoutDisplay`/`layoutClearAndDisplay`, positions u16/u8 |
| 0x80–0x86 | `page*`    | page = set of layouts, strings NUL-separated                          |
| 0x41/0x42/0x44/0x46/0x47 | images | `imgSave` (chunked), `imgDisplay`, `imgStream`, `imgDelete`, `imgList` |
| 0x50–0x53 | fonts      | list/save/select/delete                                              |
| 0x95–0x99 | animations | `animSave`/`animDisplay`/`animClear`/`animList`                       |
| 0xD0–0xD8 | configurations | `cfgWrite` (12-byte NUL-padded name + version + password), `cfgSet`, `cfgFreeSpace`, `cfgList`, … |
| 0xE0/0xE1/0xE3 | `shutdown` / `reset` / `rdDevInfo` | magic keys required; shutdown blocked on USB power |

### Memory / configuration model (fw ≥ 4.0)

Flash is a filesystem where each app owns a named configuration holding its images, fonts,
layouts, gauges and pages. Standard flow on first connect to a new pair of glasses:

1. `vers` → check firmware compatibility (compare the first two version digits against the
   version the app targets; prompt the user to update via the ActiveLook companion app if older).
2. `cfgGetNb` / `cfgList` / `cfgFreeSpace` → ensure room, call `cfgDeleteLessUsed` if needed.
3. `cfgWrite` (name, version, password) → then upload resources (`imgSave`, `fontSave`,
   `layoutSave`, `gaugeSave`, `pageSave`).
4. On later connections: `cfgSet <name>` selects the configuration, then just `layoutDisplay` /
   `pageDisplay` to update values.

Configuration writes require battery above 5%.

## 7. Demo app UX rules (ActiveLook design guidelines)

The glasses are a **memory-in-pixel microdisplay, 304×256**. On our target engo3 it is the
**color variant: 81 RG colors**, not 16 grey levels. Not a video screen. Content is composed of
icons, text, shapes and small images.

### Color-first rules (engo3)

- Draw in color: set `color` (0x3D) or `txtColor` (0x3E) before each element, or save layouts
  with `layoutSaveInColor` (0x6B). `grayscale` (0x30) still works on color glasses but throws away
  the panel's only advantage — use it only for de-emphasised/secondary content.
- **No blue.** The palette is R×G (3×3×3 = 81 entries, values 0–255 encoded RRGG). Choose hues
  from red → orange → yellow → green. Never design UI that relies on blue/cyan/violet.
- Use color semantically, not decoratively: green = good/on-target, orange = caution, red =
  alert (matches the engo3 zone conventions users already know).
- Contrast matters more than hue at 4–5 m focal distance: prefer one strong accent color plus
  white/grey text on black. Don't put red text on green.
- Images on color hardware: `imgSave` format `0x0A` (8bpp RRGG) or `0x0C` (RRGG + 4-bit alpha).
  Alpha in `0x0C` is **boolean today** (0 = fully transparent, any non-zero = opaque); don't
  build soft edges/fades on it. `0x08` (grey + alpha) is also accepted but is a grey image.
- Palette quantization happens on the host — map every source pixel to the nearest of the 81
  entries, and dither only if it visibly helps (it usually doesn't at this dot pitch).

### Layout rules (apply regardless of color)

- Bright content on black; treat black as transparent. Never full-page/photo-like content.
- Keep a usable area of about **244×206** (≈30 px horizontal, 25 px vertical margins); prefer the
  centre, avoid corners and don't draw frames/borders.
- Only redraw what changed. Target ≈1 update/second maximum.
- **Always wrap display updates in `holdFlush` hold → … → flush**, so the panel refreshes once
  and doesn't blink.
- Prefer **layouts/pages** over per-element commands — fewer BLE round trips.
- "Think erasing": the panel keeps whatever you don't overwrite. Overlay same-size content, a
  black rectangle/text, `layoutClear`, or `clear`.
- Animations are a gimmick at best (limited BLE throughput); don't design around them.
- Gesture sensor consumes about half the device power — make it togglable and off by default.
- Images/fonts must be prepared in the exact expected format (4bpp, 1bpp, Heatshrink, 8bpp
  color, 8bpp RRGG + alpha) — conversion happens on the host, so include a documented pipeline in
  `lib/resources/` rather than hard-coded blobs.

For the phone side of the demo: show connection state, battery, firmware/hardware version,
free memory, and a small "what the glasses currently display" preview mirroring the 304×256
framebuffer **in color** (use the same 81-entry palette so the preview is faithful).
`GlassesTransport` (`lib/ble/glasses_transport.dart`) has a real BLE implementation and a
simulated one (`MockGlassesTransport`) — use the simulated one for UI work and hardware-free demos.

## 8. Testing

- Pure logic (frame encoding, chunking/reassembly, resource packing, config flow) gets unit tests
  in `test/` — no BLE plugin mocking needed if the transport is abstracted.
- Widget tests for screens: keep them free of platform channels.
- `test/widget_test.dart` is the template counter test; update or delete it when `main.dart`
  changes, don't leave a failing test behind.
- Run `flutter analyze && flutter test` before declaring a task done.

## 9. Gotchas

- Never assume the glasses accept everything: check `0xE2 error` and control `0x03/0x04/0x06`.
- Graphics engine state resets on disconnect / overflow — send `holdFlush` `0xFF` before starting
  a fresh UI update sequence after a reconnect.
- `clear` is held by the graphic engine since fw 4.12; don't rely on it bypassing a hold.
- Color commands (`0x3D`, `0x3E` `txtColor`, `0x6B` `layoutSaveInColor`, image formats `0x0A` /
  `0x0C`) are **only** valid on `MDP08` color glasses — check the hardware version string
  (`MDP08` = engo3 color, `MDP05` = older 16-grey glasses) instead of assuming.
- On color glasses, `grayscale` and `layoutSave` still work, but everything is drawn in the
  equal-R=G (white/grey) palette entries; mixed color and grey commands are fine.
- 4-bit alpha in `0x0C` images is effectively boolean (0 or opaque); no soft transparency.
- Touch characteristic is a single value (`0x01`) — double tap must be detected host-side.
- Layout coordinates are unsigned; graphics coordinates are signed and may be negative.
- Strings are NUL-terminated c-strings; configuration names are max 12 bytes.
- Bluetooth permissions/entitlements are the #1 cause of "scan finds nothing" on macOS.
