# SenseCraft Voice iOS SDK

Swift Package port of the Flutter `sensecraft-voice-sdk`.

Implemented capabilities:
- BLE scan/connect/disconnect
- direct reconnect by CoreBluetooth device identifier with connection timeout/retry
- post-connect `AT+GSTAT` verification with configurable timeout/retry
- AT(JSON) transport
- recording session helpers
- device management AT helpers (pause/resume/time/pair/mode/bookmarks/delete/purge/factory reset)
- Wi-Fi hotspot BLE control (`AT+WIFI?`, `AT+WIFI=ON`, `AT+WIFI=OFF`)
- phone Wi-Fi association via `NEHotspotConfiguration`
- Wi-Fi UDP transfer (`AT+GSTAT`, `AT+DOWNLOAD`, file frame parsing, CRC ACK/NACK, session file writes)
- Wi-Fi fast sync orchestration (single and batch download, AP reuse, failure classification, teardown)
- OTA firmware package parsing (`.bin`, `.zip` manifest, size/hash validation)
- OTA transport abstraction plus `NordicMcuMgrOtaTransport` when `iOSMcuManagerLibrary` is available
- file-data frame parsing
- BLE transfer frame state helper (`BleTransferFrameHandler`)
- BLE permission facade (`SenseCraftVoiceBlePermissions`)
- Wi-Fi transfer progress helper (`TransferProgress`)
- Wi-Fi AP network error helper (`WifiNetworkErrors`)
- device status and event models

## BLE connection readiness

```swift
let client = SenseCraftVoiceClient()

// iOS direct reconnect. `deviceId` is CBPeripheral.identifier.uuidString.
let connection = await client.connectByDeviceIdAndVerify(
    deviceId,
    connectTimeout: 8,
    connectAttempts: 2,
    policy: LinkReadyRetryPolicy(attempts: 3, retryGap: 0.45, timeout: 4)
)

// Or verify a discovered scan result before handing it to session code.
let verified = try await client.connectAndVerify(
    scanResult,
    connectTimeout: 15,
    policy: LinkReadyRetryPolicy()
)
```

`connectByDeviceId` is an iOS/CoreBluetooth fast path, not a BLE-address lookup.
It returns `nil` when the identifier is malformed, CoreBluetooth no longer knows
that peripheral, or all attempts fail. A new scan is then required.

## Wi-Fi fast sync

`WifiTransferClient.downloadSession` and
`WifiFastSyncSession.downloadSession` accept `onOverallProgress` for unified
0.0–1.0 progress.

For multiple recordings, `WifiFastSyncSession.downloadBatch` enables the device
AP once, verifies UDP reachability, downloads each `WifiBatchItem`, and tears
the AP down once. `WifiFastSyncBatchResult` reports counts, recording-state
abort, and whether BLE fallback is recommended:

- `phoneWifiDisconnected`: the AP route became unreachable.
- `phoneOnOtherWifi`: UDP verification timed out or the expected AP did not reply.
- `transferFailed`: the AP still replies but no item completed.

`ClipUdpSyncClient` uses Network.framework. On iOS its UDP connection requires
a Wi-Fi interface and prohibits cellular, so a device AP with no internet does
not silently route traffic through cellular. macOS keeps normal local route
selection for Ethernet/USB test setups while excluding cellular interfaces.

## Host app capabilities

- Enable **Hotspot Configuration** for automatic AP join through
  `NEHotspotConfiguration`.
- Add `NSLocalNetworkUsageDescription` to the host app `Info.plist`; UDP access
  to the device AP requires Local Network permission.
- Add the normal Bluetooth usage description(s) required by the host app's iOS
  deployment target.
- Add Nordic's `iOSMcuManagerLibrary` to the host app/package to activate `NordicMcuMgrOtaTransport`; otherwise the fallback returns an explicit unsupported error.

## Limits

- Automatic Wi-Fi association is iOS-only. The package still builds on macOS
  for tests and command-line verification, but it does not join an AP there.
- AP association success does not prove device reachability; batch download
  performs an explicit UDP `AT+GSTAT` probe.
- UDP file transfer resumes at a file marker (`startFile`), not a byte offset.
  `resumeByteOffset` is metadata for host progress/accounting.
- The SDK does not provide a Flutter bridge, playback, decoding, merging, or
  other audio processing.
- BLE/Wi-Fi behavior, entitlement approval, Local Network prompts, AP routing,
  and cellular coexistence still require validation on physical iOS devices.

## Verification

- `swift test`
- `swift run SenseCraftVoiceVerifyCLI smoke`
- See [`../../docs/native-sdk-verification.md`](../../docs/native-sdk-verification.md)
  for BLE and hardware smoke steps.

## License

Commercial — see [`LICENSE`](LICENSE).
