# SenseCraft Voice Android Sample

This app is a manual verification host for the Android SDK. It covers BLE
scan/connect, recording start/stop/pause/resume, device status and management,
file listing, BLE download, WiFi prepare/ping/download, and `.zip` / `.bin`
firmware OTA.

## Prerequisites

- JDK 17 or newer (the SDK bytecode target remains Java 11)
- Android SDK 36
- A physical Android device with USB debugging enabled
- A SenseCraft Voice Clip for hardware operations

Set `ANDROID_HOME`, or create `local.properties` in the repository root:

```properties
sdk.dir=/absolute/path/to/Android/sdk
```

No API key or backend configuration is required.

## Build and run

From the monorepo's `sdk/android` directory:

```shell
./gradlew test
./gradlew :sample:assembleDebug
./gradlew :sample:installDebug
```

On first launch:

1. Tap **Request permissions** and grant Bluetooth, location (where requested),
   and Nearby Wi-Fi Devices.
2. Tap **Scan Clip 12s**, then tap a result to connect.
3. Use the recording and BLE download controls directly.
4. For WiFi transfer, stop recording, enter a session ID, then tap **WiFi
   Prepare**, **WiFi Ping**, and **WiFi Download** in order. Accept Android's
   device-hotspot connection prompt.
5. For OTA, stay connected, tap **Choose Firmware + OTA**, and select a valid
   `.zip` or `.bin` firmware package.

BLE, WiFi, and OTA require a physical device; an emulator is only suitable for
the local smoke checks and UI inspection. Downloaded files are written under
the app-specific external files directory in `SenseCraftDownloads`.
