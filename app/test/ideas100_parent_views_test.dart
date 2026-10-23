import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:schulpilot/parent_assignment_dialog.dart';
import 'package:schulpilot/ui.dart';

import 'parent_assignment_ux88_test.dart' as a;
import 'parent_insights_test.dart' as p;
import 'parent_hierarchy_test_tools.dart';

void main() {
  testWidgets(
    'assignment preview reflects the unsaved fields at320px200percent',
    (t) async {
      final f = a.Fixture();
      await f.open(t, width: 320, scale: 2);
      await a.ready(t);
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await a.tap(t, find.text('Auftragsvorschau vor dem Speichern'));
      expect(find.text('Englisch · Simple Past'), findsOneWidget);
      expect(find.textContaining('Verbindlich'), findsWidgets);
      expect(f.requests, isEmpty);
      f.state.api.token = 'replacement';
      f.state.refreshState();
      await t.pumpAndSettle();
      expect(find.text('Auftragsvorschau vor dem Speichern'), findsNothing);
    },
  );
  testWidgets(
    'selected assignment source stays readable without source generation',
    (t) async {
      final f = a.Fixture();
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (c) => FilledButton(
                onPressed: () => showParentAssignmentDialog(
                  c,
                  f.state,
                  f.child,
                  [],
                  parseDate: DateTime.tryParse,
                  source: {
                    'id': 'source',
                    'subject': 'Englisch',
                    'topic': 'Past Tense',
                    'title': 'Künstliche bestätigte Heftquelle',
                  },
                ),
                child: const Text('Öffnen'),
              ),
            ),
          ),
        ),
      );
      await a.tap(t, find.text('Öffnen'));
      expect(find.text('Ausgewählte Heftquelle'), findsOneWidget);
      expect(find.text('Past Tense'), findsWidgets);
      expect(find.text('Künstliche bestätigte Heftquelle'), findsWidgets);
      expect(f.requests, isEmpty);
      await t.pumpWidget(const SizedBox());
      f.state.dispose();
    },
  );
  testWidgets(
    'parent topic filter drawer and compact cards preserve source warnings',
    (t) async {
      final calls = <String>[];
      final state = p.account(
        MockClient((r) async {
          calls.add(r.method);
          if (r.url.path.endsWith('/parent-insights')) {
            return p.response(p.insight(ready: false));
          }
          final data = p.plan();
          data['topics'][0]['source_status'] = 'needs_review';
          return p.response(data);
        }),
      );
      await p.open(t, state, 'plan', width: 320, scale: 2);
      await p.tap(t, 'Meine Themen');
      expect(find.text('Suche & alle Themenfilter'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Auftragsstatus',
        ),
        findsNothing,
      );
      await p.tap(t, 'Suche & alle Themenfilter');
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Auftragsstatus',
        ),
        findsOneWidget,
      );
      await p.tap(t, 'Kompakte Auftragsliste');
      await p.tap(t, 'Suche & alle Themenfilter');
      expect(find.textContaining('Quelle geändert · prüfen'), findsWidgets);
      expect(find.text('Ziel & Termin bearbeiten'), findsNothing);
      await p.tap(t, 'Mathematik · Bruchaddition');
      await openParentDetails103(t, 'Auftrag verwalten');
      expect(find.text('Ziel & Termin bearbeiten'), findsOneWidget);
      expect(calls.every((m) => m == 'GET'), isTrue);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'parent homework opens all already delivered task titles locally',
    (t) async {
      final calls = <String>[];
      final state = p.account(
        MockClient((r) async {
          calls.add(r.method);
          final data = p.homework();
          data['photos'][0]['tasks'] = [
            for (var i = 0; i < 5; i++)
              {'title': 'Gelieferte Aufgabe $i', 'marked': i == 0},
          ];
          data['photos'][0]['task_count'] = 5;
          return p.response(data);
        }),
      );
      await p.open(t, state, 'homework', width: 320, scale: 2);
      expect(find.text('Gelieferte Aufgabe 4'), findsNothing);
      await p.tap(t, 'Alle 5 mitgelieferten Aufgaben ansehen');
      expect(find.text('Gelieferte Aufgabe 4'), findsOneWidget);
      expect(calls.every((m) => m == 'GET'), isTrue);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
