import 'dart:async';
import 'dart:typed_data';

import '../at/at_transport.dart';
import '../ble/ble_client.dart';
import '../ble/clip_file_data.dart';
import '../models/device.dart';
import '../models/device_file_meta.dart';
import '../utils/sdk_log.dart';
import 'device_event.dart';
import 'device_status.dart';

/// Result of [RecordingSession.start]: the session ID assigned by firmware
/// and the raw JSON in case the caller wants extra fields.
class RecordingStartInfo {
  /// Session ID returned by firmware. Use this with [RecordingSession.download]
  /// to fetch the recording later.
  final String sessionId;

  /// Recording mode echoed back by firmware (when reported).
  final RecordingMode? mode;

  /// Original reply, in case the caller wants vendor-specific extra fields.
  final Map<String, dynamic> raw;

  const RecordingStartInfo({
    required this.sessionId,
    required this.mode,
    required this.raw,
  });
}

/// Result of [RecordingSession.stop]: best-effort summary of the just-stopped
/// session.
class RecordingStopInfo {
  /// Session that was stopped. Some firmwares return it on STOP; otherwise we
  /// echo the [RecordingSession.activeSessionId] cached locally.
  final String? sessionId;

  /// Reported duration in seconds, when available.
  final int? durationSeconds;

  /// Reported total file count for the session, when available.
  final int? fileCount;

  /// Original reply.
  final Map<String, dynamic> raw;

  const RecordingStopInfo({
    required this.sessionId,
    required this.durationSeconds,
    required this.fileCount,
    required this.raw,
  });
}

/// One event during an `AT+DOWNLOAD` flow.
sealed class DownloadEvent {
  const DownloadEvent();
}

/// `AT+DOWNLOAD` was acknowledged by firmware; bytes are about to flow.
final class DownloadStarted extends DownloadEvent {
  final String sessionId;
  final int? totalFiles;
  final int? totalBytes;
  const DownloadStarted({
    required this.sessionId,
    required this.totalFiles,
    required this.totalBytes,
  });
}

/// A FILE_START frame: a new file is beginning in this transfer.
final class DownloadFileStarted extends DownloadEvent {
  final String filename;
  final int fileSize;
  const DownloadFileStarted({
    required this.filename,
    required this.fileSize,
  });
}

/// Progress update for the current file. [received] is bytes received for the
/// current file so far; [total] is the expected size (or `-1` if unknown).
final class DownloadFileProgress extends DownloadEvent {
  final String filename;
  final int received;
  final int total;
  const DownloadFileProgress({
    required this.filename,
    required this.received,
    required this.total,
  });
}

/// A complete file has been received.
final class DownloadFileCompleted extends DownloadEvent {
  final String filename;
  final Uint8List bytes;
  final int crc32;
  const DownloadFileCompleted({
    required this.filename,
    required this.bytes,
    required this.crc32,
  });
}

/// The whole transfer is complete (`TRANSFER_DONE` frame).
final class DownloadTransferDone extends DownloadEvent {
  final String sessionId;
  final int fileCount;
  const DownloadTransferDone({
    required this.sessionId,
    required this.fileCount,
  });
}

/// Wraps the common recording workflow:
///   1. `AT+START` → device records
///   2. `AT+STOP`  → device finishes the session and reports duration/files
///   3. `AT+LIST`  → enumerate files on device
///   4. `AT+DOWNLOAD` → pull file bytes over the file-data notify channel
///
/// Construct one [RecordingSession] per BLE connection; it is reusable for
/// multiple start/stop cycles.
class RecordingSession {
  final SenseCraftVoiceConnection connection;
  final AtTransport at;

  RecordingSession({required this.connection, required this.at});

  /// Session ID currently in progress on the device (between
  /// [start] and [stop]). `null` when idle.
  String? get activeSessionId => _activeSessionId;
  String? _activeSessionId;

  /// Broadcast stream of typed unsolicited events from the device, parsed
  /// from `at.jsonMessages`.
  ///
  /// Use this to react to the firmware's button-driven actions described in
  /// `py_test/docs/protocol.md` Appendix E:
  /// - Long-press start/stop emits a [DeviceRecordingStateEvent] with
  ///   `state: RECORDING` or `state: IDLE`.
  /// - Short-press during recording adds a bookmark and emits a
  ///   [DeviceBookmarkEvent].
  ///
  /// AT command responses **without** an `event` field are filtered out.
  /// The stream is broadcast — multiple listeners are supported and
  /// late-attached listeners only see events from the moment they subscribe.
  Stream<DeviceEvent> get deviceEvents => at.jsonMessages
      .map(parseDeviceEvent)
      .where((e) => e != null)
      .cast<DeviceEvent>();

