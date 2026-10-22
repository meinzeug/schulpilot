import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/material_actions.dart';
import 'package:schulpilot/notebook_photo.dart';
import 'package:schulpilot/subject_picker.dart';
import 'package:schulpilot/learning_preparation_screen.dart';
import 'package:schulpilot/ui.dart';

import 'material_actions_test.dart' as actions;

http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
http.Response pixels() =>
    http.Response.bytes(image.encodePng(image.Image(width: 3, height: 4)), 200);
AppState account(Future<http.Response> Function(http.Request) handler) =>
    AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient(handler),
        ),
      )
      ..familyId = 'first'
      ..user = {
        'id': 'same-parent',
        'role': 'parent',
        'display_name': 'Kunstfamilie',
      };
GoRouter? fixtureRouter;
ValueNotifier<Widget>? fixtureContent;
Widget home(Widget child) {
  if (fixtureContent == null) {
    fixtureContent = ValueNotifier<Widget>(child);
    fixtureRouter = GoRouter(
      initialLocation: '/test',
      routes: [
        GoRoute(
          path: '/test',
          builder: (_, _) => Scaffold(
            body: ValueListenableBuilder<Widget>(
              valueListenable: fixtureContent!,
              builder: (_, value, _) => value,
            ),
          ),
        ),
      ],
    );
  } else {
    fixtureContent!.value = child;
  }
  return MaterialApp.router(theme: appTheme(), routerConfig: fixtureRouter!);
}

