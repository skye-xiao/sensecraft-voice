import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensecraft_voice/sensecraft_voice.dart';

void main() {
  // Forward SDK logs to console for the demo.
  SdkLog.bind((level, message, error, stack) {
    final prefix = switch (level) {
      SdkLogLevel.debug => '[D]',
      SdkLogLevel.info => '[I]',
      SdkLogLevel.warning => '[W]',
      SdkLogLevel.error => '[E]',
    };
    // ignore: avoid_print
    print('$prefix $message${error != null ? ' | $error' : ''}');
  });

  runApp(const SenseCraftVoiceDemoApp());
}

class SenseCraftVoiceDemoApp extends StatelessWidget {
  const SenseCraftVoiceDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SenseCraft Voice SDK Demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final SenseCraftVoiceClient _sdk = SenseCraftVoiceClient();
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<int>? _batterySub;

  final List<ScanResult> _devices = <ScanResult>[];
  bool _scanning = false;
  SenseCraftVoiceConnection? _conn;
  AtTransport? _at;
  RecordingSession? _session;
  String _log = '';
  int? _battery;
  String? _activeSession;

  @override
  void initState() {
    super.initState();
    _scanSub = _sdk.scanResults.listen((results) {
      // Keep the latest snapshot, de-duped by remoteId.
      final byId = <String, ScanResult>{};
      for (final r in results) {
        byId[r.device.remoteId.str] = r;
      }
      setState(() {
        _devices
          ..clear()
          ..addAll(byId.values);
      });
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _batterySub?.cancel();
    final conn = _conn;
    if (conn != null) {
      unawaited(_sdk.disconnect(conn));
    }
    super.dispose();
  }

  void _appendLog(String line) {
    setState(() {
      _log = '$line\n$_log';
      if (_log.length > 4000) {
        _log = _log.substring(0, 4000);
      }
    });
  }

  Future<void> _startScan() async {
    try {
      setState(() {
        _scanning = true;
        _devices.clear();
      });
      await _sdk.startScan(timeout: const Duration(seconds: 12));
    } catch (e) {
      _appendLog('Scan error: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(ScanResult result) async {
    try {
      _appendLog('Connecting to ${result.device.platformName}...');
      await _sdk.stopScan();
      final conn = await _sdk.connect(result);
      final at = AtTransport(
        commandRx: conn.commandRx,
        responseTx: conn.responseTx,
        fileData: conn.fileData,
        mtu: conn.mtu,
      );
      await _batterySub?.cancel();
      _batterySub = conn.batteryLevelStream?.listen((pct) {
        setState(() => _battery = pct);
      });
      final session = RecordingSession(connection: conn, at: at);
      setState(() {
        _conn = conn;
        _at = at;
        _session = session;
      });
      _appendLog('Connected. MTU=${conn.mtu.mtu}');
    } catch (e, st) {
      _appendLog('Connect failed: $e');
      SdkLog.e('Connect failed', e, st);
    }
  }

  Future<void> _sendVersion() async {
    final at = _at;
    if (at == null) return;
    try {
      final reply = await at.send('AT+VERSION');
      _appendLog('AT+VERSION -> $reply');
    } catch (e) {
      _appendLog('AT+VERSION failed: $e');
    }
  }

  Future<void> _startRecording() async {
    final s = _session;
    if (s == null) return;
    try {
      final info = await s.start();
      setState(() => _activeSession = info.sessionId);
      _appendLog('REC START -> session=${info.sessionId} mode=${info.mode}');
    } catch (e) {
      _appendLog('REC START failed: $e');
    }
  }

  Future<void> _stopRecording() async {
    final s = _session;
    if (s == null) return;
    try {
      final info = await s.stop();
      setState(() => _activeSession = null);
      _appendLog(
        'REC STOP -> session=${info.sessionId} '
        'dur=${info.durationSeconds}s files=${info.fileCount}',
      );
    } catch (e) {
      _appendLog('REC STOP failed: $e');
    }
  }

  Future<void> _showStatus() async {
    final s = _session;
    if (s == null) return;
    try {
      final st = await s.getStatus();
      _appendLog(
        'STATUS state=${st.state} rec=${st.isRecording} '
        'session=${st.sessionId} battery=${st.batteryPercent} '
        'free=${st.freeSpaceBytes} bitrate=${st.bitrate}',
      );
    } catch (e) {
      _appendLog('GSTAT failed: $e');
    }
  }

  Future<void> _disconnect() async {
    final conn = _conn;
    if (conn == null) return;
    await _sdk.disconnect(conn);
    await _batterySub?.cancel();
    setState(() {
      _conn = null;
      _at = null;
      _session = null;
      _battery = null;
      _activeSession = null;
    });
    _appendLog('Disconnected.');
  }

  @override
  Widget build(BuildContext context) {
    final connected = _conn != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SenseCraft Voice SDK Demo'),
        actions: [
          if (_battery != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text('Battery: $_battery%')),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _scanning ? null : _startScan,
                  icon: const Icon(Icons.search),
                  label: Text(_scanning ? 'Scanning...' : 'Scan'),
                ),
                OutlinedButton.icon(
                  onPressed: connected ? _sendVersion : null,
                  icon: const Icon(Icons.send),
                  label: const Text('AT+VERSION'),
                ),
                OutlinedButton.icon(
                  onPressed: connected ? _showStatus : null,
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Status'),
                ),
                FilledButton.tonalIcon(
                  onPressed: connected && _activeSession == null
                      ? _startRecording
                      : null,
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('Record'),
                ),
                FilledButton.tonalIcon(
                  onPressed: connected && _activeSession != null
                      ? _stopRecording
                      : null,
                  icon: const Icon(Icons.stop),
                  label: Text(_activeSession == null
                      ? 'Stop'
                      : 'Stop (${_activeSession!})'),
                ),
                OutlinedButton.icon(
                  onPressed: connected ? _disconnect : null,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              flex: 2,
              child: Card(
                child: ListView.separated(
                  itemBuilder: (_, i) {
                    final r = _devices[i];
                    final name = r.device.platformName.isEmpty
                        ? '(unnamed)'
                        : r.device.platformName;
                    return ListTile(
                      title: Text(name),
                      subtitle: Text(
                        '${r.device.remoteId.str}  rssi=${r.rssi}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _connect(r),
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: _devices.length,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              flex: 3,
              child: Card(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _log.isEmpty ? '(log)' : _log,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
