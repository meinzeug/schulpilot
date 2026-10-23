import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/ui.dart';

import 'admin_operations_catalog_ux_test.dart' as operations_fixture;
import 'compact_workspace_102_test.dart' as layout_fixture;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final family in ['Nunito', 'Roboto']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
    }
  });
  for (final width in [390.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final known in [true, false]) {
        testWidgets(
          '102 queue geometry and local details at $width x $scale known=$known',
          (tester) async {
            var requests = 0;
            final state = operations_fixture.admin((_) async {
              requests++;
              return operations_fixture.reply(<String, dynamic>{});
            });
            try {
              await layout_fixture.surface(
                tester,
                AdminOperationCards({
                  'jobs': {'running': 0, if (known) 'queued': 0},
                  'stalled_queued': 0,
                  'stalled_running': 0,
                  'pending_erasure_journal': 0,
                  'push_failures_24h': 0,
                  'worker_age_seconds': 0,
                }, state: state),
                width: width,
                scale: scale,
              );
              final queue = find.widgetWithText(
                ActionPanel,
                'AUFTRAGSLEITSTAND',
              );
              final label = find.descendant(
                of: queue,
                matching: find.text('AUFTRAGSLEITSTAND'),
              );
              final count = find.descendant(
                of: queue,
                matching: find.text(known ? '0' : 'Unbekannt'),
              );
              final title = find.descendant(
                of: queue,
                matching: find.text('Wartende Aufträge'),
              );
              await tester.ensureVisible(queue);
              await tester.pumpAndSettle();
              final queueRect = tester.getRect(queue);
              final labelRect = tester.getRect(label);
              final countRect = tester.getRect(count);
              final titleRect = tester.getRect(title);
              if (scale == 1) {
                expect(countRect.top, lessThan(labelRect.bottom));
                expect(countRect.bottom, greaterThan(labelRect.top));
                expect(countRect.left, greaterThanOrEqualTo(labelRect.right));
              }
              expect(countRect.height, lessThanOrEqualTo(scale * 36));
              expect(countRect.left, greaterThanOrEqualTo(queueRect.left));
              expect(countRect.right, lessThanOrEqualTo(queueRect.right));
              expect(titleRect.top - countRect.bottom, greaterThanOrEqualTo(6));
              expect(titleRect.top - countRect.bottom, lessThanOrEqualTo(12));
              expect(
                find.descendant(
                  of: queue,
                  matching: find.text(
                    'Gespeicherte Aufträge in der Warteschlange. Diese Ansicht startet keine neue Verarbeitung.',
                  ),
                ),
                findsOneWidget,
              );
              if (!known) {
                expect(
                  find.text('Betriebsstatus unvollständig'),
                  findsOneWidget,
                );
              }
              expect(requests, 0);
              final target = find.descendant(
                of: queue,
                matching: find.byType(InkWell),
              );
              expect(target, findsOneWidget);
              expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
              await tester.tap(target);
              await tester.pumpAndSettle();
              expect(
                find.text('Wartende und laufende Aufträge'),
                findsOneWidget,
              );
              expect(
                requests,
                0,
                reason: 'Details use only the loaded queue metadata.',
              );
              expect(tester.takeException(), isNull);
              await tester.tap(find.widgetWithText(TextButton, 'Schließen'));
              await tester.pumpAndSettle();
            } finally {
              await tester.pumpWidget(const SizedBox());
              state.inbox.dispose();
              state.dispose();
            }
          },
        );
      }
    }
  }
}
