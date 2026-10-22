import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/material_actions.dart';
import 'package:schulpilot/ui.dart';

import 'material_actions_test.dart' as actions;

class _Fixture {
  final String kind;
  final String delayed;
  final requests = <http.Request>[];
  final waiting = Completer<http.Response>();
  int refreshed = 0;
  bool? result;
  late BuildContext context;
  late GoRouter router;
  late final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/delete-preview')) {
          return delayed == 'preview'
              ? waiting.future
              : response(preview: true);
        }
        return delayed == 'mutation' ? waiting.future : response();
      }),
    ),
  )..user = {'id': 'artificial-account', 'role': 'child', 'child_id': 'child'};
  _Fixture(this.kind, this.delayed);

  http.Response response({bool preview = false}) => actions.reply(
    preview
        ? {
            'count': 1,
            'unit_count': 2,
            'answer_count': 3,
            'selection_token': 'synthetic-selection-snapshot',
          }
        : kind == 'reread'
        ? {'id': 'prepared-job', 'material_id': 'new-photo'}
        : {'deleted_count': 1},
  );

  Future<void> open(WidgetTester tester) async {
    router = GoRouter(
      initialLocation: '/test',
      routes: [
        GoRoute(
          path: '/test',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (sourceContext) {
                context = sourceContext;
                return FilledButton(
                  onPressed: () async {
                    result = switch (kind) {
                      'pages' => await deleteNotebookPages(
                        sourceContext,
                        state,
                        childId: 'child',
                        ids: ['old-photo'],
                        onDeleted: () => refreshed++,
                      ),
                      'round' => await deleteLearningRound(
                        sourceContext,
                        state,
                        {'id': 'old-round'},
                      ),
                      _ => await reprocessNotebookPage(
                        sourceContext,
                        state,
                        actions.ownPage,
                        onRefresh: () => refreshed++,
                      ),
                    };
                  },
                  child: const Text('Künstliche Aktion öffnen'),
                );
              },
            ),
          ),
        ),
        GoRoute(
          path: '/material/:id/processing/:job',
          builder: (_, _) => const Scaffold(body: Text('Neue Vorbereitung')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    state.inbox.dispose();
    state.dispose();
  }
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  for (final kind in ['pages', 'round', 'reread']) {
    for (final phase in ['preview', 'confirm', 'mutation']) {
      if (kind == 'reread' && phase == 'preview') continue;
      testWidgets(
        'Old $kind $phase work cannot continue in a new session of the same child',
        (tester) async {
          final f = _Fixture(kind, phase);
          await f.open(tester);
          await _tap(tester, 'Künstliche Aktion öffnen');
          if (phase != 'preview') {
            expect(find.byType(AlertDialog), findsOneWidget);
          }
          if (phase == 'mutation') {
            await _tap(tester, switch (kind) {
              'pages' => 'Heftseite löschen',
              'round' => 'Lernrunde löschen',
              _ => 'Mit KI neu einlesen',
            });
            expect(
              f.requests.where((r) => !r.url.path.endsWith('/delete-preview')),
              hasLength(1),
            );
          }
          final newSession = {...f.state.user!};
          f.state.user = newSession;
          f.state.refreshState();
          await tester.pump();
          if (phase != 'confirm') {
            f.waiting.complete(f.response(preview: phase == 'preview'));
          }
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(f.result, isFalse);
          expect(identical(f.state.user, newSession), isTrue);
          expect(f.refreshed, 0);
          expect(find.text('Neue Vorbereitung'), findsNothing);
          expect(find.textContaining('Heftseite gelöscht.'), findsNothing);
          expect(find.text('Lernrunde gelöscht.'), findsNothing);
          if (phase != 'mutation') {
            expect(
              f.requests.where((r) => !r.url.path.endsWith('/delete-preview')),
              isEmpty,
            );
          }
          expect(tester.takeException(), isNull);
          await f.close(tester);
        },
      );
    }
  }

  testWidgets(
    'Closing an old material confirmation never pops a newer dialog',
    (tester) async {
      final f = _Fixture('pages', 'confirm');
      await f.open(tester);
      await _tap(tester, 'Künstliche Aktion öffnen');
      final oldConfirm = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Heftseite löschen'),
          )
          .onPressed!;
      unawaited(
        showDialog<void>(
          context: f.context,
          builder: (context) => AlertDialog(
            title: const Text('Neuer eigener Dialog'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Neuen Dialog schließen'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      oldConfirm();
      await tester.pumpAndSettle();
      expect(find.text('Neuer eigener Dialog'), findsOneWidget);
      expect(f.requests, hasLength(1));
      f.state.user = {...f.state.user!};
      oldConfirm();
      f.state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Neuer eigener Dialog'), findsOneWidget);
      expect(find.text('Heftseite löschen?'), findsNothing);
      expect(f.result, isFalse);
      expect(f.requests, hasLength(1));
      await _tap(tester, 'Neuen Dialog schließen');
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );
}
