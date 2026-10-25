import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'school_day_background_test.dart' as background;
import 'school_day_parts_113_test.dart' as parts;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'An interrupted transcription keeps its own phase and saved page count at $width px',
      (tester) async {
        final server = background.PreparationServer(
          stage: 'review',
          preparation: {
            'status': 'failed',
            'phase': 'extract',
            'error_code': 'invalid_output',
            'error': 'Synthetic bounded-output failure',
            'can_retry': true,
            'completed_pages': 10,
            'total_pages': 19,
          },
        );
        await parts.openParts(tester, server, width: width, textScale: 2);
        expect(find.text('Lesen unterbrochen'), findsOneWidget);
        expect(
          find.text('10 von 19 Fotos wurden bereits verarbeitet.'),
          findsOneWidget,
        );
        expect(find.textContaining('unvollständige Aufgaben'), findsNothing);
        expect(server.submissions, 0);
        await background.tapText(tester, 'Lesen fortsetzen');
        expect(server.submissions, 1);
        expect(server.starts, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'A failed package keeps the package message instead of claiming a photo failure',
    (tester) async {
      final server = background.PreparationServer(
        stage: 'review',
        preparation: {
          'status': 'failed',
          'phase': 'package',
          'error_code': 'invalid_output',
          'error': 'Synthetic schema failure',
          'can_retry': true,
        },
      );
      await parts.openParts(tester, server);
      expect(find.textContaining('unvollständige Aufgaben'), findsOneWidget);
      expect(find.text('Lesen fortsetzen'), findsNothing);
      expect(server.submissions, 0);
    },
  );

  testWidgets(
    'A server retry refusal never offers another transcription request',
    (tester) async {
      final server = background.PreparationServer(
        stage: 'review',
        preparation: {
          'status': 'failed',
          'phase': 'extract',
          'error_code': 'invalid_output',
          'can_retry': false,
        },
      );
      await parts.openParts(tester, server);
      expect(find.text('Lesen fortsetzen'), findsNothing);
      expect(server.submissions, 0);
      expect(server.starts, 0);
    },
  );
}
