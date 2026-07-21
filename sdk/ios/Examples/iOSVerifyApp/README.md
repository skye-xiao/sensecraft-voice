# SenseCraft Voice iPhone UI Sample

This sample app is a small manual verification host for the native iOS SDK.

## What it covers

- BLE scan and connect
- `AT+GSTAT`
- `AT+START` / `AT+STOP`
- `AT+VERSION` / `AT+TIME?` / `AT+PAIR?`
- `AT+MARK`
- `AT+LIST`
- `AT+DOWNLOAD` merge and finalize flows
- device time sync
- Wi-Fi hotspot enable and join
- UDP ping
- session download
- OTA file pick and upgrade trigger
- local no-hardware smoke checks

## How to use

Prerequisites:

- Xcode with iOS 16 SDK or newer
- An Apple Developer account for physical-device signing
- A physical iPhone and a SenseCraft Voice Clip

From a clean checkout, first verify the package from the repository root:

```bash
swift test
swift run SenseCraftVoiceVerifyCLI smoke
```

Then open `SenseCraftVoiceVerifyApp.xcodeproj` in Xcode:

1. Select the **SenseCraftVoiceVerifyApp** target.
2. Under **Signing & Capabilities**, select your own development **Team** and
   change the bundle identifier if needed. No development team is committed.
3. Ensure the App ID has **Hotspot Configuration** enabled. The entitlement is
   already present in `Entitlements/SenseCraftVoiceVerifyApp.entitlements`.
4. Select a physical iPhone and run.

No API key or backend configuration is required.

If the project needs to be regenerated after moving files, run this from the repository root:

```bash
ruby sdk/ios/Examples/iOSVerifyApp/Scripts/generate_xcodeproj.rb
```

## Required capabilities

- Bluetooth
- Hotspot Configuration
- Local Network

## Notes

OTA package parsing works without an extra dependency. To perform the actual
SMP/mcumgr transfer, add Nordic's package to the app target:

```text
https://github.com/NordicSemiconductor/IOS-McuManager-Library.git
```

Link the `iOSMcuManagerLibrary` product to the app. The SDK detects it with
`canImport(iOSMcuManagerLibrary)` and activates `NordicMcuMgrOtaTransport`.
Without the package, the sample still builds and reports a clear
`unsupported` result when OTA is triggered.
