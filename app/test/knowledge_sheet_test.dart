import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/knowledge_sheet.dart';

import 'child_local_tools_ux88_test.dart' as f;

Json knowledge({bool valid = true}) => {
  'source_valid': valid,
  'long_term': [
    {
      'id': 'parts',
      'label': 'Zähler und Nenner benennen',
      'confidence': 'unverified',
      'tasks': 0,
      'attempts': 0,
    },
    {
      'id': 'sum',
      'label': 'Brüche addieren',
      'confidence': 'initial_evidence',
      'tasks': 5,
      'attempts': 6,
      'independent': 1,
      'supported': 1,
      'needs_practice': 1,
      'uncertain': 1,
      'reflection_tasks': 1,
      'successful_check_dates': ['2026-10-20'],
      'review_due': '2026-10-23',
      'origin': 'validated_model_source_quote',
    },
  ],
  'prerequisites': [
    {'before': 'parts', 'after': 'sum', 'basis': 'reviewed_teaching_rule'},
  ],
};
Future<AppState> open(
  WidgetTester t,
  Future<http.Response> Function(http.Request) response,
) async {
  final state = f.account(response);
  await f.show(
    t,
    Builder(
      builder: (ctx) => TextButton(
        onPressed: () => showKnowledgeSheet(ctx, state, unitId: 'unit'),
        child: const Text('Lernziele öffnen'),
      ),
    ),
  );
  await f.tap(t, find.text('Lernziele öffnen'));
  return state;
}

void main() {
  testWidgets(
    'knowledge shows evidence categories and prerequisite without free mastery percentages',
    (t) async {
      final calls = <http.Request>[];
      await open(t, (q) async {
        calls.add(q);
        return f.reply(knowledge());
      });
      expect(find.text('Noch nicht geprüft'), findsOneWidget);
      await f.tap(t, find.text('Brüche addieren'));
      expect(find.text('5 Aufgaben · 6 Versuche'), findsOneWidget);
      expect(
        find.text('Selbstständig: 1 · Mit Hilfe/erneut richtig: 1'),
        findsOneWidget,
      );
      expect(find.text('Weiter üben: 1 · Bewertung offen: 1'), findsOneWidget);
      expect(
        find.text('Eigene Beiträge: 1 · ohne Leistungsbewertung'),
        findsOneWidget,
      );
      expect(
        find.text('Darauf baut dieses Ziel auf: Zähler und Nenner benennen'),
        findsOneWidget,
      );
      expect(find.textContaining('20.10.2026'), findsOneWidget);
      expect(find.textContaining('23.10.2026'), findsOneWidget);
      expect(
        calls.single.url.path,
        '/api/units/unit/learning-session/knowledge',
      );
      expect(calls.every((q) => q.method == 'GET'), isTrue);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'changed source retains honest open status instead of old mastery',
    (t) async {
      await open(t, (_) async => f.reply(knowledge(valid: false)));
      expect(
        find.textContaining('Heftstoff hat sich geändert'),
        findsOneWidget,
      );
      expect(find.text('Brüche addieren'), findsNothing);
    },
  );
  testWidgets(
    'knowledge refresh is deliberate and does not create a learning event',
    (t) async {
      var reads = 0;
      final calls = <http.Request>[];
      await open(t, (q) async {
        calls.add(q);
        reads++;
        return f.reply(
          reads == 1 ? {'source_valid': true, 'long_term': []} : knowledge(),
        );
      });
      expect(
        find.textContaining('noch keine belegte Zuordnung'),
        findsOneWidget,
      );
      await f.tap(t, find.text('Gespeicherten Stand aktualisieren'));
      expect(find.text('Brüche addieren'), findsOneWidget);
      expect(calls.length, 2);
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'a family change closes private learning knowledge before a delayed response',
    (t) async {
      final delayed = Completer<http.Response>();
      final state = f.account((_) => delayed.future);
      await f.show(
        t,
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showKnowledgeSheet(ctx, state, unitId: 'unit'),
            child: const Text('Lernziele öffnen'),
          ),
        ),
      );
      await t.tap(find.text('Lernziele öffnen'));
      await t.pump();
      state.familyId = 'another-family';
      state.notifyListeners();
      await t.pump();
      delayed.complete(f.reply(knowledge()));
      await t.pumpAndSettle();
      expect(find.text('Vorwissen & Lernziele'), findsNothing);
      expect(find.text('Brüche addieren'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
