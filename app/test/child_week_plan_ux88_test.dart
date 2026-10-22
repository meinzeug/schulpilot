import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/daily_plan_panel.dart';

import 'child_local_tools_ux88_test.dart' as fixture;

Json day({
  String date = '2026-10-23',
  bool free = false,
  bool mandatory = false,
  List<Json>? items,
}) => {
  'date': date,
  'free_day': free,
  'planned_minutes': 12,
  'items':
      items ??
      [
        {
          'kind': 'vocabulary',
          'subject': 'Englisch',
          'topic': 'Tiere aus meinem Heft',
          'target_locale': 'en-GB',
          'mandatory': mandatory,
        },
      ],
};
Json plan(List<Json> days) => {'date': '2026-10-22', 'week': days};
Future<void> open(
  WidgetTester tester,
  AppState state,
  Json data, {
  double scale = 1,
}) async {
  await fixture.show(
    tester,
    DailyPlanPanel(plan: data, childView: true, state: state, childId: 'child'),
    scale: scale,
    size: const Size(320, 568),
  );
}

void main() {
  testWidgets(
    'KK063 vocabulary-only future plan card opens actual topics without starting a round',
    (tester) async {
      final calls = <Object>[];
      final state = fixture.account((r) async {
        calls.add(r);
        return fixture.reply({});
      });
      await open(tester, state, plan([day()]));
      await fixture.tap(tester, find.textContaining('Morgen'));
      expect(find.text('Englisch · Tiere aus meinem Heft'), findsOneWidget);
      expect(find.text('Wortschatz ansehen'), findsOneWidget);
      expect(
        find.textContaining('Gespeicherte Elternaufträge bleiben verbindlich'),
        findsOneWidget,
      );
      expect(calls, isEmpty);
      await fixture.tap(tester, find.text('Wortschatz ansehen'));
      expect(find.text('Ziel /vocabulary/child'), findsOneWidget);
      expect(calls, isEmpty);
    },
  );
  testWidgets(
    'KK064 day labels use the persisted planning date instead of the client clock',
    (tester) async {
      await open(
        tester,
        fixture.account((_) async => fixture.reply({})),
        plan([day(), day(date: '2026-10-24')]),
      );
      expect(find.textContaining('Morgen ·'), findsOneWidget);
      expect(find.textContaining('Sa, 24.10.'), findsOneWidget);
      expect(find.textContaining('Heute ·'), findsNothing);
    },
  );
  testWidgets(
    'KK065 a future portion is clearly an estimate rather than a time minimum at 200 percent',
    (tester) async {
      await open(
        tester,
        fixture.account((_) async => fixture.reply({})),
        plan([day()]),
        scale: 2,
      );
      expect(find.text('Vorgeschlagene Portion: ca. 12 Min.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'KK066 an empty future plan offers existing learning rather than claiming completion',
    (tester) async {
      final state = fixture.account((_) async => fixture.reply({}));
      await open(tester, state, plan([]));
      expect(find.text('Mein Lernen öffnen'), findsOneWidget);
      expect(
        find.textContaining(
          'Für die nächsten Tage ist noch keine weitere Portion',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('geschafft'), findsNothing);
    },
  );
  testWidgets(
    'KK067 a real parent obligation remains visible on a day without a general time goal',
    (tester) async {
      await open(
        tester,
        fixture.account((_) async => fixture.reply({})),
        plan([
          day(free: true, mandatory: true),
          day(date: '2026-10-24', free: true),
        ]),
      );
      expect(find.textContaining('Morgen'), findsOneWidget);
      expect(
        find.text('Elternauftrag · ohne allgemeines Tagesziel'),
        findsOneWidget,
      );
      expect(find.textContaining('Sa, 24.10.'), findsNothing);
    },
  );
  testWidgets(
    'KK012 week-plan private details disappear on a new session of the same account',
    (tester) async {
      final state = fixture.account((_) async => fixture.reply({}));
      await open(tester, state, plan([day()]));
      await fixture.tap(tester, find.textContaining('Morgen'));
      final close = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Zurück zum Plan',
            ),
          )
          .onPressed!;
      state.user = {...state.user!};
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Englisch · Tiere aus meinem Heft'), findsNothing);
      close();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
