import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/schulbuddy.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/ui.dart';

const child = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    unit = '11111111111111111111111111111111';
http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json contextResult(
  String page, {
  List<Json> history = const [],
  bool available = true,
}) => {
  'context_key': page,
  'label': 'Bereich $page',
  'starters': [
    'Erkläre mir den nächsten Schritt.',
    'Wie kann ich selbst anfangen?',
    'Worauf sollte ich achten?',
  ],
  'available': available,
  if (!available) 'notice': 'Hier sind nur Bedienhinweise verfügbar.',
  'history': history,
};
Json turn({String status = 'ready', String? key}) => {
  'id': 'turn',
  'request_key': key,
  'status': status,
  'question': 'Wie beginne ich?',
  'answer': status == 'ready' ? 'Betrachte zuerst, was gesucht ist.' : null,
  'next_question': 'Was weißt du schon?',
  'sources': [],
};

class Harness {
  final AppState state;
  final GoRouter router;
  final List<http.Request> calls;
  Harness(this.state, this.router, this.calls);
}

Future<Harness> open(
  WidgetTester t, {
  Future<http.Response> Function(http.Request)? respond,
  bool parent = false,
  bool admin = false,
  double width = 390,
  double height = 844,
  double scale = 1,
  bool robot = false,
  bool unitEntry = false,
  VoidCallback? onLearn,
}) async {
  final calls = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              calls.add(r);
              return respond == null
                  ? reply(
                      contextResult(
                        r.url.queryParameters['page_kind'] ?? 'today',
                      ),
                    )
                  : respond(r);
            }),
          ),
        )
        ..user = {
          'id': 'actor',
          'role': admin
              ? 'admin'
              : parent
              ? 'parent'
              : 'child',
          if (!parent && !admin) 'child_id': child,
          if (parent)
            'families': [
              {'id': 'family', 'permission': 'owner'},
            ],
        };
  final nav = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: nav,
    initialLocation: '/app',
    routes: [
      for (final path in ['/app', '/learn/:id'])
        GoRoute(
          path: path,
          builder: (ctx, _) => Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  Text('Aufgabe $path'),
                  if (robot)
                    ChildTodayHero(
                      eyebrow: 'Heute',
                      title: 'Meine Aufgabe',
                      subtitle: 'Ein Schritt',
                      action: ActionButton(
                        label: 'Aufgabe öffnen',
                        onPressed: () async {
                          onLearn?.call();
                        },
                      ),
                    ),
                  if (unitEntry)
                    SchulbuddyButton(unitId: unit, questionId: 'q1'),
                  TextField(
                    decoration: InputDecoration(labelText: 'Aufgabenantwort'),
                  ),
                  TextButton(
                    onPressed: () => SchulbuddyScope.maybeOf(ctx)?.open(),
                    child: Text('Buddy öffnen'),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
  addTearDown(router.dispose);
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (ctx, body) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: ListenableBuilder(
          listenable: router.routeInformationProvider,
          builder: (_, _) => SchulbuddyHost(
            state: state,
            navigatorKey: nav,
            location: router.routeInformationProvider.value.uri.toString(),
            child: body!,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return Harness(state, router, calls);
}

Finder field() => find.byWidgetPredicate(
  (w) =>
      w is TextField && w.decoration?.labelText == 'Deine Frage an Schulbuddy',
);
Future<void> tap(WidgetTester t, Finder f) async {
  await t.pumpAndSettle();
  await t.ensureVisible(f.first);
  await t.tap(f.first);
  await t.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('context resolver excludes arbitrary query contents and all admin child references', () {
    final state = AppState()
      ..user = {'id': 'u', 'role': 'child', 'child_id': child};
    expect(
      SchulbuddyContext.fromLocation(
        state,
        '/unit/$unit?answer=private',
      ).fields,
      {'page_kind': 'learn', 'child_id': child, 'unit_id': unit},
    );
    state.user = {'id': 'admin', 'role': 'admin'};
    expect(
      SchulbuddyContext.fromLocation(state, '/homework/$child/$unit').fields,
      {'page_kind': 'admin'},
    );
  });
  testWidgets('opening and all three starters never send a model request', (
    t,
  ) async {
    final h = await open(t);
    await tap(t, find.text('Buddy öffnen'));
    expect(find.text('Gespräch: Bereich today'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(3));
    await tap(t, find.text('Wie kann ich selbst anfangen?'));
    expect(
      t.widget<TextField>(field()).controller!.text,
      'Wie kann ich selbst anfangen?',
    );
    expect(h.calls.every((r) => r.method == 'GET'), isTrue);
  });
  testWidgets(
    'closing and reopening preserves own draft and the mounted task answer',
    (t) async {
      final h = await open(t);
      final answer = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Aufgabenantwort',
      );
      await t.enterText(answer, '45');
      await tap(t, find.text('Buddy öffnen'));
      await t.enterText(field(), 'Meine eigene Frage');
      await tap(t, find.byTooltip('Schulbuddy schließen'));
      expect(
        t
            .widget<EditableText>(
              find.descendant(of: answer, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        '45',
      );
      await tap(t, find.text('Buddy öffnen'));
      expect(
        t.widget<TextField>(field()).controller!.text,
        'Meine eigene Frage',
      );
      expect(h.calls.where((r) => r.method == 'POST'), isEmpty);
    },
  );
  testWidgets(
    'route changes preserve conversation until an explicit read only context switch',
    (t) async {
      final h = await open(t);
      await tap(t, find.text('Buddy öffnen'));
      await t.enterText(field(), 'Frage zum ersten Bereich');
      await tap(t, find.byTooltip('Schulbuddy schließen'));
      h.router.go('/learn/$child');
      await t.pumpAndSettle();
      await tap(t, find.text('Buddy öffnen'));
      expect(find.text('Gespräch: Bereich today'), findsOneWidget);
      expect(
        t.widget<TextField>(field()).controller!.text,
        'Frage zum ersten Bereich',
      );
      await tap(t, find.text('Zur aktuellen Seite wechseln'));
      expect(find.text('Gespräch: Bereich learn'), findsOneWidget);
      expect(t.widget<TextField>(field()).controller!.text, isEmpty);
      expect(h.calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'uncertain send and reopen retain exact payload and idempotency key',
    (t) async {
      final h = await open(
        t,
        respond: (r) async => r.method == 'POST'
            ? reply({'detail': 'Antwort verloren'}, 503)
            : reply(contextResult('today')),
      );
      await tap(t, find.text('Buddy öffnen'));
      await t.enterText(field(), 'Wie beginne ich?');
      await tap(t, find.text('Frage senden'));
      await tap(t, find.byTooltip('Schulbuddy schließen'));
      await tap(t, find.text('Buddy öffnen'));
      await tap(t, find.text('Dieselbe Frage erneut senden'));
      final posts = h.calls.where((r) => r.method == 'POST').toList();
      expect(posts.length, 2);
      expect(posts.first.body, posts.last.body);
      final firstKey =
          posts.first.headers['Idempotency-Key'] ??
          posts.first.headers['idempotency-key'];
      final lastKey =
          posts.last.headers['Idempotency-Key'] ??
          posts.last.headers['idempotency-key'];
      expect(firstKey, isNotEmpty);
      expect(firstKey, lastKey);
    },
  );
  testWidgets(
    'history request key reconciles unknown acceptance with GET alone',
    (t) async {
      String? key;
      final h = await open(
        t,
        respond: (r) async {
          if (r.method == 'POST') {
            key = r.headers['Idempotency-Key'] ?? r.headers['idempotency-key'];
            return reply({'detail': 'Unterbrochen'}, 503);
          }
          return reply(
            contextResult(
              'today',
              history: key == null ? [] : [turn(key: key)],
            ),
          );
        },
      );
      await tap(t, find.text('Buddy öffnen'));
      await t.enterText(field(), 'Wie beginne ich?');
      await tap(t, find.text('Frage senden'));
      await tap(t, find.text('Nachsehen, ob die Frage angekommen ist'));
      expect(find.text('Schulbuddy · KI'), findsOneWidget);
      expect(t.widget<TextField>(field()).controller!.text, isEmpty);
      expect(h.calls.where((r) => r.method == 'POST').length, 1);
    },
  );
  testWidgets(
    'new login map dismisses private dialogue and cannot retain its text',
    (t) async {
      final h = await open(t);
      await tap(t, find.text('Buddy öffnen'));
      await t.enterText(field(), 'Privater Entwurf');
      h.state.user = {...h.state.user!};
      h.state.notifyListeners();
      await t.pumpAndSettle();
      expect(find.text('Privater Entwurf'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      await tap(t, find.text('Buddy öffnen'));
      expect(t.widget<TextField>(field()).controller!.text, isEmpty);
    },
  );
  testWidgets(
    'an unavailable admin context shows hints without enabling paid sends',
    (t) async {
      final h = await open(
        t,
        admin: true,
        respond: (r) async => reply(contextResult('admin', available: false)),
      );
      await tap(t, find.text('Buddy öffnen'));
      expect(t.widget<TextField>(field()).enabled, isFalse);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('Chat nicht verfügbar'), findsOneWidget);
      final send = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Frage senden'),
      );
      expect(send.onPressed, isNull);
      expect(
        find.text('Hier sind nur Bedienhinweise verfügbar.'),
        findsOneWidget,
      );
      expect(h.calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'saved responses are rendered and read aloud only by explicit control',
    (t) async {
      await open(
        t,
        respond: (r) async => reply(contextResult('today', history: [turn()])),
      );
      await tap(t, find.text('Buddy öffnen'));
      expect(find.text('Schulbuddy · KI'), findsOneWidget);
      expect(find.text('Was weißt du schon?'), findsOneWidget);
      expect(find.text('Vorlesen'), findsOneWidget);
    },
  );
  for (final shape in [(320.0, 568.0, 2.0), (640.0, 320.0, 2.0)]) {
    testWidgets('compact buddy keeps composer reachable at $shape', (t) async {
      await open(t, width: shape.$1, height: shape.$2, scale: shape.$3);
      await tap(t, find.text('Buddy öffnen'));
      await t.ensureVisible(field());
      await t.tap(field());
      await t.enterText(field(), 'Meine Frage');
      await t.pump();
      await t.ensureVisible(find.text('Frage senden'));
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('Today robot opens buddy without activating the learning card', (
    t,
  ) async {
    var learningStarts = 0;
    final h = await open(t, robot: true, onLearn: () => learningStarts++);
    await tap(t, find.byTooltip('Schulbuddy fragen'));
    expect(find.text('Schulbuddy'), findsOneWidget);
    expect(h.calls.every((r) => r.method == 'GET'), isTrue);
    expect(learningStarts, 0);
  });
  testWidgets(
    'focused entry binds the current question while opening remains read only',
    (t) async {
      final h = await open(t, unitEntry: true);
      await tap(t, find.byTooltip('Schulbuddy öffnen'));
      final request = h.calls.last;
      expect(request.method, 'GET');
      expect(request.url.queryParameters['unit_id'], unit);
      expect(request.url.queryParameters['question_id'], 'q1');
      expect(request.url.queryParameters['child_id'], child);
      expect(h.calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'changed sources hide old help and allow a text preserving fresh question',
    (t) async {
      final h = await open(
        t,
        respond: (r) async => r.method == 'POST'
            ? reply(turn())
            : reply(
                contextResult(
                  'today',
                  history: [
                    {
                      ...turn(),
                      'source_changed': true,
                      'answer': 'Veraltete Erklärung',
                      'sources': [
                        {'quote': 'Veraltetes Zitat'},
                      ],
                    },
                  ],
                ),
              ),
      );
      await tap(t, find.text('Buddy öffnen'));
      expect(find.textContaining('Veraltete Erklärung'), findsNothing);
      expect(find.textContaining('Veraltetes Zitat'), findsNothing);
      await t.enterText(field(), 'Meine Frage zur neuen Fassung');
      await tap(t, find.text('Neue Frage ohne bisherigen Chat'));
      expect(
        t.widget<TextField>(field()).controller!.text,
        'Meine Frage zur neuen Fassung',
      );
      await tap(t, find.text('Frage senden'));
      final body = jsonDecode(
        h.calls.singleWhere((r) => r.method == 'POST').body,
      ) as Map;
      expect(body.containsKey('reply_to'), isFalse);
    },
  );
  testWidgets(
    'closing an inflight send reconciles a queued turn without a second request',
    (t) async {
      final sent = Completer<http.Response>();
      String? key;
      final h = await open(
        t,
        respond: (r) async {
          if (r.method == 'POST') {
            key = r.headers['idempotency-key'];
            return sent.future;
          }
          return reply(
            contextResult(
              'today',
              history: key == null ? [] : [turn(status: 'queued', key: key)],
            ),
          );
        },
      );
      await tap(t, find.text('Buddy öffnen'));
      await t.enterText(field(), 'Wie beginne ich?');
      await tap(t, find.text('Frage senden'));
      await tap(t, find.byTooltip('Schulbuddy schließen'));
      await tap(t, find.text('Buddy öffnen'));
      expect(find.textContaining('Schulbuddy denkt nach'), findsOneWidget);
      expect(find.text('Dieselbe Frage erneut senden'), findsNothing);
      expect(h.calls.where((r) => r.method == 'POST').length, 1);
      sent.complete(reply(turn(key: key)));
      await t.pumpAndSettle();
      await tap(t, find.byTooltip('Schulbuddy schließen'));
    },
  );
  testWidgets(
    'private drafts wait for fresh authorization and disappear on source denial',
    (t) async {
      final delayed = Completer<http.Response>();
      var reads = 0;
      final h = await open(
        t,
        respond: (r) async =>
            ++reads == 1 ? reply(contextResult('today')) : delayed.future,
      );
      await tap(t, find.text('Buddy öffnen'));
      await t.enterText(field(), 'Mein privater Entwurf');
      await tap(t, find.byTooltip('Schulbuddy schließen'));
      await t.tap(find.text('Buddy öffnen'));
      await t.pump();
      await t.pump(Duration(milliseconds: 300));
      expect(t.widget<TextField>(field()).controller!.text, isEmpty);
      delayed.complete(reply({'detail': 'Quelle nicht mehr verfügbar'}, 403));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field()).controller!.text, isEmpty);
      expect(
        h.state.collectionViews.keys.where(
          (key) => key.startsWith('schulbuddy:'),
        ),
        isEmpty,
      );
    },
  );
}
