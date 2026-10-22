import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'parent_learning_overview_test.dart' as f;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'parent clipped today preview opens the actual learning route for the rendered child using GET only',
    (tester) async {
      final data = f.parentOverview();
      data['plan']['today'] = <dynamic>[];
      data['plan']['today_count'] = 7;
      final requests = <http.Request>[];
      final fixture = await f.mountParent(tester, data, requests);
      // The conditional link belongs to the retained plan deep-link, not Overview.
      fixture.router.go('/child/${data['child']['id']}?bereich=plan');
      await tester.pumpAndSettle();
      expect(find.text('Heute eingeplant'), findsOneWidget);
      final more = find.widgetWithText(
        TextButton,
        'Alle gespeicherten Runden ansehen',
      );
      expect(more, findsOneWidget);
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(
        GoRouterState.of(
          tester.element(find.text('Lernsammlung ${data['child']['id']}')),
        ).uri.path,
        '/learn/${data['child']['id']}',
      );
      expect(find.text('Lernsammlung ${data['child']['id']}'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'parent complete today preview does not expose a misleading more link',
    (tester) async {
      final data = f.parentOverview();
      data['plan']['today'] = <dynamic>[];
      data['plan']['today_count'] = 0;
      final requests = <http.Request>[];
      final fixture = await f.mountParent(tester, data, requests);
      fixture.router.go('/child/${data['child']['id']}?bereich=plan');
      await tester.pumpAndSettle();
      expect(find.text('Heute eingeplant'), findsOneWidget);
      expect(find.text('Alle gespeicherten Runden ansehen'), findsNothing);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
