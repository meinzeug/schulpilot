import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/parent_homework_screen.dart';
import 'package:schulpilot/parent_insights_panel.dart';
import 'package:schulpilot/parent_overview.dart';
import 'package:schulpilot/parent_plan_screen.dart';
import 'package:schulpilot/practice_evidence.dart';
import 'package:schulpilot/ui.dart';

import 'parent_insights_test.dart' as fixture;
import 'parent_learning_overview_test.dart' as overview;

Json clone(Json value) => Json.from(jsonDecode(jsonEncode(value)));

class _Fixture {
  Json plan = clone(fixture.plan()),
      insights = clone(fixture.insight()),
      homework = clone(fixture.homework()),
      summary = clone(overview.parentOverview());
  final requests = <http.Request>[];
  Future<http.Response?> Function(http.Request)? respond;
  late final state = fixture.account(
    MockClient((r) async {
      requests.add(r);
      final custom = await respond?.call(r);
      if (custom != null) return custom;
      expect(
        r.method,
        'GET',
        reason: 'Read-only parent views must not create learning work.',
      );
      return fixture.response(
        r.url.path.endsWith('/parent-insights')
            ? insights
            : r.url.path.endsWith('/homework-review')
            ? homework
            : plan,
      );
    }),
  );
  _Fixture() {
    plan['child']['id'] = 'child-a';
    plan['plan']['date'] = '2026-10-22';
    plan['topics'][0]['revision'] = 3;
  }

