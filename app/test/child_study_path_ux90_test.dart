import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/study_path_panel.dart';

import 'child_local_tools_ux88_test.dart' as f;

Json block(String id, String status) => {
  'id': id,
  'title': 'Thema $id',
  'phase': 'understand',
  'label': 'Verstehen',
  'status': status,
  'question_count': 4,
  if (status != 'planned') 'unit_id': 'unit-$id',
};
Json path(List<Json> blocks) => {
  'available': true,
  'blocks': blocks,
  'total_questions': blocks.length * 4,
  'completed_questions':
      blocks.where((b) => b['status'] == 'completed').length * 4,
  'ready_questions': blocks.where((b) => b['status'] == 'ready').length * 4,
  'can_continue': true,
  'next_block_id': blocks
      .where((b) => b['status'] != 'completed')
      .firstOrNull?['id'],
};
Future<void> open(WidgetTester tester, AppState state) =>
    f.show(tester, StudyPathPanel(state, 'child', 'day'));
void main() {
  testWidgets(
    'CK033 planned stage opens useful stored details without preparing a round',
    (tester) async {
      final requests = <http.Request>[];
      final state = f.account((r) async {
        requests.add(r);
        return f.reply(path([block('Brüche', 'planned')]));
      });
      await open(tester, state);
      await f.tap(tester, find.text('Alle Etappen'));
      await f.tap(tester, find.widgetWithText(ListTile, 'Thema Brüche'));
      expect(find.text('4 geplante Aufgaben'), findsOneWidget);
      expect(
        find.textContaining('Hier werden keine neuen Aufgaben vorbereitet.'),
        findsOneWidget,
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK034 stage search finds an actual title and resets an empty view',
    (tester) async {
      final state = f.account(
        (r) async => f.reply(
          path([block('Brüche', 'planned'), block('Flächen', 'ready')]),
        ),
      );
      await open(tester, state);
      await f.tap(tester, find.text('Alle Etappen'));
      await tester.enterText(f.input('Etappen durchsuchen'), 'Flächen');
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'Thema Flächen'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Thema Brüche'), findsNothing);
      await tester.enterText(f.input('Etappen durchsuchen'), 'Leer');
      await tester.pump();
      await f.tap(tester, find.text('Alle Etappen zeigen'));
      expect(find.text('2 von 2 Etappen in dieser Ansicht'), findsOneWidget);
    },
  );
  testWidgets(
    'CK035 stage state filter exposes only actually prepared or completed work',
    (tester) async {
      final requests = <http.Request>[];
      final state = f.account((r) async {
        requests.add(r);
        return f.reply(
          path([
            block('A', 'planned'),
            block('B', 'ready'),
            block('C', 'completed'),
          ]),
        );
      });
      await open(tester, state);
      await f.tap(tester, find.text('Alle Etappen'));
      await f.tap(tester, find.widgetWithText(ChoiceChip, 'Bereit'));
      expect(find.widgetWithText(ListTile, 'Thema B'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Thema A'), findsNothing);
      await f.tap(tester, find.widgetWithText(ChoiceChip, 'Bearbeitet'));
      expect(find.widgetWithText(ListTile, 'Thema C'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK036 server-confirmed ready stage clears only the obsolete preparation error',
    (tester) async {
      var ready = false, posts = 0;
      final state = f.account((r) async {
        if (r.method == 'POST') {
          posts++;
          return http.Response(
            jsonEncode({'detail': 'Unklare Übertragung'}),
            503,
            headers: {'content-type': 'application/json'},
          );
        }
        return f.reply(path([block('A', ready ? 'ready' : 'planned')]));
      });
      await open(tester, state);
      await f.tap(tester, find.text('Erste Etappe starten'));
      expect(find.text('Unklare Übertragung'), findsOneWidget);
      ready = true;
      await f.tap(tester, find.text('Stand prüfen'));
      expect(find.text('Unklare Übertragung'), findsNothing);
      expect(find.text('Etappe öffnen'), findsOneWidget);
      expect(posts, 1);
    },
  );
  testWidgets(
    'CK037 persisted stage failure remains understandable on a fresh GET',
    (tester) async {
      final requests = <http.Request>[];
      final failed = block('A', 'planned')
        ..['error'] = 'Die Quelle war nicht gut lesbar.';
      final state = f.account((r) async {
        requests.add(r);
        return f.reply(path([failed]));
      });
      await open(tester, state);
      expect(find.text('Die Quelle war nicht gut lesbar.'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK038 planned prepared and completed quantities are distinguished using stored facts',
    (tester) async {
      final state = f.account(
        (r) async => f.reply(
          path([
            block('A', 'planned'),
            block('B', 'ready'),
            block('C', 'completed'),
          ]),
        ),
      );
      await open(tester, state);
      expect(
        find.text(
          'Insgesamt geplant: 12 · offen und vorbereitet: 4 · bearbeitet: 4. Noch geplante Aufgaben sind keine fertigen Übungen.',
        ),
        findsOneWidget,
      );
    },
  );
}
