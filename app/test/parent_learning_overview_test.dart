import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/daily_plan_panel.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/parent_child_navigation.dart';
import 'package:schulpilot/parent_overview.dart';

Json parentOverview() {
  final data = jsonDecode(
    File('test/fixtures/child_home.json').readAsStringSync(),
  ) as Json;
  data['daily_capture'] = {'status': 'skipped'};
  (data['plan'] as Json).addAll({
    'daily_goal_minutes': 20,
    'weekly_goal_minutes': 100,
    'daily_active_seconds': 720,
    'weekly_active_seconds': 1800,
    'daily_goal_met': false,
    'weekly_goal_met': false,
    'goal_required': true,
    'optional_learning': true,
    'completed_today': 1,
    'planned_minutes': 20,
    'week': <Json>[],
  });
  data['units'][0]['estimated_minutes'] = 20;
  data['units'][0]['status'] = 'completed';
  data['day_summary']['active_minutes_approx'] = 20;
  data['day_summary']['completed_units'] = 1;
  data['day_summary']['help_requests'] = 1;
  data['day_summary']['support'] = 'Ein gespeicherter Hilfewunsch wartet.';
  data['assignments'] = [
    {
      'id': 'open-work',
      'subject': 'Mathematik',
      'topic': 'Brüche',
      'kind': 'parent',
      'mandatory': true,
      'done': false,
      'note': '',
      'due': null,
    },
    {
      'id': 'finished-work',
      'subject': 'Englisch',
      'topic': 'Verben',
      'kind': 'parent',
      'mandatory': true,
      'done': true,
      'note': '',
      'due': null,
    },
  ];
  return data;
}

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json parentUser({String permission = 'owner'}) => {
  'id': 'artificial-parent',
  'role': 'parent',
  'display_name': 'Alex',
  'families': [
    {'id': 'own-family', 'name': 'Kunstfamilie', 'permission': permission},
  ],
};

Future<({AppState state, GoRouter router})> mountParent(
  WidgetTester tester,
  Json data,
  List<http.Request> requests, {
  double width = 390,
  String permission = 'owner',
  bool familyHome = false,
  double textScale = 1,
  List<Json> activities = const [],
}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              expect(
                request.method,
                'GET',
                reason:
                    'Viewing a parent overview cannot generate or start work.',
              );
              if (request.url.path.endsWith('/activity')) {
                return jsonResponse(activities);
              }
              if (request.url.path.endsWith('/learning')) {
                return jsonResponse({
                  'items': [],
                  'subjects': [],
                  'total': 0,
                  'pages': 1,
                  'page': 1,
                  'date': '2026-10-19',
                });
              }
              if (request.url.path == '/api/families/own-family') {
                return jsonResponse({
                  'id': 'own-family',
                  'name': 'Kunstfamilie',
                  'synthetic': true,
                  'children': [
                    {
                      ...data['child'] as Json,
                      'learning_time': data['plan'],
                      'summary': data['day_summary'],
                      'open_assignments': 1,
                    },
                  ],
                });
              }
              expect(
                request.url.path,
                '/api/children/${data['child']['id']}/overview',
              );
              return jsonResponse(data);
            }),
          ),
        )
        ..user = parentUser(permission: permission)
        ..familyId = 'own-family';
  final router = GoRouter(
    initialLocation: familyHome ? '/app' : '/child/${data['child']['id']}',
    routes: [
      GoRoute(path: '/app', builder: (_, _) => DashboardScreen(state)),
      GoRoute(
        path: '/child/:id',
        builder: (_, route) => ChildDetailScreen(
          state,
          childId: data['child']['id'],
          section: route.uri.queryParameters['bereich'] ?? 'overview',
        ),
      ),
      GoRoute(
        path: '/elsewhere',
        builder: (_, _) => const Scaffold(body: Text('Andere Ansicht')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (state: state, router: router);
}

Future<void> tapText(WidgetTester tester, String label) async {
  if (label == 'Verlauf') {
    await tester.ensureVisible(find.byType(ParentChildNavigation));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ParentChildNavigation),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.text(label).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> mountPreferences(
  WidgetTester tester,
  Json data,
  List<http.Request> requests, {
  double width = 320,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              expect(request.method, 'PUT');
              expect(
                request.url.path,
                '/api/children/${data['child']['id']}/preferences',
              );
              return jsonResponse(jsonDecode(request.body));
            }),
          ),
        )
        ..user = parentUser()
        ..familyId = 'own-family';
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => preferencesDialog(context, state, data['child']),
            child: const Text('Plan ändern'),
          ),
        ),
      ),
    ),
  );
  await tapText(tester, 'Plan ändern');
}

