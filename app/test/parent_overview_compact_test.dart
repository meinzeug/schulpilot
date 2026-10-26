import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/parent_overview.dart';
import 'package:schulpilot/ui.dart';

import 'parent_learning_overview_test.dart' as fixture;

class CompactOverviewFixture {
  final Json data = fixture.parentOverview();
  final requests = <http.Request>[];
  late final AppState state;
  late final GoRouter router;

  CompactOverviewFixture({void Function(Json)? configure}) {
    data['day_summary']['help_requests'] = 0;
    data['day_summary']['coaching_support_topics'] = <String>[];
    data['assignments'] = <Json>[];
    data['learning_guidance'] = null;
    data['practice_summary'] = {
      'practiced_tasks': 11,
      'independent_tasks': 3,
      'assisted_tasks': 2,
      'needs_practice_tasks': 1,
      'uncertain_tasks': 1,
      'reflection_tasks': 4,
      'attempts': 15,
      'practiced_rounds': 4,
      'completed_rounds': 2,
      'ongoing_rounds': 2,
    };
    configure?.call(data);
    state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient((request) async {
                requests.add(request);
                if (request.method != 'GET') {
                  throw StateError('Synthetic view must not write.');
                }
                if (request.url.path.endsWith('/parent-insights')) {
                  return fixture.jsonResponse({
                    'settings': {'enabled': false, 'revision': 0},
                    'topics': [],
                    'totals': {},
                    'history': [],
                    'can_manage': true,
                    'eligible': false,
                  });
                }
                if (request.url.path.endsWith('/activity')) {
                  return fixture.jsonResponse({
                    'items': [],
                    'next_cursor': null,
                  });
                }
                if (!request.url.path.endsWith('/overview')) {
                  throw StateError('Unexpected synthetic view GET.');
                }
                return fixture.jsonResponse(jsonDecode(jsonEncode(data)));
              }),
            ),
          )
          ..user = fixture.parentUser()
          ..familyId = 'own-family';
    state.api.token = 'synthetic-parent-session';
    router = GoRouter(
      initialLocation: '/child/$childId',
      routes: [
        GoRoute(
          path: '/child/:id',
          builder: (_, route) =>
              route.uri.queryParameters['bereich'] == 'verlauf'
              ? Scaffold(body: Text('Ziel: ${route.uri}'))
              : ChildDetailScreen(
                  state,
                  childId: route.pathParameters['id']!,
                  section: route.uri.queryParameters['bereich'] ?? 'overview',
                ),
        ),
        for (final path in [
          '/progress/:id',
          '/messages/:id',
          '/parent-plan/:id',
          '/learn/:id',
          '/unit/:id',
          '/library/:id',
        ])
          GoRoute(
            path: path,
            builder: (_, route) => Scaffold(body: Text('Ziel: ${route.uri}')),
          ),
      ],
    );
  }

  String get childId => data['child']['id'] as String;

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> press(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder metric(String title) => find.byWidgetPredicate(
  (widget) => widget is ActionPanel && widget.actionLabel == title,
);

Uri visibleDestination(WidgetTester tester) {
  final finder = find.textContaining('Ziel: ');
  expect(finder, findsOneWidget);
  return Uri.parse(tester.widget<Text>(finder).data!.substring(6));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in ['Nunito', 'SpaceGrotesk']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
  });

  for (final size in [
    (320.0, 2.0),
    (390.0, 2.0),
    (820.0, 1.0),
    (1280.0, 1.0),
  ]) {
    testWidgets(
      'Compact parent core remains readable without default detail flood at $size',
      (tester) async {
        final f = CompactOverviewFixture();
        await f.mount(tester, width: size.$1, scale: size.$2);
        expect(find.text('Mika (Beispiel)'), findsOneWidget);
        expect(find.text('1 Runde heute abgeschlossen'), findsOneWidget);
        expect(find.text('Vorhandene Runden öffnen'), findsOneWidget);
        expect(find.text('11 Aufgaben mit Antwort'), findsOneWidget);
        expect(find.text('12:00 aktiv'), findsOneWidget);
        expect(
          find.textContaining('20 Min. Mindestziel · noch offen'),
          findsOneWidget,
        );
        expect(find.byType(ParentPracticeSummary), findsNothing);
        expect(find.text('Die letzten sieben Tage'), findsNothing);
        expect(find.text('Fächer im Überblick'), findsNothing);
        expect(
          find.text('Gespeicherte Übungsbelege im Detail ansehen'),
          findsNothing,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('parent-overview-open-items')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('parent-overview-open-items')),
          findsOneWidget,
        );
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Answer categories remain available after deliberate disclosure and retain their exact route',
    (tester) async {
      final f = CompactOverviewFixture();
      await f.mount(tester);
      await press(tester, find.text('Antworten genauer ansehen'));
      expect(find.byType(ParentPracticeSummary), findsOneWidget);
      for (final label in [
        '3 alleine gelöst',
        '2 mit Hilfe gelöst',
        '1 weiter üben',
        '1 Bewertung offen',
        '4 eigene Beiträge',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await press(tester, find.text('2 mit Hilfe gelöst'));
      expect(visibleDestination(tester).path, '/progress/${f.childId}');
      expect(
        visibleDestination(tester).queryParameters['ergebnis'],
        'assisted',
      );
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    'Time and subject history are disclosures with their saved values intact',
    (tester) async {
      final f = CompactOverviewFixture();
      await f.mount(tester);
      final before = f.requests.length;
      await press(tester, find.text('Zeit & Mindestziele'));
      expect(find.text('12:00 / 20 Min.'), findsOneWidget);
      expect(find.text('Tagesziel offen'), findsOneWidget);
      await press(tester, find.text('Fächer & Wochenrückblick'));
      expect(find.text('Die letzten sieben Tage'), findsOneWidget);
      expect(find.text('Fächer im Überblick'), findsOneWidget);
      expect(
        f.requests.length,
        before,
        reason: 'Local disclosures must not request an AI analysis.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in [
    ('Antwortbelege · bisher', '/progress/'),
    ('Lernzeit · heute', '/parent-plan/'),
  ]) {
    testWidgets(
      'Core metric ${entry.$1} opens its existing authorized destination without writes',
      (tester) async {
        final f = CompactOverviewFixture();
        await f.mount(tester);
        await press(tester, metric(entry.$1));
        expect(visibleDestination(tester).path, '${entry.$2}${f.childId}');
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      },
    );
  }

  testWidgets(
    'Open duties have a distinct plan action even when help requests are also present',
    (tester) async {
      final f = CompactOverviewFixture(
        configure: (data) {
          data['day_summary']['help_requests'] = 2;
          data['assignments'] = [
            {
              'id': 'synthetic-duty',
              'mandatory': true,
              'done': false,
              'source_status': 'confirmed',
            },
          ];
        },
      );
      await f.mount(tester);
      await press(tester, find.text('Offene Pflichtaufträge: 1'));
      expect(visibleDestination(tester).path, '/parent-plan/${f.childId}');
      expect(
        visibleDestination(tester).queryParameters['obligation'],
        'mandatory',
      );
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    'A saved help request is the single primary next action before planning',
    (tester) async {
      final f = CompactOverviewFixture(
        configure: (data) {
          data['day_summary']['help_requests'] = 2;
          data['assignments'] = [
            {
              'id': 'synthetic-assignment',
              'mandatory': true,
              'done': false,
              'source_status': 'confirmed',
            },
          ];
        },
      );
      await f.mount(tester);
      expect(find.text('Nachrichten ansehen'), findsOneWidget);
      expect(find.text('Lernplan ansehen'), findsNothing);
      await press(tester, find.text('Nachrichten ansehen'));
      expect(visibleDestination(tester).path, '/messages/${f.childId}');
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    'Changed source assignments retain a precise review destination without counting as confirmed duties',
    (tester) async {
      final f = CompactOverviewFixture(
        configure: (data) {
          data['assignments'] = [
            {
              'id': 'synthetic-changed-assignment',
              'mandatory': true,
              'done': false,
              'source_status': 'needs_review',
            },
          ];
        },
      );
      await f.mount(tester);
      expect(find.text('Offene Pflichtaufträge: 0'), findsOneWidget);
      expect(find.text('1 Auftragsquelle zu prüfen'), findsOneWidget);
      await press(tester, find.text('Auftragsquellen ansehen'));
      expect(visibleDestination(tester).queryParameters['source'], 'changed');
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    'Missing evidence, time and help values stay unknown instead of becoming success or zero',
    (tester) async {
      final f = CompactOverviewFixture(
        configure: (data) {
          data.remove('practice_summary');
          data.remove('assignments');
          data['plan'].remove('daily_active_seconds');
          data['plan'].remove('daily_goal_minutes');
          data['day_summary'].remove('help_requests');
        },
      );
      await f.mount(tester);
      expect(find.text('Nicht vollständig gemeldet'), findsOneWidget);
      expect(find.text('Noch nicht gemeldet'), findsOneWidget);
      expect(find.text('Hilfewünsche nicht gemeldet'), findsOneWidget);
      expect(find.text('Pflichtaufträge nicht gemeldet'), findsOneWidget);
      expect(find.text('0 Aufgaben mit Antwort'), findsNothing);
      expect(find.text('0:00 aktiv'), findsNothing);
      expect(find.text('0 Hilfewünsche'), findsNothing);
    },
  );

  testWidgets('A captured core action cannot navigate under a new session', (
    tester,
  ) async {
    final f = CompactOverviewFixture();
    await f.mount(tester);
    final callback = tester
        .widget<ActionPanel>(metric('Antwortbelege · bisher'))
        .onPressed!;
    f.state.api.token = 'synthetic-replaced-session';
    callback();
    await tester.pumpAndSettle();
    expect(find.textContaining('Ziel: ', skipOffstage: false), findsNothing);
    expect(find.byType(ParentOverview), findsOneWidget);
    expect(f.requests.every((r) => r.method == 'GET'), isTrue);
  });

  testWidgets(
    'A captured next action does not navigate through a foreign dialog',
    (tester) async {
      final f = CompactOverviewFixture();
      await f.mount(tester);
      final action = find.byWidgetPredicate(
        (widget) =>
            widget is ActionPanel &&
            widget.actionLabel == 'Vorhandene Runden öffnen',
      );
      final callback = tester.widget<ActionPanel>(action).onPressed!;
      final context = tester.element(find.byType(ParentOverview));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) =>
              const AlertDialog(title: Text('Synthetischer Fremddialog')),
        ),
      );
      await tester.pumpAndSettle();
      callback();
      await tester.pumpAndSettle();
      expect(find.text('Synthetischer Fremddialog'), findsOneWidget);
      expect(find.textContaining('Ziel: ', skipOffstage: false), findsNothing);
      expect(find.byType(ParentOverview), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'The saved controller reason remains exact instead of promising further practice',
    (tester) async {
      final f = CompactOverviewFixture(
        configure: (data) {
          data['learning_guidance'] = {
            'unit_id': 'synthetic-unit',
            'subject': 'Deutsch',
            'topic': 'Beispielthema',
            'kind': 'confirm_source',
            'title': 'Prüfe zuerst die neue Heftseite',
            'reason': 'Die gespeicherte Quelle hat sich geändert.',
          };
        },
      );
      await f.mount(tester);
      expect(find.text('Prüfe zuerst die neue Heftseite'), findsOneWidget);
      expect(
        find.textContaining('Die gespeicherte Quelle hat sich geändert.'),
        findsOneWidget,
      );
      await press(tester, find.text('Gespeicherte Runde ansehen'));
      expect(visibleDestination(tester).path, '/unit/synthetic-unit');
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    'A saved round and its reason stay reachable when a help request has priority',
    (tester) async {
      final f = CompactOverviewFixture(
        configure: (data) {
          data['day_summary']['help_requests'] = 1;
          data['learning_guidance'] = {
            'unit_id': 'synthetic-unit',
            'subject': 'Deutsch',
            'topic': 'Beispielthema',
            'title': 'Gespeicherten Schritt prüfen',
            'reason': 'Künstlicher gespeicherter Anlass.',
          };
        },
      );
      await f.mount(tester);
      expect(find.text('Aktuelle Runde · Deutsch'), findsNothing);
      await press(tester, find.text('Antworten genauer ansehen'));
      expect(
        find.textContaining('Künstlicher gespeicherter Anlass.'),
        findsOneWidget,
      );
      await press(tester, find.text('Gespeicherte Runde ansehen'));
      expect(visibleDestination(tester).path, '/unit/synthetic-unit');
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'A saved coaching observation stays reachable beside a higher priority duty',
    (tester) async {
      final f = CompactOverviewFixture(
        configure: (data) {
          data['day_summary']['coaching_support_topics'] = [
            'Künstliche Beobachtung',
          ];
          data['assignments'] = [
            {
              'id': 'synthetic-duty',
              'mandatory': true,
              'done': false,
              'source_status': 'confirmed',
            },
          ];
        },
      );
      await f.mount(tester);
      expect(find.text('Lernplan ansehen'), findsOneWidget);
      await press(tester, find.text('Rückmeldung der Lernbegleitung'));
      expect(find.byType(ParentOverview), findsNothing);
      expect(visibleDestination(tester).path, '/child/${f.childId}');
      expect(visibleDestination(tester).queryParameters['bereich'], 'verlauf');
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
