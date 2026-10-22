import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/ai_cost_panel.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/ui.dart';

import 'admin_operations_catalog_ux_test.dart' as ops;
import 'admin_workspace_test.dart' as workspace;

Json costs() => {
  'models': {
    'synthetic-cost-model': {
      'calls': 2,
      'billed_micros_usd': 1,
      'unknown_calls': 1,
      'unusable_calls': 0,
      'p50_ms': 20,
      'p95_ms': 30,
    },
  },
  'budget_policy': {
    'target_eur_micros': 7000000,
    'warning_eur_micros': 9000000,
    'hard_eur_micros': 12000000,
  },
  'child_budgets': [
    {
      'cost_centre': 'anonymous-fixture',
      'state': 'warning',
      'held_eur_micros': 9000001,
      'unsettled_calls': 1,
    },
  ],
  'cost_centres': [
    [
      'account-fixture',
      {'calls': 2, 'billed_micros_usd': 1, 'unknown_calls': 1},
    ],
  ],
};
Json policy(int revision) => {
  'revision': revision,
  'effective_reasoning_effort': 'medium',
  'policy': {
    'enabled': false,
    'routes': {
      'luna': {
        'model': 'synthetic-route-$revision',
        'upstreams': ['fixture-upstream'],
        'under13_approved': false,
      },
    },
  },
};

void main() {
  testWidgets(
    'AA012 the whole KI overview card opens saved configuration with GET only',
    (t) async {
      final requests = <http.Request>[];
      await workspace.mount(t, requests);
      await workspace.tap(t, find.text('synthetic-model'));
      expect(find.text('Konfiguration sicher speichern'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA009 admin overview clears cached metadata on replacement login',
    (t) async {
      final requests = <http.Request>[];
      await workspace.mount(t, requests);
      final screen = t.widget<AdminScreen>(find.byType(AdminScreen));
      final stale = t
          .widget<ActionPanel>(
            find.widgetWithText(ActionPanel, 'KI-Konfiguration öffnen'),
          )
          .onPressed!;
      screen.state.user = {...screen.state.user!};
      screen.state.refreshState();
      await t.pumpAndSettle();
      expect(find.text('synthetic-model'), findsNothing);
      stale();
      await t.pumpAndSettle();
      expect(find.text('Konfiguration sicher speichern'), findsNothing);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA014 model cost card opens only its existing aggregate without another request',
    (t) async {
      final calls = <http.Request>[];
      var routing = 0;
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply(costs());
      });
      await ops.mount(t, AiCostPanel(s, onOpenRouting: () => routing++));
      await ops.tap(t, find.text('synthetic-cost-model'));
      expect(find.text('Verbrauch für synthetic-cost-model'), findsOneWidget);
      expect(find.text('Unbrauchbare Ergebnisse'), findsOneWidget);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'GET');
      await ops.tap(t, find.text('Routingregeln ansehen'));
      expect(routing, 1);
      expect(calls, hasLength(1));
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA015 one measured micro-USD is never rounded to a displayed zero',
    (t) async {
      final s = ops.admin((_) async => ops.reply(costs()));
      await ops.mount(t, AiCostPanel(s));
      expect(find.text('2 Aufrufe · 0.000001 USD erfasst'), findsOneWidget);
      expect(find.textContaining('0.00000 USD'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA016 missing model cost numbers are unknown and cannot crash the cost view',
    (t) async {
      final s = ops.admin(
        (_) async => ops.reply({
          'models': {'incomplete-model': <String, dynamic>{}},
          'budget_policy': <String, dynamic>{},
        }),
      );
      await ops.mount(t, AiCostPanel(s));
      expect(
        find.text('nicht gemeldet Aufrufe · nicht gemeldet erfasst'),
        findsOneWidget,
      );
      expect(
        find.textContaining('nicht gemeldet Aufrufe / Minute'),
        findsOneWidget,
      );
      expect(find.textContaining('Ziel nicht gemeldet'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA017 budget cost-centre tile opens anonymous held-cost facts with no family access',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply(costs());
      });
      await ops.mount(t, AiCostPanel(s));
      await ops.tap(t, find.text('Kostenstelle anonymous-fixture'));
      expect(find.text('Mit Reservierungen gebunden'), findsOneWidget);
      expect(find.text('9.000001 €'), findsOneWidget);
      expect(find.textContaining('keine privaten Familien'), findsOneWidget);
      expect(calls, hasLength(1));
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA018 account cost-centre opens its loaded attribution with GET only',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply(costs());
      });
      await ops.mount(t, AiCostPanel(s));
      await ops.tap(t, find.text('Kostenstellen'));
      await ops.tap(t, find.text('Konto account-fixture'));
      expect(find.text('Kostenstelle account-fixture'), findsOneWidget);
      expect(find.text('Kostenstellenkennung'), findsOneWidget);
      expect(find.text('0.000001 USD'), findsOneWidget);
      expect(calls, hasLength(1));
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA019 routing card names its exact route and focuses the existing draft without saving',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply(policy(1));
      });
      await ops.mount(t, AiRoutingPanel(s));
      await ops.tap(t, find.textContaining('synthetic-route-1'));
      expect(find.text('Gespeicherte Route luna'), findsOneWidget);
      expect(find.text('fixture-upstream'), findsOneWidget);
      await ops.tap(t, find.text('Routingentwurf öffnen'));
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.controller!.text, contains('synthetic-route-1'));
      expect(calls, hasLength(1));
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA020 routing reload cancellation preserves draft and explicit confirmation reads the new revision',
    (t) async {
      var reads = 0;
      final s = ops.admin((r) async {
        expect(r.method, 'GET');
        return ops.reply(policy(++reads));
      });
      await ops.mount(t, AiRoutingPanel(s));
      await ops.tap(t, find.text('Routingregeln bearbeiten'));
      await t.enterText(find.byType(TextField), '{"own_draft":true}');
      await ops.tap(t, find.byTooltip('Gespeicherte Routingregeln neu laden'));
      await ops.tap(t, find.text('Abbrechen'));
      expect(reads, 1);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        '{"own_draft":true}',
      );
      await ops.tap(t, find.byTooltip('Gespeicherte Routingregeln neu laden'));
      await ops.tap(t, find.text('Bestätigen'));
      expect(reads, 2);
      expect(
        find.text('Gespeicherte Routingregeln · Revision 2'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
}
