# SenseCraft Voice App

Complete Flutter demo for the SDK:

1. Forward SDK logs via `SdkLog.bind`
2. Scan for SenseCraft Voice Clip devices
3. Connect to one device
4. Send `AT+VERSION` and show the JSON reply
5. Stream battery level
6. Start / stop recording via `RecordingSession`
7. Read device status via `RecordingSession.getStatus()`
8. Download sessions over BLE or WiFi fast sync
9. Pick a `.zip` / `.bin` firmware package and run OTA

## Run

```bash
cd app
flutter pub get
flutter run   # use a physical device for reliable BLE
```

From the repository root you can also run `bash setup.sh android` or
`bash setup.sh ios` to validate the host environment and install dependencies.

The example already contains the Android BLE/WiFi permissions and the iOS
Bluetooth, Local Network, Bonjour, and Hotspot Configuration settings required
by these flows.

For iOS, open `ios/Runner.xcworkspace` once, select the Runner target, and choose
your own Apple Developer **Team**. No Seeed development team is committed to
the project. The Hotspot Configuration entitlement must be enabled for the
selected App ID. Then run `flutter run` on a physical iPhone.

For Android, make sure `ANDROID_HOME` is set (or create
`android/local.properties` with `sdk.dir=...`) and run on a physical Android
device. Android 13+ prompts for Nearby Wi-Fi Devices in addition to Bluetooth.

No API key or backend configuration is required. A SenseCraft Voice Clip is
required for BLE, WiFi, and OTA hardware verification. See the SDK
[README "Platform setup"](../sdk/flutter/README.md#platform-setup) and
[INTEGRATION.md](../sdk/flutter/INTEGRATION.md) for host-app integration
details.
