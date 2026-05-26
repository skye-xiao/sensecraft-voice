# sensecraft_voice example

Minimal Flutter app that demonstrates:

1. Forwarding SDK logs via `SdkLog.bind`
2. Scanning for SenseCraft Voice Clip devices
3. Connecting to one
4. Sending `AT+VERSION` and showing the JSON reply
5. Streaming battery level

## Run

```bash
cd example
flutter pub get
flutter run        # plug an Android phone (BLE works in iOS simulator only partially)
```

Make sure the host app's Android `AndroidManifest.xml` and iOS `Info.plist`
declare the BLE / location permissions — see the SDK
[README "Platform setup"](../README.md#platform-setup).
