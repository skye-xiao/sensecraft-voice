import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/sdk_log.dart';
import 'ble_permissions.dart';
import 'ble_uuids.dart';
import 'mtu_manager.dart';

/// A live BLE link to a SenseCraft Voice Clip device, exposing the three
/// custom characteristics (command / response / file-data), the MTU manager
/// and an optional battery level stream.
class SenseCraftVoiceConnection {
  final BluetoothDevice device;
  final BluetoothCharacteristic commandRx;
  final BluetoothCharacteristic responseTx;
  final BluetoothCharacteristic fileData;
  final MtuManager mtu;

  /// BLE Battery Level (0x2A19) subscription stream when supported by the
  /// device. Values are clamped to `0..100`.
  final Stream<int>? batteryLevelStream;

  final BluetoothCharacteristic? _batteryCharacteristic;

  SenseCraftVoiceConnection({
    required this.device,
    required this.commandRx,
    required this.responseTx,
    required this.fileData,
    required this.mtu,
    this.batteryLevelStream,
    BluetoothCharacteristic? batteryCharacteristic,
  }) : _batteryCharacteristic = batteryCharacteristic;
}

/// Top-level entry point of the SDK.
///
/// Wraps `flutter_blue_plus` to scan for, connect to and disconnect from
/// SenseCraft Voice Clip devices. Use [SenseCraftVoiceConnection] with
/// [AtTransport] to send AT commands and receive recording files.
class SenseCraftVoiceClient {
  /// Live BLE scan results from the underlying stack.
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  /// Whether the stack is currently scanning.
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  /// Phone Bluetooth adapter state (on / off / turningOn / …).
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  /// Android only: show the system dialog to turn Bluetooth on.
  Future<void> turnOnAdapter() => FlutterBluePlus.turnOn();

  /// Latest adapter state (waits briefly if the stack still reports [BluetoothAdapterState.unknown]).
  Future<BluetoothAdapterState> getCurrentAdapterState() async {
    try {
      return await adapterState.first.timeout(const Duration(seconds: 2));
    } catch (_) {
      return BluetoothAdapterState.unknown;
    }
  }

