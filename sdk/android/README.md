# SenseCraft Voice Android SDK

Kotlin port of the Flutter `sensecraft-voice-sdk`.

Implemented in this first pass:
- BLE scan/connect/disconnect
- AT(JSON) transport
- recording session helpers
- device runtime snapshot, mark, list files, list bookmarks, device time sync
- device management AT helpers (pause/resume/time/pair/mode/bookmarks/delete/purge/factory reset)
- Wi-Fi hotspot BLE control (`AT+WIFI?`, `AT+WIFI=ON`, `AT+WIFI=OFF`)
- phone Wi-Fi association via `WifiNetworkSpecifier` (API 29+) and `WifiConfiguration` fallback
- Wi-Fi UDP transfer (`AT+GSTAT`, `AT+DOWNLOAD`, file frame parsing, CRC ACK/NACK, session file writes)
- Wi-Fi fast sync orchestration (single/batch download, verification, BLE fallback reason, teardown)
- periodic Android process binding to the device AP for the prepared session lifetime
- BLE download merge and finalize flows
- reusable resume markers, canonical expected-byte verification, slice inventory, and merge helpers
- OTA firmware package parsing (`.bin`, `.zip` manifest, size/hash validation)
- OTA SMP/mcumgr transfer via `NordicMcuMgrOtaTransport`
- file-data frame parsing
- BLE transfer frame state helper (`BleTransferFrameHandler`)
- BLE permission facade (`SenseCraftVoiceBlePermissions`)
- Wi-Fi transfer progress helper (`TransferProgress`)
- Wi-Fi AP network error helper (`WifiNetworkErrors`)
- device status and event models

`WifiTransferClient.downloadSession` / `WifiFastSyncSession.downloadSession` also accept `onOverallProgress` for a unified 0.0-1.0 progress value.

## Wi-Fi batch fast sync

`WifiFastSyncSession.downloadBatch` keeps one device hotspot session alive for all
items, checks UDP reachability before transfer, stops when recording starts, and
returns a typed `WifiBleFallbackReason` when the caller should hand off to BLE.
Each `WifiBatchItem` carries the local/device ids, destination directory,
expected bytes, and resume metadata. A `WifiBatchResolveStartFile` callback can
resolve the marker immediately before each transfer.

While prepared, the SDK reapplies `forceWifiUsage(true)` every 10 seconds.
`teardown` cancels that coroutine, disposes UDP jobs/sockets, unbinds the process,
and unregisters the Android `NetworkCallback`, including failure paths.

## Public session file helpers

The package-level APIs `resolveSessionResumeStartFile`,
`resolveSessionResumeMarkers`, `resolveResumeByteFloor`,
`canonicalTransferExpectedBytes`, `inventorySessionOpusParts`, and
`mergeSessionOpusPartsInDirectory` are shared by `RecordingSession` and direct
SDK consumers. Merge inventory ignores partial files and does not append stale
`part_last.opus` after numbered slices appear.

## Maven / AAR

Coordinates are currently:

```text
io.sensecraft:sensecraft-voice-android:0.1.0
```

The Gradle `release` Maven publication includes the release AAR and sources JAR.
No remote repository or credentials are configured. To validate artifacts
locally without publishing externally:

```shell
./gradlew assembleRelease generatePomFileForReleasePublication
```

Integration notes:
- Pass an Android `Context` to `WifiFastSyncSession(at, context)` or `WifiHotspotConnector(at, context)` for automatic AP join.
- Runtime Wi-Fi/location permissions are still the host app's responsibility.
- Use `OtaSession(deviceId, NordicMcuMgrOtaTransport(context, bluetoothDevice))` for OTA.

Verification:
- `./gradlew test`
- `./gradlew :sample:assembleDebug`
- `./gradlew :sample:installDebug`
- sample Activity covers scan/connect, recording controls, runtime snapshot,
  mark, list files/bookmarks, time sync, BLE merge/finalize, Wi-Fi
  prepare/ping/download, OTA file selection/upgrade, and basic smoke checks
- See [`sample/README.md`](sample/README.md) for clean-environment setup and the
  recommended hardware verification order.
- See [`../../docs/native-sdk-verification.md`](../../docs/native-sdk-verification.md)
  for BLE and hardware smoke steps.

License:
- Commercial — see [`LICENSE`](LICENSE).
