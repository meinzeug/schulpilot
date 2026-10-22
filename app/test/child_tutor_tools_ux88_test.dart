import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/tutor_sheet.dart';
import 'package:schulpilot/api.dart';

import 'child_local_tools_ux88_test.dart' as f;

Future<AppState> open(WidgetTester tester, List<http.Request> calls) async {
  final state = f.account((r) async {
    calls.add(r);
    return f.reply({
      'questions': [
        for (var n = 1; n <= 4; n++)
          {
            'id': 'turn$n',
            'created': n,
            'status': n == 2 ? 'failed' : 'ready',
            'question': 'Frage $n zu Bruchteilen',
            'reply_to': null,
            'reply': n == 2
                ? null
                : {
                    'answer': n == 1
                        ? 'Alte Erklärung zur Größe'
                        : 'Erklärung $n',
                    'kind': 'answer',
                    'sources': [],
                  },
          },
      ],
      'next_cursor': null,
    });
  });
  await f.show(
    tester,
    Builder(
      builder: (ctx) => TextButton(
        onPressed: () =>
            showTutorSheet(ctx, state, childId: 'child', dayId: 'day'),
        child: Text('Hilfe öffnen'),
      ),
    ),
  );
  await f.tap(tester, find.text('Hilfe öffnen'));
  await f.tap(tester, find.text('Frühere Fragen (3)'));
  return state;
}

void main() {
  testWidgets(
    'KK084 loaded tutor history can be searched while the latest answer stays visible',
    (tester) async {
      final calls = <http.Request>[];
      await open(tester, calls);
      await tester.enterText(
        f.input('Geladene frühere Fragen durchsuchen'),
        'Größe',
      );
      await tester.pumpAndSettle();
      expect(find.text('Frage 1 zu Bruchteilen'), findsOneWidget);
      expect(find.text('Frage 2 zu Bruchteilen'), findsNothing);
      expect(find.text('Frage 4 zu Bruchteilen'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'KK085 tutor history filters failed and changed-source questions without creating retries',
    (tester) async {
      final calls = <http.Request>[];
      await open(tester, calls);
      await f.tap(tester, find.byType(DropdownButtonFormField<String>));
      await f.tap(tester, find.text('Fehlgeschlagene Fragen').last);
      expect(find.text('Frage 2 zu Bruchteilen'), findsOneWidget);
      expect(find.text('Frage 1 zu Bruchteilen'), findsNothing);
      expect(find.text('Frage 4 zu Bruchteilen'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'KK012 tutor private history is cleared after a family switch of the same account map',
    (tester) async {
      final calls = <http.Request>[];
      final state = await open(tester, calls);
      state.familyId = 'other-family';
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Frage 4 zu Bruchteilen'), findsNothing);
      expect(find.text('Bitte melde dich erneut an.'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
