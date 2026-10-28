import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:schulpilot/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/learning_preparation_screen.dart';

import 'child_local_tools_ux88_test.dart' as f;

void main() {
  for (final queued in [false, true]) {
    testWidgets(
      'repaired preparation is read without another generation $queued',
      (t) async {
        const replacement = '12345678901234567890123456789012';
        final calls = <String>[];
        var reads = 0;
        final state = f.account((request) async {
          calls.add('${request.method} ${request.url.path}');
          expect(request.method, 'GET');
          if (request.url.path == '/api/jobs/old') {
            return f.reply({
              'kind': 'unit',
              'status': 'failed',
              'error': 'Old failure',
              'recovery_job_id': replacement,
            });
          }
          expect(request.url.path, '/api/jobs/$replacement');
          reads++;
          return f.reply({
            'kind': 'unit',
            'status': queued && reads == 1 ? 'running' : 'completed',
            'result': queued && reads == 1 ? null : {'unit_id': 'ready-unit'},
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
                jobId: 'old',
              ),
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
        await t.pump();
        await t.pump();
        if (queued) {
          expect(find.text('Deine Runde entsteht …'), findsOneWidget);
          await t.pump(const Duration(seconds: 3));
          await t.pumpAndSettle();
        }
        expect(find.text('Deine Runde ist bereit.'), findsOneWidget);
        expect(find.text('Los geht’s'), findsOneWidget);
        expect(find.text('Old failure'), findsNothing);
        final count = calls.length;
        await t.pump(const Duration(seconds: 6));
        expect(calls.length, count);
        expect(calls.length, queued ? 4 : 2);
        expect(t.takeException(), isNull);
      },
    );
  }
}