Finder icon(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

Future<void> clean(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(const SizedBox());
  state.inbox.dispose();
  fixtureRouter?.dispose();
  fixtureContent?.dispose();
  fixtureRouter = null;
  fixtureContent = null;
}

void main() {
  for (final material in [false, true]) {
    testWidgets(
      'RR058 covered ${material ? 'material' : 'learning'} preparation does not poll on app resume',
      (tester) async {
        var reads = 0;
        final state = account((request) async {
          expect(request.method, 'GET');
          if (request.url.path.contains('/materials/')) {
            return reply({'id': 'page', 'child_id': 'child'});
          }
          reads++;
          return reply({
            'kind': material ? 'extract' : 'unit',
            'status': 'running',
            if (material) 'material_id': 'page',
          });
        });
        late BuildContext source;
        await tester.pumpWidget(
          home(
            Builder(
              builder: (context) {
                source = context;
                return material
                    ? MaterialProcessingScreen(
                        state,
                        materialId: 'page',
                        jobId: 'job',
                      )
                    : LearningPreparationScreen(
                        state,
                        childId: 'child',
                        jobId: 'job',
                      );
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(reads, 1);
        unawaited(
          showDialog<void>(
            context: source,
            builder: (_) =>
                const AlertDialog(title: Text('Kurze Unterbrechung')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        expect(reads, 1);
        await clean(tester, state);
      },
    );
  }
  testWidgets(
    'RR048 an old material confirmation cannot mutate after family switch',
    (tester) async {
      final h = await actions.mount(
        tester,
        (_) async =>
            actions.reply({'count': 1, 'selection_token': 'synthetic'}),
        deleting: true,
      );
      h.state.familyId = 'first';
      await actions.tap(tester, 'Aktion öffnen');
      final saved = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Heftseite löschen'),
          )
          .onPressed!;
      h.state.familyId = 'second';
      h.state.refreshState();
      saved();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(h.result, isFalse);
      expect(h.requests, hasLength(1));
      await clean(tester, h.state);
    },
  );

  testWidgets(
    'RR049 material status discards delayed same-ID old-session data',
    (tester) async {
      final old = Completer<http.Response>();
      var reads = 0;
      final state = account((request) async {
        if (request.url.path.endsWith('/new-photo')) {
          return reply({'id': 'new-photo', 'child_id': 'child'});
        }
        if (++reads == 1) return old.future;
        return reply({
          'kind': 'extract',
          'status': 'failed',
          'error': 'Neuer sicher geladener Status',
          'material_id': 'new-photo',
        });
      });
      await tester.pumpWidget(
        home(
          MaterialProcessingScreen(
            state,
            materialId: 'new-photo',
            jobId: 'job',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      state.user = {...state.user!};
      state.refreshState();
      await tester.pump();
      await tester.pump();
      old.complete(
        reply({
          'kind': 'extract',
          'status': 'completed',
          'result': {'material_id': 'new-photo'},
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Der Text ist bereit.'), findsNothing);
      expect(find.text('Das Einlesen hat nicht geklappt.'), findsOneWidget);
      expect(reads, 2);
      await clean(tester, state);
    },
  );

  testWidgets(
    'RR050 material status follows a replacement job without reopening the page',
    (tester) async {
      final paths = <String>[];
      final state = account((request) async {
        paths.add(request.url.path);
        return request.url.path.contains('/materials/')
            ? reply({'id': 'page', 'child_id': 'child'})
            : reply({
                'kind': 'extract',
                'status': 'failed',
                'material_id': 'page',
              });
      });
      Widget page(String id) =>
          home(MaterialProcessingScreen(state, materialId: 'page', jobId: id));
      await tester.pumpWidget(page('first'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(page('second'));
      await tester.pumpAndSettle();
      expect(paths, [
        '/api/materials/page',
        '/api/jobs/first',
        '/api/materials/page',
        '/api/jobs/second',
      ]);
      await clean(tester, state);
    },
  );

  testWidgets(
    'RR051 private photo reloads under the new family without keeping old pixels',
    (tester) async {
      final fresh = Completer<http.Response>();
      var reads = 0;
      final state = account(
        (_) async => ++reads == 1 ? pixels() : fresh.future,
      );
      await tester.pumpWidget(home(NotebookPhoto(state, materialId: 'page')));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      state.familyId = 'second';
      state.refreshState();
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      fresh.complete(reply({'detail': 'Nicht mehr verfügbar'}, 403));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(reads, 2);
      await clean(tester, state);
    },
  );

  testWidgets(
    'RR052 replacing photo AppState uses the new API and removes old listeners',
    (tester) async {
      var a = 0, b = 0;
      final first = account((_) async {
        a++;
        return pixels();
      });
      final second = account((_) async {
        b++;
        return pixels();
      });
      await tester.pumpWidget(home(NotebookPhoto(first, materialId: 'page')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(home(NotebookPhoto(second, materialId: 'page')));
      await tester.pumpAndSettle();
      first.user = {...first.user!};
      first.refreshState();
      await tester.pump();
      expect(a, 1);
      expect(b, 1);
      expect(find.byType(Image), findsOneWidget);
      await clean(tester, second);
      first.inbox.dispose();
    },
  );

  testWidgets('RR053 a saved photo zoom cannot alter a different page', (
    tester,
  ) async {
    final state = account((_) async => pixels());
    Widget page(String id) =>
        home(NotebookPhoto(state, materialId: id, zoomable: true));
    await tester.pumpWidget(page('first'));
    await tester.pumpAndSettle();
    final zoom = tester.widget<IconButton>(icon('Foto vergrößern')).onPressed!;
    await tester.pumpWidget(page('second'));
    await tester.pumpAndSettle();
    zoom();
    await tester.pump();
    expect(find.text('100 %'), findsOneWidget);
    await clean(tester, state);
  });

  testWidgets(
    'RR054 obsolete full-screen photo closes only its own route on family change',
    (tester) async {
      final state = account((_) async => pixels());
      late BuildContext source;
      await tester.pumpWidget(
        home(
          Builder(
            builder: (context) {
              source = context;
              return const Text('Quelle');
            },
          ),
        ),
      );
      unawaited(zoomNotebookPhoto(source, state, {'id': 'page'}));
      await tester.pumpAndSettle();
      final oldClose = tester.widget<IconButton>(icon('Schließen')).onPressed!;
      unawaited(
        showDialog<void>(
          context: source,
          builder: (_) => const AlertDialog(title: Text('Neuer Dialog')),
        ),
      );
      await tester.pumpAndSettle();
      oldClose();
      await tester.pumpAndSettle();
      expect(find.text('Neuer Dialog'), findsOneWidget);
      state.familyId = 'second';
      state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Neuer Dialog'), findsOneWidget);
      expect(find.byType(NotebookPhoto), findsNothing);
      await clean(tester, state);
    },
  );

  testWidgets(
    'RR055 subject choice closes on family switch and old close preserves newer dialog',
    (tester) async {
      final state = account(
        (_) async => reply({
          'items': [
            {'id': 'math', 'title': 'Mathematik'},
          ],
        }),
      );
      final controller = TextEditingController();
      late BuildContext source;
      await tester.pumpWidget(
        home(
          Builder(
            builder: (context) {
              source = context;
              return SubjectField(
                state,
                childId: 'child',
                controller: controller,
                enabled: true,
                changed: () {},
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Fach auswählen'));
      await tester.pumpAndSettle();
      final oldClose = tester.widget<IconButton>(icon('Schließen')).onPressed!;
      unawaited(
        showDialog<void>(
          context: source,
          builder: (_) => const AlertDialog(title: Text('Neuer Dialog')),
        ),
      );
      await tester.pumpAndSettle();
      oldClose();
      await tester.pumpAndSettle();
      expect(find.text('Neuer Dialog'), findsOneWidget);
      state.familyId = 'second';
      state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Neuer Dialog'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(controller.text, isEmpty);
      await clean(tester, state);
      controller.dispose();
    },
  );

  testWidgets('RR056 existing selected subject is first and explicitly named', (
    tester,
  ) async {
    final state = account(
      (_) async => reply({
        'items': [
          {'id': 'bio', 'title': 'Biologie'},
          {'id': 'math', 'title': 'Mathematik'},
        ],
      }),
    );
    final controller = TextEditingController(text: 'Mathematik');
    await tester.pumpWidget(
      home(
        SubjectField(
          state,
          childId: 'child',
          controller: controller,
          enabled: true,
          changed: () {},
        ),
      ),
    );
    await tester.tap(find.text('Mathematik'));
    await tester.pumpAndSettle();
    final rows = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((rows.first.title! as Text).data, 'Mathematik');
    expect(find.text('Aktuell ausgewählt'), findsOneWidget);
    await clean(tester, state);
    controller.dispose();
  });

  testWidgets(
    'RR057 learning preparation clears private results on family change',
    (tester) async {
      final state = account(
        (_) async => reply({
          'kind': 'unit',
          'status': 'failed',
          'error': 'Privater alter Fehler',
        }),
      );
      await tester.pumpWidget(
        home(LearningPreparationScreen(state, childId: 'child', jobId: 'job')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Privater alter Fehler'), findsOneWidget);
      state.familyId = 'second';
      state.refreshState();
      await tester.pump();
      expect(find.text('Privater alter Fehler'), findsNothing);
      await clean(tester, state);
    },
  );
}
