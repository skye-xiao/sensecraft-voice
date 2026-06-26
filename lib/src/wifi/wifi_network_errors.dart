import 'dart:io';

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
        msg.contains('host is down')) {
      return true;
    }
  }
  final s = error.toString().toLowerCase();
  return s.contains('network is unreachable') ||
      s.contains('network is down') ||
      s.contains('errno = 101') ||
      s.contains('errno = 100');
}
