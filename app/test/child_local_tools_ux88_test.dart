import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_account.dart';
import 'package:schulpilot/child_messages.dart';
import 'package:schulpilot/coaching_panel.dart';
import 'package:schulpilot/homework_screen.dart';
import 'package:schulpilot/language_workshop.dart';
import 'package:schulpilot/learning_navigation.dart';
import 'package:schulpilot/learning_room.dart';
import 'package:schulpilot/preparation_card.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/vocabulary_screen.dart';

import 'homework_screen_test.dart' as homework;
import 'vocabulary_test.dart' as vocabulary;

http.Response reply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
AppState account(Future<http.Response> Function(http.Request) handle) =>
    AppState(
      api: Api(base: 'https://example.invalid/api', client: MockClient(handle)),
    )..user = {'id': 'child-user', 'role': 'child', 'child_id': 'child'};
Future<GoRouter> show(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            child is VocabularyScreen ||
                child is HomeworkScreen ||
                child is ChildAccount ||
                child is LanguageWorkshop
            ? child
            : Scaffold(body: SingleChildScrollView(child: child)),
      ),
      for (final path in [
        '/material/:id',
        '/unit/:id',
        '/after-school/:id',
        '/privacy',
        '/vocabulary/:id',
        '/library/:id/subject/:subjectId',
        '/learn/:id',
        '/notifications',
        '/language-projects/:id',
      ])
        GoRoute(
          path: path,
          builder: (_, route) => Scaffold(body: Text('Ziel ${route.uri.path}')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Finder input(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Json mailData() => {
  'child': {'id': 'child'},
  'messages': [
    {
      'id': 'one',
      'body': 'Bitte Brüche weiter üben.',
      'sender_role': 'parent',
      'kind': 'reply',
      'created': 1792600100,
    },
    {
      'id': 'two',
      'body': 'Ich möchte Tiere entdecken.',
      'sender_role': 'child',
      'kind': 'help',
      'created': 1792600000,
    },
  ],
};
Widget mailbox(AppState state, Json data) => ChildMessagesHub(
  state,
  data: data,
  onCompose: (_, _) async {},
  onWriteMessage: () async {},
);

void main() {
  testWidgets(
    'KK027 message search finds real text, resets an empty result, and makes no request',
    (tester) async {
      final requests = <http.Request>[];
      final state = account((r) async {
        requests.add(r);
        return reply({});
      });
      await show(tester, mailbox(state, mailData()));
      await tester.enterText(input('Nachrichten durchsuchen'), 'BRÜCHE');
      await tester.pumpAndSettle();
      expect(find.text('Bitte Brüche weiter üben.'), findsOneWidget);
      expect(find.text('Ich möchte Tiere entdecken.'), findsNothing);
      await tester.enterText(input('Nachrichten durchsuchen'), 'nicht da');
      await tester.pumpAndSettle();
      await tap(tester, find.text('Suche und Absender zurücksetzen'));
      expect(find.text('Ich möchte Tiere entdecken.'), findsOneWidget);
      expect(requests, isEmpty);
    },
  );
  testWidgets(
    'KK028 sender filter separates parent advice from own requests without resolving',
    (tester) async {
      final state = account((_) async => reply({}));
      await show(tester, mailbox(state, mailData()));
      await tap(tester, find.byType(DropdownButtonFormField<String>).first);
      await tap(tester, find.text('Von meinen Eltern').last);
      expect(find.text('Bitte Brüche weiter üben.'), findsOneWidget);
      expect(find.text('Ich möchte Tiere entdecken.'), findsNothing);
      expect(state.collectionViews['child_mailbox:child']?['sender'], 'parent');
    },
  );
  testWidgets('KK029 oldest-first order uses real message timestamps', (
    tester,
  ) async {
    await show(tester, mailbox(account((_) async => reply({})), mailData()));
    await tap(tester, find.byType(DropdownButtonFormField<String>).last);
    await tap(tester, find.text('Älteste zuerst').last);
    expect(
      tester.getTopLeft(find.text('Ich möchte Tiere entdecken.')).dy,
      lessThan(tester.getTopLeft(find.text('Bitte Brüche weiter üben.')).dy),
    );
  });
  testWidgets(
    'KK030 long message opens a bounded reading view and disappears on account change',
    (tester) async {
      final state = account((_) async => reply({}));
      final data = mailData();
      data['messages'][0]['body'] = List.filled(
        80,
        'Ein hilfreicher Hinweis.',
      ).join(' ');
      await show(
        tester,
        mailbox(state, data),
        scale: 2,
        size: const Size(320, 568),
      );
      await tap(tester, find.text('Nachricht in Ruhe lesen'));
      expect(find.text('Nachricht von deinen Eltern'), findsOneWidget);
      state.user = {...state.user!};
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'KK032 word import state card opens authenticated GET details without retrying',
    (tester) async {
      final requests = <http.Request>[];
      final row = {
        'id': 'import',
        'title': 'Tierwörter',
        'status': 'failed',
        'error': 'Das Foto war nicht lesbar.',
      };
      final state = account((r) async {
        requests.add(r);
        if (r.url.path.endsWith('/imports')) {
          return reply({
            'imports': [row],
          });
        }
        if (r.url.path.endsWith('/imports/import')) return reply(row);
        return reply(vocabulary.listing());
      });
      await show(tester, VocabularyScreen(state, childId: 'child'));
      await tap(tester, find.text('Prüfen'));
      await tap(tester, find.text('Tierwörter'));
      expect(
        find.text('Die Wörter konnten nicht vorbereitet werden.'),
        findsOneWidget,
      );
      expect(
        requests.where((r) => r.url.path.endsWith('/imports/import')),
        hasLength(1),
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'KK033 word source link names and opens only a supplied source ID',
    (tester) async {
      final words = vocabulary.listing();
      words['items'][0]['origin'] = 'material';
      words['items'][0]['source_revisions'] = [
        {'id': 'a' * 32, 'revision': 1},
      ];
      final state = account(
        (r) async => r.url.path.endsWith('/imports')
            ? reply({'imports': []})
            : reply(words),
      );
      await show(tester, VocabularyScreen(state, childId: 'child'));
      await tap(tester, find.text('Heftseite zum Wort ansehen'));
      expect(find.text('Ziel /material/${'a' * 32}'), findsOneWidget);
    },
  );
  testWidgets(
    'KK034 reviewed-empty card returns to the same word collection with GET only',
    (tester) async {
      final requests = <http.Request>[];
      final state = account((r) async {
        requests.add(r);
        return r.url.path.endsWith('/imports')
            ? reply({'imports': []})
            : reply(vocabulary.listing());
      });
      await show(tester, VocabularyScreen(state, childId: 'child'));
      await tap(tester, find.text('Prüfen'));
      await tap(tester, find.text('Zum Wortschatz'));
      expect(find.text('Dein Wortschatz'), findsOneWidget);
      expect(requests, hasLength(2));
    },
  );
  testWidgets(
    'KK035 changed word revision is hidden again until a new explicit reveal',
    (tester) async {
      final words = vocabulary.listing();
      final requests = <http.Request>[];
      final state = account((r) async {
        requests.add(r);
        return r.url.path.endsWith('/imports')
            ? reply({'imports': []})
            : reply(words);
      });
      await show(tester, VocabularyScreen(state, childId: 'child'));
      await tap(tester, find.text('Wort aufdecken'));
      expect(find.text('apple'), findsOneWidget);
      words['items'][0]['word'] = 'pear';
      words['items'][0]['meaning'] = 'Birne';
      words['items'][0]['revision'] = 2;
      await tap(tester, find.byTooltip('Aktualisieren'));
      expect(find.text('pear'), findsNothing);
      expect(find.text('Birne'), findsOneWidget);
      expect(find.text('Wort aufdecken'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
    },
  );
  testWidgets(
    'KK031 import polling stops below a covering route and resumes with a GET',
    (tester) async {
      final requests = <http.Request>[];
      final state = account((r) async {
        requests.add(r);
        return r.url.path.endsWith('/imports')
            ? reply({
                'imports': [
                  {'id': 'i', 'title': 'Wörter', 'status': 'queued'},
                ],
              })
            : reply(vocabulary.listing());
      });
      final router = await show(
        tester,
        VocabularyScreen(state, childId: 'child'),
      );
      router.push('/privacy');
      await tester.pumpAndSettle();
      final before = requests.length;
      await tester.pump(const Duration(seconds: 7));
      expect(requests.length, before);
      router.pop();
      await tester.pumpAndSettle();
      expect(requests.length, before + 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'KK036 KK037 homework search/status inspect only loaded photos, never infer correctness',
    (tester) async {
      final requests = <http.Request>[];
      final state = account((r) async {
        requests.add(r);
        return reply({
          'photos': [
            {
              'id': 'one',
              'topic': 'Brüche',
              'subject': 'Mathematik',
              'confirmed': true,
              'marked_done': 2,
            },
            {
              'id': 'two',
              'topic': 'Tiere',
              'subject': 'Biologie',
              'confirmed': false,
              'marked_done': 0,
            },
          ],
          'next_cursor': 'two',
        });
      });
      await homework.open(tester, state, overview: true);
      await tap(tester, find.text('Foto noch prüfen'));
      expect(find.text('Tiere'), findsOneWidget);
      expect(find.text('Brüche'), findsNothing);
      await tap(tester, find.text('Alle Fotos'));
      await tap(tester, find.text('Foto suchen'));
      await tester.enterText(input('In geladenen Fotos suchen'), 'Mathematik');
      await tester.pumpAndSettle();
      expect(find.text('Brüche'), findsOneWidget);
      expect(find.text('Tiere'), findsNothing);
      expect(find.textContaining('1 von 2 geladenen Fotos'), findsOneWidget);
      await tester.enterText(input('In geladenen Fotos suchen'), '');
      await tester.pumpAndSettle();
      await tap(tester, find.text('Mit Häkchen'));
      expect(
        find.textContaining('zeigen nicht, ob eine Antwort richtig ist'),
        findsOneWidget,
      );
      expect(requests, hasLength(1));
    },
  );
  testWidgets(
    'KK038 homework list remembers local view only in its account RAM',
    (tester) async {
      final state = account(
        (_) async => reply({
          'photos': [
            {'id': 'a', 'topic': 'Brüche', 'confirmed': false},
          ],
          'next_cursor': null,
        }),
      );
      await show(tester, HomeworkScreen(state, childId: 'child'));
      await tap(tester, find.text('Foto noch prüfen'));
      await tap(tester, find.text('Foto suchen'));
      await tester.enterText(input('In geladenen Fotos suchen'), 'Brü');
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await show(tester, HomeworkScreen(state, childId: 'child'));
      expect(
        tester
            .widget<TextField>(input('In geladenen Fotos suchen'))
            .controller
            ?.text,
        'Brü',
      );
      expect(state.collectionViews['homework_list:child']?['filter'], 'review');
    },
  );
  testWidgets(
    'KK039 empty homework card opens only explicit local photo choice',
    (tester) async {
      final requests = <http.Request>[];
      final state = account((r) async {
        requests.add(r);
        return reply({'photos': [], 'next_cursor': null});
      });
      await homework.open(tester, state, overview: true);
      await tester.ensureVisible(
        find.text('Erstes Hausaufgabenfoto aufnehmen'),
      );
      await tester.tap(find.text('Erstes Hausaufgabenfoto aufnehmen'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Foto auswählen'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'KK040 saved homework practice card opens its exact existing round',
    (tester) async {
      final data = homework.fixture();
      data['practice'] = {'kind': 'unit', 'id': 'existing'};
      final requests = <http.Request>[];
      final state = account((r) async {
        requests.add(r);
        return reply(data);
      });
      await homework.open(tester, state);
      await tap(
        tester,
        find.text(
          'Deine gespeicherte Lernrunde zu diesem Foto bleibt erreichbar. Deine Häkchen sind weiterhin nur eine Checkliste.',
        ),
      );
      expect(find.text('Gespeicherte Lernrunde existing'), findsOneWidget);
      expect(
        requests.where(
          (r) => r.method == 'POST' && !r.url.path.endsWith('/start'),
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'KK044 entire primary preparation card opens existing day without request',
    (tester) async {
      await show(
        tester,
        PreparationCard(
          childId: 'child',
          primary: true,
          preparation: {
            'status': 'needs_review',
            'day_id': 'day',
            'date': '2026-10-22',
          },
        ),
      );
      await tap(tester, find.text('Deine Heftseiten sind erkannt.'));
      expect(find.text('Ziel /after-school/child'), findsOneWidget);
    },
  );
  testWidgets(
    'KK045 account section resumes locally after reading notifications',
    (tester) async {
      final state = account((_) async => reply([]));
      await show(tester, ChildAccount(state));
      await tap(tester, find.text('Über die App'));
      await tester.pumpWidget(const SizedBox());
      await show(tester, ChildAccount(state));
      expect(find.text('Dein Lernen bleibt persönlich'), findsOneWidget);
      expect(state.collectionViews['child_account']?['section'], 'about');
    },
  );
  testWidgets(
    'KK046 child privacy card opens the real local privacy route without POST',
    (tester) async {
      final state = account((_) async => reply([]));
      await show(tester, ChildAccount(state));
      await tap(tester, find.text('Über die App'));
      await tap(tester, find.text('Wer sieht meine Daten?'));
      expect(find.text('Ziel /privacy'), findsOneWidget);
    },
  );
  testWidgets(
    'KK047 outcome cards reveal stored matching answers without assessment or HTTP',
    (tester) async {
      final data = [
        {
          'id': 'one',
          'prompt': 'Selbst gelöste Aufgabe',
          'attempts': [
            {'answer': '45', 'outcome': 'correct', 'assisted': false},
          ],
        },
        {
          'id': 'two',
          'prompt': 'Unklare Aufgabe',
          'attempts': [
            {
              'answer': 'Eigene Antwort',
              'outcome': 'uncertain',
              'assisted': false,
            },
          ],
        },
      ];
      await show(tester, RoundAnswerExplorer(questions: data));
      await tap(tester, find.text('1 noch unklar'));
      expect(find.text('Unklare Aufgabe'), findsOneWidget);
      expect(find.text('Selbst gelöste Aufgabe'), findsNothing);
      await tap(tester, find.text('1 selbstständig'));
      expect(find.text('Selbst gelöste Aufgabe'), findsOneWidget);
      expect(find.text('Unklare Aufgabe'), findsNothing);
      expect(data[1]['attempts'], [
        {'answer': 'Eigene Antwort', 'outcome': 'uncertain', 'assisted': false},
      ]);
    },
  );
  testWidgets(
    'KK051 large text keeps leave/pause controls visible after long task scroll',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var left = 0, paused = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: LearningRoom(
              title: 'Lange Aufgabe',
              phase: 1,
              scrollController: scroll,
              onLeave: () => left++,
              onPause: () => paused++,
              child: Text(
                List.filled(120, 'Ein langer Aufgabentext.').join(' '),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(
        find.byTooltip('Lernrunde verlassen').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Pause machen'));
      expect(paused, 1);
      await tester.tap(find.byTooltip('Lernrunde verlassen'));
      expect(left, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'KK052 device card opens real session info and never signs out on card tap',
    (tester) async {
      final requests = <http.Request>[];
      final state = account((r) async {
        requests.add(r);
        return reply([
          {
            'id': 'device',
            'device': 'Mein Tablet',
            'current': false,
            'created': 1792600000,
            'seen': 1792600100,
          },
        ]);
      });
      await show(tester, ChildAccount(state));
      await tap(tester, find.text('Mein Tablet'));
      expect(find.textContaining('Angemeldet seit:'), findsOneWidget);
      expect(find.textContaining('Zuletzt aktiv:'), findsWidgets);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      state.user = {...state.user!};
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets('KK053 device refresh loads actual updated sessions', (
    tester,
  ) async {
    var gets = 0;
    final state = account((_) async {
      gets++;
      return reply([
        {
          'id': 'device',
          'device': gets == 1 ? 'Tablet' : 'Neues Handy',
          'current': false,
        },
      ]);
    });
    await show(tester, ChildAccount(state));
    await tap(tester, find.text('Geräte aktualisieren'));
    expect(gets, 2);
    expect(find.text('Neues Handy'), findsOneWidget);
    expect(find.text('Tablet'), findsNothing);
  });
  testWidgets(
    'KK012 delayed saved-round start cannot navigate after same-ID new login',
    (tester) async {
      final pending = Completer<http.Response>();
      final state = account((_) => pending.future);
      await show(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openPlanItem(
              context,
              state,
              {
                'child': {'id': 'child'},
              },
              {'id': 'unit', 'kind': 'unit'},
            ),
            child: Text('Start'),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pump();
      state.user = {...state.user!};
      pending.complete(reply({}));
      await tester.pumpAndSettle();
      expect(find.text('Ziel /unit/unit'), findsNothing);
    },
  );
  testWidgets(
    'KK012 delayed assignment lookup cannot POST after family changes',
    (tester) async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final state = account((r) async {
        requests.add(r);
        return pending.future;
      });
      await show(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openPlanItem(
              context,
              state,
              {
                'child': {'id': 'child'},
                'materials': [],
              },
              {
                'id': 'assignment',
                'kind': 'assignment',
                'subject': 'Mathematik',
                'topic': 'Brüche',
              },
            ),
            child: Text('Start'),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pump();
      state.familyId = 'new-family';
      pending.complete(
        reply({
          'items': [
            {'id': 'source'},
          ],
        }),
      );
      await tester.pumpAndSettle();
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  for (final invalidation in ['logout', 'new-session', 'covered-route']) {
    testWidgets(
      'KK012 old account message shortcut rejects $invalidation without reading a new child or crashing',
      (tester) async {
        final calls = <http.Request>[];
        final state = account((request) async {
          calls.add(request);
          return reply([]);
        });
        final router = await show(tester, ChildAccount(state));
        await tap(tester, find.text('Über die App'));
        final oldOpen = tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Nachrichten & Wünsche'),
            )
            .onPressed!;
        if (invalidation == 'logout') {
          state.user = null;
          state.notifyListeners();
        } else if (invalidation == 'new-session') {
          state.user = {...state.user!, 'child_id': 'different-child'};
          state.notifyListeners();
        } else {
          router.push('/privacy');
        }
        await tester.pumpAndSettle();
        final location = router.routeInformationProvider.value.uri;
        final count = calls.length;
        oldOpen();
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri, location);
        expect(calls, hasLength(count));
        expect(calls.every((call) => call.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