  /// Start a BLE scan.
  ///
  /// When [filterByService] is `true` (default), the scan filters by the
  /// custom Clip AT service UUID; this is cleaner and faster. When `false`,
  /// it falls back to a name keyword filter (`"Clip"`) which matches the
  /// Python tooling.
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 12),
    bool filterByService = true,
  }) async {
    final ok = await SenseCraftVoiceBlePermissions.ensureGranted();
    if (!ok) {
      throw StateError('Bluetooth permissions not granted');
    }

    // iOS: adapterState often starts "unknown"; wait for "on" before scan.
    if (Platform.isIOS) {
      try {
        final state = await FlutterBluePlus.adapterState
            .where((s) =>
                s == BluetoothAdapterState.on ||
                s == BluetoothAdapterState.unauthorized)
            .first
            .timeout(const Duration(seconds: 15));
        if (state == BluetoothAdapterState.unauthorized) {
          throw StateError('Bluetooth permission denied');
        }
        SdkLog.i('SenseCraftVoiceClient: iOS adapter ready (on)');
      } on TimeoutException {
        SdkLog.w(
          'SenseCraftVoiceClient: iOS adapter state timeout; '
          'attempting scan anyway',
        );
      }
    }

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    // Short settle time for the Android BLE stack.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    if (filterByService) {
      await FlutterBluePlus.startScan(
        withServices: [SenseCraftVoiceBleUuids.clipAtService],
        androidScanMode: AndroidScanMode.lowLatency,
        timeout: timeout,
      );
      return;
    }

    await FlutterBluePlus.startScan(
      // Fallback: match by name keyword. Note: flutter_blue_plus on Android
      // restricts combining `withKeywords` with other filters.
      withKeywords: const ['Clip'],
      androidScanMode: AndroidScanMode.lowLatency,
      timeout: timeout,
    );
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  /// Connect by device ID without scanning (fast path for reconnect).
  ///
  /// Returns `null` if direct connect fails (e.g. device out of range, or
  /// the platform requires a fresh scan first).
  Future<SenseCraftVoiceConnection?> connectByDeviceId(String deviceId) async {
    BluetoothDevice? device;
    try {
      device = BluetoothDevice.fromId(deviceId);
      SdkLog.i(
        'SenseCraftVoiceClient.connectByDeviceId: '
        'attempting direct connect to $deviceId',
      );
      await device.connect();
      await device.connectionState
          .where((s) => s == BluetoothConnectionState.connected)
          .first
          .timeout(const Duration(seconds: 8));
      return _buildConnection(device);
    } catch (e) {
      SdkLog.w(
        'SenseCraftVoiceClient.connectByDeviceId failed',
        e,
        StackTrace.current,
      );
      if (device != null) {
        try {
          await device.disconnect();
        } catch (_) {}
      }
      return null;
    }
  }

  /// Connect to a previously-discovered scan result.
  Future<SenseCraftVoiceConnection> connect(ScanResult result) async {
    final device = result.device;
    SdkLog.i('Connecting to ${device.remoteId} ${device.platformName}');

    await device.connect();
    await device.connectionState
        .where((s) => s == BluetoothConnectionState.connected)
        .first;

    return _buildConnection(device);
  }

  Future<SenseCraftVoiceConnection> _buildConnection(
    BluetoothDevice device,
  ) async {
    final mtuManager = MtuManager(device);
    await mtuManager.startListening();

    Object? lastError;
    StackTrace? lastStack;
    for (var pass = 1; pass <= 2; pass++) {
      // Tracks whether *this* attempt created a brand-new bond. If so, a
      // follow-up GATT hiccup must NOT trigger removeBond+createBond — that
      // would pop a *second* system pairing dialog for what is usually just a
      // transient GATT 133. We only repair a genuinely *stale* bond.
      final freshBond = _FreshBondFlag();
      try {
        return await _buildConnectionAttempt(device, mtuManager, freshBond);
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        if (!Platform.isAndroid ||
            pass >= 2 ||
            freshBond.value ||
            !_looksLikeAndroidAuthFailure(e)) {
          Error.throwWithStackTrace(e, st);
        }
        SdkLog.w(
          'BLE bond: Clip GATT auth/encryption failed with existing bond; '
          'repairing stale bond before retry (pass $pass)',
          e,
          st,
        );
        await _repairAndroidBond(device);
      }
    }

    Error.throwWithStackTrace(
      lastError ?? StateError('BLE Clip connection setup failed'),
      lastStack ?? StackTrace.current,
    );
  }

  Future<SenseCraftVoiceConnection> _buildConnectionAttempt(
    BluetoothDevice device,
    MtuManager mtuManager,
    _FreshBondFlag freshBond,
  ) async {
    // Clip firmware requires LE Secure Connections; some Android OEMs (e.g.
    // MIUI) drop the link with GATT status 5 instead of showing the pairing
    // dialog when we enable notify without a bond — call createBond early.
    freshBond.value = await _ensureAndroidBonded(device);
    // Conservative MTU: very large MTU causes link drops on some firmwares.
    await mtuManager.requestHighMtu();

    final services = await device.discoverServices();
    BluetoothCharacteristic? cmd;
    BluetoothCharacteristic? resp;
    BluetoothCharacteristic? file;

    for (final s in services) {
      if (s.uuid == SenseCraftVoiceBleUuids.clipAtService) {
        for (final c in s.characteristics) {
          if (c.uuid == SenseCraftVoiceBleUuids.commandRxCharacteristic) {
            cmd = c;
          }
          if (c.uuid == SenseCraftVoiceBleUuids.responseTxCharacteristic) {
            resp = c;
          }
          if (c.uuid == SenseCraftVoiceBleUuids.fileDataCharacteristic) {
            file = c;
          }
        }
      }
    }

    if (cmd == null || resp == null || file == null) {
      throw StateError('Clip AT characteristics not found on device');
    }

    // Some Android stacks (incl. Huawei) return GATT 133 on the first CCCD write;
    // retry after a short settle before tearing down the link.
    if (Platform.isAndroid) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await _setNotifyWithRetry(resp, true, label: 'responseTx');
    await _setNotifyWithRetry(file, true, label: 'fileData');
    await _requestAndroidHighConnectionPriority(device);

    Stream<int>? batteryStream;
    BluetoothCharacteristic? batteryChar;
    for (final s in services) {
      if (s.uuid == SenseCraftVoiceBleUuids.batteryService) {
        for (final c in s.characteristics) {
          if (c.uuid == SenseCraftVoiceBleUuids.batteryLevelCharacteristic) {
            batteryChar = c;
            break;
          }
        }
        break;
      }
    }
    if (batteryChar != null) {
      try {
        await batteryChar.setNotifyValue(true);
        batteryStream = batteryChar.lastValueStream
            .where((v) => v.isNotEmpty)
            .map((v) => v[0].clamp(0, 100));
        await batteryChar.read();
        SdkLog.i('BLE battery service subscribed');
      } catch (e) {
        SdkLog.w('BLE battery subscribe failed', e, StackTrace.current);
        batteryChar = null;
      }
    }

    _logLinkSnapshot(
      device: device,
      mtu: mtuManager,
      cmd: cmd,
      resp: resp,
      file: file,
      discoveredServicesCount: services.length,
    );
    _logRssiAfterConnect(device);

    return SenseCraftVoiceConnection(
      device: device,
      commandRx: cmd,
      responseTx: resp,
      fileData: file,
      mtu: mtuManager,
      batteryLevelStream: batteryStream,
      batteryCharacteristic: batteryChar,
    );
  }

  Future<void> disconnect(SenseCraftVoiceConnection conn) async {
    try {
      await conn.mtu.dispose();
      await conn.responseTx.setNotifyValue(false);
      await conn.fileData.setNotifyValue(false);
      final bc = conn._batteryCharacteristic;
      if (bc != null) {
        try {
          await bc.setNotifyValue(false);
        } catch (_) {}
      }
    } catch (_) {}
    await conn.device.disconnect();
  }
}

