# ActiveLook demo app

A Flutter demo for **ActiveLook®** (MICROOLED "Light AR") glasses. It scans for a pair of
glasses over Bluetooth Low Energy, connects, and displays **"Hi"** on the head-up display.

Built and tested against **engo3** — the color variant (`ALKxx-MDP08…`, 81 red/green colors,
304×256). On older 16-grey-level glasses (`MDP05`) the same code falls back to `txt`/`grayscale`.

**Warning: vibe-coded.** Most of the code and docs is written by a LLM. THe resulting app works for me on Mac / Android + ENGO 3 glasses, but your mileage may vary.

**Russian UI**, this may change if that project is useful for anyone non Russian-speaking.

## What it does

- Scans BLE devices and highlights ActiveLook advertisements (name `A.Look …` or manufacturer
  data ending in `0x08F2`).
- Connects, discovers the ActiveLook GATT service, subscribes to TX / Control / touch / gesture
  notifications, and honours the glasses' flow control.
- Reads firmware, hardware revision, serial and battery level.
- Sends the demo text as one flicker-free update: `hold → clear → txtColor (or txt) → flush`.
- Includes a **full-screen animated color demo** with three modes:
  - **Pulse rings** — full-screen redraw of 7 rings (`color` + `circf`).
  - **Low-BLE sweep** — appends one arc segment per frame (`color` + `arc`, ~21 bytes).
  - **Fast counter** — one short `txtColor` per frame with an alternating color
    (`hold → clear → txtColor → flush`, ~31 bytes).
  Speed is adjustable from 2 to 30 fps (15 fps by default), and the UI shows the measured
  per-frame cost and KB/s. The preview mirrors the exact frame and can be opened full screen.
- Shows a live HUD-style **compass** ribbon (`N`/`NE`/`E`… every 45°, ticks every 15°) that
  follows the phone's magnetometer. It can be mirrored on the glasses as a held
  `line`/`txt` frame refreshed once per second. Mobile only: `flutter_compass` has no macOS
  implementation, so the whole compass section is hidden on desktop.
- Lets you pick a palette color, change luminance, play built-in demo patterns and clear the
  display, and shows the raw protocol frames in a log.
- Includes a **simulated** link so you can run and demo the UI without any hardware.

## Платформы

- Android 8+
- macOS (целевая платформа разработки)
- Должно работать на iOS, Linux и Windows

## Running it

Prerequisites, SDK setup and the dev environment are described in [`INSTALL.md`](INSTALL.md).

No glasses at hand? Tap **Run the demo without glasses** on the scan screen.

Before committing, install the pre-commit hook (format, analyze and test):

```bash
contrib/install-hooks.sh
```

The same checks run in CI (`.github/workflows/flutter-workflow.yaml`), which also builds a
release APK and uploads it as a workflow artifact.

## Tests

```bash
flutter analyze
flutter test
```

The tests cover frame encoding (against examples from the API spec), chunk reassembly,
advertisement detection and the controller/UI flow using the simulated transport.

## How it is organised

```
lib/
  main.dart, app/        app shell and theme
  ble/                   scanning, BLE transport, UUIDs, simulated transport
  protocol/              frame codec, command builders, palette
  models/                plain data classes (scan results)
  features/scan/         device discovery screen
  features/glasses/      controller, control screen, 304×256 preview
```

See `AGENTS.md` for the protocol cheat-sheet and project conventions.

## Reference

- API specification: <https://github.com/ActiveLook/Activelook-API-Documentation>
- Getting started: <https://www.activelook.net/news-blog/developing-with-activelook-getting-started>

## Licensing note

BLE uses [`flutter_blue_plus`](https://pub.dev/packages/flutter_blue_plus) 2.x, which requires a
license declaration on connect. This demo passes `License.nonprofit` (personal, educational and
non-profit use). **Commercial use requires a paid flutter_blue_plus license** — check the package
LICENSE before shipping, or swap in another BLE plugin (all plugin usage is confined to `lib/ble/`).
