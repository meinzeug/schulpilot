import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/lesson_voice.dart';
import 'package:schulpilot/ui.dart';

import 'child_local_tools_ux88_test.dart' as f;

Future<void> mount(
  WidgetTester tester,
  AppState state, {
  String kind = 'interest',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => FilledButton(
            onPressed: () => showLearningMessage(
              ctx,
              state,
              childId: 'child',
              kind: kind,
              title: 'Meine Idee',
              refresh: () {},
              offerLiveCall: false,
            ),
            child: Text('Öffnen'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'CK043 empty interest stays in the field and never makes a request',
    (tester) async {
      final requests = <http.Request>[];
      final state = f.account((r) async {
        requests.add(r);
        return f.reply({});
      });
      await mount(tester, state);
      await f.tap(tester, find.text('Öffnen'));
      await f.tap(tester, find.text('Senden'));
      expect(
        find.text('Schreibe kurz, was du mitteilen möchtest.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(f.input('Deine Nachricht'))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(requests, isEmpty);
      await tester.enterText(f.input('Deine Nachricht'), 'Brüche entdecken');
      await tester.pump();
      expect(
        find.text('Schreibe kurz, was du mitteilen möchtest.'),
        findsNothing,
      );
    },
  );
  testWidgets('CK043 help remains possible without compulsory writing', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final state = f.account((r) async {
      requests.add(r);
      return f.reply({});
    });
    await mount(tester, state, kind: 'help');
    await f.tap(tester, find.text('Öffnen'));
    await tester.enterText(f.input('Deine Nachricht'), '');
    await tester.pump();
    await f.tap(tester, find.text('Um Hilfe bitten'));
    expect(
      jsonDecode(requests.single.body)['body'],
      'Ich brauche Unterstützung beim Lernen.',
    );
  });
  testWidgets(
    'CK044 system back retains the exact draft while explicit cancel discards it',
    (tester) async {
      final state = f.account((r) async => f.reply({}));
      await mount(tester, state);
      await f.tap(tester, find.text('Öffnen'));
      await tester.enterText(f.input('Deine Nachricht'), 'Meine neue Idee');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await f.tap(tester, find.text('Öffnen'));
      expect(
        tester.widget<TextField>(f.input('Deine Nachricht')).controller!.text,
        'Meine neue Idee',
      );
      await f.tap(tester, find.text('Abbrechen'));
      await f.tap(tester, find.text('Öffnen'));
      expect(
        tester.widget<TextField>(f.input('Deine Nachricht')).controller!.text,
        '',
      );
    },
  );
  testWidgets(
    'CK045 pending send visibly locks text and cancel without issuing duplicate messages',
    (tester) async {
      final pending = Completer<http.Response>();
      var posts = 0;
      final state = f.account((r) async {
        posts++;
        return pending.future;
      });
      await mount(tester, state);
      await f.tap(tester, find.text('Öffnen'));
      await tester.enterText(f.input('Deine Nachricht'), 'Meine neue Idee');
      await tester.pump();
      final send = tester
          .widget<ActionButton>(find.widgetWithText(ActionButton, 'Senden'))
          .onPressed;
      unawaited(send());
      await tester.pump();
      await tester.pump(Duration(milliseconds: 100));
      expect(
        tester.widget<TextField>(f.input('Deine Nachricht')).enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Abbrechen'))
            .onPressed,
        isNull,
      );
      unawaited(send());
      await tester.pump();
      expect(posts, 1);
      pending.complete(f.reply({}));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'CK049 retry after an uncertain message and reopening uses the same request key',
    (tester) async {
      final requests = <http.Request>[];
      final state = f.account((r) async {
        requests.add(r);
        return requests.length == 1
            ? http.Response(
                jsonEncode({'detail': 'Vorübergehend nicht erreichbar'}),
                503,
                headers: {'content-type': 'application/json'},
              )
            : f.reply({});
      });
      await mount(tester, state);
      await f.tap(tester, find.text('Öffnen'));
      await tester.enterText(f.input('Deine Nachricht'), 'Meine neue Idee');
      await tester.pump();
      await f.tap(tester, find.text('Senden'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await f.tap(tester, find.text('Öffnen'));
      await f.tap(tester, find.text('Senden'));
      expect(requests.length, 2);
      final first = jsonDecode(requests.first.body),
          second = jsonDecode(requests.last.body);
      expect(first['request_key'], matches(RegExp(r'^[A-Za-z0-9_-]{16,80}$')));
      expect(second['request_key'], first['request_key']);
      expect(second, first);
    },
  );
  testWidgets(
    'CK046 wish types filter only existing wishes and offer a clear empty return',
    (tester) async {
      final state = f.account(
        (r) async => throw StateError('No request expected'),
      );
      final data = f.mailData();
      data['messages'] = [
        {
          'id': 'idea',
          'kind': 'interest',
          'body': 'Tiere erforschen',
          'sender_role': 'child',
        },
        {
          'id': 'plan',
          'kind': 'plan_change',
          'body': 'Am Mittwoch lernen',
          'sender_role': 'child',
        },
      ];
      await f.show(tester, f.mailbox(state, data));
      await f.tap(tester, find.text('Meine Wünsche'));
      await f.tap(
        tester,
        find.byKey(const ValueKey('child-mobile-filter-toggle')),
      );
      await f.tap(tester, find.text('Lernideen'));
      expect(find.text('Tiere erforschen'), findsOneWidget);
      expect(find.text('Am Mittwoch lernen'), findsNothing);
      await f.tap(tester, find.text('Planwünsche'));
      expect(find.text('Am Mittwoch lernen'), findsOneWidget);
      expect(find.text('Tiere erforschen'), findsNothing);
      await tester.enterText(
        f.input('Nachrichten durchsuchen'),
        'Nicht vorhanden',
      );
      await tester.pump();
      await f.tap(tester, find.text('Alle Wünsche in dieser Ansicht zeigen'));
      expect(find.text('Tiere erforschen'), findsOneWidget);
      expect(find.text('Am Mittwoch lernen'), findsOneWidget);
    },
  );
  testWidgets(
    'CK047 long-message reader offers an explicit German read-aloud control only',
    (tester) async {
      final state = f.account((r) async => f.reply({}));
      final data = f.mailData();
      data['messages'][0]['body'] =
          'Eine lange künstliche Elternnachricht. ' * 20;
      await f.show(tester, f.mailbox(state, data));
      await f.tap(tester, find.text('Nachricht in Ruhe lesen'));
      final voice = tester.widget<ReadAloudButton>(
        find.byType(ReadAloudButton),
      );
      expect(voice.locale, 'de-DE');
      expect(voice.text, data['messages'][0]['body']);
      expect(find.text('Zurück zum Postfach'), findsOneWidget);
    },
  );
}
