# Changelog

## 0.1.0 — Initial preview release

Initial preview release, extracted from the SenseCraft Voice reference app.

### Added

- BLE scanning, connection, MTU management for SenseCraft Voice Clip devices
  (`SenseCraftVoiceClient`, `SenseCraftVoiceConnection`, `MtuManager`).
- AT(JSON) protocol transport with chunked write, JSON object framing, and
  reply matching (`AtTransport`).
- BLE permission helper for iOS/Android (`SenseCraftVoiceBlePermissions`).
- Battery level subscription.
- Device, `DeviceFileMeta`, `WifiHotspotInfo` data models.
- Pluggable logger (`SdkLog`).
- `OtaFirmwareProcessor` — parse `.zip` (with `manifest.json`) or `.bin`
  firmware packages into mcumgr `Image`s.
- `OtaSession` — high-level OTA orchestrator with normalised phases
  (`preparing → uploading → validating → resetting → success`), aggregated
  byte progress across multi-image archives, and `cancel()`.
- `WifiHotspotConnector` — enable / disable / probe device AP, join from the
  phone (Android + iOS).
- `ClipUdpSyncClient` + `WifiTransferClient` — UDP file sync on the device AP
  (port 8089).
- `RecordingSession` — high-level wrapper for `AT+START` / `AT+STOP` /
  `AT+CANCEL` / `AT+LIST` / `AT+GSTAT` / `AT+DOWNLOAD`. Exposes
  `Stream<DownloadEvent>`.
- `DeviceStatus` — typed view of `AT+GSTAT` reply.
- `parseDeviceEvent` — typed device push events on the JSON notify stream.
- Protocol reference: `docs/DEVICE_BLE_PROTOCOL.md`.
- Example app demonstrating scan, connect, `AT+VERSION`, and
  `RecordingSession.start/stop/getStatus`.

### Out of scope

- Cloud / ASR / LLM helpers — the SDK is backend-agnostic; bring your own cloud.
