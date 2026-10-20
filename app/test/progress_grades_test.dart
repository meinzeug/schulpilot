import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/coaching_panel.dart';
import 'package:schulpilot/grades_screen.dart';
import 'package:schulpilot/progress_screen.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Object value, [int code = 200]) => http.Response(
  jsonEncode(value),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json evidence({int tasks = 7}) => {
  'practiced_tasks': tasks,
  'attempts': tasks + 2,
  'independent_tasks': 3,
  'assisted_tasks': 2,
  'needs_practice_tasks': 1,
  'uncertain_tasks': 1,
  'practiced_rounds': 3,
  'completed_rounds': 2,
  'ongoing_rounds': 1,
};

Json grades({
  bool manage = true,
  bool enabled = true,
  List<Json> items = const [],
}) => {
  'child_id': 'kid',
  'child_name': 'Mika (Beispiel)',
  'today': '2026-10-17',
  'can_manage': manage,
  'planning_enabled': enabled,
  'subjects': ['Mathematik'],
  'items': items,
  'pagination': {'page': 1, 'pages': 1, 'total': items.length},
  'focus': [
    {
      'subject': 'Mathematik',
      'average': 4.5,
      'scale': 'grade_1_6',
      'observations': 2,
      'reason': 'Mehr angeleitete Übung einplanen',
      'trend': 'not_enough_data',
    },
  ],
  'notice': 'Nur eingetragene Noten, kein Zeugnisdurchschnitt.',
};

