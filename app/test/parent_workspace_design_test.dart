import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/coaching_panel.dart';
import 'package:schulpilot/parent_overview.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/ui.dart';

import 'parent_learning_overview_test.dart' as overview_fixture;
import 'parent_hierarchy_test_tools.dart';

http.Response _response(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  for (final configuration in [
    for (final brightness in [Brightness.light, Brightness.dark]) ...[
      (320.0, 2.0, brightness),
      (390.0, 1.0, brightness),
      (1440.0, 1.0, brightness),
    ],
  ]) {
    testWidgets(
      'Parent management has clear isolated sections at ${configuration.$1} px and ${configuration.$2} scale in ${configuration.$3.name}',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        await tester.binding.setSurfaceSize(Size(configuration.$1, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final requests = <http.Request>[];
        final state =
            AppState(
                api: Api(
                  base: 'https://example.invalid/api',
                  client: MockClient((request) async {
                    requests.add(request);
                    expect(request.method, 'GET');
                    final path = request.url.path;
                    if (path.endsWith('/sessions')) {
                      return _response([
                        {
                          'id': 'device',
                          'device': 'Ein sehr lang benanntes künstliches Familiengerät',
                          'current': true,
                        },
                      ]);
                    }
                    if (path.endsWith('/inbox')) {
                      return _response({'items': [], 'unread': 0});
                    }
                    if (path.endsWith('/devices')) return _response([]);
                    if (path.endsWith('/members')) {
                      return _response([
                        {
                          'id': 'owner',
                          'display_name': 'Künstlicher Familieninhaber',
                          'permission': 'owner',
                        },
                        {
                          'id': 'other-parent',
                          'display_name': 'Weiterer berechtigter Elternzugang',
                          'permission': 'manage',
                        },
                      ]);
                    }
                    if (path.endsWith('/invitations')) {
                      return _response([
                        {
                          'id': 'invitation',
                          'email': 'synthetic-parent@example.invalid',
                          'permission': 'view',
                        },
                      ]);
                    }
                    if (path.endsWith('/families/family')) {
                      return _response({
                        'children': [
                          {
                            'id': 'child',
                            'display_name': 'Künstliches Testkind',
                            'username': 'synthetic-child',
                          },
                        ],
                      });
                    }
                    if (path.endsWith('/usage')) {
                      return _response({
                        'calls_remaining': 90,
                        'calls_limit': 100,
                        'plan': 'Künstlicher Testtarif',
                        'period': '2026-10',
                        'budget_remaining_micros_usd': 1000000,
                        'unknown_cost_calls': 0,
                        'cost_notice':
                            'Künstliche Nutzung ohne Anbieteraufruf.',
                      });
                    }
                    return _response({'available': false});
                  }),
                ),
              )
              ..user = {
                'id': 'owner',
                'role': 'parent',
                'display_name': 'Künstlicher Elternzugang',
                'username': 'synthetic-parent',
                'families': [
                  {
                    'id': 'family',
                    'name': 'Kunstfamilie',
                    'permission': 'owner',
                  },
                ],
              }
              ..familyId = 'family';
        final router = GoRouter(
          initialLocation: '/settings',
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => SettingsScreen(state),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp.router(
            theme: appTheme(brightness: configuration.$3),
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(configuration.$2)),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Zugänge & Einstellungen'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Konto & Geräte'),
          findsOneWidget,
        );
        expect(find.text('Hier abmelden'), findsOneWidget);
        expect(find.text('Elternzugänge'), findsNothing);
        expect(find.text('Deine Familiendaten'), findsNothing);
        expect(
          requests.any((r) => r.url.path.endsWith('/members')),
          isFalse,
          reason: 'Account opening does not fetch hidden family management.',
        );

        Future<void> choose(String title) async {
          final button = find.widgetWithText(OutlinedButton, title);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          await tester.tap(button);
          await tester.pumpAndSettle();
        }

        await choose('Familie');
        expect(find.text('Dein Zugang'), findsNothing);
        expect(find.text('Elternzugänge'), findsOneWidget);
        expect(find.text('Kinderzugänge verwalten'), findsOneWidget);
        expect(find.text('Rechte entziehen'), findsOneWidget);
        expect(find.text('Einladung widerrufen'), findsOneWidget);
        expect(find.text('Kindergerät abmelden'), findsOneWidget);
        expect(find.text('Deine Familiendaten'), findsNothing);
        expect(tester.takeException(), isNull);

        await choose('Daten & Umfang');
        expect(find.text('Elternzugänge'), findsNothing);
        expect(find.text('Enthaltener Lernumfang'), findsOneWidget);
        expect(find.text('Familienexport herunterladen'), findsOneWidget);
        expect(find.text('Eigenes Elternkonto löschen'), findsOneWidget);
        expect(requests.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        state.inbox.dispose();
        state.dispose();
      },
    );
  }

  testWidgets(
    'Parent projection handles missing optional metadata without invalid round links',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ParentOverview(
                data: {
                  'child': {'id': 'artificial-child'},
                  'plan': null,
                  'learning_guidance': {
                    'subject': 'Mathematik',
                    'unit_id': null,
                  },
                  'learning_paths': [],
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openParentDetails103(tester, 'Zeit & Mindestziele');
      expect(find.text('Noch keine Zeitdaten verfügbar.'), findsOneWidget);
      expect(find.text('Tagesziel offen'), findsNothing);
      expect(find.text('Gespeicherte Runde ansehen'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Deduplicated saved learning paths do not also show an empty-state notice',
    (tester) async {
      final data = overview_fixture.parentOverview();
      data['learning_paths'] = [
        for (var i = 0; i < 2; i++)
          {
            'subject': 'Mathematik',
            'topic': 'Brüche',
            'latest_unit_id': 'artificial-unit',
            'successful_check_days': 1,
          },
      ];
      data['mastery'] = [];
      final requests = <http.Request>[];
      await overview_fixture.mountParent(tester, data, requests);
      await overview_fixture.tapText(
        tester,
        'Festigung & nächste Wiederholungen',
      );
      expect(find.byType(LearningProgressPanel), findsOneWidget);
      expect(find.text('Lernbegleitung und Antworten ansehen'), findsOneWidget);
      expect(
        find.text(
          'Nach den ersten Übungen erscheinen hier Beobachtungen zur späteren Festigung.',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Family cards keep missing summary and time data explicitly unavailable',
    (tester) async {
      final data = overview_fixture.parentOverview();
      data['day_summary'] = null;
      data['plan'] = null;
      data['child']['display_name'] = null;
      final requests = <http.Request>[];
      await overview_fixture.mountParent(
        tester,
        data,
        requests,
        familyHome: true,
        width: 320,
        textScale: 2,
      );
      expect(find.text('Kinderzugang'), findsOneWidget);
      expect(find.text('Noch keine Zeitdaten verfügbar.'), findsOneWidget);
      expect(find.text('Tagesziel offen'), findsNothing);
      expect(find.text('0 Antworten heute'), findsNothing);
      expect(find.text('0 Runden heute'), findsNothing);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
