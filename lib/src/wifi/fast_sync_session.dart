import '../at/at_transport.dart';
import '../models/wifi_hotspot_info.dart';
import '../utils/sdk_log.dart';
import 'hotspot_connector.dart';
import 'transfer_client.dart';

/// Orchestrates BLE hotspot enable → phone join → UDP session download → cleanup.
///
/// For batch downloads, call [prepare] once, use [transferClient] for each
/// session, then [teardown]. For a single session, [downloadSession] wraps
/// the full flow.
class WifiFastSyncSession {
  final AtTransport at;

  WifiHotspotConnector? _connector;
  WifiTransferClient? _client;
  WifiHotspotInfo? _hotspot;

  WifiFastSyncSession({required this.at});

  /// Active hotspot credentials after [prepare]. `null` before prepare or
  /// after [teardown].
  WifiHotspotInfo? get hotspot => _hotspot;

  /// UDP client valid between [prepare] and [teardown].
  WifiTransferClient? get transferClient => _client;

  /// Underlying BLE hotspot connector (e.g. for [WifiHotspotConnector.connectToHotspot] retries).
  WifiHotspotConnector? get connector => _connector;

  bool get isPrepared => _hotspot != null && _client != null;

  /// Re-bind app traffic to the device AP (see [WifiHotspotConnector.forceWifiUsage]).
  /// No-op if the connector is not yet created.
  Future<void> forceWifiUsage(bool force) async {
    final connector = _connector;
    if (connector == null) return;
    await connector.forceWifiUsage(force);
  }

  /// Enable device AP and create the UDP client. Does not join phone WiFi.
  Future<WifiHotspotInfo> enableHotspot() async {
    _connector ??= WifiHotspotConnector(at: at);
    SdkLog.i('[WiFi] WifiFastSyncSession: enable AP');
    _hotspot = await _connector!.enable();
    _client = WifiTransferClient(_hotspot!);
    return _hotspot!;
  }

  /// Join the phone to the active device AP. Call after [enableHotspot].
  Future<bool> connectPhone() async {
    final hotspot = _hotspot;
    final connector = _connector;
    if (hotspot == null || connector == null) {
      throw StateError('WifiFastSyncSession: call enableHotspot() first');
    }
    SdkLog.i('[WiFi] WifiFastSyncSession: join phone to "${hotspot.ssid}"');
    return connector.connectToHotspot(hotspot);
  }

  /// Enable device AP and optionally join from the phone. Keeps the session
  /// open for one or more [WifiTransferClient.downloadSession] calls.
  ///
  /// When [requirePhoneJoin] is `false`, a failed join is logged but does not
  /// throw — callers may verify with UDP ping (as the host app batch flow does).
  Future<WifiHotspotInfo> prepare({
    bool joinPhone = true,
    bool requirePhoneJoin = false,
  }) async {
    final hotspot = await enableHotspot();

    if (joinPhone) {
      final joined = await connectPhone();
      if (!joined) {
        final msg = 'Phone failed to join device AP "${hotspot.ssid}"';
        if (requirePhoneJoin) {
          throw StateError(
            '$msg. Check WiFi / Local Network permissions.',
          );
        }
        SdkLog.w('[WiFi] $msg — caller may retry UDP anyway');
      }
    }

    return hotspot;
  }

  /// Disconnect phone WiFi and disable device AP (best-effort).
  Future<void> teardown({
    bool disconnectPhone = true,
    bool disableHotspot = true,
  }) async {
    final hotspot = _hotspot;
    final connector = _connector;
    _client?.dispose();
    _client = null;

    if (connector != null) {
      if (hotspot != null && disconnectPhone) {
        await connector.disconnectFromHotspot(hotspot);
      }
      if (disableHotspot) {
        await connector.disable();
      }
    }

    _connector = null;
    _hotspot = null;
  }

  /// One-shot: [prepare] → UDP download → [teardown].
  Future<int> downloadSession({
    required String sessionId,
    required String sessionDir,
    String? startFile,
    WifiTransferProgress? onFileProgress,
    void Function(int fileIndex, int totalFiles, int overallBytes)?
        onOverallProgress,
    bool Function()? shouldCancel,
    bool disableHotspotAfter = true,
    bool disconnectPhoneAfter = true,
  }) async {
    try {
      await prepare(joinPhone: true, requirePhoneJoin: true);
      SdkLog.i('[WiFi] WifiFastSyncSession: UDP download session=$sessionId');
      final bytes = await _client!.downloadSession(
        sessionId: sessionId,
        sessionDir: sessionDir,
        startFile: startFile,
        onFileProgress: onFileProgress,
        onOverallProgress: onOverallProgress,
        shouldCancel: shouldCancel,
      );
      SdkLog.i('[WiFi] WifiFastSyncSession: done bytes=$bytes');
      return bytes;
    } finally {
      await teardown(
        disconnectPhone: disconnectPhoneAfter,
        disableHotspot: disableHotspotAfter,
      );
    }
  }
}
