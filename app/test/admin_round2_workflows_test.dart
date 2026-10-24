import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/ai_cost_panel.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/settings_screen.dart';

import 'parent_hierarchy_test_tools.dart';

import 'admin_operations_catalog_ux_test.dart' as ops;

Finder field(String label) => find.widgetWithText(TextFormField, label);
TextField input(WidgetTester t, String label) => t.widget<TextField>(
  find.descendant(of: field(label), matching: find.byType(TextField)),
);
Json event(String action, {String? target, int offset = 0}) => {
  'action': action,
  'target': target ?? 'fixture-target',
  'actor': 'synthetic-admin',
  'created': 1792600000 + offset,
};
Json jobs() => {
  'jobs': {'queued': 2, 'running': 1},
  'stalled_queued': 1,
  'stalled_running': 0,
  'push_failures_24h': 3,
  'pending_erasure_journal': 0,
  'worker_age_seconds': 17,
};

void main() {
  testWidgets(
    'AA021 credit receipt shows an exact draft total before any POST',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({});
      });
      await ops.mount(t, CreditReceiptForm(s, onSaved: () {}));
      await ops.tap(t, find.text('Vorhandenen Guthabenbeleg erfassen'));
      await t.enterText(field('Erworbenes Guthaben in USD'), '10,25');
      await t.enterText(field('Tatsächliche Kaufgebühr in USD'), '0,5');
      await t.pump();
      expect(
        find.text(
          'Belegentwurf: 10.250000 USD Guthaben + 0.500000 USD Kaufgebühr = 10.750000 USD Gesamtzahlung.',
        ),
        findsOneWidget,
      );
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA022 credit receipt Next and Done do not record a purchase or a receipt',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({});
      });
      await ops.mount(t, CreditReceiptForm(s, onSaved: () {}));
      await ops.tap(t, find.text('Vorhandenen Guthabenbeleg erfassen'));
      await t.showKeyboard(field('Eindeutige Belegkennung'));
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump();
      expect(
        input(t, 'Erworbenes Guthaben in USD').focusNode!.hasFocus,
        isTrue,
      );
      await t.showKeyboard(field('Tatsächliche Kaufgebühr in USD'));
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(
        input(t, 'Tatsächliche Kaufgebühr in USD').focusNode!.hasFocus,
        isFalse,
      );
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA023 a confirmed receipt clears the confirmed fields without retaining a ready duplicate',
    (t) async {
      final calls = <http.Request>[];
      var saved = 0;
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({});
      });
      await ops.mount(t, CreditReceiptForm(s, onSaved: () => saved++));
      await ops.tap(t, find.text('Vorhandenen Guthabenbeleg erfassen'));
      await t.enterText(field('Eindeutige Belegkennung'), 'synthetic-receipt');
      await t.enterText(field('Erworbenes Guthaben in USD'), '10');
      await t.enterText(field('Tatsächliche Kaufgebühr in USD'), '0');
      await ops.tap(t, find.text('Vorhandenen Beleg speichern'));
      expect(saved, 1);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'POST');
      expect(
        t
            .widgetList<TextFormField>(find.byType(TextFormField))
            .every((w) => w.controller!.text.isEmpty),
        isTrue,
      );
      await ops.tap(t, find.text('Vorhandenen Beleg speichern'));
      expect(calls, hasLength(1));
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA024 invalid credit receipt reveals and focuses the first actual error',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({});
      });
      await ops.mount(
        t,
        CreditReceiptForm(s, onSaved: () {}),
        width: 320,
        scale: 2,
      );
      await ops.tap(t, find.text('Vorhandenen Guthabenbeleg erfassen'));
      await ops.tap(t, find.text('Vorhandenen Beleg speichern'));
      expect(input(t, 'Eindeutige Belegkennung').focusNode!.hasFocus, isTrue);
      expect(
        find.text('8–64 Buchstaben, Zahlen, - oder _ verwenden.'),
        findsOneWidget,
      );
      expect(calls, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA025 queued and running cards reveal only their loaded status and explicit protocol route',
    (t) async {
      final calls = <http.Request>[];
      var protocol = 0;
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({});
      });
      await ops.mount(
        t,
        AdminOperationCards(jobs(), state: s, onOpenProtocol: () => protocol++),
      );
      await ops.tap(t, find.text('Wartende Aufträge'));
      expect(find.text('Wartende und laufende Aufträge'), findsOneWidget);
      expect(find.text('Überfällig wartend'), findsOneWidget);
      await ops.tap(t, find.text('Administratives Protokoll ansehen'));
      expect(protocol, 1);
      expect(calls, isEmpty);
      await ops.tap(t, find.text('In Bearbeitung'));
      expect(find.text('Laufende Aufträge prüfen'), findsOneWidget);
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA026 the push-failure metric itself opens only the intended push destination',
    (t) async {
      var pushes = 0;
      final s = ops.admin((_) async => ops.reply({}));
      await ops.mount(
        t,
        AdminOperationCards(jobs(), state: s, onOpenPush: () => pushes++),
      );
      await ops.tap(t, find.text('Pushfehler · 24 Stunden'));
      expect(pushes, 1);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA027 worker signal opens its real observation and preserves the evidence boundary',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({});
      });
      await ops.mount(t, AdminOperationCards(jobs(), state: s));
      await ops.tap(t, find.text('Worker · letztes Signal vor 17 s'));
      expect(find.text('Signal des Hintergrunddienstes'), findsOneWidget);
      expect(find.text('Vor 17 s'), findsOneWidget);
      expect(
        find.textContaining('beweist keine vollständige Bearbeitung'),
        findsOneWidget,
      );
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA028 audit card opens copyable existing metadata without repeating the operation',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({});
      });
      await ops.mount(
        t,
        AdminAuditList([event('admin.provider_update')], state: s),
      );
      await ops.tap(t, find.text('Ereignisdetails ansehen'));
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('KI-Konfiguration gespeichert'),
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SelectableText, 'fixture-target'),
        findsOneWidget,
      );
      expect(
        find.textContaining('führt keine damalige Aktion erneut aus'),
        findsOneWidget,
      );
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA029 audit family target is an explicit allowed metadata search, arbitrary URLs are inert',
    (t) async {
      final s = ops.admin((_) async => ops.reply({}));
      const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      String? target;
      await ops.mount(
        t,
        AdminAuditList(
          [event('admin.entitlements_update', target: id)],
          state: s,
          onOpenFamily: (value) => target = value,
        ),
      );
      await ops.tap(t, find.text('Ereignisdetails ansehen'));
      expect(target, isNull);
      await ops.tap(t, find.text('Genannte Familie suchen'));
      expect(target, id);
      await ops.mount(
        t,
        AdminAuditList(
          [
            event(
              'admin.entitlements_update',
              target: 'https://example.invalid/private',
            ),
          ],
          state: s,
          onOpenFamily: (value) => target = value,
        ),
      );
      await ops.tap(t, find.text('Ereignisdetails ansehen'));
      expect(find.text('Genannte Familie suchen'), findsNothing);
      expect(target, id);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA029 an explicit located family starts one bounded server metadata query',
    (t) async {
      final calls = <http.Request>[];
      const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({
          'items': <Json>[],
          'pagination': {'page': 1, 'pages': 1, 'total': 0},
        });
      });
      await ops.mount(
        t,
        AdminFamilyList(
          s,
          initialSearch: id,
          revision: 1,
          onEdit: (_) async {},
        ),
      );
      expect(calls, hasLength(1));
      expect(calls.single.method, 'GET');
      expect(calls.single.url.queryParameters['search'], id);
      expect(calls.single.url.queryParameters['page_size'], '50');
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA030 audit reset clears both visible query and combined filters locally',
    (t) async {
      final s = ops.admin((_) async => ops.reply({}));
      await ops.mount(
        t,
        AdminAuditList([event('admin.provider_update')], state: s),
      );
      await toggleParentDetails104(t, 'Protokoll durchsuchen & filtern');
      await t.enterText(find.byType(TextField), 'does-not-match');
      await t.pump();
      expect(find.text('Keine passenden Einträge.'), findsOneWidget);
      await ops.tap(t, find.text('Alle Protokollfilter zurücksetzen'));
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('Ereignisdetails ansehen'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA031 operational changes and checks filter only already loaded event categories',
    (t) async {
      await ops.mount(
        t,
        AdminAuditList([
          event('admin.provider_update'),
          event('admin.provider_read'),
          event('admin.provider_check'),
        ]),
      );
      await toggleParentDetails104(t, 'Protokoll durchsuchen & filtern');
      await ops.tap(t, find.widgetWithText(ChoiceChip, 'Änderungen'));
      expect(find.text('Aktion: admin.provider_update'), findsOneWidget);
      expect(find.text('Aktion: admin.provider_read'), findsNothing);
      await ops.tap(t, find.widgetWithText(ChoiceChip, 'Prüfungen'));
      expect(find.text('Aktion: admin.provider_check'), findsOneWidget);
      expect(find.text('Aktion: admin.provider_update'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA032 audit records retain the actual seconds within the same minute',
    (t) async {
      await ops.mount(
        t,
        AdminAuditList([
          event('admin.provider_update'),
          event('admin.provider_update', offset: 1),
        ]),
      );
      final time = DateTime.fromMillisecondsSinceEpoch(1792600000 * 1000)
          .toLocal();
      String pair(int v) => v.toString().padLeft(2, '0');
      final prefix =
          '${pair(time.day)}.${pair(time.month)}.${time.year} · ${pair(time.hour)}:${pair(time.minute)}:';
      expect(find.text('$prefix${pair(time.second)}'), findsOneWidget);
      expect(find.text('$prefix${pair(time.second + 1)}'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
}