/// Tracks whether a connection attempt freshly created the bond.
class _FreshBondFlag {
  bool value = false;
}

/// Android-only: ensure the Clip bond exists before encrypted GATT ops.
///
/// [BluetoothDevice.createBond] shows the system pairing UI when needed.
/// Safe to call when already bonded (no-op). Returns `true` only when a brand
/// new bond was created in this call (i.e. the system pairing dialog was shown
/// and confirmed) so callers can avoid re-prompting on a subsequent hiccup.
Future<bool> _ensureAndroidBonded(BluetoothDevice device) async {
  if (!Platform.isAndroid) return false;

  var current = await _readAndroidBondState(device);

  if (current == BluetoothBondState.bonded) {
    SdkLog.i('BLE bond: already bonded remoteId=${device.remoteId}');
    await _reconnectAndroidGattIfNeeded(device);
    return false;
  }

  // Not bonded yet. Clip firmware sends an SMP Security Request right after
  // connect, so on most phones the *stack* auto-initiates bonding within a few
  // hundred ms. Calling createBond() while that auto-pairing is already in
  // flight pops a SECOND system dialog — the user sees two pairing prompts.
  //
  // Give the firmware/stack a short grace window to start bonding on its own;
  // only fall back to an explicit createBond() if nothing happens within it
  // (some OEMs, e.g. MIUI, never auto-pair and instead drop the link with GATT
  // status 5, so the explicit bond is still required there).
  if (current == BluetoothBondState.none) {
    try {
      current = await device.bondState
          .where((s) => s != BluetoothBondState.none)
          .first
          .timeout(const Duration(seconds: 3));
      SdkLog.i(
        'BLE bond: stack auto-initiated bonding ($current) — '
        'not calling createBond remoteId=${device.remoteId}',
      );
    } on TimeoutException {
      SdkLog.i(
        'BLE bond: no auto-bonding within grace window; '
        'falling back to createBond remoteId=${device.remoteId}',
      );
      current = BluetoothBondState.none;
    } catch (e, st) {
      SdkLog.w('BLE bond: grace-window watch failed', e, st);
      current = await _readAndroidBondState(device);
    }
  }

  // Auto-bonding already started (or finished): just wait it out, never prompt
  // a second time with createBond.
  if (current == BluetoothBondState.bonding ||
      current == BluetoothBondState.bonded) {
    if (current == BluetoothBondState.bonding) {
      SdkLog.i(
        'BLE bond: pairing in progress, waiting remoteId=${device.remoteId}',
      );
      // Diagnostic: log every bond-state transition so we can tell whether the
      // peripheral re-runs SMP (e.g. bonding->none->bonding->bonded), which
      // shows up to the user as two system pairing dialogs and is a firmware
      // (not app) issue. A clean single pairing is just bonding->bonded.
      await _awaitAndroidBondedLogged(device);
    }
    await _reconnectAndroidGattIfNeeded(device);
    return true;
  }

  SdkLog.i(
    'BLE bond: createBond — confirm the system pairing dialog '
    'remoteId=${device.remoteId}',
  );
  await device.createBond(timeout: 90);
  SdkLog.i('BLE bond: createBond ok remoteId=${device.remoteId}');
  // Many Android stacks drop GATT briefly after bonding; reconnect before CCCD.
  await _reconnectAndroidGattIfNeeded(device);
  return true;
}

