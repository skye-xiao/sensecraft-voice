# SenseCraft Voice

Monorepo for the SenseCraft Voice Flutter app and Flutter, Android, and iOS
SDKs. The SDKs communicate directly with a SenseCraft Voice Clip over BLE and
the device Wi-Fi access point; no API key or backend configuration is required.

## Repository layout

```text
app/                  Complete Flutter demo
sdk/flutter/          Flutter SDK
sdk/android/          Native Android SDK and sample
sdk/ios/              Native iOS SDK and samples
docs/                 Integration and verification guides
scripts/              Environment checks
```

## Run the Flutter app

Use a physical phone for BLE, Wi-Fi transfer, and OTA:

```bash
git clone <repository-url> sensecraft-voice
cd sensecraft-voice
bash setup.sh android
# or: bash setup.sh ios
cd app
flutter run
```

The setup command checks the required toolchain and installs project
dependencies. On iOS, open `app/ios/Runner.xcworkspace`, choose your own
development Team, and ensure the App ID has Hotspot Configuration enabled.

## Run the native samples

Android:

```bash
cd sdk/android
./gradlew :sample:installDebug
adb shell am start -n io.sensecraft.voice.android.sample/.MainActivity
```

iOS:

```bash
cd sdk/ios
swift test
open Examples/iOSVerifyApp/SenseCraftVoiceVerifyApp.xcodeproj
```

See the [Android sample guide](sdk/android/sample/README.md) and
[iPhone sample guide](sdk/ios/Examples/iOSVerifyApp/README.md) for signing,
permissions, button order, Wi-Fi, OTA and troubleshooting.

## SDK verification

```bash
# Flutter
cd sdk/flutter
flutter pub get
flutter analyze
flutter test

# Android
cd sdk/android
./gradlew test
./gradlew :sample:assembleDebug

# iOS
cd sdk/ios
swift test
swift run SenseCraftVoiceVerifyCLI smoke
```

See [Getting started](docs/getting-started.md),
[native SDK verification](docs/native-sdk-verification.md), and each SDK's
README for platform-specific integration details.
