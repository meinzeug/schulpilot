import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/tutor_sheet.dart';

import 'child_local_tools_ux88_test.dart' as f;

String id(int i) => i.toRadixString(16).padLeft(32, '0');
Json turn(int i, {bool fresh = false}) => {
  'id': id(i),
  'created': i,
  'status': 'ready',
  'question': 'Künstliche Frage $i',
  'reply_to': null,
  'reply': {
    'kind': 'answer',
    'answer': '${fresh ? 'Frische' : 'Belegte'} Erklärung $i',
    'sources': [],
  },
};
Future<void> open(WidgetTester t, AppState state) async {
  await f.show(
    t,
    Builder(
      builder: (ctx) => TextButton(
        onPressed: () =>
            showTutorSheet(ctx, state, childId: 'child', dayId: 'day'),
        child: const Text('Hilfe öffnen'),
      ),
    ),
  );
  await f.tap(t, find.text('Hilfe öffnen'));
}

void main() {
  testWidgets(
    'RQ094 a source change after selecting an explanation preserves input and clears its old reply relation',
    (t) async {
      final calls = <http.Request>[];
      var changed = false;
      final state = f.account((r) async {
        calls.add(r);
        if (r.method == 'POST') return f.reply(turn(2));
        return f.reply({
          'questions': [
            {...turn(1), 'source_changed': changed},
          ],
          'next_cursor': null,
        });
      });
      await open(t, state);
      await f.tap(t, find.text('Dazu nachfragen'));
      final input = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Deine Frage',
      );
      await t.enterText(input, 'Mein erhaltener eigener Text');
      changed = true;
      await f.tap(t, find.byTooltip('Fragen aktualisieren'));
      expect(
        find.textContaining('bisher gewählte Erklärung ist nicht mehr aktuell'),
        findsOneWidget,
      );
      expect(
        t.widget<TextField>(input).controller!.text,
        'Mein erhaltener eigener Text',
      );
      await f.tap(t, find.text('Frage stellen'));
      expect(
        jsonDecode(
          calls.singleWhere((q) => q.method == 'POST').body,
        )['reply_to'],
        isNull,
      );
    },
  );
  testWidgets(
    'RQ027 older tutor pages are refreshed by bounded reauthorized ids',
    (t) async {
      final calls = <http.Request>[];
      var refreshed = false;
      final state = f.account((r) async {
        calls.add(r);
        final older = r.url.queryParameters.containsKey('cursor');
        final retained = r.url.queryParameters.containsKey('retain');
        if (retained) refreshed = true;
        return f.reply({
          'questions': [
            for (var i = older ? 1 : 21; i <= (older ? 20 : 40); i++) turn(i),
          ],
          'next_cursor': older ? null : id(21),
          'retained_questions': retained
              ? [for (var i = 1; i <= 20; i++) turn(i, fresh: true)]
              : [],
          'retained_cursor': retained ? id(1) : null,
        });
      });
      await open(t, state);
      await f.tap(t, find.text('Ältere Fragen laden'));
      await f.tap(t, find.text('Frühere Fragen (39)'));
      await f.tap(t, find.text('Künstliche Frage 1'));
      expect(find.text('Belegte Erklärung 1'), findsOneWidget);
      await f.tap(t, find.byTooltip('Fragen aktualisieren'));
      expect(refreshed, isTrue);
      expect(find.text('Frische Erklärung 1'), findsOneWidget);
      expect(find.text('Belegte Erklärung 1'), findsNothing);
      final ids = calls.last.url.queryParameters['retain']!.split(',');
      expect(ids.length, lessThanOrEqualTo(80));
      expect(ids, contains(id(1)));
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ028 reset returns from an older history slice to the latest authorized page',
    (t) async {
      final calls = <http.Request>[];
      final state = f.account((r) async {
        calls.add(r);
        final older = r.url.queryParameters.containsKey('cursor');
        return f.reply({
          'questions': [
            for (var i = older ? 1 : 21; i <= (older ? 20 : 40); i++) turn(i),
          ],
          'next_cursor': older ? null : id(21),
        });
      });
      await open(t, state);
      await f.tap(t, find.text('Ältere Fragen laden'));
      await f.tap(t, find.text('Nur neueste Fragen zeigen'));
      expect(find.text('Frühere Fragen (19)'), findsOneWidget);
      expect(calls.last.url.queryParameters.containsKey('retain'), isFalse);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ050 manual refresh is read only even without a pending answer',
    (t) async {
      var count = 0;
      final calls = <http.Request>[];
      final state = f.account((r) async {
        calls.add(r);
        count++;
        return f.reply({
          'questions': [turn(count)],
          'next_cursor': null,
        });
      });
      await open(t, state);
      await f.tap(t, find.byTooltip('Fragen aktualisieren'));
      expect(find.text('Künstliche Frage 2'), findsOneWidget);
      expect(calls.length, 2);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  for (final changed in [false, true]) {
    testWidgets(
      'RQ094 a follow-up targets its selected saved explanation; changed source starts a fresh question $changed',
      (t) async {
        final calls = <http.Request>[];
        final state = f.account((r) async {
          calls.add(r);
          if (r.method == 'POST') return f.reply(turn(3));
          return f.reply({
            'questions': [
              {...turn(1), 'source_changed': changed},
              {
                ...turn(2),
                'reply': {
                  ...Json.from(turn(2)['reply']),
                  'next_question': 'Was denkst du dazu?',
                },
              },
            ],
            'next_cursor': null,
          });
        });
        await open(t, state);
        await f.tap(t, find.text('Frühere Fragen (1)'));
        await f.tap(t, find.text('Künstliche Frage 1'));
        final oldCard = find
            .ancestor(
              of: find.text('Belegte Erklärung 1'),
              matching: find.byType(ExpansionTile),
            )
            .first;
        await f.tap(
          t,
          find.descendant(
            of: oldCard,
            matching: find.text(
              changed ? 'Neu dazu fragen' : 'Dazu nachfragen',
            ),
          ),
        );
        final input = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Deine Frage',
        );
        await t.enterText(input, 'Meine gezielte Rückfrage');
        await t.pumpAndSettle();
        await f.tap(t, find.text('Frage stellen'));
        final sent = jsonDecode(
          calls.singleWhere((r) => r.method == 'POST').body,
        ) as Map;
        expect(sent['reply_to'], changed ? isNull : id(1));
        expect(sent['question'], 'Meine gezielte Rückfrage');
      },
    );
  }
}
