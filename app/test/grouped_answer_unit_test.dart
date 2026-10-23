import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/grouped_answer_board.dart';

import 'grouped_answer_board_test.dart' show fieldGroup;
import 'learning_room_test.dart' as round;

Json groupedQuestion() => {
  ...round.question('cat', type: 'grouped'),
  'prompt': 'Ergänze das Wort und wähle die Zeitform.',
  'options': <String>[],
  'field_group': fieldGroup(),
};

Json savedSession({
  String? answer,
  String source = 'source-one',
  int revision = 0,
}) => {
  'version': 1,
  'revision': 3,
  'draft_revision': revision,
  'updated': 1,
  'source_signature': source,
  'working_memory': {
    if (answer != null)
      'draft': {
        'question_id': 'cat',
        'answer': answer,
        'input_method': 'typed',
      },
  },
  'action': {'kind': 'practice'},
};

class _GroupServer extends round.SavedRound {
  final drafts = <Json>[];
  final submitted = <Json>[];
  final capabilities = <String>[];
  _GroupServer() : super(questions: [groupedQuestion()]);

  @override
  Future<http.Response> handle(http.Request request) async {
    capabilities.add(
      request.headers['X-Schulpilot-Capabilities'] ??
          request.headers['x-schulpilot-capabilities'] ??
          '',
    );
    if (request.method == 'GET') {
      calls.add('GET ${request.url.path}');
      if (request.url.path != '/api/units/unit') {
        throw StateError('Unexpected synthetic GET: ${request.url.path}');
      }
      return round.jsonReply(value);
    }
    if (request.url.path.endsWith('/draft')) {
      final body = Json.from(jsonDecode(request.body));
      drafts.add(body);
      final session = savedSession(
        answer: body['answer'],
        revision: body['revision'] + 1,
      );
      value['learning_session'] = session;
      return round.jsonReply(session);
    }
    if (request.url.path.endsWith('/answer')) {
      final body = Json.from(jsonDecode(request.body));
      submitted.add(body);
      answers++;
      final q = (value['questions'] as List).first as Json;
      final attempt = {
        'answer': body['answer'],
        'outcome': 'incorrect',
        'assisted': false,
        'evaluation': {
          'method': 'grouped_v1',
          'parts': [
            {'id': 'word', 'outcome': 'correct'},
            {'id': 'tense', 'outcome': 'incorrect'},
          ],
        },
      };
      (q['attempts'] as List).add(attempt);
      value['pending_feedback'] = {
        'attempt_id': 'group-attempt',
        'question_id': 'cat',
        ...attempt,
      };
      return round.jsonReply({'unit': value, ...attempt, 'explanation': null});
    }
    return super.handle(request);
  }
}

Finder input() => find.byKey(const ValueKey('group-field-cat-word'));
Finder select() => find.byKey(const ValueKey('group-field-cat-tense'));

Future<void> pick(WidgetTester tester, [int index = 0]) async {
  await tester.ensureVisible(select());
  await tester.pumpAndSettle();
  await tester.tap(select());
  await tester.pumpAndSettle();
  final option = find.byKey(ValueKey('group-option-tense-$index'));
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  await tester.ensureVisible(input());
  await tester.enterText(input(), 'walk; „gehen“');
  await tester.pump();
  await pick(tester);
}

