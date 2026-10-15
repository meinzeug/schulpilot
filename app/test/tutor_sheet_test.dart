import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/tutor_sheet.dart';
import 'package:schulpilot/ui.dart';

http.Response _json(Object data, {int status = 200}) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
AppState _state(MockClient client, {String role = 'child'}) => AppState(
  api: Api(base: 'https://example.invalid/api', client: client),
)..user = {'id': role, 'role': role, 'child_id': 'child'};
Json _turn({
  String id = 'turn',
  String status = 'ready',
  String question = 'Warum bleibt der Nenner gleich?',
}) => {
  'id': id,
  'question': question,
  'status': status,
  'reply_to': null,
  'day_id': 'day',
  'created': id == 'turn' ? 1 : 2,
  'job_id': 'job',
  'error': status == 'failed'
      ? 'Die Erklärung konnte nicht vorbereitet werden.'
      : null,
  'reply': status == 'ready'
      ? {
          'answer': 'Die Teile sind gleich groß. Deshalb zählst du nur die Zähler zusammen.',
          'kind': 'answer',
          'next_question': 'Kannst du mir ein Beispiel zeigen?',
          'sources': [
            {
              'ref': 'm1',
              'label': 'Heftseite 1',
              'material_id': 'material',
              'quote': 'Bei gleichem Nenner addierst du die Zähler.',
            },
          ],
        }
      : null,
};
void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _open(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () =>
                showTutorSheet(context, state, childId: 'child', dayId: 'day'),
            child: const Text('Fragen öffnen'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Fragen öffnen'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void _resume(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void _pause(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void main() {
  testWidgets(
    'Starter and follow-up text need an explicit send; only pending questions poll',
    (tester) async {
      _viewport(tester);
      var reads = 0;
      final posts = <http.Request>[];
      final state = _state(
        MockClient((request) async {
          expect(request.url.path, '/api/children/child/tutor/questions');
          if (request.method == 'POST') {
            posts.add(request);
            return _json(
              _turn(status: 'queued', question: 'Erklär es einfacher'),
              status: 202,
            );
          }
          reads++;
          expect(request.url.queryParameters, {'day_id': 'day'});
          return _json({
            'questions': reads == 1
                ? []
                : [_turn(question: 'Erklär es einfacher')],
            'next_cursor': null,
          });
        }),
      );
      await _open(tester, state);
      expect(posts, isEmpty);
      await _tap(tester, 'Erklär es einfacher');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Erklär es einfacher',
      );
      expect(posts, isEmpty);
      await _tap(tester, 'Frage stellen');
      expect(posts.length, 1);
      expect(jsonDecode(posts.single.body), {
        'day_id': 'day',
        'question': 'Erklär es einfacher',
      });
      expect(posts.single.headers['Idempotency-Key'], isNotEmpty);
      expect(find.text('Ich schaue in deinem Stoff nach.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(reads, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(reads, 2);
      expect(
        find.text(
          'Die Teile sind gleich groß. Deshalb zählst du nur die Zähler zusammen.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('„Bei gleichem Nenner addierst du die Zähler.“'),
        findsNothing,
      );
      await _tap(tester, 'Wo steht das?');
      expect(
        find.text('„Bei gleichem Nenner addierst du die Zähler.“'),
        findsOneWidget,
      );
      await _tap(tester, 'Kannst du mir ein Beispiel zeigen?');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Kannst du mir ein Beispiel zeigen?',
      );
      await tester.pump(const Duration(seconds: 9));
      expect(reads, 2);
      expect(posts.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'An unconfirmed transport retry reuses the exact body and idempotency key',
    (tester) async {
      _viewport(tester);
      final posts = <http.Request>[];
      final state = _state(
        MockClient((request) async {
          if (request.method == 'GET') {
            return _json({'questions': [], 'next_cursor': null});
          }
          posts.add(request);
          if (posts.length == 1) {
            throw http.ClientException('Artificial transport interruption');
          }
          return _json(_turn(question: 'Zeig mir ein Beispiel'), status: 202);
        }),
      );
      await _open(tester, state);
      await _tap(tester, 'Zeig mir ein Beispiel');
      await _tap(tester, 'Frage stellen');
      expect(posts.length, 1);
      expect(find.text('Erneut senden'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.pump(const Duration(seconds: 9));
      expect(posts.length, 1);
      await _tap(tester, 'Erneut senden');
      expect(posts.length, 2);
      expect(posts[1].body, posts[0].body);
      expect(
        posts[1].headers['Idempotency-Key'],
        posts[0].headers['Idempotency-Key'],
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A stored failed answer retries its saved question with a fresh key, preserving history',
    (tester) async {
      _viewport(tester);
      final posts = <http.Request>[];
      final state = _state(
        MockClient((request) async {
          if (request.method == 'GET') {
            return _json({'questions': [], 'next_cursor': null});
          }
          posts.add(request);
          return _json(
            _turn(
              id: posts.length == 1 ? 'turn' : 'second',
              status: posts.length == 1 ? 'failed' : 'ready',
              question: 'Warum ist das so?',
            ),
            status: 202,
          );
        }),
      );
      await _open(tester, state);
      await _tap(tester, 'Warum ist das so?');
      await _tap(tester, 'Frage stellen');
      await tester.enterText(
        find.byType(TextField),
        'Eine andere noch ungesendete Frage',
      );
      await _tap(tester, 'Noch einmal fragen');
      expect(posts.length, 2);
      expect(jsonDecode(posts[1].body), jsonDecode(posts[0].body));
      expect(
        posts[1].headers['Idempotency-Key'],
        isNot(posts[0].headers['Idempotency-Key']),
      );
      expect(find.text('Frühere Fragen (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A parent sees saved answers but has no question creation controls',
    (tester) async {
      _viewport(tester);
      final methods = <String>[];
      final state = _state(
        MockClient((request) async {
          methods.add(request.method);
          return _json({
            'questions': [_turn()],
            'next_cursor': null,
          });
        }),
        role: 'parent',
      );
      await _open(tester, state);
      expect(find.text('Fragen zum Stoff'), findsOneWidget);
      expect(
        find.text(
          'Die Teile sind gleich groß. Deshalb zählst du nur die Zähler zusammen.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Frage stellen'), findsNothing);
      expect(find.text('Noch einmal fragen'), findsNothing);
      expect(methods, ['GET']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Changed source history stays visible; a new question drops the old reply context with the keyboard open',
    (tester) async {
      _viewport(tester);
      addTearDown(tester.view.resetViewInsets);
      final posts = <http.Request>[];
      final previous = _turn()..['source_changed'] = true;
      final state = _state(
        MockClient((request) async {
          if (request.method == 'GET') {
            return _json({
              'questions': [previous],
              'next_cursor': null,
            });
          }
          posts.add(request);
          return _json(
            _turn(
              id: 'new',
              status: 'queued',
              question: 'Was steht auf meiner neuen Heftseite?',
            ),
            status: 202,
          );
        }),
      );
      await _open(tester, state);
      expect(
        find.text('Die Heftseite wurde inzwischen geändert.'),
        findsOneWidget,
      );
      await _tap(tester, 'Neu dazu fragen');
      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      await tester.pump();
      await tester.enterText(
        find.byType(TextField),
        'Was steht auf meiner neuen Heftseite?',
      );
      expect(posts, isEmpty);
      await _tap(tester, 'Frage stellen');
      expect(posts.length, 1);
      expect(jsonDecode(posts.single.body), {
        'day_id': 'day',
        'question': 'Was steht auf meiner neuen Heftseite?',
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Background and covering routes stop polling; dispose never restarts requests',
    (tester) async {
      _viewport(tester);
      var reads = 0;
      final state = _state(
        MockClient((request) async {
          expectSync(request.method, 'GET');
          reads++;
          return _json({
            'questions': [_turn(status: 'queued')],
            'next_cursor': null,
          });
        }),
      );
      addTearDown(() => _resume(tester));
      await _open(tester, state);
      expect(reads, 1);
      _pause(tester);
      await tester.pump(const Duration(seconds: 9));
      expect(reads, 1);
      _resume(tester);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(reads, 2);
      final context = tester.element(
        find.text('Ich schaue in deinem Stoff nach.'),
      );
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Andere Ansicht')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      expect(reads, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 9));
      expect(reads, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
