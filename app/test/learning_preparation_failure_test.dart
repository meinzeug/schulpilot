import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/learning_preparation_screen.dart';
import 'package:schulpilot/ui.dart';

import 'child_local_tools_ux88_test.dart' as f;

void main() {
  for (final kind in ['decision', 'unit']) {
    testWidgets(
      'failed $kind preparation names the correct step and only returns to saved work',
      (t) async {
        final calls = <http.Request>[];
        final state = f.account((q) async {
          calls.add(q);
          return f.reply({
            'id': 'job',
            'kind': kind,
            'status': 'failed',
            'error': 'Die gespeicherten Antworten bleiben erhalten.',
          });
        });
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => LearningPreparationScreen(
                state,
                childId: 'child',
                jobId: 'job',
              ),
            ),
            GoRoute(
              path: '/learn/child',
              builder: (_, _) =>
                  const Scaffold(body: Text('Gespeicherte Runden')),
            ),
          ],
        );
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          router.dispose();
        });
        await t.pumpWidget(
          MaterialApp.router(theme: appTheme(), routerConfig: router),
        );
        await t.pumpAndSettle();
        expect(
          find.text(
            kind == 'decision'
                ? 'Dein Lernplan konnte nicht vorbereitet werden.'
                : 'Diese Runde konnte nicht vorbereitet werden.',
          ),
          findsOneWidget,
        );
        await t.pump(const Duration(seconds: 9));
        expect(calls.where((q) => q.url.path == '/api/jobs/job'), hasLength(1));
        expect(calls.every((q) => q.method == 'GET'), isTrue);
        await f.tap(t, find.text('Gespeicherte Runden ansehen'));
        expect(router.state.uri.path, '/learn/child');
        expect(find.text('Gespeicherte Runden'), findsOneWidget);
        expect(calls.where((q) => q.url.path == '/api/jobs/job'), hasLength(1));
        expect(calls.every((q) => q.method == 'GET'), isTrue);
        expect(t.takeException(), isNull);
      },
    );
  }
}
