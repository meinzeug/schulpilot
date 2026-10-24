import 'dart:async';
import 'dart:convert';

import 'parent_hierarchy_test_tools.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/ui.dart';

Json row(String id, {bool synthetic = false, int budget = 1000000}) => {
  'id': id,
  'plan': 'Synthetic plan',
  'synthetic': synthetic,
  'child_limit': 2,
  'call_limit': 100,
  'budget_micros': budget,
};
http.Response page(
  List<Json> rows, {
  int current = 1,
  int pages = 1,
  int? total,
}) => http.Response(
  jsonEncode({
    'items': rows,
    'pagination': {
      'page': current,
      'pages': pages,
      'page_size': 50,
      'total': total ?? rows.length,
    },
    'filters': {},
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
AppState account(Future<http.Response> Function(http.Request) handler) =>
    AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient(handler),
      ),
    )..user = {'id': 'synthetic-admin', 'role': 'admin'};
Finder input() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'Familie suchen',
);
Future<void> press(WidgetTester t, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> mount(
  WidgetTester t,
  AppState s, {
  double scale = 1,
  bool openFilters = true,
}) async {
  t.view.physicalSize = const Size(390, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AdminFamilyList(s, revision: 0, onEdit: (_) async {}),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  // Existing filter scenarios explicitly open the optional102 tools.
  if (openFilters) await toggleParentDetails104(t, 'Suche & Haushaltsfilter');
}

Future<void> clean(WidgetTester t, AppState s) async {
  await t.pumpWidget(const SizedBox());
  s.inbox.dispose();
  s.dispose();
}

void main() {
  testWidgets(
    'families use server pagination and never imply the loaded slice is the complete total',
    (t) async {
      final requests = <http.Request>[];
      final s = account((r) async {
        requests.add(r);
        return r.url.queryParameters['page'] == '2'
            ? page([row('last-family')], current: 2, pages: 2, total: 51)
            : page(
                [row('first-family'), row('second-family')],
                pages: 2,
                total: 51,
              );
      });
      await mount(t, s);
      expect(requests.single.url.queryParameters['paginated'], 'true');
      expect(requests.single.url.queryParameters['page_size'], '50');
      expect(find.text('2 von 51 Familien · Seite 1 von 2'), findsOneWidget);
      await press(t, find.text('Nächste Seite'));
      expect(find.text('last-family'), findsOneWidget);
      expect(find.text('first-family'), findsNothing);
      expect(find.text('1 von 51 Familien · Seite 2 von 2'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Nächste Seite'),
            )
            .onPressed,
        isNull,
      );
      expect(
        requests.every(
          (r) => r.method == 'GET' && r.url.path == '/api/admin/families',
        ),
        isTrue,
      );
      await clean(t, s);
    },
  );
  testWidgets(
    'search is explicit, literal and sent to the server instead of filtering the first200',
    (t) async {
      final requests = <http.Request>[];
      final s = account((r) async {
        requests.add(r);
        return r.url.queryParameters.containsKey('search')
            ? page([row('remote-result')])
            : page([row('first-page')]);
      });
      await mount(t, s);
      await t.enterText(input(), 'id%_literal');
      await t.pumpAndSettle();
      expect(requests, hasLength(1));
      await press(t, find.widgetWithText(FilledButton, 'Suchen'));
      expect(requests.last.url.queryParameters['search'], 'id%_literal');
      expect(requests.last.url.queryParameters['page'], '1');
      expect(find.text('remote-result'), findsOneWidget);
      expect(find.text('first-page'), findsNothing);
      await press(t, find.byTooltip('Familiensuche leeren'));
      expect(requests.last.url.queryParameters.containsKey('search'), isFalse);
      expect(t.widget<TextField>(input()).controller!.text, isEmpty);
      await clean(t, s);
    },
  );
  testWidgets(
    'failed page has no old edit actions and can be explicitly reloaded with GET only',
    (t) async {
      var second = 0;
      final requests = <http.Request>[];
      final s = account((r) async {
        requests.add(r);
        if (r.url.queryParameters['page'] == '2' && second++ == 0) {
          return http.Response(
            '{"detail":"Künstlicher Listenfehler"}',
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return r.url.queryParameters['page'] == '2'
            ? page([row('recovered')], current: 2, pages: 2, total: 51)
            : page([row('old-row')], pages: 2, total: 51);
      });
      await mount(t, s);
      await press(t, find.text('Nächste Seite'));
      expect(find.text('old-row'), findsNothing);
      expect(find.text('Tarif bearbeiten'), findsNothing);
      expect(find.text('Künstlicher Listenfehler'), findsOneWidget);
      await press(t, find.text('Familien erneut laden'));
      expect(find.text('recovered'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await clean(t, s);
    },
  );
  testWidgets(
    'synthetic filter preserves a visible distinction and exact small budget',
    (t) async {
      final requests = <http.Request>[];
      final s = account((r) async {
        requests.add(r);
        return page([row('synthetic-row', synthetic: true, budget: 1)]);
      });
      await mount(t, s);
      await press(t, find.widgetWithText(ChoiceChip, 'Demo / Test'));
      expect(requests.last.url.queryParameters['synthetic'], 'true');
      expect(find.text('Kostenlimit: 0.000001 USD / Monat'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Tag),
          matching: find.text('Demo / Test'),
        ),
        findsOneWidget,
      );
      final label = find.widgetWithText(ActionPanel, 'Tarif bearbeiten');
      expect(label, findsOneWidget);
      final semantics = t.ensureSemantics();
      final description = t.getSemantics(label).getSemanticsData();
      expect(description.label, contains('synthetic-row'));
      expect(description.label, contains('Tarif bearbeiten'));
      semantics.dispose();
      await clean(t, s);
    },
  );
  testWidgets(
    'late family response is hidden after a new session with the same account id',
    (t) async {
      final pending = Completer<http.Response>();
      final s = account((_) => pending.future);
      await mount(t, s);
      s.user = {'id': 'synthetic-admin', 'role': 'admin'};
      s.refreshState();
      await t.pump();
      pending.complete(page([row('PRIVATE OLD METADATA')]));
      await t.pumpAndSettle();
      expect(find.text('PRIVATE OLD METADATA'), findsNothing);
      expect(find.text('Tarif bearbeiten'), findsNothing);
      expect(t.takeException(), isNull);
      await clean(t, s);
    },
  );
  testWidgets(
    'clamped server page replaces the requested page after a changing total',
    (t) async {
      final s = account(
        (r) async => r.url.queryParameters['page'] == '2'
            ? page([row('remaining')], current: 1, pages: 1, total: 1)
            : page([row('before')], pages: 2, total: 51),
      );
      await mount(t, s);
      await press(t, find.text('Nächste Seite'));
      expect(find.text('1 von 1 Familien · Seite 1 von 1'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Vorherige Seite'),
            )
            .onPressed,
        isNull,
      );
      await clean(t, s);
    },
  );
  testWidgets('family filters and operational cards reflow with large text', (
    t,
  ) async {
    final s = account(
      (_) async => page([row('long-synthetic-family-identifier')]),
    );
    await mount(t, s, scale: 2);
    await t.ensureVisible(find.text('Tarif bearbeiten'));
    expect(t.takeException(), isNull);
    await clean(t, s);
  });
  testWidgets(
    'clearing a query preserves the deliberately selected household type',
    (t) async {
      final requests = <http.Request>[];
      final s = account((r) async {
        requests.add(r);
        return page([row('demo', synthetic: true)]);
      });
      await mount(t, s);
      await press(t, find.widgetWithText(ChoiceChip, 'Demo / Test'));
      await t.enterText(input(), 'demo');
      await press(t, find.widgetWithText(FilledButton, 'Suchen'));
      await press(t, find.byTooltip('Familiensuche leeren'));
      expect(requests.last.url.queryParameters['synthetic'], 'true');
      expect(requests.last.url.queryParameters.containsKey('search'), isFalse);
      await clean(t, s);
    },
  );
}
