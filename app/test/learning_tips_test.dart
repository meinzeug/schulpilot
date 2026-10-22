import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_tips.dart';
import 'package:schulpilot/subject_picker.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json content(int n, {bool text = false}) => {
  'id': 'content-$n',
  'topic_id': 'topic-1',
  'title': 'Künstlicher Lerntipp $n',
  'content_type': text ? 'learning_text' : 'video',
  'provider': 'Sofatutor',
  'url': 'https://www.sofatutor.com/mathematik/videos/artificial-$n?topic=1',
  'relation': 'known_level',
  'reason': 'Zum bestätigten Thema Brüche.',
};
Json tips() => {
  'state': 'ready',
  'revision': 1,
  'subject_id': 'math',
  'can_respond': true,
  'source_confirmed': true,
  'topics': [
    {'id': 'topic-1', 'title': 'Brüche addieren'},
  ],
  'recommended': [content(1), content(2, text: true), content(3), content(4)],
  'additional': [],
  'has_more': true,
};

Future<AppState> mount(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) respond, {
  bool browser = false,
  bool parent = false,
  double width = 390,
  double height = 800,
  double scale = 1,
  double keyboard = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient(respond),
          ),
        )
        ..user = {
          'id': 'own-user',
          'role': parent ? 'parent' : 'child',
          'child_id': 'child',
        };
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: browser
            ? TopicBrowser(state, childId: 'child', subjectId: 'math')
            : SingleChildScrollView(
                child: LearningTips(
                  state,
                  childId: 'child',
                  kind: 'material',
                  resourceId: 'page',
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'Only complete HTTPS Sofatutor hosts and ordinary navigation query strings',
    () {
      expect(
        safeSofatutorUri('https://www.sofatutor.com/videos/math?topic=42')
            ?.query,
        'topic=42',
      );
      for (final value in [
        'http://sofatutor.com/x',
        'https://sofatutor.com.evil.org/x',
        'https://evil.org@sofatutor.com/x',
        'https://sofatutor.com:444/x',
        'https://sofatutor.com/x?access_token=synthetic',
        'https://sofatutor.com/x#token',
      ]) {
        expect(safeSofatutorUri(value), isNull);
      }
    },
  );

  testWidgets(
    'Only explicit expansion reads tips, first three and text type are honest',
    (tester) async {
      final requests = <http.Request>[];
      await mount(tester, (request) async {
        requests.add(request);
        return reply(tips());
      });
      expect(requests, isEmpty);
      await tap(tester, find.text('Lerntipps'));
      expect(requests.single.method, 'GET');
      expect(find.text('Künstlicher Lerntipp 1'), findsOneWidget);
      expect(find.text('Sofatutor · Lerntext'), findsOneWidget);
      expect(find.text('Künstlicher Lerntipp 4'), findsNothing);
      await tap(tester, find.text('Weitere anzeigen'));
      expect(find.text('Künstlicher Lerntipp 4'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(requests.last.url.queryParameters['limit'], '12');
    },
  );

  testWidgets(
    'A mismatched suggestion records one explicit feedback then refreshes',
    (tester) async {
      final requests = <http.Request>[];
      bool rejected = false;
      await mount(tester, (r) async {
        requests.add(r);
        if (r.method == 'POST') {
          rejected = true;
          return reply({'saved': true});
        }
        final value = tips();
        if (rejected) value['recommended'] = [];
        return reply(value);
      });
      await tap(tester, find.text('Lerntipps'));
      await tap(tester, find.text('Passt nicht').first);
      final writes = requests.where((r) => r.method == 'POST').toList();
      expect(writes, hasLength(1));
      final body = jsonDecode(writes.single.body) as Map;
      expect(body['kind'], 'not_relevant');
      expect(body['topic_id'], 'topic-1');
      expect(body['request_key'], hasLength(32));
      expect(
        find.textContaining('Noch kein passender Lerntipp.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Old backend hides optional tips without changing learning or retrying',
    (tester) async {
      var count = 0;
      await mount(tester, (_) async {
        count++;
        return http.Response('{"detail":"Nicht gefunden"}', 404);
      });
      await tap(tester, find.text('Lerntipps'));
      expect(find.text('Lerntipps'), findsNothing);
      expect(count, 1);
    },
  );

  testWidgets(
    'Logout while a GET is pending cannot reveal its previous context',
    (tester) async {
      final pending = Completer<http.Response>();
      final state = await mount(tester, (_) => pending.future);
      await tester.tap(find.text('Lerntipps'));
      await tester.pump();
      state.user = null;
      state.refreshState();
      await tester.pump();
      pending.complete(reply(tips()));
      await tester.pumpAndSettle();
      expect(find.text('Künstlicher Lerntipp 1'), findsNothing);
      expect(find.text('Lerntipps'), findsNothing);
    },
  );

  testWidgets('Read-only parents see content and no modifying controls', (
    tester,
  ) async {
    await mount(
      tester,
      (_) async => reply(tips()..['can_respond'] = false),
      parent: true,
    );
    await tap(tester, find.text('Lerntipps'));
    expect(find.text('Künstlicher Lerntipp 1'), findsOneWidget);
    expect(find.text('Passt nicht'), findsNothing);
    expect(find.text('Thema auswählen'), findsNothing);
  });

  testWidgets(
    'Topic browser pages and explicitly filters known levels using GET only',
    (tester) async {
      final requests = <http.Request>[];
      await mount(tester, (r) async {
        requests.add(r);
        final page = int.parse(r.url.queryParameters['page'] ?? '1');
        return reply({
          'subject': {'title': 'Mathematik'},
          'has_known_level': true,
          'can_manage': false,
          'items': [
            {'id': 'topic-$page', 'title': 'Brüche Seite $page'},
          ],
          'total': 21,
          'page': page,
        });
      }, browser: true);
      await tap(tester, find.byTooltip('Weitere Themen'));
      expect(find.text('Brüche Seite 2'), findsOneWidget);
      await tap(tester, find.text('Meine Stufe'));
      expect(requests.last.url.queryParameters, containsPair('scope', 'known'));
      expect(requests.last.url.queryParameters, containsPair('page', '1'));
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    'Small topic browser survives 200 percent text and native keyboard',
    (tester) async {
      await mount(
        tester,
        (_) async => reply({
          'subject': {'title': 'Deutsch als Zweitsprache'},
          'can_manage': false,
          'items': [
            {'id': 'topic-1', 'title': 'Satzbau und eigene kurze Sätze'},
          ],
          'total': 1,
        }),
        browser: true,
        width: 320,
        height: 568,
        scale: 2,
        keyboard: 300,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Simple Past');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Subject correction offers fixed subjects before any pages', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Unzugeordnet');
    final state = AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient(
          (r) async => reply({
            'items': [
              {'id': 'math', 'title': 'Mathematik'},
              {'id': 'english', 'title': 'Englisch'},
            ],
          }),
        ),
      ),
    )..user = {'id': 'own-user', 'role': 'child'};
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: SubjectField(
            state,
            childId: 'child',
            controller: controller,
            enabled: true,
            changed: () {},
          ),
        ),
      ),
    );
    await tap(tester, find.byType(OutlinedButton));
    expect(find.text('Mathematik'), findsOneWidget);
    await tap(tester, find.text('Englisch'));
    expect(controller.text, 'Englisch');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
