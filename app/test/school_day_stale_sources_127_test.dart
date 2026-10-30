import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'school_day_background_test.dart' as background;
import 'school_day_parts_113_test.dart' as parts;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final confirmed in [false, true]) {
    testWidgets(
      'Historical ready header reflects pending source review: $confirmed',
      (tester) async {
        final server = background.PreparationServer(
          stage: 'ready',
          pages: [background.source(1, confirmed: confirmed)],
        );
        server.archived = true;
        await parts.openParts(tester, server);
        final selected = tester.widget<Text>(
          find.text(confirmed ? '3 Fertig' : '2 Prüfen'),
        );
        expect(selected.style?.fontWeight, FontWeight.w700);
        parts.expectNoWrites(server);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final changed in [false, true]) {
    testWidgets('Six old parts have honest currentness: $changed', (
      tester,
    ) async {
      final server = parts.partsServer({
        'status': 'failed',
        'phase': 'package',
        'can_retry': true,
        'sources_changed': changed,
        'total_parts': 7,
        'completed_parts': 6,
        'active_part': 6,
        'error_code': 'invalid_output',
        'error': 'Synthetic previous provider failure',
      });
      await parts.openParts(tester, server, width: 320, textScale: 2);
      parts.expectNoWrites(server);
      if (changed) {
        expect(find.text('Eine Heftseite wurde geändert'), findsOneWidget);
        expect(find.textContaining('gehört zur alten Fassung'), findsOneWidget);
        expect(find.text('6 von 7 Teilen gespeichert'), findsNothing);
        expect(
          find.byKey(const ValueKey('school-day-preparation-progress')),
          findsNothing,
        );
        expect(find.text('Fehlenden Teil erneut vorbereiten'), findsNothing);
        await background.tapText(
          tester,
          'Mit den aktuellen Seiten neu vorbereiten',
        );
      } else {
        expect(find.text('6 von 7 Teilen gespeichert'), findsOneWidget);
        expect(parts.progress(tester).value, closeTo(6 / 7, .00001));
        expect(
          find.text('Mit den aktuellen Seiten neu vorbereiten'),
          findsNothing,
        );
        await background.tapText(tester, 'Fehlenden Teil erneut vorbereiten');
      }
      expect(server.submissions, 1);
      expect(server.starts, 0);
      expect(server.requests.where((r) => !r.startsWith('GET ')), [
        'POST /api/school-days/day/prepare',
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Stale source keeps a genuine retry blocker and never posts', (
    tester,
  ) async {
    final server = parts.partsServer({
      'status': 'failed',
      'phase': 'package',
      'can_retry': false,
      'sources_changed': true,
      'total_parts': 7,
      'completed_parts': 6,
      'retry_blocker': {
        'code': 'quota_exhausted',
        'message': 'Neue KI-Inhalte können gerade nicht vorbereitet werden.',
      },
    });
    await parts.openParts(tester, server);
    expect(find.textContaining('gehört zur alten Fassung'), findsOneWidget);
    expect(
      find.textContaining(
        'Neue KI-Inhalte können gerade nicht vorbereitet werden.',
      ),
      findsOneWidget,
    );
    expect(find.text('Mit den aktuellen Seiten neu vorbereiten'), findsNothing);
    expect(find.text('Fehlenden Teil erneut vorbereiten'), findsNothing);
    expect(find.text('6 von 7 Teilen gespeichert'), findsNothing);
    parts.expectNoWrites(server);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Corrected source can start a new plan despite old HTTP error', (
    tester,
  ) async {
    final server = parts.partsServer({
      'status': 'failed',
      'phase': 'package',
      'can_retry': true,
      'sources_changed': true,
      'error_code': 'not_configured',
      'error': 'KI-Anbieter meldet HTTP 400. Schlüssel, Modell, Freigabe oder Kontingent prüfen.',
    });
    await parts.openParts(tester, server, width: 390);
    parts.expectNoWrites(server);
    await background.tapText(
      tester,
      'Mit den aktuellen Seiten neu vorbereiten',
    );
    expect(server.submissions, 1);
    expect(server.requests.where((r) => !r.startsWith('GET ')), [
      'POST /api/school-days/day/prepare',
    ]);
    expect(tester.takeException(), isNull);
  });
}
