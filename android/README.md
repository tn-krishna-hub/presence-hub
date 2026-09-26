# Presence Beacon (Android)

The phone half of the Presence system. A foreground service advertises a
**per-install UUID** over BLE as a non-connectable service-UUID beacon.

## Build

Requires Android Studio (or Gradle 8.9+ with JDK 17) and SDK 35.

1. Open this folder in Android Studio.
2. Let it configure the Gradle wrapper (first sync), then run on a physical phone —
   BLE advertising does **not** work reliably on emulators.
3. On first launch, accept Bluetooth + notification permissions.

## What to do

1. Tap **Start beacon** (a persistent "Beacon active" notification stays up).
2. Copy the **identity UUID** shown on screen.
3. Paste it into the macOS app's Settings → Identity.

## Layout

| File | Purpose |
|---|---|
| `BeaconAdvertiser.kt` | Wraps `BluetoothLeAdvertiser`; non-connectable, service-UUID advertisement |
| `BeaconService.kt` | Foreground service (`connectedDevice`) that keeps the advert alive in background |
| `IdentityStore.kt` | One stable UUID per install |
| `MainActivity.kt` | Permissions, identity display, start/stop |
| `AdvPacket.kt` | Packet-budget model for the legacy 31-byte advertising packet |

## Design notes

- **Non-connectable** + **`AllowDuplicates`** on the Mac's scan is what makes the Mac see
  fresh RSSI continuously. Connectable beacons cause the stack to try pairing instead.
- A full 128-bit UUID fits the legacy 31-byte packet (see `AdvPacket` + tests).
- Battery: `LOW_LATENCY` mode is used for reliability in v1; a low-power toggle is a
  sensible future change.

## Tests

```bash
./gradlew :app:testDebugUnitTest
```