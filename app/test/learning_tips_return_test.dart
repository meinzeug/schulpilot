import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_tips.dart';
import 'package:schulpilot/ui.dart';

import 'learning_room_test.dart' show SavedRound, openRound, jsonReply;
import 'learning_tips_test.dart' show tips, reply;

Json returnedTip({String status = 'watched'}) => tips()
  ..['supports_media_return'] = true
  ..['media_return'] = {
    'status': status,
    'content_id': 'content-1',
    'topic_id': 'topic-1',
    'question_id': 'cat',
    'check_available': true,
  };

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Inline media return stays on the learning route at 320px/$scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final requests = <http.Request>[];
        final state = AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              return reply(returnedTip());
            }),
          ),
        )..user = {'id': 'own-child', 'role': 'child', 'child_id': 'child'};
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            theme: appTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(body: Text('Startseite')),
          ),
        );
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    const Text('Gespeicherte Lernrunde'),
                    LearningTips(
                      state,
                      childId: 'child',
                      kind: 'unit',
                      resourceId: 'unit',
                      questionId: 'cat',
                      initiallyExpanded: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final back = find.text('Zur gespeicherten Aufgabe');
        await tester.ensureVisible(back);
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.text('Gespeicherte Lernrunde'), findsOneWidget);
        expect(find.text('Startseite'), findsNothing);
        expect(find.text('Jetzt selbst ausprobieren'), findsNothing);
        expect(requests.every((request) => request.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Inline return opens the saved exercise without an answer or hint at $scale',
      (tester) async {
        final server = SavedRound();
        server.value['introduction_seen'] = false;
        var introductions = 0;
        final harness = await openRound(
          tester,
          server,
          textScale: scale,
          handle: (request) async {
            if (request.url.path.contains('/learning-tips/')) {
              expect(request.method, 'GET');
              return reply(returnedTip());
            }
            if (request.url.path.endsWith('/introduction')) {
              introductions++;
              server.value['introduction_seen'] = true;
              return jsonReply(server.value);
            }
            return server.handle(request);
          },
        );
        await tester.ensureVisible(find.text('Lerntipps'));
        await tester.tap(find.text('Lerntipps'));
        await tester.pumpAndSettle();
        final back = find.text('Zur gespeicherten Aufgabe');
        await tester.ensureVisible(back);
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.text('Was bedeutet cat?'), findsOneWidget);
        expect(introductions, 1);
        expect(server.answers, 0);
        expect(server.hints, 0);
        expect(tester.takeException(), isNull);
        await harness.close();
      },
    );

    testWidgets('Sheet return closes only the help sheet at 320px/$scale', (
      tester,
    ) async {
      final server = SavedRound();
      final harness = await openRound(
        tester,
        server,
        textScale: scale,
        handle: (request) async {
          if (request.url.path.contains('/learning-tips/')) {
            expect(request.method, 'GET');
            return reply(returnedTip());
          }
          return server.handle(request);
        },
      );
      await tester.tap(find.text('Hilfe'));
      await tester.pumpAndSettle();
      final moreHelp = find.text('Mehr Hilfe');
      await tester.ensureVisible(moreHelp);
      await tester.tap(moreHelp);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final tipsButton = find.text('Passendes Erklärvideo');
      await tester.ensureVisible(tipsButton);
      await tester.tap(tipsButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      final back = find.text('Zur gespeicherten Aufgabe');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(back);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(find.text('Jetzt selbst ausprobieren'), findsNothing);
      expect(server.answers, 0);
      expect(server.hints, 1); // Only the explicitly requested initial hint.
      expect(tester.takeException(), isNull);
      await harness.close();
    });
  }

  for (final entry in {
    'opened': 'Vom Kind geöffnet.',
    'watched': 'Vom Kind als angesehen bestätigt.',
    'not_helpful': 'Vom Kind als nicht hilfreich gemeldet.',
    'skipped': 'Vom Kind übersprungen.',
    'broken': 'Das Kind hat ein Problem mit dem Link oder Zugang gemeldet.',
  }.entries) {
    testWidgets(
      'Parent media status ${entry.key} is read-only and is no mastery claim',
      (tester) async {
        final server = SavedRound();
        final requests = <http.Request>[];
        final harness = await openRound(
          tester,
          server,
          parent: true,
          textScale: 2,
          handle: (request) async {
            requests.add(request);
            if (request.url.path.contains('/learning-tips/')) {
              return reply(returnedTip(status: entry.key));
            }
            return server.handle(request);
          },
        );
        await tester.ensureVisible(find.text('Lerntipps'));
        await tester.tap(find.text('Lerntipps'));
        await tester.pumpAndSettle();
        expect(find.text('Lerntipp im Lernverlauf'), findsOneWidget);
        expect(find.text(entry.value), findsOneWidget);
        expect(
          find.text(
            'Ob der Inhalt geholfen hat, zeigen spätere eigene Antworten.',
          ),
          findsOneWidget,
        );
        expect(find.text('Ich habe ihn angesehen'), findsNothing);
        expect(find.text('Mit 2 neuen Aufgaben prüfen'), findsNothing);
        expect(find.text('Zur gespeicherten Aufgabe'), findsNothing);
        expect(requests.every((request) => request.method == 'GET'), isTrue);
        expect(server.answers, 0);
        expect(tester.takeException(), isNull);
        await harness.close();
      },
    );
  }
}