Future<void> fill(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pump();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'Parent sees twelve actual of twenty minutes and explicit open goal at $width px',
      (tester) async {
        final requests = <http.Request>[];
        final data = parentOverview();
        data['practice_summary'] = {
          'practiced_tasks': 4,
          'attempts': 5,
          'practiced_rounds': 1,
          'independent_tasks': 3,
          'assisted_tasks': 1,
        };
        data['mastery'] = [
          {
            'subject': 'Mathematik',
            'topic': 'Brüche',
            'next_review': '2026-10-20',
            'description': 'Später erneut abrufen',
          },
        ];
        await mountParent(tester, data, requests, width: width);
        expect(find.text('5 Versuche · 1 Runde'), findsOneWidget);
        expect(
          find.textContaining('Nächste Wiederholung: 20.10.2026'),
          findsNothing,
        );
        await tapText(tester, 'Festigung & nächste Wiederholungen');
        expect(
          find.textContaining('Nächste Wiederholung: 20.10.2026'),
          findsOneWidget,
        );
        expect(find.text('12:00 / 20 Min.'), findsOneWidget);
        expect(find.text('30:00 / 100 Min.'), findsOneWidget);
        expect(find.text('Tagesziel offen'), findsOneWidget);
        expect(find.text('Tagesziel erfüllt'), findsNothing);
        expect(find.text('Offene Pflichtaufträge: 1'), findsOneWidget);
        expect(find.text('1 Hilfewunsch heute'), findsOneWidget);
        expect(
          find.text('Anliegen und Antworten findet ihr in den Nachrichten.'),
          findsOneWidget,
        );
        final progress = tester
            .widgetList<LinearProgressIndicator>(
              find.descendant(
                of: find.byType(LearningGoalPanel),
                matching: find.byType(LinearProgressIndicator),
              ),
            )
            .first;
        expect(progress.value, 0.6);
        expect(requests.where((request) => request.method != 'GET'), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('Family cards use measured child goal counters at $width px', (
      tester,
    ) async {
      final requests = <http.Request>[];
      await mountParent(
        tester,
        parentOverview(),
        requests,
        width: width,
        familyHome: true,
      );
      expect(find.text('12:00 / 20 Min.'), findsOneWidget);
      expect(find.text('Tagesziel offen'), findsOneWidget);
      expect(find.text('1 offener Auftrag'), findsOneWidget);
      expect(find.text('Lernüberblick öffnen'), findsOneWidget);
      expect(requests.map((request) => request.url.path), [
        '/api/families/own-family',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'An empty recommendation after a finished estimated twenty minute round still asks for the open twelve of twenty minute goal',
    (tester) async {
      final data = parentOverview(), requests = <http.Request>[];
      data['plan']['today'] = <Json>[];
      await mountParent(tester, data, requests, width: 320);
      expect(find.text('12:00 / 20 Min.'), findsOneWidget);
      expect(find.text('Tagesziel offen'), findsOneWidget);
      expect(find.text('Tagesziel erfüllt'), findsNothing);
      expect(
        find.text(
          'Das Mindestziel ist noch offen. Im Lernraum geht es mit weiteren Runden weiter.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('später wiederkommen'), findsNothing);
      expect(requests.every((request) => request.method == 'GET'), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Parent child overview refreshes stored activity after fifteen seconds, never local estimated time',
    (tester) async {
      final data = parentOverview(), requests = <http.Request>[];
      await mountParent(tester, data, requests);
      final before = requests.length;
      data['plan']['daily_active_seconds'] = 780;
      await tester.pump(const Duration(seconds: 14));
      expect(requests.length, before);
      expect(find.text('12:00 / 20 Min.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(requests.length, before + 1);
      expect(find.text('13:00 / 20 Min.'), findsOneWidget);
      expect(find.text('Tagesziel offen'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Parent activity polling pauses in background and refreshes on foreground return',
    (tester) async {
      final data = parentOverview(), requests = <http.Request>[];
      await mountParent(tester, data, requests);
      final before = requests.length;
      for (final lifecycle in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
      }
      await tester.pump(const Duration(seconds: 45));
      expect(requests.length, before);
      data['plan']['daily_active_seconds'] = 840;
      for (final lifecycle in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
      }
      await tester.pumpAndSettle();
      expect(requests.length, before + 1);
      expect(find.text('14:00 / 20 Min.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('A covered parent route stops reads until returning', (
    tester,
  ) async {
    final data = parentOverview(), requests = <http.Request>[];
    final mounted = await mountParent(tester, data, requests);
    final before = requests.length;
    mounted.router.push('/elsewhere');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 31));
    expect(requests.length, before);
    mounted.router.pop();
    await tester.pumpAndSettle();
    expect(requests.length, before + 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Polling cannot continue after the observing account logs out', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final mounted = await mountParent(tester, parentOverview(), requests);
    final before = requests.length;
    mounted.state.user = null;
    await tester.pump(const Duration(seconds: 31));
    expect(requests.length, before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'A parent with viewing rights can read goals but cannot edit preferences',
    (tester) async {
      final requests = <http.Request>[];
      await mountParent(tester, parentOverview(), requests, permission: 'view');
      await tapText(tester, 'Plan ansehen');
      expect(find.text('Lernvorgaben anpassen'), findsNothing);
      expect(find.text('Auftrag oder Klassenarbeit anlegen'), findsNothing);
      expect(find.textContaining('Mindestziele:'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets(
      'Parent evidence keeps all categories and large text at $width',
      (tester) async {
        final data = parentOverview(), requests = <http.Request>[];
        data['practice_summary'] = {
          'practiced_tasks': 11,
          'attempts': 15,
          'practiced_rounds': 4,
          'independent_tasks': 3,
          'assisted_tasks': 2,
          'needs_practice_tasks': 1,
          'uncertain_tasks': 1,
          'reflection_tasks': 4,
          'completed_rounds': 2,
          'ongoing_rounds': 2,
        };
        await mountParent(tester, data, requests, width: width, textScale: 2);
        expect(find.text('11 Aufgaben geübt'), findsOneWidget);
        expect(find.text('3 alleine gelöst'), findsOneWidget);
        expect(find.text('2 mit Hilfe gelöst'), findsOneWidget);
        expect(find.text('1 weiter üben'), findsOneWidget);
        expect(find.text('1 Bewertung offen'), findsOneWidget);
        expect(find.text('4 eigene Beiträge'), findsOneWidget);
        expect(find.text('Im ersten Versuch'), findsOneWidget);
        expect(find.text('Oder nach erneutem Versuch'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(ParentPracticeSummary)).dy,
          lessThan(tester.getTopLeft(find.text('Was jetzt wichtig ist')).dy),
        );
        expect(find.text('Erledigte Aufträge anzeigen'), findsNothing);
        expect(requests.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Seven-day plan remains readable at 320 px and double text', (
    tester,
  ) async {
    final data = parentOverview(), requests = <http.Request>[];
    data['plan']['week'] = [
      for (var day = 20; day < 27; day++)
        {
          'date': '2026-10-$day',
          'free_day': false,
          'paused': false,
          'planned_minutes': 20,
          'items': [
            {'kind': 'none', 'subject': 'Mathematik und Naturwissenschaften'},
          ],
        },
    ];
    await mountParent(tester, data, requests, width: 320, textScale: 2);
    await tapText(tester, 'Plan ansehen');
    expect(find.text('ca. 20 Min.'), findsNWidgets(7));
    expect(requests.every((r) => r.method == 'GET'), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Mandatory and optional assignments have distinct counts in the overview',
    (tester) async {
      final data = parentOverview(), requests = <http.Request>[];
      data['assignments'].addAll([
        for (var i = 0; i < 4; i++)
          {'id': 'optional-$i', 'mandatory': false, 'done': false},
      ]);
      data['practice_summary'] = {
        'practiced_tasks': 4,
        'attempts': 5,
        'practiced_rounds': 2,
        'completed_rounds': 1,
        'ongoing_rounds': 1,
      };
      await mountParent(tester, data, requests);
      expect(find.text('Offene Pflichtaufträge: 1'), findsOneWidget);
      expect(
        find.textContaining('4 freiwillige Aufträge im Plan.'),
        findsOneWidget,
      );
      expect(
        find.text('Runden mit Antworten: 1 abgeschlossen · 1 noch offen'),
        findsOneWidget,
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Plan is addressable, hides completed assignments and viewing remains GET only',
    (tester) async {
      final requests = <http.Request>[];
      await mountParent(tester, parentOverview(), requests);
      await tapText(tester, 'Plan ansehen');
      expect(
        tester
            .widget<ChildDetailScreen>(find.byType(ChildDetailScreen).last)
            .section,
        'plan',
      );
      expect(find.text('Mathematik · Brüche'), findsWidgets);
      expect(find.text('Englisch · Verben'), findsNothing);
      await tapText(tester, 'Erledigte Aufträge anzeigen');
      expect(find.text('Englisch · Verben'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Logout immediately hides the cached parent child contents', (
    tester,
  ) async {
    final mounted = await mountParent(tester, parentOverview(), []);
    expect(find.text('Lernstand auf einen Blick'), findsOneWidget);
    mounted.state.user = null;
    mounted.state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(ParentOverview), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Grouped parent mobile form saves minimum goals through existing API fields and preserves unrelated settings',
    (tester) async {
      final data = parentOverview(), requests = <http.Request>[];
      data['child']['preferences']['subject_days'] = {
        'Mathematik': [1, 3],
      };
      data['child']['preferences']['push_consent'] = true;
      await mountPreferences(tester, data, requests);
      expect(find.text('Lernziele & Plan'), findsOneWidget);
      expect(find.text('Mindestlernzeit'), findsOneWidget);
      expect(
        find.textContaining('Danach darf dein Kind freiwillig weiterlernen.'),
        findsOneWidget,
      );
      await fill(tester, 'Mindestziel pro Tag', '25');
      await fill(tester, 'Mindestziel pro Woche', '125');
      await fill(tester, 'Rundendauer', '10');
      await fill(tester, 'Lernpause', '4');
      await fill(tester, 'Fächer', 'Mathematik, Englisch');
      await fill(
        tester,
        'Themen zum Wiederholen',
        'Mathematik: Brüche, Englisch: Verben',
      );
      await tapText(tester, 'Speichern');
      expect(requests, hasLength(1));
      final body = jsonDecode(requests.single.body) as Json;
      expect(body['daily_minutes'], 25);
      expect(body['weekly_minutes'], 125);
      expect(body['session_minutes'], 10);
      expect(body['break_minutes'], 4);
      expect(body['focus_subjects'], ['Mathematik', 'Englisch']);
      expect(body['repeat_topics'], ['Mathematik: Brüche', 'Englisch: Verben']);
      expect(body['subject_days'], {
        'Mathematik': [1, 3],
      });
      expect(body['weekdays'], data['child']['preferences']['weekdays']);
      expect(body['quiet_start'], 20);
      expect(body['quiet_end'], 8);
      expect(body['push_consent'], true);
      expect(body['timezone'], 'Europe/Berlin');
      expect(body.containsKey('daily_limit_minutes'), false);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Invalid minimum input stays editable and cannot send a zero fallback',
    (tester) async {
      final requests = <http.Request>[];
      await mountPreferences(tester, parentOverview(), requests);
      await fill(tester, 'Mindestziel pro Tag', '0');
      await tapText(tester, 'Speichern');
      expect(find.text('Bitte 5 bis 120 eingeben.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(requests, isEmpty);
      await tapText(tester, 'Abbrechen');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'E10 unmapped technical events remain behind the disclosure and reading never writes',
    (tester) async {
      final requests = <http.Request>[];
      await mountParent(
        tester,
        parentOverview(),
        requests,
        activities: [
          {
            'kind': 'active_time',
            'created': 1792407600,
            'detail': {'seconds': 20},
          },
          {'kind': 'feedback_pending', 'created': 1792407601, 'detail': {}},
          {'kind': 'answer', 'created': 1792407602, 'detail': {}},
        ],
      );
      await tapText(tester, 'Verlauf');
      expect(find.text('active_time'), findsNothing);
      expect(find.text('feedback_pending'), findsNothing);
      expect(find.textContaining('Antwort gespeichert'), findsOneWidget);
      await tapText(tester, 'Technische Ereignisse');
      expect(find.text('active_time'), findsOneWidget);
      expect(find.text('feedback_pending'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
