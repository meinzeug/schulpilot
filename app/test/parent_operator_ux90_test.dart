import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/parent_operator_audit.dart';
import 'package:schulpilot/settings_screen.dart';

import 'parent_saved_tools_ux90_test.dart' as saved;
import 'parent_insights_test.dart' show response;
import 'parent_workflows_ux90_test.dart' show choose;
import 'parent_messages_ux88_test.dart' show tap;
import 'parent_hierarchy_test_tools.dart';

Future<void> reveal(WidgetTester t, Finder target) async {
  if (target.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      target,
      160,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
  }
  await t.ensureVisible(target);
  await t.pumpAndSettle();
}

Future<void> open(WidgetTester t, saved.Fixture f) async {
  f.state.user = {'id': 'operator', 'role': 'admin'};
  await f.mount(
    t,
    (c) => TextButton(
      onPressed: () => showAdminAuditExplorer(c, f.state),
      child: const Text('Öffnen'),
    ),
  );
  await tap(t, find.text('Öffnen'));
  await openParentDetails103(t, 'Protokoll suchen & eingrenzen');
}

void main() {
  testWidgets('PK048 actual audit continuation appends with stable snapshot', (
    t,
  ) async {
    final f = saved.Fixture();
    f.respond = (r) async {
      final v = saved.auditData(
        cursor: r.url.queryParameters.containsKey('cursor') ? null : 'stable',
      );
      if (r.url.queryParameters.containsKey('cursor')) {
        v['items'][0]['id'] = '3' * 32;
      }
      return response(v);
    };
    await open(t, f);
    await reveal(t, find.text('Weitere Ereignisse laden'));
    await tap(t, find.text('Weitere Ereignisse laden'));
    expect(f.requests.last.url.queryParameters['cursor'], 'stable');
    expect(f.requests.last.url.queryParameters['snapshot'], '1792569000');
    expect(find.text('2 von 2 passenden Ereignissen geladen'), findsOneWidget);
  });
  testWidgets(
    'PK049 full audit search is explicitly submitted and reset is GET only',
    (t) async {
      final f = saved.Fixture();
      f.respond = (r) async => response(saved.auditData());
      await open(t, f);
      final field = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Gesamtes Protokoll durchsuchen',
      );
      await t.enterText(field, ' target_% ');
      expect(f.requests, hasLength(1));
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      expect(f.requests.last.url.queryParameters['q'], 'target_%');
      await reveal(t, find.text('Serverseitige Protokollfilter zurücksetzen'));
      await tap(t, find.text('Serverseitige Protokollfilter zurücksetzen'));
      expect(f.requests.last.url.queryParameters.containsKey('q'), isFalse);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets('PK050 exact audit actor and action combine without mutation', (
    t,
  ) async {
    final f = saved.Fixture();
    f.respond = (r) async => response(saved.auditData());
    await open(t, f);
    await tap(t, find.text('Akteur, Aktion und UTC-Zeitraum eingrenzen'));
    await choose(t, 'Exakter Aktionscode', 'synthetic.write');
    await reveal(t, find.text('Exakte Akteurkennung'));
    await choose(t, 'Exakte Akteurkennung', '2' * 32);
    expect(f.requests.last.url.queryParameters['action'], 'synthetic.write');
    expect(f.requests.last.url.queryParameters['actor'], '2' * 32);
    expect(f.requests.every((r) => r.method == 'GET'), isTrue);
  });
  testWidgets('PK051 UTC date interval validates before audit request', (
    t,
  ) async {
    final f = saved.Fixture();
    f.respond = (r) async => response(saved.auditData());
    await open(t, f);
    await tap(t, find.text('Akteur, Aktion und UTC-Zeitraum eingrenzen'));
    final from = find.widgetWithText(TextFormField, 'Zeitraum von'),
        to = find.widgetWithText(TextFormField, 'Zeitraum bis');
    await reveal(t, from);
    await t.enterText(from, '02.01.2021');
    await reveal(t, to);
    await t.enterText(to, '01.01.2021');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(f.requests, hasLength(1));
    expect(
      find.text('Das Ende muss am oder nach dem Beginn liegen.'),
      findsOneWidget,
    );
    await t.enterText(to, '03.01.2021');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(f.requests.last.url.queryParameters['start'], '2021-01-02');
    expect(f.requests.last.url.queryParameters['end'], '2021-01-03');
  });
  testWidgets('PK053 selected audit action count leads to exact action GET', (
    t,
  ) async {
    final f = saved.Fixture();
    f.respond = (r) async => response(saved.auditData());
    await open(t, f);
    await reveal(t, find.text('Aktionen in diesem Zeitbereich'));
    await tap(t, find.text('Aktionen in diesem Zeitbereich'));
    await tap(t, find.widgetWithText(ListTile, '2 Ereignisse'));
    expect(f.requests.last.url.queryParameters['action'], 'synthetic.read');
    expect(f.requests.every((r) => r.method == 'GET'), isTrue);
  });
  testWidgets(
    'PK048 pending audit metadata disappears on same-id fresh login',
    (t) async {
      final f = saved.Fixture();
      final pending = Completer<http.Response>();
      f.respond = (r) => pending.future;
      f.state.user = {'id': 'operator', 'role': 'admin'};
      await f.mount(
        t,
        (c) => TextButton(
          onPressed: () => showAdminAuditExplorer(c, f.state),
          child: const Text('Öffnen'),
        ),
      );
      await t.tap(find.text('Öffnen'));
      await t.pump();
      f.replaceAccount();
      await t.pump();
      pending.complete(response(saved.auditData()));
      await t.pumpAndSettle();
      expect(find.text('Gesamtes Betriebsprotokoll'), findsNothing);
      expect(find.text('synthetic.read'), findsNothing);
    },
  );
  testWidgets('PK048 explorer opens from existing authorized audit list', (
    t,
  ) async {
    final f = saved.Fixture();
    f.state.user = {'id': 'operator', 'role': 'admin'};
    f.respond = (r) async => response(saved.auditData());
    await f.mount(
      t,
      (_) => SingleChildScrollView(child: AdminAuditList([], state: f.state)),
    );
    await toggleParentDetails104(t, 'Protokoll durchsuchen & filtern');
    await tap(t, find.text('Gesamtes Protokoll gezielt durchsuchen'));
    expect(find.text('Gesamtes Betriebsprotokoll'), findsOneWidget);
    expect(f.requests.single.url.path, '/api/admin/audit-events');
    expect(f.requests.single.method, 'GET');
  });
}
