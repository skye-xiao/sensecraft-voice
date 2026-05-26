import '../at/at_transport.dart';
import '../models/wifi_hotspot_info.dart';
import '../utils/sdk_log.dart';
import 'hotspot_connector.dart';
import 'transfer_client.dart';

/// Orchestrates BLE hotspot enable → phone join → UDP session download → cleanup.
///
/// Typical usage:
///
/// ```dart
/// final sync = WifiFastSyncSession(at: at);
/// final bytes = await sync.downloadSession(
///   sessionId: '20260401/foo',
///   sessionDir: '/tmp/downloads/20260401/foo',
/// );
/// ```
class WifiFastSyncSession {
  final AtTransport at;

  WifiHotspotConnector? _connector;
  WifiTransferClient? _client;

  WifiFastSyncSession({required this.at});

  /// Enable the device AP, join from the phone, download [sessionId] over UDP,
  /// then disable the AP and disconnect the phone (best-effort).
  ///
  /// Returns total bytes written under [sessionDir]. Throws [StateError] when
  /// the phone fails to join the AP or UDP transfer fails.
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
    _connector = WifiHotspotConnector(at: at);
    WifiHotspotInfo? hotspot;
    try {
      SdkLog.i('[WiFi] WifiFastSyncSession: enable AP');
      hotspot = await _connector!.enable();

      SdkLog.i('[WiFi] WifiFastSyncSession: join phone to "${hotspot.ssid}"');
      final joined = await _connector!.connectToHotspot(hotspot);
      if (!joined) {
        throw StateError(
          'Phone failed to join device AP "${hotspot.ssid}". '
          'Check WiFi / Local Network permissions.',
        );
      }

      _client = WifiTransferClient(hotspot);
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
      _client?.dispose();
      _client = null;
      if (hotspot != null && disconnectPhoneAfter) {
        await _connector?.disconnectFromHotspot(hotspot);
      }
      if (disableHotspotAfter) {
        await _connector?.disable();
      }
      _connector = null;
    }
  }
}
