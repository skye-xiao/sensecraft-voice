import 'package:flutter_test/flutter_test.dart';
import 'package:sensecraft_voice/sensecraft_voice.dart';

void main() {
  group('TransferProgress', () {
    test('wifiAligned caps at 0.995 for expectedSession branch', () {
      final r = TransferProgress.wifiAligned(
        framedMode: false,
        currentFileDeclaredSize: 0,
        bytesThisFile: 0,
        receivedSession: 999,
        expectedSession: 1000,
        filesCompleted: 0,
        deviceTotalFiles: 0,
        deviceSessionBytes: 0,
      );
      expect(r, closeTo(0.995, 1e-9));
    });

    test('sessionTransferBytesComplete when slices match download count', () {
      expect(
        TransferProgress.sessionTransferBytesComplete(
          eventFileCount: 7,
          fileCompleteCount: 3,
          deviceTotalFilesFromDownload: 7,
        ),
        isTrue,
      );
      expect(
        TransferProgress.sessionTransferBytesComplete(
          eventFileCount: 0,
          fileCompleteCount: 7,
          deviceTotalFilesFromDownload: 7,
        ),
        isTrue,
      );
    });
  });

  group('TransferJsonEventParser', () {
    test('parses wrapped file_complete', () {
      final ev = TransferJsonEventParser.parse({
        'ok': true,
        'data': {'event': 'file_complete', 'filename': '0001.opus'},
      });
      expect(ev, isA<TransferJsonFileComplete>());
      expect((ev! as TransferJsonFileComplete).filename, '0001.opus');
    });

    test('parses transfer_complete files', () {
      final ev = TransferJsonEventParser.parse({
        'event': 'transfer_complete',
        'files': '3',
      });
      expect(ev, isA<TransferJsonTransferComplete>());
      expect((ev! as TransferJsonTransferComplete).files, 3);
    });
  });
}