  Future<GoRouter> mount(
    WidgetTester tester, {
    String path = '/plan/child-a',
    double width = 390,
    double scale = 1,
    Brightness brightness = Brightness.dark,
    bool settle = true,
    bool showInsights = false,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: path,
      routes: [
        for (final prefix in ['plan', 'parent-plan'])
          GoRoute(
            path: '/$prefix/:child',
            builder: (_, route) => ParentPlanScreen(
              state,
              childId: route.pathParameters['child']!,
            ),
          ),
        GoRoute(
          path: '/homework/:child',
          builder: (_, route) => ParentHomeworkScreen(
            state,
            childId: route.pathParameters['child']!,
          ),
        ),
        GoRoute(
          path: '/insights/:child',
          builder: (_, route) => PageFrame(
            state: state,
            title: 'Lernkompass',
            child: ParentInsightsPanel(
              state,
              childId: route.pathParameters['child']!,
            ),
          ),
        ),
        GoRoute(
          path: '/overview',
          builder: (_, _) => PageFrame(
            state: state,
            title: 'Überblick',
            child: ParentOverview(
              data: summary,
              state: showInsights ? state : null,
            ),
          ),
        ),
        GoRoute(
          path: '/progress/:child',
          builder: (_, route) => Scaffold(
            body: Text(
              'Belege ${route.uri.queryParameters['fach'] ?? 'alle'} · ${route.uri.queryParameters['thema'] ?? 'alle'}',
            ),
          ),
        ),
        GoRoute(
          path: '/unit/:id',
          builder: (_, route) =>
              Scaffold(body: Text('Runde ${route.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/material/:id',
          builder: (_, route) =>
              Scaffold(body: Text('Quelle ${route.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/homework/:child/:id',
          builder: (_, route) => Scaffold(
            body: Text('Hausaufgabendetails ${route.pathParameters['id']}'),
          ),
        ),
        GoRoute(
          path: '/learning-preparation/:child/:id',
          builder: (_, _) =>
              const Scaffold(body: Text('Unzulässiger alter Sprung')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(brightness: brightness),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    return router;
  }
}

Future<void> click(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'P36 an old topic preparation cannot disable or navigate the next child',
    (tester) async {
      final pending = Completer<http.Response>();
      final f = _Fixture();
      f.respond = (r) async => r.method == 'POST' ? pending.future : null;
      final router = await f.mount(tester);
      await click(tester, 'Meine Themen');
      await tester.ensureVisible(find.text('KI-Runde vorbereiten'));
      await tester.tap(find.text('KI-Runde vorbereiten'));
      await tester.pump();
      router.go('/plan/child-b');
      await tester.pumpAndSettle();
      await click(tester, 'Meine Themen');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'KI-Runde vorbereiten'),
            )
            .onPressed,
        isNotNull,
      );
      pending.complete(fixture.response({'kind': 'job', 'id': 'old-job'}));
      await tester.pumpAndSettle();
      expect(find.text('Unzulässiger alter Sprung'), findsNothing);
      expect(f.requests.where((r) => r.method == 'POST'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P36 a pending old review setting does not hold the next child busy',
    (tester) async {
      final pending = Completer<http.Response>();
      final f = _Fixture();
      f.respond = (r) async => r.method == 'PUT' ? pending.future : null;
      final router = await f.mount(tester, path: '/insights/child-a');
      await tester.ensureVisible(find.byType(SwitchListTile));
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(
        true,
      );
      await tester.pump();
      router.go('/insights/child-b');
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNotNull,
      );
      pending.complete(fixture.response({'enabled': true}));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P37 plan view and completed filter remain bound to their own child',
    (tester) async {
      final f = _Fixture();
      f.state.collectionViews['parent-plan:child-a'] = {
        'section': 1,
        'page': 2,
        'include_completed': true,
      };
      f.plan['pagination'] = {'page': 2, 'pages': 2, 'total': 21};
      final router = await f.mount(tester);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Meine Themen'))
            .selected,
        isTrue,
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(f.requests.first.url.queryParameters['page'], '2');
      expect(f.requests.first.url.queryParameters['include_completed'], 'true');
      router.go('/plan/child-b');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'KI-Lernweg'))
            .selected,
        isTrue,
      );
      router.go('/plan/child-a');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Meine Themen'))
            .selected,
        isTrue,
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P37 switching homework children restores only their own valid remembered filter',
    (tester) async {
      final f = _Fixture();
      f.state.collectionViews['parent-homework:child-a'] = {'filter': 'worked'};
      f.state.collectionViews['parent-homework:child-b'] = {'filter': 'review'};
      f.state.collectionViews['parent-homework:child-c'] = {
        'filter': 'invalid',
      };
      final router = await f.mount(tester, path: '/homework/child-a');
      expect(f.requests.last.url.queryParameters['state'], 'worked');
      router.go('/homework/child-b');
      await tester.pumpAndSettle();
      expect(f.requests.last.url.queryParameters['state'], 'review');
      router.go('/homework/child-a');
      await tester.pumpAndSettle();
      expect(f.requests.last.url.queryParameters['state'], 'worked');
      router.go('/homework/child-c');
      await tester.pumpAndSettle();
      expect(f.requests.last.url.queryParameters['state'], 'all');
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P38 refresh hides obsolete interactive short plans until the saved response arrives',
    (tester) async {
      final pending = Completer<http.Response>();
      final f = _Fixture();
      f.plan['instructional_plans'] = [
        {
          'unit_id': 'unit',
          'subject': 'Mathematik',
          'topic': 'Bisheriger künstlicher Kurzplan',
          'cursor': 0,
          'steps': [],
        },
      ];
      var reads = 0;
      f.respond = (r) async =>
          r.url.path.endsWith('/learning-plan') && ++reads > 1
          ? pending.future
          : null;
      await f.mount(tester);
      expect(
        find.text('Mathematik · Bisheriger künstlicher Kurzplan'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byTooltip('Aktualisieren'));
      await tester.tap(find.byTooltip('Aktualisieren'));
      await tester.pump();
      expect(
        find.text('Mathematik · Bisheriger künstlicher Kurzplan'),
        findsNothing,
      );
      expect(
        find.text('Der gespeicherte Plan wird aktualisiert …'),
        findsOneWidget,
      );
      pending.complete(
        fixture.response({...f.plan, 'instructional_plans': []}),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Mathematik · Bisheriger künstlicher Kurzplan'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P39 changed sources explain the generation lock and expose a read-only source route',
    (tester) async {
      final f = _Fixture();
      f.plan['topics'][0].addAll({
        'source_status': 'needs_review',
        'material_id': 'source',
      });
      await f.mount(tester);
      await click(tester, 'Meine Themen');
      expect(
        find.textContaining('Prüfe zuerst die geänderte Heftquelle'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'KI-Runde vorbereiten'),
            )
            .onPressed,
        isNull,
      );
      await click(tester, 'Geänderte Heftquelle prüfen');
      expect(find.text('Quelle source'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final status in ['ready', 'active', 'paused']) {
    testWidgets(
      'P40 P41 P42 saved $status rounds retain their status and old goal revision',
      (tester) async {
        final f = _Fixture();
        f.plan['topics'][0].addAll({
          'available_unit': {'id': 'saved', 'status': status},
          'recent_units': [
            {
              'id': 'older',
              'topic': 'Ältere Aufgabe',
              'status': status,
              'revision': 1,
            },
          ],
        });
        await f.mount(tester);
        await click(tester, 'Meine Themen');
        expect(find.text('Runde: ${statusLabel(status)}'), findsOneWidget);
        await click(tester, 'Gespeicherte Runden zu diesem Auftrag');
        expect(
          find.text('${statusLabel(status)} · Frühere Auftragsfassung'),
          findsOneWidget,
        );
        await click(tester, 'Gespeicherte Runde ansehen');
        expect(find.text('Runde saved'), findsOneWidget);
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'P43 stored short-plan positions use visible text instead of icon-only status',
    (tester) async {
      final f = _Fixture();
      f.plan['instructional_plans'] = [
        {
          'unit_id': 'unit',
          'subject': 'Mathematik',
          'topic': 'Brüche',
          'cursor': 1,
          'steps': [
            for (final kind in ['check_understanding', 'explain', 'practice'])
              {
                'kind': kind,
                'reason': r'Vergleiche $\frac{1}{3}$ und $\frac{2}{6}$.',
                'expected_result': 'Eine neue Antwort beobachten.',
              },
          ],
        },
      ];
      await f.mount(tester);
      expect(find.text('Bereits durchlaufen'), findsOneWidget);
      expect(find.text('Aktueller Schritt'), findsOneWidget);
      expect(find.text('Danach vorgesehen'), findsOneWidget);
      expect(find.text('2. Gezielt verstehen'), findsOneWidget);
      expect(find.byType(LearningContent), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final when in ['past', 'today', 'future']) {
    testWidgets(
      'P44 P45 P46 exam $when timing follows the server day without a failed generation request',
      (tester) async {
        final f = _Fixture();
        f.plan['topics'][0].addAll({
          'kind': 'exam',
          'due': when == 'past'
              ? '2026-10-20'
              : when == 'today'
              ? '2026-10-22'
              : '2026-10-28',
          if (when == 'future') 'scheduled_for': '2026-10-25',
        });
        await f.mount(tester);
        await click(tester, 'Meine Themen');
        expect(find.text('Klassenarbeit'), findsOneWidget);
        if (when != 'future') {
          expect(
            find.text(when == 'past' ? 'Termin liegt zurück' : 'Termin heute'),
            findsOneWidget,
          );
        } else {
          expect(find.textContaining('ab 25.10.2026 möglich'), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'KI-Runde vorbereiten'),
                )
                .onPressed,
            isNull,
          );
        }
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'P47 topic pagination names its destination and preserves the server page boundary',
    (tester) async {
      final f = _Fixture();
      await f.mount(tester, width: 320, scale: 2);
      await click(tester, 'Meine Themen');
      expect(find.text('Vorherige Themenseite'), findsOneWidget);
      expect(find.text('Nächste Themenseite'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Nächste Themenseite'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final kind in ['unit', 'material', 'assignment']) {
    testWidgets(
      'P48 P49 P50 weekly $kind entries have a useful saved-content route and explicit date/conflict context',
      (tester) async {
        final f = _Fixture();
        f.plan['plan'].addAll({
          'conflicts': [
            {'topic': 'Brüche', 'due': '2026-10-23'},
          ],
          'week': [
            {
              'date': '2026-10-22',
              'planned_minutes': 10,
              'items': [
                {
                  'kind': kind,
                  'id': 'saved',
                  'subject': 'Mathematik',
                  'topic': 'Wochenquelle',
                  'estimated_minutes': 10,
                },
              ],
            },
          ],
        });
        await f.mount(tester);
        await click(tester, 'Woche & Vorgaben');
        expect(find.text('Heute · Donnerstag · 22.10.2026'), findsOneWidget);
        expect(
          find.textContaining('Termin prüfen: Brüche bis 23.10.2026'),
          findsOneWidget,
        );
        await click(tester, 'Mathematik · Wochenquelle');
        if (kind == 'assignment') {
          expect(
            tester
                .widget<ChoiceChip>(
                  find.widgetWithText(ChoiceChip, 'Meine Themen'),
                )
                .selected,
            isTrue,
          );
        } else {
          expect(
            find.text('${kind == 'unit' ? 'Runde' : 'Quelle'} saved'),
            findsOneWidget,
          );
        }
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'P51 P52 P53 P54 historical reports stay distinct while loading and return to the latest with GET only',
    (tester) async {
      final pending = Completer<http.Response>();
      final f = _Fixture();
      f.insights['latest']['id'] = 'new';
      f.insights['latest']['report']['summary'] =
          'Neuester künstlicher Bericht';
      f.insights['history'] = [
        {'id': 'new', 'finished': 1792569011},
        {'id': 'old', 'finished': 1792569010},
      ];
      f.respond = (r) async =>
          r.url.queryParameters['review_id'] == 'old' ? pending.future : null;
      await f.mount(tester, path: '/insights/child-a');
      final picker = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(find.textContaining('Neueste ·'), findsWidgets);
      await tester.tap(find.textContaining('2. Auswertung ·').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Neuester künstlicher Bericht'), findsNothing);
      final old = clone(f.insights);
      old['latest']['id'] = 'old';
      old['latest']['report']['summary'] = 'Historischer künstlicher Bericht';
      old['latest_attempt'] = {
        'status': 'failed',
        'error': 'Künstlicher neuer Fehlversuch',
      };
      pending.complete(fixture.response(old));
      await tester.pumpAndSettle();
      expect(find.text('Historischer künstlicher Bericht'), findsOneWidget);
      expect(
        find.textContaining('Gespeicherte KI-Einschätzung ·'),
        findsOneWidget,
      );
      expect(
        find.text('Der letzte Auswertungsversuch wurde nicht abgeschlossen.'),
        findsOneWidget,
      );
      await click(tester, 'Neueste gespeicherte Auswertung ansehen');
      expect(find.text('Neuester künstlicher Bericht'), findsOneWidget);
      expect(
        f.requests.last.url.queryParameters.containsKey('review_id'),
        isFalse,
      );
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P55 P56 preview limits and the actual practice date remain explicit',
    (tester) async {
      final f = _Fixture();
      f.insights['topics'] = [
        for (var i = 0; i < 10; i++)
          {
            ...fixture.topic(),
            'ref': 'topic-$i',
            'topic': 'Künstliches Thema $i',
            'last_activity': 1792482600,
          },
      ];
      f.insights['latest']['observations']['topics'] = f.insights['topics'];
      f.insights['latest']['report']['findings'] = [
        for (var i = 0; i < 6; i++)
          {
            'topic_ref': 'topic-$i',
            'need': 'support',
            'interpretation': 'Belegte künstliche Hilfe.',
            'next_check': 'Neue Aufgabe.',
          },
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ParentInsightsPanel(
                f.state,
                childId: 'child-a',
                compact: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          '3 von 10 Themen in dieser Vorschau. Alle Belege stehen im Lernstand.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '3 von 6 KI-Schwerpunkten in dieser Vorschau. Der Lernplan zeigt die vollständige gespeicherte Auswertung.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Zuletzt geübt: ${reviewDate(1792482600)}'),
        findsNWidgets(3),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P57 a proposed step opens the matching existing topic evidence without generating work',
    (tester) async {
      final f = _Fixture();
      await f.mount(tester, path: '/insights/child-a');
      await click(tester, 'Belege zu diesem Schritt ansehen');
      expect(find.text('Belege Mathematik · Bruchaddition'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P58 P59 retrying a setting clears only the previous error and announces the pending action',
    (tester) async {
      var writes = 0;
      final pending = Completer<http.Response>();
      final f = _Fixture();
      f.respond = (r) async => r.method == 'PUT'
          ? ++writes == 1
                ? fixture.response({'detail': 'Künstlicher erster Fehler'}, 409)
                : pending.future
          : null;
      await f.mount(tester, path: '/insights/child-a');
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(
        true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Künstlicher erster Fehler'), findsOneWidget);
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(
        true,
      );
      await tester.pump();
      expect(find.text('Künstlicher erster Fehler'), findsNothing);
      expect(find.text('Einstellung speichern …'), findsOneWidget);
      pending.complete(fixture.response({'enabled': true}));
      await tester.pumpAndSettle();
      expect(writes, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('P60 a failed compass read offers an explicit GET-only retry', (
    tester,
  ) async {
    var reads = 0;
    final f = _Fixture();
    f.respond = (r) async => ++reads == 1
        ? fixture.response({'detail': 'Künstlicher Ladefehler'}, 503)
        : null;
    await f.mount(tester, path: '/insights/child-a');
    await click(tester, 'Lernkompass erneut laden');
    expect(reads, 2);
    expect(find.text('Künstlicher Ladefehler'), findsNothing);
    expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'P61 P62 P63 P65 P66 homework previews identify uncertain photos, use the content renderer and bound task details',
    (tester) async {
      final f = _Fixture();
      final photo = f.homework['photos'][0];
      photo.addAll({
        'title': 'Künstliches Arbeitsblatt A',
        'subject': '',
        'topic': '',
        'confirmed': false,
        'task_count': 5,
        'tasks': [
          for (var i = 0; i < 5; i++)
            {
              'title':
                  'Aufgabe $i: '
                  r'$\frac{1}{4}+\frac{1}{8}$',
              'marked': i == 0,
            },
        ],
      });
      await f.mount(tester, path: '/homework/child-a');
      expect(
        find.text('Hausaufgabenfoto · Fach und Thema noch prüfen'),
        findsOneWidget,
      );
      expect(find.text('Künstliches Arbeitsblatt A'), findsOneWidget);
      expect(find.text('Noch nicht abgehakt'), findsNWidgets(2));
      expect(find.byType(LearningContent), findsNWidgets(3));
      expect(find.text('2 weitere Aufgaben in den Details'), findsOneWidget);
      await click(tester, 'Foto & Begleitung ansehen');
      expect(find.text('Hausaufgabendetails photo'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P64 P67 partial homework marks and server order are explained without a completion claim',
    (tester) async {
      final f = _Fixture();
      f.homework['photos'][0]['task_count'] = 5;
      await f.mount(tester, path: '/homework/child-a');
      await click(tester, 'Mit Häkchen');
      expect(
        find.text(
          'Mindestens eine Aufgabe ist vom Kind abgehakt. Das Foto muss noch nicht vollständig bearbeitet sein.',
        ),
        findsOneWidget,
      );
      expect(find.text('1 von 5 abgehakt'), findsOneWidget);
      expect(find.text('Neueste Fotos zuerst'), findsOneWidget);
      expect(f.requests.last.url.queryParameters['state'], 'worked');
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P68 tapping the current homework filter preserves already loaded pages without another request',
    (tester) async {
      final f = _Fixture();
      f.respond = (r) async {
        if (!r.url.path.endsWith('/homework-review')) return null;
        final data = clone(f.homework);
        final more = r.url.queryParameters['cursor'] != null;
        data['photos'][0]['id'] = more ? 'second' : 'first';
        data['photos'][0]['title'] = more
            ? 'Zweites künstliches Foto'
            : 'Erstes künstliches Foto';
        data['next_cursor'] = more ? null : 'first';
        data['total'] = 2;
        return fixture.response(data);
      };
      await f.mount(tester, path: '/homework/child-a');
      await click(tester, 'Weitere Fotos laden');
      final count = f.requests.length;
      await click(tester, 'Alle Fotos');
      expect(f.requests.length, count);
      expect(find.text('Erstes künstliches Foto'), findsOneWidget);
      expect(find.text('Zweites künstliches Foto'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P69 changed mandatory sources remain visible as a separate planning need',
    (tester) async {
      final f = _Fixture();
      f.summary['assignments'] = [
        {...f.summary['assignments'][0], 'source_status': 'needs_review'},
      ];
      await f.mount(tester, path: '/overview');
      expect(find.text('Offene Pflichtaufträge: 0'), findsOneWidget);
      expect(find.text('1 Auftragsquelle prüfen'), findsOneWidget);
      await click(tester, 'Aufträge im Lernplan prüfen');
      expect(find.byType(ParentPlanScreen), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P70 P74 weekly attempts and actual finished topics remain separate from closed rounds',
    (tester) async {
      final f = _Fixture();
      f.summary['week_summary'] = {
        'completed_units': 0,
        'hints_used': 1,
        'answer_count': 5,
        'topics': ['Mathematik: Brüche', 'Biologie: Zellen'],
        'support': 'Künstliche gespeicherte Beobachtung',
      };
      await f.mount(tester, path: '/overview');
      expect(
        find.textContaining(
          '0 abgeschlossene Runden · 5 gespeicherte Antwortversuche',
        ),
        findsOneWidget,
      );
      expect(find.text('Mathematik: Brüche'), findsOneWidget);
      expect(find.text('Biologie: Zellen'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P71 repetition observations lead to existing topic evidence without starting a review',
    (tester) async {
      final f = _Fixture();
      f.summary['mastery'] = [
        {
          'subject': 'Physik',
          'topic': 'Kräfte',
          'next_review': '2026-10-23',
          'description': 'Künstlicher späterer Abruf',
        },
      ];
      await f.mount(tester, path: '/overview');
      await click(tester, 'Festigung & nächste Wiederholungen');
      await click(tester, 'Physik · Kräfte');
      expect(find.text('Belege Physik · Kräfte'), findsOneWidget);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P72 P73 the saved total is distinct from today and detail evidence has a direct route',
    (tester) async {
      final f = _Fixture();
      f.summary['material_count'] = 31;
      await f.mount(tester, path: '/overview');
      expect(find.text('Gespeicherte Seiten & Tagespakete'), findsOneWidget);
      expect(find.text('31 gespeicherte Seiten insgesamt'), findsOneWidget);
      expect(find.text('Heutige Heftseiten & Vorbereitung'), findsNothing);
      await click(tester, 'Gespeicherte Übungsbelege im Detail ansehen');
      expect(find.text('Belege alle · alle'), findsOneWidget);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P75 an assisted or repeated success is honestly named without rewriting the evidence',
    (tester) async {
      final data = {'practiced_tasks': 1, 'assisted_tasks': 1, 'attempts': 2};
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(body: PracticeEvidence(data)),
        ),
      );
      expect(find.text('1 mit Hilfe/erneut gelöst'), findsOneWidget);
      expect(find.text('2 Versuche · 0 Runden'), findsOneWidget);
      expect(data['assisted_tasks'], 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('P101 unresolved help is not falsely limited to today', (
    tester,
  ) async {
    final f = _Fixture();
    f.summary['day_summary']['help_requests'] = 1;
    await f.mount(tester, path: '/overview');
    expect(find.text('1 offener Hilfewunsch'), findsOneWidget);
    expect(find.text('1 Hilfewunsch heute'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