Finder check() => find.byKey(const ValueKey('learning-primary-action'));

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'all visible Unicode field values match the single stored JSON draft',
    (tester) async {
      final server = _GroupServer();
      final group = {
        'version': 1,
        'fields': [
          for (var i = 0; i < 4; i++)
            {
              'id': 'f$i',
              'label': 'Feld $i',
              'kind': 'text',
              'options': <String>[],
            },
        ],
      };
      (server.value['questions'] as List).first['field_group'] = group;
      server.value['learning_session'] = savedSession();
      await round.openRound(tester, server);
      for (var i = 0; i < 4; i++) {
        final field = find.byKey(ValueKey('group-field-cat-f$i'));
        await tester.ensureVisible(field);
        await tester.enterText(field, '😀' * 160);
        await tester.pump();
        expect(tester.widget<TextField>(field).controller!.text, '😀' * 160);
      }
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(server.drafts, hasLength(1));
      final encoded = server.drafts.single['answer'] as String;
      expect(encoded.length, greaterThan(1000));
      expect(encoded.runes.length, lessThanOrEqualTo(1000));
      final fields = jsonDecode(encoded)['fields'];
      for (var i = 0; i < 4; i++) {
        final field = find.byKey(ValueKey('group-field-cat-f$i'));
        expect(fields['f$i'], tester.widget<TextField>(field).controller!.text);
      }
      expect(tester.widget<FilledButton>(check()).onPressed, isNotNull);
      expect(server.answers, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mixed group submits one JSON answer only on deliberate common check',
    (tester) async {
      final server = _GroupServer();
      server.value['supports_answer_idempotency'] = true;
      await round.openRound(tester, server);
      expect(server.answers, 0);
      expect(tester.widget<FilledButton>(check()).onPressed, isNull);
      await fill(tester);
      expect(server.answers, 0);
      expect(server.submitted, isEmpty);
      expect(find.text('Richtig'), findsNothing);
      expect(tester.widget<FilledButton>(check()).onPressed, isNotNull);
      await tester.tap(check());
      await tester.pumpAndSettle();
      expect(server.answers, 1);
      expect(server.submitted, hasLength(1));
      final body = server.submitted.single;
      expect(jsonDecode(body['answer']), {
        'version': 1,
        'fields': {'word': 'walk; „gehen“', 'tense': 'Simple Present'},
      });
      expect(body['request_id'], isNotEmpty);
      expect(body['guided_feedback'], isTrue);
      expect(
        server.capabilities.every(
          (header) => header.split(',').contains('grouped-v1'),
        ),
        isTrue,
      );
      expect(find.byType(GroupedAnswerSummary), findsOneWidget);
      expect(find.text('walk; „gehen“'), findsOneWidget);
      expect(find.text('Richtig'), findsOneWidget);
      expect(find.text('Noch einmal prüfen'), findsOneWidget);
      expect(find.text(body['answer']), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual room overview filters locally without posting or selecting a question',
    (tester) async {
      final server = _GroupServer();
      await round.openRound(tester, server);
      final before = server.calls
          .where((call) => call.startsWith('POST'))
          .toList();
      await tester.tap(find.byKey(const ValueKey('round-overview-open')));
      await tester.pumpAndSettle();
      expect(find.text('Deine Rundenübersicht'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('round-filter-open')));
      await tester.pumpAndSettle();
      expect(
        server.calls.where((call) => call.startsWith('POST')).toList(),
        before,
      );
      expect(server.answers, 0);
      expect(server.drafts, isEmpty);
    },
  );

  testWidgets(
    'oversized JSON remains a local draft and cannot create a server attempt',
    (tester) async {
      final server = _GroupServer();
      final group = {
        'version': 1,
        'fields': [
          for (var i = 0; i < 4; i++)
            {
              'id': 'f$i',
              'label': 'Feld $i',
              'kind': 'text',
              'options': <String>[],
            },
        ],
      };
      (server.value['questions'] as List).first['field_group'] = group;
      server.value['learning_session'] = savedSession();
      final h = await round.openRound(tester, server);
      for (var i = 0; i < 4; i++) {
        final field = find.byKey(ValueKey('group-field-cat-f$i'));
        await tester.ensureVisible(field);
        await tester.enterText(field, '\\' * 160);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.text('4 von 4 Feldern ausgefüllt'), findsOneWidget);
      expect(find.textContaining('zusammen zu lang'), findsOneWidget);
      expect(tester.widget<FilledButton>(check()).onPressed, isNull);
      expect(server.drafts, isEmpty);
      expect(server.answers, 0);
      final local = await h.state.learningDrafts.get('own-child', 'unit');
      expect((local!['answer'] as String).length, greaterThan(1000));
      expect(jsonDecode(local['answer'])['fields']['f3'], '\\' * 160);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'partial JSON draft restores and saves using the existing revision contract',
    (tester) async {
      final server = _GroupServer();
      final spec = GroupedAnswerSpec.tryParse(fieldGroup())!;
      server.value['learning_session'] = savedSession(
        answer: spec.encode({'word': 'gespeichert; ✓'}),
        revision: 4,
      );
      final h = await round.openRound(tester, server);
      expect(find.text('gespeichert; ✓'), findsOneWidget);
      expect(find.text('1 von 2 Feldern ausgefüllt'), findsOneWidget);
      expect(server.answers, 0);
      expect(server.drafts, isEmpty);
      await pick(tester, 1);
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(server.drafts, hasLength(1));
      expect(server.drafts.single['revision'], 4);
      expect(jsonDecode(server.drafts.single['answer'])['fields'], {
        'word': 'gespeichert; ✓',
        'tense': 'Simple Past',
      });
      expect(server.answers, 0);
      await h.close();
      await round.openRound(tester, server);
      expect(find.text('gespeichert; ✓'), findsOneWidget);
      expect(find.text('Simple Past'), findsOneWidget);
      expect(find.text('2 von 2 Feldern ausgefüllt'), findsOneWidget);
      expect(server.answers, 0);
    },
  );

  testWidgets(
    'reset and undo restore all JSON field values without an attempt',
    (tester) async {
      final server = _GroupServer();
      await round.openRound(tester, server);
      await fill(tester);
      await round.tapText(tester, 'Eingabe zurücksetzen');
      expect(find.text('0 von 2 Feldern ausgefüllt'), findsOneWidget);
      expect(find.text('walk; „gehen“'), findsNothing);
      await round.tapText(tester, 'Eingabe wiederherstellen');
      expect(find.text('2 von 2 Feldern ausgefüllt'), findsOneWidget);
      expect(find.text('walk; „gehen“'), findsOneWidget);
      expect(server.answers, 0);
    },
  );

  testWidgets(
    'old-account callbacks and open choices cannot edit a new identity',
    (tester) async {
      final server = _GroupServer();
      final h = await round.openRound(tester, server);
      final old = tester
          .widget<GroupedAnswerBoard>(find.byType(GroupedAnswerBoard))
          .onChanged;
      await tester.tap(select());
      await tester.pumpAndSettle();
      h.state.user = {...h.state.user!, 'id': 'another-child'};
      h.state.notifyListeners();
      await tester.pumpAndSettle();
      old('{"version":1,"fields":{"word":"private","tense":"Simple Past"}}');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(GroupedAnswerBoard), findsNothing);
      expect(server.answers, 0);
      expect(server.drafts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same-id source change clears fields and rejects captured callbacks',
    (tester) async {
      final server = _GroupServer();
      server.value['learning_session'] = savedSession();
      await round.openRound(tester, server);
      await tester.enterText(input(), 'old source');
      await tester.pump();
      final old = tester
          .widget<GroupedAnswerBoard>(find.byType(GroupedAnswerBoard))
          .onChanged;
      server.value['learning_session'] = savedSession(source: 'source-two');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      // Simulate the newer server context after the old draft's bounded flush.
      server.value['learning_session'] = savedSession(source: 'source-two');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      old('{"version":1,"fields":{"word":"stale","tense":"Simple Past"}}');
      await tester.pump();
      expect(find.text('old source'), findsNothing);
      expect(find.text('stale'), findsNothing);
      expect(
        find.text('0 von 2 Feldern ausgefüllt'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      expect(server.answers, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('parent review renders labelled saved fields rather than JSON', (
    tester,
  ) async {
    final server = _GroupServer();
    final q = (server.value['questions'] as List).first as Json;
    final answer = GroupedAnswerSpec.tryParse(fieldGroup())!
        .encode({'word': 'walk', 'tense': 'Simple Past'});
    q['attempts'] = [
      {
        'answer': answer,
        'outcome': 'uncertain',
        'assisted': false,
        'evaluation': {
          'parts': [
            {'id': 'word', 'outcome': 'uncertain'},
          ],
        },
      },
    ];
    await round.openRound(tester, server, parent: true);
    final summary = find.byType(GroupedAnswerSummary);
    await tester.ensureVisible(summary);
    await tester.pumpAndSettle();
    expect(summary, findsOneWidget);
    expect(find.text('Englisches Wort'), findsOneWidget);
    expect(find.text('walk'), findsOneWidget);
    expect(find.text('Simple Past'), findsOneWidget);
    expect(find.textContaining('{"version"'), findsNothing);
    expect(server.answers, 0);
    expect(server.drafts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'malformed public groups show a notice and keep common check disabled',
    (tester) async {
      final server = _GroupServer();
      (server.value['questions'] as List).first['field_group'] = {
        'version': 99,
        'fields': [],
      };
      await round.openRound(tester, server);
      expect(find.textContaining('nicht sicher angezeigt'), findsOneWidget);
      expect(find.byType(GroupedAnswerBoard), findsNothing);
      expect(tester.widget<FilledButton>(check()).onPressed, isNull);
      expect(server.answers, 0);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'actual room at 320px / $scale keeps common action and every field reachable',
      (tester) async {
        final server = _GroupServer();
        (server.value['questions'] as List).first['field_group'] = fieldGroup(
          longLabels: true,
        );
        await round.openRound(tester, server, textScale: scale);
        await tester.ensureVisible(input());
        expect(tester.getSize(input()).height, greaterThanOrEqualTo(48));
        await tester.enterText(input(), 'walk');
        await tester.pump();
        await pick(tester);
        expect(tester.getSize(select()).height, greaterThanOrEqualTo(48));
        expect(check().hitTestable(), findsOneWidget);
        expect(server.answers, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
