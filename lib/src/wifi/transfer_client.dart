import '../models/wifi_hotspot_info.dart';
import '../utils/sdk_log.dart';
import 'udp_sync_client.dart';

typedef WifiTransferProgress = void Function(int received, int total);

/// WiFi (UDP) file sync over device AP — aligned with `py_test/tools/udp_sync.py`
/// and `py_test/clip/wifi.py` (port 8089, binary frames + plain `AT+…\\n`).
class WifiTransferClient {
  WifiTransferClient(this.hotspot);

  final WifiHotspotInfo hotspot;
  ClipUdpSyncClient? _udp;

  Future<void> _ensureConnected() async {
    _udp ??= ClipUdpSyncClient(receiveTimeout: const Duration(seconds: 8));
    await _udp!.connect(hotspot.ip, hotspot.port);
  }

  /// UDP + `AT+GSTAT` (or device idle) — not HTTP.
  Future<bool> ping() async {
    try {
      await _ensureConnected();
      SdkLog.i('[WiFi] UDP ping → ${hotspot.ip}:${hotspot.port} (AT+GSTAT)');
      final ok = await _udp!.ping();
      if (ok) {
        SdkLog.i('[WiFi] SUCCESS: UDP reachable at ${hotspot.ip}:${hotspot.port} (sync path ready)');
      } else {
        SdkLog.w('[WiFi] UDP ping returned false (${hotspot.ip}:${hotspot.port})');
      }
      return ok;
    } catch (e) {
      SdkLog.w('[WiFi] UDP ping failed (${hotspot.ip}:${hotspot.port})', e);
      return false;
    }
  }

  /// Download session via UDP binary transfer (FILE_START / DATA / FILE_END / TRANSFER_DONE).
  Future<int> downloadSession({
    required String sessionId,
    required String sessionDir,
    String? startFile,
    WifiTransferProgress? onFileProgress,
    void Function(int fileIndex, int totalFiles, int overallBytes)? onOverallProgress,
    bool Function()? shouldCancel,
  }) async {
    await _ensureConnected();
    final udp = _udp!;

    return udp.downloadSession(
      sessionId: sessionId,
      sessionDir: sessionDir,
      startFile: startFile,
      shouldCancel: shouldCancel,
      onProgress: (currentFile, filesDone, totalFiles, receivedBytes, totalBytes) {
        onFileProgress?.call(receivedBytes, totalBytes ?? -1);
        onOverallProgress?.call(filesDone, totalFiles, receivedBytes);
      },
    );
  }

  void dispose() {
    _udp?.dispose();
    _udp = null;
  }
}
