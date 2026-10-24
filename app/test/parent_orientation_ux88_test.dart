import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/ui.dart';

import 'parent_cards_ux88_test.dart' as fixture;
import 'parent_messages_ux88_test.dart' show tap, settle;
import 'parent_hierarchy_test_tools.dart';

void week(fixture.Fixture f, List<dynamic> items) {
  f.plan['plan'] = {
    'date': '2026-10-22',
    'week': [
      {'date': '2026-10-22', 'planned_minutes': 20, 'items': items},
    ],
  };
}

void main() {
  testWidgets(
    'PP078 stored-page overview card opens its own notebook collection with no generation',
    (tester) async {
      final f = fixture.Fixture();
      f.overview['material_count'] = 12;
      await f.mount(tester, '/overview');
      await tap(tester, find.text('Gespeicherte Seiten & Tagespakete'));
      await tap(tester, find.text('12 gespeicherte Heftseiten'));
      expect(find.text('Ziel /library/child'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets('PP079 learning-time card opens the saved weekly framework', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final f = fixture.Fixture();
      f.overview['plan'] = {
        'daily_active_seconds': 600,
        'weekly_active_seconds': 600,
        'daily_goal_minutes': 20,
        'weekly_goal_minutes': 100,
      };
      await f.mount(tester, '/overview');
      await openParentDetails103(tester, 'Zeit & Mindestziele');
      final card = find.ancestor(
        of: find.text('Zeitrahmen und Wochenvorschlag ansehen'),
        matching: find.byType(ActionPanel),
      );
      await tester.ensureVisible(card);
      final data = tester.getSemantics(card).getSemanticsData();
      expect(data.role, isNot(ui.SemanticsRole.progressBar));
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.label, contains('10:00 / 20 Min.'));
      expect(data.label, contains('10:00 / 100 Min.'));
      await tap(tester, find.text('Zeitrahmen und Wochenvorschlag ansehen'));
      expect(parentPlanModeSelected103(tester, 'Woche & Vorgaben'), isTrue);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
    'PP080 parent-goal card lands on actual topics rather than AI administration',
    (tester) async {
      final f = fixture.Fixture();
      f.respond = (request) async {
        if (!request.url.path.endsWith('/learning-plan')) return null;
        expect(request.method, 'GET');
        return fixture.response({
          ...f.plan,
          'filters': request.url.queryParameters,
        });
      };
      await f.mount(tester, '/overview');
      await tap(tester, find.text('Offene Pflichtaufträge: 1'));
      expect(parentPlanModeSelected103(tester, 'Meine Themen'), isTrue);
      expect(find.text('Mathematik · Bruchaddition'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'PP080 explicit week section opens safely and unknown initial section retains the known view',
    (tester) async {
      final f = fixture.Fixture();
      await f.mount(tester, '/parent-plan/child?ansicht=week');
      expect(parentPlanModeSelected103(tester, 'Woche & Vorgaben'), isTrue);
    },
  );
  testWidgets(
    'PP081 weekly vocabulary opens the existing locale-specific word collection',
    (tester) async {
      final f = fixture.Fixture();
      week(f, [
        {
          'kind': 'vocabulary',
          'id': 'words',
          'target_locale': 'fr-FR',
          'subject': 'Französisch',
          'topic': 'Bestätigte Wörter',
          'estimated_minutes': 5,
        },
      ]);
      await f.mount(tester, '/parent-plan/child?ansicht=week');
      await tap(tester, find.text('Französisch · Bestätigte Wörter'));
      expect(find.text('Ziel /vocabulary/child?locale=fr-FR'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'PP082 weekly entries separate saved rounds and source proposals visibly',
    (tester) async {
      final f = fixture.Fixture();
      week(f, [
        {
          'kind': 'unit',
          'id': 'saved',
          'subject': 'Mathematik',
          'topic': 'Brüche',
          'estimated_minutes': 10,
          'status': 'completed',
        },
        {
          'kind': 'material',
          'id': 'source',
          'subject': 'Deutsch',
          'topic': 'Wortarten',
          'estimated_minutes': 10,
        },
      ]);
      await f.mount(tester, '/parent-plan/child?ansicht=week');
      expect(
        find.textContaining('Gespeicherte Runde · Abgeschlossen'),
        findsOneWidget,
      );
      expect(find.textContaining('Heftseite als Grundlage'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'PP083 a deadline conflict reveals matching stored goals instead of an inert warning',
    (tester) async {
      final f = fixture.Fixture();
      week(f, []);
      f.plan['filters'] = {};
      f.plan['plan']['conflicts'] = [
        {'id': 'assignment', 'topic': 'Bruchaddition', 'due': '2026-10-22'},
      ];
      await f.mount(tester, '/parent-plan/child?ansicht=week');
      await tap(tester, find.text('Aufträge zu diesem Termin prüfen'));
      expect(parentPlanModeSelected103(tester, 'Meine Themen'), isTrue);
      expect(f.requests.last.url.queryParameters['q'], 'Bruchaddition');
      expect(f.requests.last.url.queryParameters['page'], '1');
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'PP084 insight refresh cannot submit stale review settings or a second review',
    (tester) async {
      final f = fixture.Fixture();
      final pending = Completer<http.Response>();
      bool delayed = false;
      f.respond = (r) async => delayed ? pending.future : null;
      await f.mount(tester, '/insights');
      await tester.ensureVisible(find.byTooltip('Lernkompass neu laden'));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Lernkompass neu laden').hitTestable(),
        findsOneWidget,
      );
      delayed = true;
      await tester.tap(find.byTooltip('Lernkompass neu laden'));
      await tester.pump();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      final button = find.widgetWithText(
        FilledButton,
        'Jetzt mit KI auswerten',
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      pending.complete(fixture.response(f.insights));
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'PP085 a missing retained report explicitly explains the GET-only return to latest',
    (tester) async {
      final f = fixture.Fixture();
      f.insights['latest']['id'] = 'new';
      f.insights['history'] = [
        {'id': 'new', 'finished': 1792569011},
        {'id': 'old', 'finished': 1792569010},
      ];
      f.respond = (r) async => r.url.queryParameters['review_id'] == 'old'
          ? http.Response(
              jsonEncode({'detail': 'Nicht mehr vorhanden.'}),
              404,
              headers: {'content-type': 'application/json'},
            )
          : null;
      await f.mount(tester, '/insights');
      final dropdown = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Gespeicherte Auswertung ansehen',
      );
      await tap(tester, dropdown);
      await tap(tester, find.textContaining('2. Auswertung ·').last);
      await settle(tester);
      expect(
        find.textContaining('Diese ältere Auswertung ist nicht mehr verfügbar'),
        findsOneWidget,
      );
      expect(
        f.requests.last.url.queryParameters.containsKey('review_id'),
        isFalse,
      );
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
