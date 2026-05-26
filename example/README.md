# sensecraft_voice example

Minimal Flutter app demonstrating the SDK:

1. Forward SDK logs via `SdkLog.bind`
2. Scan for SenseCraft Voice Clip devices
3. Connect to one device
4. Send `AT+VERSION` and show the JSON reply
5. Stream battery level
6. Start / stop recording via `RecordingSession`
7. Read device status via `RecordingSession.getStatus()`

WiFi fast sync and OTA are documented in the SDK [README](../README.md) and
[INTEGRATION.md](../INTEGRATION.md); run those flows from a host app or extend
this example when testing on hardware.

## Run

```bash
cd example
flutter pub get
flutter run   # use a physical device for reliable BLE
```

Ensure Android `AndroidManifest.xml` and iOS `Info.plist` declare BLE /
location permissions — see the SDK
[README "Platform setup"](../README.md#platform-setup).
