# 宿主 App 集成

> 配合 [README.md](README.md)、[docs/DEVICE_BLE_PROTOCOL.md](docs/DEVICE_BLE_PROTOCOL.md)。
> 本 SDK 提供 **BLE / AT / OTA / WiFi / RecordingSession** 设备层能力；UI、云端、
> 本地 DB、业务续传策略由宿主 App 自行维护。

---

## 依赖方式

### 本地开发（monorepo）

```yaml
dependencies:
  sensecraft_voice:
    path: ../sensecraft-voice-sdk
```

### CI / 发版（Git 引用）

```yaml
dependencies:
  sensecraft_voice:
    git:
      url: https://github.com/Seeed-Studio/sensecraft-voice-sdk.git
      ref: v0.1.0
```

---

## 宿主 App 应自行提供

| 项 | 说明 | SenseCraft Voice App 示例 |
|----|------|---------------------------|
| 平台权限 | BLE、Location（Android &lt; 12）、Local Network（iOS WiFi） | `AndroidManifest.xml` / `Info.plist` |
| 设备 UI | 扫描、连接、详情、固件升级页 | `lib/src/features/device/` |
| 录音业务 | 多设备、后台续传、DB 索引、云端同步 | `lib/src/features/device/presentation/device_controller.dart` |
| 云端 | ASR / LLM / 存储 — SDK **不包含** | `lib/src/core/server/` |
| 日志桥接 | 可选 `SdkLog.bind(...)` 转发到 App logger | `lib/src/bootstrap.dart` |

---

## SDK 层 vs 产品层

| 层级 | 范围 | 本 SDK |
|------|------|--------|
| 设备协议 | BLE GATT、AT(JSON)、UDP 快传、OTA | ✅ |
| 高层会话 | `RecordingSession` start/stop/list/download | ✅ |
| 产品业务 | 录音列表 DB、Portal JWT、转写流程 | ❌ |

---

## 已知宿主 App

| App | 包名 / Bundle ID | SDK 依赖 | 业务文档 |
|-----|------------------|----------|----------|
| SenseCraft Voice | `cc.seeed.voice` | `path: ../sensecraft-voice-sdk` | 宿主仓库 `docs/RECORDING_FLOW.md` |

---

## 集成自检清单

```
- [ ] pubspec 引用 sensecraft_voice（path 或 git ref）
- [ ] Android：BLUETOOTH_SCAN / CONNECT / ADVERTISE；Android < 12 需 ACCESS_FINE_LOCATION
- [ ] iOS：NSBluetoothAlwaysUsageDescription；WiFi 快传需 Local Network 描述
- [ ] SdkLog.bind 已接入（可选，便于联调）
- [ ] 扫描 → connect → AtTransport → RecordingSession 最小链路可跑通
- [ ] OTA：使用 OtaFirmwareProcessor + mcumgr，或 OtaSession 高层封装
- [ ] WiFi 快传：WifiHotspotConnector.enable → WifiTransferClient.downloadSession
- [ ] 改设备协议行为时同步更新 docs/DEVICE_BLE_PROTOCOL.md
```

---

## Agent 接到任务时读什么

```
1. sensecraft-voice-sdk — 协议、公共 API、INTEGRATION.md
2. 宿主 App 仓库 — UI、DB、云端、业务续传策略
```