Future<({AppState state, GoRouter router})> mount(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handle, {
  double width = 390,
  bool child = false,
  bool gradePage = false,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient(handle),
          ),
        )
        ..user = {
          'id': 'owned-user',
          'display_name': 'Kunstfamilie',
          'role': child ? 'child' : 'parent',
          'child_id': 'kid',
          'families': [
            {'id': 'own-family', 'name': 'Kunstfamilie', 'permission': 'owner'},
          ],
        };
  final router = GoRouter(
    initialLocation: gradePage ? '/grades/kid' : '/progress/kid',
    routes: [
      GoRoute(
        path: '/progress/:id',
        builder: (_, s) => ProgressScreen(
          state,
          childId: s.pathParameters['id']!,
          initialSubject: s.uri.queryParameters['fach'],
          initialTopic: s.uri.queryParameters['thema'],
        ),
      ),
      GoRoute(
        path: '/grades/:id',
        builder: (_, s) =>
            GradesScreen(state, childId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, s) => Scaffold(
          body: Text('Eigene gespeicherte Runde ${s.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: '/app',
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const Scaffold()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return (state: state, router: router);
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'Every exercise is visible before retrieval-day details at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: LearningProgressPanel({
                  'subject': 'Biologie',
                  'topic': 'Wirbeltiere',
                  'topic_practice': evidence(),
                  'successful_check_days': 0,
                  'required_check_days': 3,
                  'secure_observation': false,
                }),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('7 Aufgaben geübt'), findsOneWidget);
        expect(find.text('3 alleine gelöst'), findsOneWidget);
        expect(find.text('2 mit Hilfe gelöst'), findsOneWidget);
        expect(find.text('1 weiter üben'), findsOneWidget);
        expect(find.text('1 Bewertung offen'), findsOneWidget);
        expect(find.text('0 von 3 Prüftagen'), findsNothing);
        await tester.tap(find.text('Was bleibt über mehrere Tage hängen?'));
        await tester.pumpAndSettle();
        expect(find.text('0 von 3 Prüftagen'), findsOneWidget);
        expect(find.text('7 Aufgaben geübt'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Parent follows subject, topic and every saved round with GET only',
    (tester) async {
      final reads = <http.Request>[];
      await mount(tester, (r) async {
        reads.add(r);
        expect(r.method, 'GET');
        final topic = r.url.queryParameters['topic'],
            subject = r.url.queryParameters['subject'];
        return reply({
          'level': topic != null
              ? 'rounds'
              : subject != null
              ? 'topics'
              : 'subjects',
          'selected_totals': evidence(),
          'totals': evidence(),
          'child_name': 'Mika (Beispiel)',
          'items': [
            {
              ...evidence(),
              'subject': 'Mathematik',
              'topic': 'Brüche',
              'topic_count': 1,
              'id': 'owned-round',
              'last_activity': 1792220000,
              'status': 'paused',
            },
          ],
          'pagination': {'page': 1, 'pages': 1},
        });
      });
      expect(find.text('Mika (Beispiel)'), findsOneWidget);
      await tester.ensureVisible(find.text('Mathematik'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mathematik'));
      await tester.pumpAndSettle();
      expect(reads.last.url.queryParameters['subject'], 'Mathematik');
      await tester.ensureVisible(find.text('Brüche'));
      await tester.tap(find.text('Brüche'));
      await tester.pumpAndSettle();
      expect(reads.last.url.queryParameters['topic'], 'Brüche');
      await tester.ensureVisible(find.textContaining('Runde vom'));
      await tester.tap(find.textContaining('Runde vom'));
      await tester.pumpAndSettle();
      expect(
        find.text('Eigene gespeicherte Runde owned-round'),
        findsOneWidget,
      );
      expect(reads.length, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A restored subject filter can return to all subjects even at the bare progress URL',
    (tester) async {
      final reads = <http.Request>[];
      final mounted = await mount(tester, (r) async {
        reads.add(r);
        return reply({
          'child_name': 'Mika (Beispiel)',
          'level': r.url.queryParameters['subject'] == null
              ? 'subjects'
              : 'topics',
          'selected_totals': evidence(),
          'items': [],
          'pagination': {'page': 1, 'pages': 1},
        });
      });
      mounted.router.go('/app');
      await tester.pumpAndSettle();
      mounted.state.collectionViews['progress:kid'] = {
        'subject': 'Mathematik',
        'page': 1,
      };
      mounted.router.go('/progress/kid');
      await tester.pumpAndSettle();
      expect(reads.last.url.queryParameters['subject'], 'Mathematik');
      await tester.ensureVisible(find.text('Alle Fächer'));
      await tester.tap(find.text('Alle Fächer'));
      await tester.pumpAndSettle();
      expect(reads.last.url.queryParameters.containsKey('subject'), false);
      expect(find.text('Fächer'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A late response after account change cannot reveal the former child',
    (tester) async {
      final late = Completer<http.Response>();
      FlutterSecureStorage.setMockInitialValues({});
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((_) => late.future),
        ),
      )..user = {'id': 'old', 'role': 'child', 'child_id': 'kid'};
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => ProgressScreen(state, childId: 'kid'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pump();
      state.user = {'id': 'new', 'role': 'child', 'child_id': 'other'};
      state.notifyListeners();
      late.complete(
        reply({
          'selected_totals': evidence(),
          'items': [],
          'pagination': {'page': 1, 'pages': 1},
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('7 Aufgaben geübt'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'Parent grade overview fits $width and does not silently save or generate',
      (tester) async {
        final requests = <http.Request>[];
        await mount(
          tester,
          (r) async {
            requests.add(r);
            expect(r.method, 'GET');
            return reply(grades());
          },
          width: width,
          gradePage: true,
        );
        expect(find.text('Notenschnitt: 4,5'), findsOneWidget);
        expect(find.text('Mehr angeleitete Übung einplanen'), findsOneWidget);
        expect(find.text('Note eintragen'), findsOneWidget);
        expect(requests.length, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Changing a grade filter never presents old grades under the new subject',
    (tester) async {
      final response = Completer<http.Response>();
      var calls = 0;
      await mount(tester, (r) async {
        expect(r.method, 'GET');
        if (++calls == 1) return reply(grades());
        return response.future;
      }, gradePage: true);
      await tester.ensureVisible(
        find.byKey(const ValueKey('grade-subject-null')),
      );
      await tester.tap(find.byKey(const ValueKey('grade-subject-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mathematik').last);
      await tester.pump();
      expect(find.text('Notenschnitt: 4,5'), findsNothing);
      response.complete(reply({'detail': 'Künstlicher Ladefehler'}, 503));
      await tester.pumpAndSettle();
      expect(find.text('Künstlicher Ladefehler'), findsOneWidget);
      expect(find.text('Notenschnitt: 4,5'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Read-only family member sees grades without managing accounts or results',
    (tester) async {
      await mount(
        tester,
        (_) async => reply(grades(manage: false)),
        gradePage: true,
      );
      expect(find.text('Notenschnitt: 4,5'), findsOneWidget);
      expect(find.text('Note eintragen'), findsNothing);
      await tester.ensureVisible(find.text('Einfluss auf den Lernplan'));
      await tester.tap(find.text('Einfluss auf den Lernplan'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'Explicit grade entry validates values and uses a stable idempotency key at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final saves = <http.Request>[];
        await mount(tester, (r) async {
          if (r.method == 'GET') return reply(grades());
          saves.add(r);
          if (saves.length == 1) {
            return reply({'detail': 'Vorübergehend nicht erreichbar'}, 503);
          }
          return reply({'id': 'new-grade'}, 201);
        }, gradePage: true);
        await tester.tap(find.text('Note eintragen'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(0), 'Mathematik');
        await tester.enterText(find.byType(TextFormField).at(2), '8');
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        expect(saves, isEmpty);
        await tester.enterText(find.byType(TextFormField).at(2), '5');
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        expect(find.text('Vorübergehend nicht erreichbar'), findsOneWidget);
        await tester.tap(find.text('Speichern'));
        await tester.pumpAndSettle();
        expect(saves.length, 2);
        expect(
          saves.first.headers['Idempotency-Key'],
          saves.last.headers['Idempotency-Key'],
        );
        expect(saves.first.headers['Idempotency-Key'], startsWith('grade-'));
        final body = jsonDecode(saves.last.body) as Json;
        expect(body['value'], 5);
        expect(body['subject'], 'Mathematik');
        expect(body['assessed_on'], '2026-10-17');
        expect(find.byType(GradeEditor), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
