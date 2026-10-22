import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/admin_workspace_ui.dart';
import 'package:schulpilot/ai_cost_panel.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/ui.dart';

import 'admin_workspace_test.dart' as workspace;
import 'codex_provider_form_test.dart' as catalog;

http.Response reply(Object value, [int code = 200]) => http.Response(
  jsonEncode(value),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
AppState admin(Future<http.Response> Function(http.Request) handler) =>
    AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient(handler),
      ),
    )..user = {'id': 'synthetic-operator', 'role': 'admin'};
Future<void> mount(
  WidgetTester tester,
  Widget body, {
  double width = 390,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: body),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'missing operation metrics are unknown, measured zero stays zero',
    (tester) async {
      await mount(tester, const AdminOperationCards({}));
      expect(find.text('Betriebsstatus unvollständig'), findsOneWidget);
      expect(find.text('Unbekannt'), findsNWidgets(4));
      expect(
        find.textContaining('Unbekannte Werte sind keine gemessene Null'),
        findsOneWidget,
      );
      expect(find.text('0'), findsNothing);
      await mount(
        tester,
        const AdminOperationCards({
          'jobs': {'queued': 0, 'running': 0},
          'stalled_queued': 0,
          'stalled_running': 0,
          'push_failures_24h': 0,
          'pending_erasure_journal': 0,
          'worker_age_seconds': 0,
        }),
      );
      expect(find.text('Betriebsmeldungen'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(4));
      expect(find.text('Worker · letztes Signal vor 0 s'), findsOneWidget);
    },
  );
  testWidgets(
    'operations show exact heartbeat age and distinct stalled queues with direct remedies',
    (tester) async {
      var push = 0, protocol = 0;
      await mount(
        tester,
        AdminOperationCards(
          {
            'jobs': {'queued': 2, 'running': 3},
            'stalled_queued': 1,
            'stalled_running': 2,
            'push_failures_24h': 4,
            'pending_erasure_journal': 1,
            'worker_age_seconds': 7261,
          },
          onOpenPush: () => push++,
          onOpenProtocol: () => protocol++,
        ),
      );
      expect(find.text('Davon wartend: 1 · laufend: 2'), findsOneWidget);
      expect(
        find.text('Worker · letztes Signal vor 2 h 1 min (7261 s)'),
        findsOneWidget,
      );
      await tap(tester, find.text('Push-Versand prüfen'));
      expect(push, 1);
      await tap(tester, find.text('Protokoll ansehen'));
      expect(protocol, 1);
      await tap(tester, find.text('Offene Löschprotokolle prüfen'));
      expect(
        find.textContaining('keine automatische Rücksicherung'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'operation values reflow at 320 and large text with missing metrics',
    (tester) async {
      await mount(tester, const AdminOperationCards({}), width: 320, scale: 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'operations failed refresh preserves last successful timestamp without implying fresh data',
    (tester) async {
      var operationReads = 0;
      final state = admin((request) async {
        if (request.url.path.endsWith('/operations')) {
          return ++operationReads == 1
              ? reply({
                  'jobs': {'queued': 0, 'running': 0},
                  'stalled_queued': 0,
                  'stalled_running': 0,
                  'pending_erasure_journal': 0,
                  'push_failures_24h': 0,
                  'worker_age_seconds': 0,
                })
              : reply({'detail': 'Künstlicher Abruffehler'}, 503);
        }
        return reply(
          request.url.path.endsWith('/families')
              ? {
                  'items': [],
                  'pagination': {
                    'page': 1,
                    'pages': 1,
                    'total': 0,
                    'page_size': 50,
                  },
                }
              : request.url.path.endsWith('/audit')
              ? []
              : workspace.provider(),
        );
      });
      final router = GoRouter(
        initialLocation: '/admin',
        routes: [
          GoRoute(path: '/admin', builder: (_, _) => AdminScreen(state)),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      final stamp = tester
          .widget<Text>(
            find.textContaining('Betriebsdaten zuletzt erfolgreich geladen:'),
          )
          .data;
      await tap(tester, find.text('Aktualisieren'));
      expect(find.text('Künstlicher Abruffehler'), findsOneWidget);
      expect(find.text(stamp!), findsOneWidget);
      expect(operationReads, 2);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'audit displays bounded scope, known labels, actors and original unknown codes',
    (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await mount(
        tester,
        AdminAuditList([
          {
            'action': 'admin.emergency_stop',
            'actor': 'synthetic-op-a',
            'target': 'global',
            'created': now,
          },
          {
            'action': 'future.action',
            'actor': 'synthetic-op-b',
            'target': 'target-b',
            'created': now - 10 * 86400,
          },
        ]),
      );
      expect(find.textContaining('höchstens den 200'), findsOneWidget);
      expect(find.text('KI-Notfallstopp aktiviert'), findsOneWidget);
      expect(find.text('Aktion: future.action'), findsOneWidget);
      expect(find.text('Akteur: synthetic-op-b'), findsOneWidget);
      final actor = find.byType(DropdownButtonFormField<String>).first;
      await tap(tester, actor);
      await tester.tap(find.text('synthetic-op-b').last);
      await tester.pumpAndSettle();
      expect(find.text('1 von 2 geladenen Einträgen'), findsOneWidget);
      expect(find.text('KI-Notfallstopp aktiviert'), findsNothing);
      await tap(tester, find.byType(DropdownButtonFormField<String>).last);
      await tester.tap(find.text('Heute (Gerätezeit)').last);
      await tester.pumpAndSettle();
      expect(find.text('Keine passenden Einträge.'), findsOneWidget);
    },
  );
  testWidgets(
    'audit local search includes readable action and actor without requests',
    (tester) async {
      await mount(
        tester,
        const AdminAuditList([
          {
            'action': 'admin.provider_update',
            'actor': 'synthetic-op',
            'target': 'disabled',
          },
          {'action': 'future.action', 'actor': 'other-op', 'target': 'target'},
        ]),
      );
      await tester.enterText(find.byType(TextField), 'gespeichert');
      await tester.pump();
      expect(find.text('1 von 2 geladenen Einträgen'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'other-op');
      await tester.pump();
      expect(find.text('Aktion: future.action'), findsOneWidget);
    },
  );
  testWidgets(
    'admin headings and tab group expose meaningful semantics and status labels',
    (tester) async {
      final handle = tester.ensureSemantics();

      await mount(
        tester,
        Column(
          children: [
            const AdminWorkspaceHeader(
              title: 'Betriebstest',
              subtitle: 'Metadaten',
              currentPath: '/admin',
            ),
            const AdminSectionHeading(
              title: 'Abschnitttest',
              subtitle: 'Details',
              icon: Icons.info,
            ),
            AdminContextTabs(
              items: const [
                (Icons.home, 'Übersicht'),
                (Icons.tune, 'Konfiguration'),
              ],
              selected: 1,
              onSelected: (_) {},
            ),
            const AdminStatusLine(label: 'Bereit', value: 'Ja', ready: true),
            const AdminStatusLine(label: 'Offen', value: 'Nein', ready: false),
            const AdminStatusLine(label: 'Status', value: 'Unbekannt'),
          ],
        ),
      );
      final semantics = tester.widgetList<Semantics>(find.byType(Semantics));
      expect(
        semantics.where((s) => s.properties.header == true).length,
        greaterThanOrEqualTo(2),
      );
      expect(
        find.bySemanticsLabel('Betriebsbereiche; aktuell Konfiguration'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Prüfzustand erfüllt')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Prüfzustand offen')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Kein Prüfzustand gemeldet')),
        findsOneWidget,
      );
      handle.dispose();
    },
  );
  testWidgets(
    'catalog local search preserves selection and shows full IDs plus source',
    (tester) async {
      var reads = 0;
      await catalog.mount(
        tester,
        handler: (_) async {
          reads++;
          return reply(catalog.catalog());
        },
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('isolierte Codex CLI 0.162.1'),
        findsOneWidget,
      );
      expect(
        find.text('Gewähltes Lernmodell: Alpha · fixture-alpha'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Geladenen Modellkatalog durchsuchen'),
        'fixture-beta',
      );
      await tester.pump();
      final picker = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: catalog.pickerDropdown('lesson'),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(picker.items!.map((e) => e.value), [
        'fixture-alpha',
        'fixture-beta',
      ]);
      expect(reads, 1);
      expect(catalog.selected(tester, 'lesson'), 'fixture-alpha');
      await tap(tester, find.byTooltip('Modellsuche leeren'));
      expect(reads, 1);
      expect(find.textContaining('Modelle ohne Texteingang'), findsOneWidget);
    },
  );
  testWidgets(
    'failed catalog refresh explicitly labels retained metadata and choice',
    (tester) async {
      var reads = 0;
      await catalog.mount(
        tester,
        handler: (_) async => ++reads == 1
            ? reply(catalog.catalog())
            : reply({'detail': 'Künstlicher Katalogfehler'}, 503),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Modelle neu laden'));
      expect(find.textContaining('zuletzt geladene Katalog'), findsOneWidget);
      expect(catalog.selected(tester, 'lesson'), 'fixture-alpha');
      expect(reads, 2);
    },
  );
  testWidgets(
    'reasoning adjustment is a live status and disabled model reason is shown',
    (tester) async {
      await catalog.mount(
        tester,
        handler: (_) async => reply(
          catalog.catalog(
            models: [
              ...catalog.catalog()['models'],
              catalog.catalogModel(
                'image-only',
                'Nur Bild',
                ['low'],
                'low',
                inputs: ['image'],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await catalog.select(tester, 'lesson', 'Beta (fixture-beta)');
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: find.textContaining('Denkstufe auf high angepasst'),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .liveRegion,
        true,
      );
      await tap(tester, catalog.pickerDropdown('lesson'));
      expect(find.textContaining('kein Texteingang'), findsWidgets);
    },
  );
  testWidgets(
    'cost anomaly filtering, latency explanation and empty cost centres are local',
    (tester) async {
      var reads = 0;
      final state = admin((_) async {
        reads++;
        return reply({
          'models': {
            'healthy': {
              'calls': 1,
              'billed_micros_usd': 10,
              'unknown_calls': 0,
              'unusable_calls': 0,
            },
            'open': {
              'calls': 2,
              'billed_micros_usd': 20,
              'unknown_calls': 1,
              'unusable_calls': 0,
            },
          },
          'cost_centres': [],
        });
      });
      await mount(tester, AiCostPanel(state));
      await tap(tester, find.text('Offene Kosten / unbrauchbar'));
      expect(find.text('healthy'), findsNothing);
      expect(find.text('open'), findsOneWidget);
      await tap(tester, find.text('Was bedeuten P50 und P95?'));
      expect(find.textContaining('Die Hälfte'), findsOneWidget);
      await tap(tester, find.text('Kostenstellen'));
      expect(
        find.text('Noch keine zugeordneten Kostenstellen.'),
        findsOneWidget,
      );
      expect(reads, 1);
    },
  );
  testWidgets(
    'routing save adopts canonical server policy and real reasoning metadata',
    (tester) async {
      final state = admin(
        (req) async => reply({
          'revision': req.method == 'PUT' ? 2 : 1,
          'effective_reasoning_effort': 'high',
          'policy': {
            'enabled': false,
            'routes': {
              'luna': {'model': 'synthetic-model', 'upstreams': []},
            },
            if (req.method == 'PUT') 'canonical': true,
          },
        }),
      );
      await mount(tester, AiRoutingPanel(state));
      expect(
        find.textContaining('Kompakte Aufgaben und Hilfen'),
        findsOneWidget,
      );
      expect(find.textContaining('Denkstufe: high'), findsOneWidget);
      await tap(tester, find.text('Routingregeln bearbeiten'));
      await tester.enterText(find.byType(TextField), '{}');
      await tester.pump();
      expect(
        find.textContaining('Ungespeicherter Routingentwurf'),
        findsOneWidget,
      );
      await tap(
        tester,
        find.text('Regeln speichern und zur Prüfung vormerken'),
      );
      expect(
        find.text('Gespeicherte Routingregeln · Revision 2'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        contains('"canonical": true'),
      );
    },
  );
}
