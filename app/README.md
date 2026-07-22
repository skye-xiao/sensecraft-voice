# respeaker-app

**reSpeaker** —— 穿戴式 AI 麦克风配套 App（Flutter 跨平台，iOS / Android）。

---

## 产品简介

respeaker-app 连接 ReSpeaker 硬件设备与云端服务，为用户提供 **录音 → 同步 → 转写 → 总结** 的一站式语音处理体验。

```
┌──────────────┐      BLE         ┌──────────────────┐      HTTPS       ┌──────────────────┐
│ ReSpeaker    │◄────────────────►│  respeaker-app    │◄────────────────►│  后端服务         │
│ 硬件设备     │   录音/文件传输   │  (Flutter)        │   OSS/ASR/LLM    │  sensecraft-      │
└──────────────┘                  └──────────────────┘                  │  respeaker-service│
                                                                        └──────────────────┘
```

---

## 核心功能

| 模块 | 说明 |
|------|------|
| **设备管理** | BLE 扫描/连接、边录边传、断点续传、OTA 固件升级 |
| **录音管理** | 设备 & 本地文件列表（首页按页加载 + 上拉加载更多）、文件夹管理、搜索、回收站 |
| **语音转写** | 多厂商 ASR（阿里云、Azure 等），支持多语言，异步 Job 模式 |
| **智能总结** | 多厂商 LLM（OpenAI、通义千问等），流式 SSE，可自定义 Prompt 模版 |
| **AI 配置** | STT/LLM 多厂商配置、模版 CRUD、配置分享、新手引导 |
| **账号体系** | OAuth（Google/Apple/GitHub）+ 邮箱登录/注册、Token 自动刷新 |

---

## 技术栈

| 维度 | 技术 |
|------|------|
| 框架 | Flutter (Dart) |
| 架构 | Feature-first + Clean Architecture |
| 状态管理 | Riverpod |
| 路由 | go_router |
| 本地存储 | sqflite (SQLite) |
| 设备通信 | BLE (GATT) / AT 命令协议 |
| 固件升级 | SMP (mcumgr) over BLE |

---

## 文档

完整索引与阅读顺序见 **[docs/README.md](docs/README.md)**。常用条目：

| 文档 | 说明 |
|------|------|
| [设计框架与架构](docs/project_design_framework.md) | 系统分层、架构选型、数据流、App↔后端接口契约 |
| [录音与同步流程](docs/recording_flow.md) | 录音→设备同步（含断点续传、索引）→转写→总结→播放 |
| [设备 BLE 协议](../../sensecraft-voice/docs/DEVICE_BLE_PROTOCOL.md) | BLE UUID、AT 命令、返回值约定（SDK 权威文档） |
| [OTA 固件升级](docs/ota_firmware_update.md) | 固件升级步骤与错误处理 |
| [路由速查](docs/app_routes.md) | 路由路径与页面对应关系 |
| [本地数据库](docs/local_db.md) | SQLite 表结构与业务逻辑 |
| [API 速查](docs/api_reference.md) | App 调用的后端 API 接口 |
| [AI 厂商参数](docs/ai_provider_params.md) | STT/LLM 各厂商字段映射 |
| [国内 Android 上架](docs/china_android_store.md) | 隐私弹窗、隐藏第三方登录、本地 run / 打包 |

---

## 设备兼容性