/// Waits for [device] to reach [BluetoothBondState.bonded] while logging every
/// intermediate transition with the elapsed time between them. The transition
/// trace is the evidence we hand to firmware when the user reports "two system
/// pairing dialogs": a single clean pairing is `bonding -> bonded`, whereas a
/// firmware that re-issues SMP shows `bonding -> none -> bonding -> bonded`
/// (each `none -> bonding` flip is a fresh system dialog).
Future<void> _awaitAndroidBondedLogged(
  BluetoothDevice device, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final completer = Completer<void>();
  var last = DateTime.now();
  var transitions = 0;
  late final StreamSubscription<BluetoothBondState> sub;
  sub = device.bondState.listen((s) {
    final now = DateTime.now();
    final deltaMs = now.difference(last).inMilliseconds;
    last = now;
    transitions++;
    SdkLog.i(
      'BLE bond transition #$transitions: $s (+${deltaMs}ms) '
      'remoteId=${device.remoteId}',
    );
    if (s == BluetoothBondState.bonded && !completer.isCompleted) {
      completer.complete();
    }
  });
  try {
    await completer.future.timeout(timeout);
    if (transitions > 2) {
      SdkLog.w(
        'BLE bond: completed but observed $transitions state transitions — '
        'peripheral likely re-ran SMP (extra system pairing dialog). This is a '
        'firmware-side issue, not the app. remoteId=${device.remoteId}',
      );
    } else {
      SdkLog.i('BLE bond: pairing completed remoteId=${device.remoteId}');
    }
  } catch (e, st) {
    SdkLog.w('BLE bond: wait for bonding failed', e, st);
  } finally {
    await sub.cancel();
  }
}