  /// Start a new recording.
  Future<RecordingStartInfo> start({
    RecordingMode mode = RecordingMode.normal,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final cmd = mode == RecordingMode.enhanced ? 'AT+START=enhanced' : 'AT+START';
    final resp = await at.send(cmd, timeout: timeout);
    if (resp['ok'] != true) {
      throw RecordingException(
        'AT+START failed: ${_errorDetail(resp)}',
        raw: resp,
      );
    }
    final sid = _extractSession(resp);
    if (sid == null || sid.isEmpty) {
      throw RecordingException('AT+START did not return a session', raw: resp);
    }
    _activeSessionId = sid;
    final reportedMode = _extractRecordingMode(resp);
    SdkLog.i('RecordingSession started: session=$sid mode=$mode');
    return RecordingStartInfo(
      sessionId: sid,
      mode: reportedMode ?? mode,
      raw: resp,
    );
  }

  /// Stop the active recording.
  Future<RecordingStopInfo> stop({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final resp = await at.send('AT+STOP', timeout: timeout);
    final sid = _extractSession(resp) ?? _activeSessionId;
    final data = resp['data'];
    final m = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final dur = _asInt(m['duration']);
    final fileCount = _asInt(m['file_count']);
    _activeSessionId = null;
    SdkLog.i(
      'RecordingSession stopped: session=$sid duration=${dur}s files=$fileCount',
    );
    return RecordingStopInfo(
      sessionId: sid,
      durationSeconds: dur,
      fileCount: fileCount,
      raw: resp,
    );
  }

  /// Cancel any in-flight recording **or** transfer. Best-effort — failures
  /// are logged and ignored.
  Future<void> cancel() async {
    try {
      await at.send('AT+CANCEL', timeout: const Duration(seconds: 4));
    } catch (e, st) {
      SdkLog.w('RecordingSession.cancel: AT+CANCEL failed', e, st);
    }
    _activeSessionId = null;
  }

  /// Query the device's global status (`AT+GSTAT`).
  Future<DeviceStatus> getStatus({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final resp = await at.send('AT+GSTAT', timeout: timeout);
    if (resp['ok'] != true) {
      throw RecordingException(
        'AT+GSTAT failed: ${_errorDetail(resp)}',
        raw: resp,
      );
    }
    return DeviceStatus.fromAtReply(resp);
  }

  /// Maximum byte length the firmware accepts for `AT+NAME=<value>` payload.
  /// Aligned with `py_test/docs/protocol.md` 3.3.7 AT+NAME validation rules
  /// (1–32 characters, printable UTF-8). Apps should validate user input
  /// before calling [setUserDeviceName] to surface rejections inline.
  static const int userDeviceNameMaxBytes = 32;

  /// Sentinel value defined by the protocol to clear the user-defined name.
  /// `AT+NAME=CLEAR` resets the persisted name on the device to empty.
  static const String userDeviceNameClearToken = 'CLEAR';

  /// Returns `true` when [name] is acceptable to send via [setUserDeviceName]
  /// without using the [userDeviceNameClearToken] escape.
  ///
  /// Per `protocol.md` 3.3.7:
  /// - 1–32 UTF-8 bytes (CJK counts as 3 bytes each)
  /// - No control characters (0x00–0x1F)
  /// - Empty string is rejected — use `setUserDeviceName(null)` to clear
  static bool isValidUserDeviceName(String name) {
    if (name.isEmpty) return false;
    final bytes = name.codeUnits;
    if (bytes.length > userDeviceNameMaxBytes) return false;
    for (final c in name.runes) {
      if (c < 0x20) return false;
    }
    return true;
  }

  /// Read the user-defined device name persisted on the device
  /// (`AT+NAME?`).
  ///
  /// Returns an empty string when no name is set. Throws
  /// [RecordingException] when the firmware reports `ok:false`.
  Future<String> getUserDeviceName({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final resp = await at.send('AT+NAME?', timeout: timeout);
    if (resp['ok'] != true) {
      throw RecordingException(
        'AT+NAME? failed: ${_errorDetail(resp)}',
        raw: resp,
      );
    }
    final data = resp['data'];
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final n = m['name'];
      if (n is String) return n;
      if (n != null) return n.toString();
    }
    // Some firmwares return the value at the root.
    final root = resp['name'] ?? resp['value'];
    if (root is String) return root;
    if (root != null) return root.toString();
    return '';
  }

  /// Persist a user-defined name on the device (`AT+NAME=<value>` /
  /// `AT+NAME=CLEAR`). Survives reboots and does not affect BLE / WiFi
  /// advertising names.
  ///
  /// Pass `null` (or empty string) to clear the stored name. Validates
  /// against the protocol rules first; throws [ArgumentError] for inputs
  /// that the firmware would reject. Throws [RecordingException] when the
  /// firmware itself returns `ok:false`.
  Future<void> setUserDeviceName(
    String? name, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final String cmd;
    if (name == null || name.isEmpty) {
      cmd = 'AT+NAME=$userDeviceNameClearToken';
    } else {
      if (!isValidUserDeviceName(name)) {
        throw ArgumentError.value(
          name,
          'name',
          'AT+NAME requires 1-32 UTF-8 chars, no control characters '
              '(use null or "" to clear).',
        );
      }
      cmd = 'AT+NAME=$name';
    }
    final resp = await at.send(cmd, timeout: timeout);
    if (resp['ok'] != true) {
      throw RecordingException(
        'AT+NAME failed: ${_errorDetail(resp)}',
        raw: resp,
      );
    }
  }

  /// List recording files on the device. When [sessionId] is `null`, returns
  /// every file the firmware reports.
  Future<List<DeviceFileMeta>> listFiles({
    String? sessionId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final cmd = sessionId == null ? 'AT+LIST' : 'AT+LIST=$sessionId';
    final resp = await at.send(cmd, timeout: timeout);
    if (resp['ok'] != true) {
      throw RecordingException(
        'AT+LIST failed: ${_errorDetail(resp)}',
        raw: resp,
      );
    }
    return _parseFileList(resp);
  }

  /// Stream events for an `AT+DOWNLOAD` flow.
  ///
  /// - Sends `AT+DOWNLOAD=$sessionId[:startFile]`.
  /// - Listens to the file-data notify characteristic for FILE_START / DATA /
  ///   FILE_END / TRANSFER_DONE frames.
  /// - Buffers raw DATA bytes per file and emits [DownloadFileCompleted] with
  ///   the full payload when the firmware sends FILE_END.
  ///
  /// The stream completes after [DownloadTransferDone] or on timeout / error.
  /// Cancelling the subscription does **not** send `AT+CANCEL` automatically;
  /// call [cancel] yourself if you need that.
  Stream<DownloadEvent> download({
    required String sessionId,
    String? startFile,
    Duration timeout = const Duration(minutes: 10),
  }) {
    final controller = StreamController<DownloadEvent>();

    String? currentFile;
    int currentExpected = 0;
    final fileBuf = BytesBuilder(copy: false);

    StreamSubscription<List<int>>? framesSub;
    Timer? timeoutTimer;

    Future<void> closeOnDone(Object? error, [StackTrace? st]) async {
      timeoutTimer?.cancel();
      await framesSub?.cancel();
      framesSub = null;
      if (controller.isClosed) return;
      if (error != null) {
        controller.addError(error, st);
      }
      await controller.close();
    }

    controller.onListen = () async {
      try {
        framesSub = at.fileDataBytes.listen((bytes) {
          final frame = parseClipFileDataNotify(bytes);
          switch (frame) {
            case ClipParsedFileStart():
              currentFile = frame.filename;
              currentExpected = frame.fileSize;
              fileBuf.clear();
              controller.add(DownloadFileStarted(
                filename: frame.filename,
                fileSize: frame.fileSize,
              ));
              break;
            case ClipParsedData():
              if (currentFile == null) {
                // Pre-FILE_START data is dropped; legacy firmwares without
                // FILE_START frames should use the raw `at.fileDataBytes`
                // stream directly.
                return;
              }
              fileBuf.add(frame.payload);
              controller.add(DownloadFileProgress(
                filename: currentFile!,
                received: fileBuf.length,
                total: currentExpected,
              ));
              break;
            case ClipParsedFileEnd():
              final fname = currentFile ?? '';
              final payload = fileBuf.toBytes();
              controller.add(DownloadFileCompleted(
                filename: fname,
                bytes: payload,
                crc32: frame.crc32,
              ));
              currentFile = null;
              currentExpected = 0;
              fileBuf.clear();
              break;
            case ClipParsedTransferDone():
              controller.add(DownloadTransferDone(
                sessionId: frame.sessionId,
                fileCount: frame.fileCount,
              ));
              unawaited(closeOnDone(null));
              break;
            case ClipParsedRaw():
              // Legacy / unknown frame — surface as completed file with empty
              // crc when we have a buffer; otherwise ignore so we don't pollute
              // the event stream.
              if (currentFile != null) {
                fileBuf.add(frame.bytes);
              }
              break;
            case ClipParsedInvalid():
              SdkLog.w(
                'RecordingSession.download: malformed file frame: ${frame.reason}',
              );
              break;
          }
        }, onError: (Object e, StackTrace st) {
          unawaited(closeOnDone(e, st));
        });

        timeoutTimer = Timer(timeout, () {
          unawaited(closeOnDone(
            TimeoutException('Download stalled', timeout),
            StackTrace.current,
          ));
        });

        final cmd = (startFile != null && startFile.trim().isNotEmpty)
            ? 'AT+DOWNLOAD=$sessionId:${startFile.trim()}'
            : 'AT+DOWNLOAD=$sessionId';
        final resp = await at.send(cmd, timeout: const Duration(seconds: 10));
        if (resp['ok'] != true) {
          await closeOnDone(RecordingException(
            'AT+DOWNLOAD failed: ${_errorDetail(resp)}',
            raw: resp,
          ));
          return;
        }
        final dataMap = resp['data'] is Map
            ? Map<String, dynamic>.from(resp['data'] as Map)
            : const <String, dynamic>{};
        controller.add(DownloadStarted(
          sessionId: sessionId,
          totalFiles: _asInt(dataMap['files'] ?? dataMap['file_count']),
          totalBytes: _asInt(dataMap['bytes'] ?? dataMap['size']),
        ));
      } catch (e, st) {
        await closeOnDone(e, st);
      }
    };

    controller.onCancel = () async {
      timeoutTimer?.cancel();
      await framesSub?.cancel();
    };

    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _errorDetail(Map<String, dynamic> resp) {
    final msg = resp['error'] ?? resp['msg'] ?? resp['message'];
    if (msg != null && '$msg'.isNotEmpty) return msg.toString();
    final data = resp['data'];
    if (data is Map && data['msg'] != null) return data['msg'].toString();
    return resp.toString();
  }

  static String? _extractSession(Map<String, dynamic> resp) {
    final root = (resp['session'] ?? '').toString().trim();
    if (root.isNotEmpty) return root;
    final data = resp['data'];
    if (data is Map) {
      final inner = (data['session'] ?? '').toString().trim();
      if (inner.isNotEmpty) return inner;
    }
    return null;
  }

  static RecordingMode? _extractRecordingMode(Map<String, dynamic> resp) {
    final data = resp['data'];
    if (data is Map) {
      final s = (data['mode'] ?? '').toString().trim().toLowerCase();
      if (s.isEmpty) return null;
      if (s == 'enhanced' || s == '1') return RecordingMode.enhanced;
      return RecordingMode.normal;
    }
    return null;
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static List<DeviceFileMeta> _parseFileList(Map<String, dynamic> resp) {
    final data = resp['data'];
    if (data is! Map) return const [];
    final items = data['items'] ?? data['files'];
    if (items is! List) return const [];
    final out = <DeviceFileMeta>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final path = (m['path'] ?? m['file'] ?? '').toString();
      if (path.isEmpty) continue;
      out.add(DeviceFileMeta(
        deviceId: '',
        path: path,
        name: (m['name'] ?? path.split('/').last).toString(),
        sizeBytes: _asInt(m['size'] ?? m['bytes']) ?? 0,
        durationSeconds: _asInt(m['duration']) ?? 0,
        bookmarkCount: _asInt(m['bookmark_count'] ?? m['bookmarks']) ?? 0,
        createdAt: _parseTimestamp(m['created_at'] ?? m['mtime']),
      ));
    }
    return out;
  }

  static DateTime? _parseTimestamp(Object? v) {
    if (v == null) return null;
    if (v is int) {
      // Heuristic: seconds vs milliseconds.
      final ms = v > 4102444800 ? v : v * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed;
      final n = int.tryParse(v);
      if (n != null) {
        final ms = n > 4102444800 ? n : n * 1000;
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    return null;
  }
}

/// Generic error thrown by [RecordingSession] when the firmware reply is
/// `ok:false` or otherwise unusable.
class RecordingException implements Exception {
  final String message;
  final Map<String, dynamic>? raw;

  const RecordingException(this.message, {this.raw});

  @override
  String toString() => 'RecordingException: $message';
}
