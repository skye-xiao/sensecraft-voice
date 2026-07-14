import 'dart:io';

const _wifiUdpStackMarkers = <String>[
  'udp_sync_client.dart',
  'transfer_client.dart',
  'wifi_transfer_controller.dart',
  'ClipUdpSyncClient._send',
  'ClipUdpSyncClient.ping',
  'ClipUdpSyncClient.downloadSession',
  'ClipUdpSyncClient.sendAtCommand',
  'WifiTransferClient.ping',
  '_wifiStillReachable',
  '_wifiReachabilityProbe',
];

/// Heuristic: phone cannot route UDP to the device AP (Wi‑Fi off, wrong network, etc.).
/// Used to fail fast instead of retrying ping for ~60s when the path is clearly dead.
bool isDeviceApNetworkUnreachable(Object error) {
  if (error is SocketException) {
    final code = error.osError?.errorCode;
    // ENETUNREACH / ENETDOWN / EHOSTUNREACH (Linux/Android/iOS vary).
    if (code == 51 || code == 65 || code == 100 || code == 101 || code == 113) {
      return true;
    }
    final msg = error.message.toLowerCase();
    if (msg.contains('network is unreachable') ||
        msg.contains('network is down') ||
        msg.contains('no route to host') ||
        msg.contains('host is down') ||
        msg.contains('machine is not on the network')) {
      return true;
    }
  }
  final s = error.toString().toLowerCase();
  return s.contains('network is unreachable') ||
      s.contains('network is down') ||
      s.contains('machine is not on the network') ||
      s.contains('errno = 101') ||
      s.contains('errno = 100') ||
      s.contains('errno = 64');
}

/// True when a routing failure is the normal Wi‑Fi AP reachability probe outcome
/// (phone left device AP / Wi‑Fi disabled). These should not be crash reports.
bool isWifiApReachabilitySocketNoise(
  Object error, {
  StackTrace? stackTrace,
}) {
  if (!isDeviceApNetworkUnreachable(error)) return false;
  final trace = stackTrace?.toString() ?? '';
  if (trace.isEmpty) {
    return error is SocketException;
  }
  return _stackLooksLikeWifiUdpProbe(trace);
}

bool _stackLooksLikeWifiUdpProbe(String trace) {
  for (final marker in _wifiUdpStackMarkers) {
    if (trace.contains(marker)) return true;
  }
  return false;
}