Future<void> _waitAndroidConnected(
  BluetoothDevice device, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (!device.isDisconnected) return;
  await device.connect(timeout: timeout);
  await device.connectionState
      .where((s) => s == BluetoothConnectionState.connected)
      .first
      .timeout(timeout);
  if (Platform.isAndroid) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

Future<void> _reconnectAndroidGattIfNeeded(BluetoothDevice device) async {
  if (!Platform.isAndroid) return;
  if (!device.isDisconnected) return;
  SdkLog.i(
    'BLE bond: reconnecting GATT after bond transition remoteId=${device.remoteId}',
  );
  await _waitAndroidConnected(device);
}

Future<BluetoothBondState> _readAndroidBondState(BluetoothDevice device) async {
  try {
    return await device.bondState.first.timeout(const Duration(seconds: 3));
  } catch (_) {
    return BluetoothBondState.none;
  }
}

/// Only true for *genuine* auth/encryption failures that indicate a stale bond
/// (LTK mismatch), NOT generic transient errors. Matching GATT 133 or the word
/// "gatt" here was too broad: a transient 133 right after a fresh createBond
/// would wrongly trigger removeBond+createBond and pop a 2nd pairing dialog.
///
/// Relevant ATT/GATT statuses:
/// - 5  (0x05) insufficient authentication
/// - 15 (0x0F) insufficient encryption
/// - 137 (0x89) GATT_AUTH_FAIL
bool _looksLikeAndroidAuthFailure(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('insufficient authentication') ||
      msg.contains('insufficient encryption') ||
      msg.contains('gatt_auth_fail') ||
      msg.contains('auth_fail') ||
      msg.contains('status 5') ||
      msg.contains('status 15') ||
      msg.contains('status 137');
}

/// Clears a stale phone-side bond then re-pairs once. Used after unbind when
/// the Clip was reset but Android still caches the old bond.
Future<void> _repairAndroidBond(BluetoothDevice device) async {
  if (!Platform.isAndroid) return;

  SdkLog.w('BLE bond: repairing stale bond remoteId=${device.remoteId}');

  if (!device.isDisconnected) {
    try {
      await device.removeBond(timeout: 30);
    } catch (e, st) {
      SdkLog.w('BLE bond: removeBond during repair failed', e, st);
    }
  } else {
    try {
      await device.removeBond(timeout: 10);
    } catch (_) {}
  }

  await Future<void>.delayed(const Duration(milliseconds: 300));
  var bond = await _readAndroidBondState(device);
  if (bond != BluetoothBondState.none && device.isDisconnected) {
    try {
      await _waitAndroidConnected(device);
      try {
        await device.removeBond(timeout: 30);
      } catch (e, st) {
        SdkLog.w('BLE bond: removeBond after reconnect failed', e, st);
      }
      bond = await _readAndroidBondState(device);
    } catch (e, st) {
      SdkLog.w('BLE bond: connect-for-unbond failed', e, st);
    }
  }

  try {
    await device.disconnect();
  } catch (_) {}
  await Future<void>.delayed(const Duration(milliseconds: 250));

  await _waitAndroidConnected(device);
  bond = await _readAndroidBondState(device);
  if (bond != BluetoothBondState.bonded) {
    await device.createBond(timeout: 90);
  }
  await _reconnectAndroidGattIfNeeded(device);
}

/// Android-only: ask the stack for high (low-latency) connection priority to
/// boost notify throughput. The peripheral may reject the parameter update,
/// in which case this is a no-op.
Future<void> _setNotifyWithRetry(
  BluetoothCharacteristic characteristic,
  bool enable, {
  required String label,
  int maxAttempts = 3,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await characteristic.setNotifyValue(enable);
      if (attempt > 1) {
        SdkLog.i(
          'BLE setNotifyValue($enable) $label succeeded on attempt $attempt',
        );
      }
      return;
    } catch (e, st) {
      lastError = e;
      if (attempt >= maxAttempts) break;
      SdkLog.w(
        'BLE setNotifyValue($enable) $label attempt $attempt/$maxAttempts failed',
        e,
        st,
      );
      await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
    }
  }
  Error.throwWithStackTrace(
    lastError ?? StateError('setNotifyValue failed for $label'),
    StackTrace.current,
  );
}

Future<void> _requestAndroidHighConnectionPriority(
  BluetoothDevice device,
) async {
  if (!Platform.isAndroid) return;
  try {
    await device.requestConnectionPriority(
      connectionPriorityRequest: ConnectionPriority.high,
    );
    SdkLog.i(
      'BLE: requestConnectionPriority(high) sent (Android) — '
      'stack may use shorter conn interval; peripheral can reject',
    );
  } catch (e, st) {
    SdkLog.w('BLE: requestConnectionPriority(high) failed', e, st);
  }
}

void _logLinkSnapshot({
  required BluetoothDevice device,
  required MtuManager mtu,
  required BluetoothCharacteristic cmd,
  required BluetoothCharacteristic resp,
  required BluetoothCharacteristic file,
  required int discoveredServicesCount,
}) {
  final os = Platform.isIOS
      ? 'iOS'
      : Platform.isAndroid
          ? 'Android'
          : Platform.operatingSystem;
  final pc = cmd.properties;
  final pr = resp.properties;
  final pf = file.properties;
  SdkLog.i(
    'BLE Clip link: os=$os remoteId=${device.remoteId} '
    'name="${device.platformName}" connected=${device.isConnected} '
    'mtuManager=${mtu.mtu} mtuFbpNow=${device.mtuNow} '
    'attPayload~${mtu.payloadSize}B gattServices=$discoveredServicesCount | '
    'commandRx write=${pc.write} writeWithoutResp=${pc.writeWithoutResponse} '
    'read=${pc.read} | responseTx notify=${pr.notify} indicate=${pr.indicate} | '
    'fileData notify=${pf.notify} indicate=${pf.indicate}',
  );
}

void _logRssiAfterConnect(BluetoothDevice device) {
  Future<void>(() async {
    try {
      final rssi = await device.readRssi(timeout: 8);
      SdkLog.i(
        'BLE link RSSI: $rssi dBm remoteId=${device.remoteId} '
        '(mtuFbpNow=${device.mtuNow} for cross-check)',
      );
    } catch (e, st) {
      SdkLog.w('BLE link RSSI: read failed', e, st);
    }
  });
}
