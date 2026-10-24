# Presence

**A private, cloud-free BLE presence system.** Your Android phone quietly advertises a
per-install identity over Bluetooth; a macOS menu-bar app watches for that identity and
locks your screen when you walk away with your phone. Returning is *notification-only* —
nothing ever unlocks automatically.

This is the feature big smart-home ecosystems wrap in a HomePod/ecosystem; here it's
~0 extra hardware (uses the Mac's built-in Bluetooth), zero cloud, zero telemetry, and
fully source-available.

```
 ┌─────────────────────────┐   BLE advertisement    ┌──────────────────────────────┐
 │      Android phone      │  (non-connectable,     │            macOS              │
 │                          │   service-UUID beacon) │                              │
 │  BeaconService (FGS)    │ ─────────────────────► │  CoreBluetooth scanner        │
 │   └── BeaconAdvertiser   │   ~10 Hz, RSSI per     │   (AllowDuplicates)          │
 │       sha single identity│    packet              │      │ RSSI samples           │
 │                         │                         │      ▼                       │
 └─────────────────────────┘                         │  PresenceStateMachine        │
                                                     │  (pure, unit-tested)         │
                                                     │      │ confirmed transitions │
                                                     │      ▼                       │
                                                     │  away → LockController       │
                                                     │  home → local notification  │
                                                     │      │                       │
                                                     │      ▼                       │
                                                     │  TimelineStore (NDJSON)      │
                                                     └──────────────────────────────┘
```

## Why this design

| Decision | Rationale |
|---|---|
| **Non-connectable beacon** | The Mac's CoreBluetooth scan (`AllowDuplicates`) is only fed continuous RSSI by a non-connectable advertiser. A connectable one would be treated as "pair with me" and stop reporting. |
| **Pure state machine** | All debounce/lock decisions live in `PresenceStateMachine` with zero I/O — the entire tuning strategy is unit-tested without hardware. |
| **Confirmation counts + stale timeout** | BLE RSSI is noisy. One fading sample must never lock your screen mid-typing; a *silence* (beacon stopped advertising) must count as gone. |
| **Per-install UUID** | Identity is derived from what your phone advertises, not who is "connected". Other people's Bluetooth devices are invisible to the scanner — only your UUID matters. |
| **No auto-unlock** | Security posture worth keeping: lock on away, inform on return, never bypass the OS password. |

## Repository layout

```
presence-hub/
├── android/             Kotlin — the phone beacon (foreground service + advertiser)
└── macos/               Swift — detector core, CLI tuning tool, SwiftUI menu-bar app
```

## Build & run

### 1. Android beacon (requires Android Studio / SDK 35)

Open `android/` in Android Studio and run on your phone (or `./gradlew :app:assembleDebug`).
Android Studio will configure the Gradle wrapper on first sync.

Permissions requested at first launch: **Advertise**, **Connect** (Bluetooth), **Notifications**
(for the ongoing foreground-service notification).

Tap **Start beacon**, then copy the shown UUID — this is your identity.

### 2. macOS detector

```bash
cd macos
swift test                                  # behaviour is verified here
./Scripts/make_app.sh                       # → dist/Presence.app
open dist/Presence.app                      # later: drag to /Applications
```

Open the menu-bar **Presence** icon → **Settings… → Identity** → paste the phone's UUID.

### 3. Tune before trusting it (recommended)

Signal strength varies by hardware and room. Measure real numbers first with the CLI:

```bash
swift run PresenceCLI <phone-uuid> --dump     # raw RSSI near / away from your Mac
swift run PresenceCLI <phone-uuid>            # state machine + live transitions
```

Take notes of RSSI when the phone is on your desk vs. in the next room, and set the
**signal threshold** between those values in the menu-bar Settings → Tuning.

If you live in a small space (one hostel room, thin walls) the *maximum-power* default
beacon is heard clearly from far away and the boundary is fuzzy. Set the beacon's
**TX power to Low** in the phone app and recalibrate — the signal then collapses over a
few metres, so walking out the door genuinely trips the lock. Calibration with the phone
**in your hand at both spots** gives the most honest threshold, because hand/body
blocking shifts RSSI by ±15 dB; the app's smoothing + confirmation counts absorb that
flutter. Expect in-hand detection to be decisive but occasionally a second or two later.

##### Short-range mode (recommended for small rooms)

BLUETOOTH hint at 10 m walking distance rarely separates "desk" from "corridor", because
in-hand the signal stays strong through thin hostel walls. The reliable contract in a
small space is **short-range**: sit at the desk → Settings → Tuning → **"Set boundary
where I'm sitting now"** → the lock line anchors ~10 dB under your desk signal. The
Tuning tab shows live **headroom** (current signal minus the line; green/orange/red), so
you can see at a glance whether sitting there is safely in range or a lock is imminent.
Leaving the desk spot by >10 dB (usually 1–3 m) trips the lock; sitting back down is seen
again instantly (never auto-unlocked).

## Behaviour & configuration

| Control | Default | Meaning |
|---|---|---|
| Lock when away | on | On a *confirmed* away transition, the Mac locks: `CGSession -suspend` if present, else Ctrl+⌘+Q (needs Accessibility), else the built-in screen-saver lock (`open -a ScreenSaverEngine` + require-password policy), else `pmset displaysleepnow`. |

> **Unlock nuance:** the screen-saver lock requires a password (or Watch / Touch ID) to dismiss once `askForPassword` is enabled (the app sets this on first lock). Apple Watch / Touch ID auto-unlock makes returning seamless; to force a hard password, temporarily remove the watch or use an unregistered finger.
| Notify when back | on | Local notification on a confirmed home transition. **Never** unlocks. |
| Signal threshold | -80 dBm | Below this = out of range. |
| Away confirmations | 3 | Consecutive out-of-range samples before locking. |
| Home confirmations | 3 | Consecutive in-range samples before "back". |
| Stale timeout | 15 s | No samples at all → treat as away. |

## Testing

```bash
cd macos && swift test          # PresenceStateMachine (8) + TimelineStore (1)
```

The state machine tests pin the hard guarantees: single-sample blips never lock,
away/home transitions need their confirmation counts, stale gaps force away, no
duplicate transitions while already in a state.

Android ships a JVM test for the advertisement packet budget (`AdvPacket`).

## Honest limitations

- **Range ≠ room.** Bluetooth reach is tens of metres and walls are fuzzy. "Away" means
  "signal faded or voice gap", not "left the bedroom". Good enough to lock your Mac;
  not a floor-plan sensor.
- **No physical automation.** This repo locks the screen and writes a timeline. Driving a
  lamp directly needs a relay / smart plug (later ESP32 v2).
- **Spoofing model.** Identity is the advertised UUID; the practical threat for a home hobby
  build is negligible. A future hardening pass adds a secret token in manufacturer data.
- **Notifications** require macOS notification permission for the bundled app.
- **Bluetooth permission** is tied to the bundled app's
  `NSBluetoothAlwaysUsageDescription`. The bare `swift run` binaries work best for
  tuning the state machine offline; for live scanning run the app from
  `dist/Presence.app` (or otherwise grant BT access under System Settings →
  Privacy & Security).
- Built & certified on **macOS 13+**, **Android 9+** (BLE advertising). Android build artifacts
  are generated by Android Studio / Gradle 8.9+.

## Roadmap (ideas, not promises)

- [ ] **Windows 10/11 Support**: Native Win32 background detector service using `LockWorkStation` & BLE GATT watcher (launching in the next few weeks!)
- [ ] Secret token in manufacturer data (defence-in-depth)
- [ ] ESP32 v2: drop-in battery-powered box with a fixed antenna position → room-level tuning
- [ ] Export timeline to CSV for a "personal movement log"
- [ ] Configurable advertisement mode (low-power when idle)