- **三星等大字体设备**：全局限制文字缩放（0.9~1.2x），避免系统大字体导致布局异常
- **华为设备**：Ogg Opus 播放兼容处理，自动回退 WAV 解码
- **iOS**：息屏 BLE 断开自动重连，跳过 Ogg Opus 直接走 WAV；若同步卡在 0% 且日志出现 `JSON decode failed`，多为 **JSON 通知特征值** 上混入了非 JSON 字节或 **`"bytes"` 进度字段被截断**（如 `raw` 里出现 `"bytes":lu`）——App 端会：① 对损坏的 `bytes` 尝试修复为 `0` 后重新解析，避免 `AT+DOWNLOAD` 一直等不到合法 JSON；② 在等 `AT+DOWNLOAD` 应答时忽略误到达的 **GSTAT（IDLE）** 帧，避免把状态查询当成下载应答；③ 仍会忽略纯合成解析失败帧。仍建议固件保证 **响应 Notify** 与 **文件数据 Notify** 严格分流，且进度 JSON 完整发出。
- **BLE 吞吐排障（日志）**：连接成功后会打印 `BLE MTU stream:`、`BLE Clip link:`、`BLE link RSSI:`、`BLE link +500ms:`。其中 `BLE Clip link` 含 `connected`、`mtuManager`（本连接监听）、`mtuFbpNow`（FBP 全局缓存，可与前者对照）、已发现 **GATT 服务数量**、各特征的 `write` / `writeWithoutResp` / `notify`；`+500ms` 行再次对比 `mtuManager` 与 `mtuFbpNow`。**Android** 会调用 `requestMtu(185)`（与对端取 min），并在打开 notify 后调用 `requestConnectionPriority(high)`，向系统请求更短 **连接间隔**（外设仍可拒绝或只部分生效）。**iOS**：FBP 无 `requestMtu`；**无**与 Android 对等的 App 侧「设置 connection interval」公开 API，MTU 由 **CoreBluetooth 自动协商**。若有效载荷已很大而速度仍偏低，瓶颈多在 **连接间隔 / 链路层 / 固件发包**。
- **点录音时仍像在读旧会话**：固件在传文件时 GSTAT 有时仍为 `IDLE`，或 `AT+START` 后 GSTAT 的 `session` 尚未切到新会话；App 若仅按「空闲」去续传，可能对 **别的会话** 发 `AT+DOWNLOAD`。当前逻辑：① 续传前若 GSTAT 未给出录音中的 session，则改用本机 `activeRecordingSessionId`（`AT+START` 成功后已写入），只同步该会话；② 在「录音态→GSTAT idle」的回调里，若本机仍有活动录音 session、或仍有 BLE 传输跟踪、或处于录音开始保护期，则 **不** 自动触发续传；③ 开始录音前 **总是** 再发一次 `AT+CANCEL`，减少固件仍在 drain 上一路传输时立刻 `START` 的竞态。
- **多条待同步时先传旧日期**：续传曾用 `COALESCE(transfer_started_at, created_at)` **升序**，故会先传 4 月 3 日再传 4 月 7 日。已改为 **降序**，与列表一致（先传最新一条）。
- **重新同步「没反应」**：① 列表/横幅的 `retryTransfer` 会检查 `downloadSessionToLocal` 是否真正启动；若被录音保护、Wi‑Fi 快传占用、或与当前 BLE 传输互斥而 **未启动**，提示 `resyncCouldNotStart` 而非误报「已开始」。② 未连接设备时点列表同步图标会提示先连接。③ 顶部传输卡片在 **边录边传、总长未知** 时也会显示「重新同步」（取消按钮仍仅在已知总长或已结束时可用）。
- **列表上多条同时在「同步中」、日志里同一毫秒大量重复 `TRANSFER_DONE` / `FILE_START`**：固件侧同一时间只能一路传输；此前 App 里 `downloadSessionToLocal` 在写入 `_activeTransferRecordingId` 之前有一段异步准备窗口，**重新同步、自动续传、resume 循环**等可并发进入，多路逻辑同时订阅同一 BLE 通知，表现为多文件一起动、进度乱跳、`PathNotFound` 临时文件、以及 `AT+DOWNLOAD` /「Transfer already in progress」打架。现用 **`_bleDownloadExclusiveChain` 全局串行**：任一时间只有一个 `downloadSessionToLocal` 实例跑完（含 finally）后，下一个才会开始。
- **上一片传完开始下一片，进度条仍 100%**：`TransferProgressBanner` 里 `_AnimatedTransferProgress` 用 `_progressFloor` 防止抖动回退；多文件时新 `FILE_START` 后 **比例会从 ~99% 掉回当前片比例**，但 **已收字节仍单调增加**，旧逻辑不会重置 floor，显示一直被钳在 100%。现当 **目标进度明显下降（>4%）且已收字节未回退** 时同步降低 floor，允许条与「同步中 n%」跟上下一片。
- **同步中已显示 100% 但仍有速率**：传输中 DB/UI 将比例上限钳在 **0.995**（未完成不当真 100%），而 `(0.995*100).round()` 在 Dart 中为 **100**，进度条也几乎铺满。现：**同步中**条形与文案上限 **0.99**，百分比用 **floor** 最高 **99%**；**结束**后再显示 100%。
- **多切片连续传时新文件一开仍像满格**：上一片 `FILE_END` 会把 `transferProgress` 写到接近 0.995，下一片 `FILE_START` 之前不写库，直到下一片数据满足 **8 KiB / 2 s** 节流 —— 顶层横幅仍显示上一片进度。现：**每条 `BLE FILE_START` 立即按当前片 0 字节重算进度并入库**；横幅侧对「已收字节增加且比例略低于 floor」额外放宽回落，避免缓存的 `_progressFloor` 短时锁死。
- **长时间停在「同步中 99%」**：只要 `transfer_state` 仍为 transferring，[`_wifiAlignedBleTransferProgress`](lib/src/features/device/presentation/device_controller.dart) 会把写入 DB 的比例 **封顶 0.995**；横幅再用 **0.99 + floor** 显示，容易长时间看起来「卡在 99%」——尤其当前分片在 **sliceBytes** 分支时，单片传到尾会一直顶格，整体会话仍在继续。**定位**：在 Xcode / `flutter run` 控制台搜 `BLE transferProgress near 0.995 cap`，看 `branch=`（`sliceBytes` / `filesOnly` / `files+sessionBytes` / `expectedSession`）、`rawRatio`（未封顶的真实比例）与 `slice=`、`files=`；对照 SQLite `received_bytes`、`expected_bytes`、`transfer_progress`。若 `rawRatio` 已远大于 1 或 `devSessBytes` 明显偏小，多为分母与固件不一致。
- **固件已 TRANSFER_DONE（如 877/877）仍像 99%**：`filesOnly` 算出 1.0 也会被 0.995 钳住，合并 800+ 分片前一直像未满。现：当 `TRANSFER_DONE` / JSON `transfer_complete` 的 **files** 与 `AT+DOWNLOAD` 的 **total** 一致（或 `fileCompleteCount` 已达），写 **`transfer_progress=1.0`**；横幅对 **`p==1.0` 且仍 transferring** 显示 **100%**（合并阶段），避免误以为 BLE 未传完。
- **大文件播放/波形**：本地播放用 8 kHz WAV 兜底以缩短解码；转写上传仍为 16 kHz；波形按时间块渐进刷新，详情页延迟订阅波形流以优先出声音
