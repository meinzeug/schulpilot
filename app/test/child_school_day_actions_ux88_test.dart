import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/school_day_screen.dart';
import 'package:schulpilot/ui.dart';

import 'school_day_background_test.dart' as fixture;
import 'child_local_tools_ux88_test.dart' as local;

Future<GoRouter> open(
  WidgetTester tester,
  AppState state, {
  bool capture = false,
}) async {
  final router = GoRouter(
    initialLocation: '/after-school/child${capture ? '?capture=1' : ''}',
    routes: [
      GoRoute(
        path: '/after-school/:id',
        builder: (_, route) => SchoolDayScreen(
          state,
          childId: route.pathParameters['id']!,
          startWithPhotos: route.uri.queryParameters['capture'] == '1',
        ),
      ),
      GoRoute(
        path: '/app',
        builder: (_, _) => Scaffold(body: Text('Dein Heute')),
      ),
      GoRoute(
        path: '/library/:id',
        builder: (_, _) => Scaffold(body: Text('Gespeicherte Hefte')),
      ),
      GoRoute(
        path: '/after-school/:id/history',
        builder: (_, _) => Scaffold(body: Text('Frühere Schultage')),
      ),
      GoRoute(
        path: '/new',
        builder: (_, _) => Scaffold(body: Text('Neuere Ansicht')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await fixture.settleUi(tester);
  return router;
}

Future<void> tap(WidgetTester tester, String text) =>
    fixture.tapText(tester, text);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'KK061 plain empty day visits and refresh stay GET-only until an explicit start',
    (tester) async {
      final calls = <http.Request>[];
      Json? day;
      final server = fixture.PreparationServer(pages: []);
      final state = local.account((r) async {
        calls.add(r);
        if (r.method == 'POST') {
          day = server.day;
          return fixture.response(day!);
        }
        return fixture.response({'day': day});
      });
      await open(tester, state);
      expect(find.text('Heutige Fotos beginnen'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      await tap(tester, 'Heutigen Stand prüfen');
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      await tap(tester, 'Heutige Fotos beginnen');
      expect(calls.where((r) => r.method == 'POST'), hasLength(1));
      expect(
        calls.where((r) => r.method == 'POST').single.url.path,
        '/api/children/child/school-day/today',
      );
      expect(find.text('Zeig mir deine Heftseiten'), findsOneWidget);
      expect(calls.any((r) => r.url.path.endsWith('/prepare')), isFalse);
    },
  );
  testWidgets(
    'KK061 explicit capture creates normalized today once and later reopens read-only',
    (tester) async {
      final server = fixture.PreparationServer(pages: []);
      var created = false, posts = 0;
      final state = local.account((r) async {
        if (r.method == 'POST') {
          posts++;
          created = true;
          return fixture.response(server.day);
        }
        return fixture.response({'day': created ? server.day : null});
      });
      await open(tester, state, capture: true);
      expect(posts, 1);
      expect(find.text('Zeig mir deine Heftseiten'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await open(tester, state, capture: true);
      expect(posts, 1);
    },
  );
  testWidgets(
    'KK054 postponed day photo action reaches collection instead of reopening postponed state',
    (tester) async {
      final server = fixture.PreparationServer(
        pages: [],
        preparation: {'status': 'postponed'},
      );
      final state = server.state();
      await open(tester, state);
      expect(find.text('Für später abgelegt'), findsOneWidget);
      await tap(tester, 'Heute neu fotografieren');
      expect(find.text('Zeig mir deine Heftseiten'), findsOneWidget);
      expect(find.text('Für später abgelegt'), findsNothing);
      expect(server.requests.every((r) => r.startsWith('GET ')), isTrue);
    },
  );
  testWidgets(
    'KK056 local discard removes only displayed day photos and keeps other days',
    (tester) async {
      final server = fixture.PreparationServer(pages: []);
      final state = server.state();
      final bytes = Uint8List.fromList(
        image.encodePng(image.Image(width: 3, height: 3)),
      );
      final selected = await state.pendingUploads.add(
        'kid',
        'child',
        'day',
        bytes,
      );
      final other = await state.pendingUploads.add(
        'kid',
        'child',
        'other-day',
        bytes,
      );
      await open(tester, state);
      await tap(tester, 'Mehr zu diesem Tag');
      await tap(tester, 'Gespeicherte Fotos entfernen');
      expect(find.text('1 vorgemerktes Foto entfernen?'), findsOneWidget);
      expect(find.textContaining('Fotos anderer Tage'), findsOneWidget);
      await tap(tester, 'Vorgemerkte Fotos entfernen');
      final remaining = await state.pendingUploads.read('kid');
      expect(remaining.map((r) => r['key']), [other]);
      expect(remaining.any((r) => r['key'] == selected), isFalse);
      expect(server.requests.every((r) => r.startsWith('GET ')), isTrue);
    },
  );
  testWidgets('KK056 cancelling local discard retains every pending photo', (
    tester,
  ) async {
    final server = fixture.PreparationServer(pages: []);
    final state = server.state();
    await state.pendingUploads.add(
      'kid',
      'child',
      'day',
      Uint8List.fromList([1]),
    );
    await open(tester, state);
    await tap(tester, 'Mehr zu diesem Tag');
    await tap(tester, 'Gespeicherte Fotos entfernen');
    await tap(tester, 'Behalten');
    expect(await state.pendingUploads.read('kid'), hasLength(1));
  });
  testWidgets(
    'KK012 pending preview closes with same-ID new session and old close cannot pop a newer route',
    (tester) async {
      final server = fixture.PreparationServer(pages: []);
      final state = server.state();
      await state.pendingUploads.add(
        'kid',
        'child',
        'day',
        Uint8List.fromList(image.encodePng(image.Image(width: 3, height: 3))),
      );
      final router = await open(tester, state);
      await tap(tester, 'Vorgemerktes Foto 1 ansehen');
      final close = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Zurück zu deinen Fotos',
            ),
          )
          .onPressed!;
      state.user = {...state.user!};
      state.notifyListeners();
      await fixture.settleUi(tester);
      expect(find.text('Dein vorgemerktes Foto'), findsNothing);
      router.push('/new');
      await tester.pumpAndSettle();
      close();
      await tester.pumpAndSettle();
      expect(find.text('Neuere Ansicht'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'KK012 delayed today data cannot populate a different child context',
    (tester) async {
      final old = Completer<http.Response>();
      final server = fixture.PreparationServer();
      final state = local.account(
        (r) async => r.url.path.contains('/child/')
            ? old.future
            : fixture.response({'day': null}),
      );
      final router = await open(tester, state);
      state.user = {...state.user!, 'child_id': 'other'};
      state.notifyListeners();
      router.go('/after-school/other');
      await fixture.settleUi(tester);
      old.complete(fixture.response({'day': server.day}));
      await tester.pumpAndSettle();
      expect(find.text('Künstliche Bruchaufgabe 1'), findsNothing);
      expect(find.text('Heutige Fotos beginnen'), findsOneWidget);
    },
  );
  testWidgets(
    'KK058 completed package does not claim the time minimum or whole day is finished',
    (tester) async {
      final server = fixture.PreparationServer(
        pages: [fixture.source(1, confirmed: true)],
        stage: 'ready',
      );
      server.units = [
        {
          'id': 'done',
          'status': 'completed',
          'subject': 'Mathematik',
          'topic': 'Brüche',
        },
      ];
      await open(tester, server.state());
      expect(find.text('Lernpaket bearbeitet'), findsOneWidget);
      expect(find.text('Für heute geschafft'), findsNothing);
    },
  );
  testWidgets(
    'KK060 day source destinations name subject and topic from stored metadata',
    (tester) async {
      final server = fixture.PreparationServer(
        pages: [fixture.source(1, confirmed: true)],
        stage: 'ready',
      );
      await open(tester, server.state());
      await tap(tester, 'Was ist im Paket?');
      expect(find.text('Heftseite 1 · Mathematik'), findsOneWidget);
      expect(find.text('Künstliche Bruchaufgabe 1'), findsOneWidget);
      expect(server.requests.every((r) => r.startsWith('GET ')), isTrue);
    },
  );
  testWidgets(
    'KK062 empty checking has an explicit guarded route back to adding pages',
    (tester) async {
      final server = fixture.PreparationServer(pages: [], stage: 'review');
      await open(tester, server.state());
      await tap(tester, 'Heftseite hinzufügen');
      expect(find.text('Zeig mir deine Heftseiten'), findsOneWidget);
      expect(
        server.requests.where((r) => r.startsWith('PUT ')),
        ['/api/school-days/day/stage'].map((p) => 'PUT $p'),
      );
      expect(server.requests.any((r) => r.endsWith('/prepare')), isFalse);
    },
  );
  testWidgets(
    'KK055 preparing card itself opens its clearly labelled home destination without creating work',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final server = fixture.PreparationServer(
          preparation: {'status': 'running', 'phase': 'recognition'},
        );
        await open(tester, server.state());
        final statusCard = find.ancestor(
          of: find.text('Wir lesen deine Heftseiten'),
          matching: find.byType(ActionPanel),
        );
        await tester.ensureVisible(statusCard);
        await fixture.settleUi(tester);
        expect(
          tester.getSemantics(statusCard),
          matchesSemantics(
            isButton: true,
            isFocusable: true,
            hasFocusAction: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            label: 'Fotos abgegeben\nWir lesen deine Heftseiten\nDu kannst die App schließen und später weitermachen.\n0 von 1 Seite\nZur Startseite',
          ),
        );
        await tap(tester, 'Wir lesen deine Heftseiten');
        expect(find.text('Dein Heute'), findsOneWidget);
        expect(server.requests.every((r) => r.startsWith('GET ')), isTrue);
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets(
    'KK090 actual stored school date is visible before expanding day details',
    (tester) async {
      final server = fixture.PreparationServer(pages: []);
      await open(tester, server.state());
      expect(find.text('Schultag · 15.10.2026'), findsOneWidget);
      expect(find.text('Mehr zu diesem Tag'), findsOneWidget);
    },
  );
  testWidgets(
    'KK091 subject packet opens only the pages actually referenced by that group',
    (tester) async {
      final server = fixture.PreparationServer(
        pages: [fixture.source(1, confirmed: true)],
        stage: 'ready',
      );
      server.todayOverride = {
        ...server.day,
        'plan': {
          'groups': [
            {
              'subject': 'Mathematik',
              'topics': ['Brüche'],
              'material_ids': ['page1', 'foreign-page'],
            },
          ],
          'estimated_minutes': 8,
        },
      };
      await open(tester, server.state());
      await tap(tester, 'Was ist im Paket?');
      await tap(tester, 'Mathematik');
      expect(find.text('Mathematik · Heftseiten'), findsOneWidget);
      expect(find.text('Heftseite 1'), findsOneWidget);
      expect(find.textContaining('foreign-page'), findsNothing);
      expect(server.requests.every((r) => r.startsWith('GET ')), isTrue);
    },
  );
}
