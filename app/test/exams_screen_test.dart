import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/exam_plan_editor.dart';
import 'package:schulpilot/exams_screen.dart';
import 'package:schulpilot/exams_scope.dart';
import 'package:schulpilot/ui.dart';

const sourceId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Json source() => {
  'id': sourceId,
  'revision': 1,
  'subject': 'Mathematik',
  'topic': 'Brüche',
  'title': 'Bestätigter Heftstoff',
};
Json exam({
  String id = 'exam',
  String purpose = 'preparation',
  bool child = true,
}) => {
  'id': id,
  'child_id': 'child',
  'title': purpose == 'review'
      ? 'Geschriebene Beispielarbeit'
      : 'Bruchtest vorbereiten',
  'purpose': purpose,
  'kind': 'classwork',
  'subject': 'Mathematik',
  'exam_date': null,
  'timezone': 'Europe/Berlin',
  'revision': 1,
  'minutes': 15,
  'topics': [
    {
      'id': 'topic',
      'label': 'Brüche',
      'question_count': 6,
      'material_refs': [
        {'id': sourceId, 'revision': 1},
      ],
    },
  ],
  'schedule': {
    'dates': ['2027-01-20'],
  },
  'reminders': false,
  'reminder_time': '16:00',
  'archived': false,
  'source_status': 'confirmed',
  'planned_days': 1,
  'requested_questions': 6,
  'can_manage': true,
  'can_prepare': child,
  'sources': [source()],
  'sessions': [
    {
      'id': 'session',
      'date': '2027-01-20',
      'minutes': 15,
      'topics': [
        {'id': 'topic', 'label': 'Brüche', 'question_count': 6},
      ],
      'status': 'planned',
      'requested_questions': 6,
      'planned_rounds': 2,
      'completed_rounds': 0,
      'rounds': [
        {
          'id': 'round',
          'ordinal': 0,
          'topic_id': 'topic',
          'topic_label': 'Brüche',
          'question_count': 3,
          'status': 'planned',
          'unit_id': null,
          'unit_status': null,
          'job_id': null,
          'error': null,
        },
      ],
    },
  ],
};
Json review({bool child = true}) => {
  'exam_id': 'exam',
  'child_id': 'child',
  'revision': 1,
  'context_revision': 'a' * 64,
  'status': 'ready',
  'pages': [],
  'analysis_id': 'analysis',
  'analysis_revision': 1,
  'summary': 'Eine künstliche Beispielaufgabe.',
  'uncertainties': [],
  'error': null,
  'can_manage': true,
  'can_analyze': false,
  'notebook_sources': [source()],
  'turns': [],
  'notice': 'KI-Hinweise sind keine Note.',
  'tasks': [
    {
      'id': 'task',
      'question': 'Wie heißt ein Teil von zwei gleichen Teilen?',
      'original_answer': 'Ein Viertel.',
      'teacher_feedback': 'Bezeichnung prüfen.',
      'score_label': '0/1 Punkte',
      'ai_proposal': 'Prüfe die Zahl der gleich großen Teile.',
      'uncertainties': [],
      'sources': [
        {
          'ref': 'p1',
          'quote': 'Bezeichnung prüfen.',
          'material_id': sourceId,
          'label': 'Original',
        },
      ],
      if (child) 'draft': {'text': '', 'revision': 0, 'updated': 0},
    },
  ],
};
http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Fixture {
  final calls = <http.Request>[];
  late final AppState state;
  late final GoRouter router;
  late Json details, report;
  Json? listOverride;
  Completer<http.Response>? listWait;
  String prepareKind = 'job';
  final String role;
  Fixture({this.role = 'child'}) {
    details = exam(child: role == 'child');
    report = review(child: role == 'child');
    state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient(handle),
            ),
          )
          ..user = {
            'id': 'synthetic-$role',
            'role': role,
            'child_id': 'child',
            'display_name': 'Künstliches Beispiel',
            if (role == 'parent')
              'families': [
                {'id': 'family', 'permission': 'owner'},
              ],
          }
          ..familyId = 'family';
    state.api.token = 'synthetic-session';
  }
  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/children/child/exams')) {
      if (listWait != null) return listWait!.future;
      return reply(
        listOverride ??
            {
              'child_id': 'child',
              'can_manage': true,
              'can_prepare': role == 'child',
              'exams': [
                details,
                exam(
                  id: 'review-exam',
                  purpose: 'review',
                  child: role == 'child',
                ),
              ],
              'sources': [source()],
              'total': 2,
              'has_more': false,
            },
      );
    }
    if (request.method == 'GET' && path.endsWith('/children/child/subjects')) {
      return reply({
        'items': [
          {'id': 'math', 'title': 'Mathematik'},
        ],
      });
    }
    if (request.method == 'GET' && path.endsWith('/exams/exam/review')) {
      return reply(report);
    }
    if (request.method == 'GET' &&
        (path.endsWith('/exams/exam') || path.endsWith('/exams/created'))) {
      return reply(details);
    }
    if (request.method == 'POST' &&
        path.endsWith('/sessions/session/prepare')) {
      return reply({'kind': prepareKind, 'id': 'saved', 'status': 'queued'});
    }
    if (request.method == 'POST' && path.endsWith('/units/saved/start')) {
      return reply({});
    }
    if (request.method == 'POST' && path.endsWith('/children/child/exams')) {
      details = {...details, ...jsonDecode(request.body), 'id': 'created'};
      return reply(details);
    }
    if (request.method == 'PUT' && path.endsWith('/exams/exam')) {
      return reply({...details, ...jsonDecode(request.body), 'revision': 2});
    }
    if (request.method == 'PUT' && path.endsWith('/tasks/task/draft')) {
      final body = jsonDecode(request.body) as Map;
      return reply({
        'draft': {'text': body['text'], 'revision': 1, 'updated': 1},
      });
    }
    if (request.method == 'POST' && path.endsWith('/tasks/task/help')) {
      return reply({
        'id': 'turn',
        'task_id': 'task',
        'status': 'ready',
        'action': jsonDecode(request.body)['action'],
        'reply': {'answer': 'Denke an zwei gleich große Teile.'},
      });
    }
    if (request.method == 'POST' && path.endsWith('/tasks/task/practice')) {
      return reply({'id': 'practice-job', 'status': 'queued'});
    }
    if (request.method == 'GET') {
      return reply({'items': [], 'unread_count': 0, 'available': false});
    }
    throw StateError('Unexpected fixture mutation: ${request.method} $path');
  }

  Future<void> mount(
    WidgetTester tester, {
    String? selected,
    String tab = 'prepare',
    Size size = const Size(390, 844),
    double scale = 1,
    bool editor = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.binding.setSurfaceSize(size);
    router = GoRouter(
      initialLocation: '/exams/child',
      routes: [
        GoRoute(
          path: '/exams/:child',
          builder: (_, route) => editor
              ? Scaffold(
                  body: Builder(
                    builder: (context) => FilledButton(
                      onPressed: () => showDialog<Json>(
                        context: context,
                        builder: (_) => ExamPlanEditor(
                          state,
                          childId: 'child',
                          sources: [source()],
                          existing: details,
                        ),
                      ),
                      child: const Text('Editor öffnen'),
                    ),
                  ),
                )
              : ExamsScreen(
                  state,
                  childId: 'child',
                  examId: selected ?? route.uri.queryParameters['exam'],
                  initialTab: route.uri.queryParameters['tab'] ?? tab,
                ),
        ),
        GoRoute(
          path: '/learning-preparation/:child/:id',
          builder: (_, route) =>
              Scaffold(body: Text('Job ${route.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/unit/:id',
          builder: (_, route) =>
              Scaffold(body: Text('Runde ${route.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/material/:id',
          builder: (_, _) => const Scaffold(body: Text('Original prüfen')),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
    });
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
    if (editor) {
      await tester.tap(find.text('Editor öffnen'));
      await tester.pumpAndSettle();
    }
  }

  List<http.Request> get writes =>
      calls.where((call) => call.method != 'GET').toList();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> pause(WidgetTester tester) async {
  for (final value in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(value);
    await tester.pump();
  }
}

Future<void> resume(WidgetTester tester) async {
  for (final value in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(value);
    await tester.pump();
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
  });
  testWidgets('two separate tabs read saved plans without preparing work', (
    tester,
  ) async {
    final fixture = Fixture();
    await fixture.mount(tester);
    expect(find.text('Bruchtest vorbereiten'), findsOneWidget);
    expect(find.text('Geschriebene Beispielarbeit'), findsNothing);
    final before = fixture.calls.length;
    await tap(tester, find.text('Nacharbeiten'));
    expect(find.text('Geschriebene Beispielarbeit'), findsOneWidget);
    expect(find.text('Bruchtest vorbereiten'), findsNothing);
    expect(fixture.calls.length, before);
    expect(fixture.writes, isEmpty);
  });
  testWidgets(
    'child deliberately prepares one session using an idempotency key',
    (tester) async {
      final fixture = Fixture();
      await fixture.mount(tester, selected: 'exam');
      expect(fixture.writes, isEmpty);
      await tap(tester, find.text('Sitzung bewusst starten'));
      expect(find.text('Job saved'), findsOneWidget);
      expect(fixture.writes, hasLength(1));
      expect(
        fixture.writes.single.url.path,
        '/api/exams/exam/sessions/session/prepare',
      );
      expect(fixture.writes.single.headers['Idempotency-Key'], isNotEmpty);
    },
  );
  testWidgets(
    'saved child round starts only after an explicit session action',
    (tester) async {
      final fixture = Fixture()..prepareKind = 'unit';
      await fixture.mount(tester, selected: 'exam');
      await tap(tester, find.text('Sitzung bewusst starten'));
      expect(find.text('Runde saved'), findsOneWidget);
      expect(fixture.writes.map((call) => call.url.path), [
        '/api/exams/exam/sessions/session/prepare',
        '/api/units/saved/start',
      ]);
    },
  );
  testWidgets('parent can read preparation but never starts child learning', (
    tester,
  ) async {
    final fixture = Fixture(role: 'parent');
    await fixture.mount(tester, selected: 'exam');
    expect(find.text('Sitzung bewusst starten'), findsNothing);
    expect(
      find.text('Das Kind startet die Vorbereitung in seinem Zugang.'),
      findsOneWidget,
    );
    expect(fixture.writes, isEmpty);
  });
  testWidgets('planned counts remain separate from actually completed rounds', (
    tester,
  ) async {
    final fixture = Fixture();
    await fixture.mount(tester, selected: 'exam');
    expect(find.text('6 Aufgaben geplant'), findsOneWidget);
    expect(find.text('0 von 2 Runden bearbeitet'), findsOneWidget);
    expect(find.textContaining('Aufgaben richtig'), findsNothing);
    expect(fixture.writes, isEmpty);
  });
  testWidgets('view membership cannot open planning editor', (tester) async {
    final fixture = Fixture(role: 'parent');
    fixture.listOverride = {
      'child_id': 'child',
      'can_manage': false,
      'can_prepare': false,
      'exams': [],
      'sources': [source()],
      'has_more': false,
    };
    await fixture.mount(tester);
    expect(find.text('Arbeit planen'), findsNothing);
    expect(fixture.writes, isEmpty);
  });
  for (final change in ['account', 'family', 'token', 'background', 'cover']) {
    testWidgets('saved start callback is inert after $change', (tester) async {
      final fixture = Fixture();
      await fixture.mount(tester, selected: 'exam');
      final button = tester.widget<ActionButton>(
        find.widgetWithText(ActionButton, 'Sitzung bewusst starten'),
      );
      if (change == 'account') {
        fixture.state.user = {...fixture.state.user!, 'id': 'other'};
        fixture.state.refreshState();
      }
      if (change == 'family') {
        fixture.state.familyId = 'other';
        fixture.state.refreshState();
      }
      if (change == 'token') {
        fixture.state.api.token = 'other';
        fixture.state.refreshState();
      }
      if (change == 'background') await pause(tester);
      if (change == 'cover') {
        unawaited(
          showDialog<void>(
            context: tester.element(find.byType(ExamsScreen)),
            builder: (_) => const AlertDialog(title: Text('Andere Ansicht')),
          ),
        );
        await tester.pumpAndSettle();
      }
      await tester.pumpAndSettle();
      await button.onPressed();
      await tester.pumpAndSettle();
      expect(fixture.writes, isEmpty);
      if (change == 'background') await resume(tester);
      expect(tester.takeException(), isNull);
    });
  }
  for (final count in [6, 11, 50, 0, 51]) {
    testWidgets(
      'plan quantity $count uses bounded individual field and preserves CAS',
      (tester) async {
        final fixture = Fixture();
        await fixture.mount(tester, editor: true, size: const Size(700, 1000));
        await tap(tester, find.text('Weiter'));
        final field = find.widgetWithText(
          TextField,
          'Aufgaben je Thema und Lerntag',
        );
        await tester.enterText(field, '$count');
        await tester.pump();
        await tap(tester, find.text('Weiter'));
        if (count < 1 || count > 50) {
          expect(
            find.text('Wähle pro Thema zwischen 1 und 50 Aufgaben je Lerntag.'),
            findsOneWidget,
          );
          expect(find.text('Schritt 2 von 4 · Themen'), findsOneWidget);
          expect(fixture.writes, isEmpty);
        } else {
          await tap(tester, find.text('Weiter'));
          await tap(tester, find.text('Plan speichern'));
          expect(fixture.writes, hasLength(1));
          final body = jsonDecode(fixture.writes.single.body);
          expect(body['topics'][0]['question_count'], count);
          expect(body['revision'], 1);
          expect(body['schedule']['dates'], ['2027-01-20']);
          expect(body['topics'][0]['material_refs'], [
            {'id': sourceId, 'revision': 1},
          ]);
          expect(fixture.writes.single.method, 'PUT');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'written-work creation needs no unrelated existing notebook topic',
    (tester) async {
      final fixture = Fixture();
      fixture.listOverride = {
        'child_id': 'child',
        'can_manage': true,
        'exams': [],
        'sources': [],
        'has_more': false,
      };
      await fixture.mount(tester, tab: 'review');
      await tap(tester, find.text('Geschriebene Arbeit hinzufügen'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Titel der Arbeit'),
        'Meine Beispielarbeit',
      );
      await tap(tester, find.text('Fach auswählen'));
      await tap(tester, find.text('Mathematik'));
      await tap(tester, find.text('Arbeit anlegen'));
      expect(fixture.writes, hasLength(1));
      final body = jsonDecode(fixture.writes.single.body);
      expect(body['purpose'], 'review');
      expect(body['topics'], isEmpty);
      expect(body['schedule']['dates'], isEmpty);
      expect(body['subject'], 'Mathematik');
      expect(fixture.writes.single.headers['Idempotency-Key'], isNotEmpty);
    },
  );
  testWidgets(
    'original answer teacher marking and AI proposal remain distinct',
    (tester) async {
      final fixture = Fixture();
      await fixture.mount(tester, selected: 'exam', tab: 'review');
      for (final label in [
        'Deine ursprüngliche Antwort',
        'Rückmeldung deiner Lehrkraft',
        'KI-Vorschlag · bitte prüfen',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Ein Viertel.'), findsOneWidget);
      expect(find.text('Bezeichnung prüfen.'), findsOneWidget);
      expect(fixture.writes, isEmpty);
      expect(
        fixture.calls.where((call) => call.url.path.endsWith('/image')),
        isEmpty,
      );
    },
  );
  testWidgets('typing is local until explicit session-private draft save', (
    tester,
  ) async {
    final fixture = Fixture();
    await fixture.mount(tester, selected: 'exam', tab: 'review');
    final field = find.widgetWithText(TextField, 'Dein Verbesserungsversuch');
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Ein Halb.');
    await tester.pump();
    expect(fixture.writes, isEmpty);
    await tap(tester, find.text('Entwurf speichern'));
    expect(fixture.writes, hasLength(1));
    final request = fixture.writes.single;
    expect(request.method, 'PUT');
    expect(request.url.path, '/api/exams/exam/review/tasks/task/draft');
    expect(jsonDecode(request.body), {
      'revision': 1,
      'context_revision': 'a' * 64,
      'draft_revision': 0,
      'text': 'Ein Halb.',
    });
  });
  testWidgets(
    'explicit help saves own attempt first and remains an AI opinion',
    (tester) async {
      final fixture = Fixture();
      await fixture.mount(tester, selected: 'exam', tab: 'review');
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Dein Verbesserungsversuch'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dein Verbesserungsversuch'),
        'Ein Halb.',
      );
      await tap(tester, find.text('Meinen Versuch ansehen lassen'));
      expect(fixture.writes.map((call) => call.method), ['PUT', 'POST']);
      expect(jsonDecode(fixture.writes.last.body)['action'], 'check');
      expect(fixture.writes.last.headers['Idempotency-Key'], isNotEmpty);
      expect(find.text('KI-Lernhilfe · keine Benotung'), findsOneWidget);
    },
  );
  testWidgets(
    'parent never receives an editable child correction or help action',
    (tester) async {
      final fixture = Fixture(role: 'parent');
      fixture.report['tasks'][0]['draft'] = {
        'text': 'Darf im Elternformular nicht erscheinen',
        'revision': 1,
      };
      await fixture.mount(tester, selected: 'exam', tab: 'review');
      expect(
        find.widgetWithText(TextField, 'Dein Verbesserungsversuch'),
        findsNothing,
      );
      expect(
        find.text('Darf im Elternformular nicht erscheinen'),
        findsNothing,
      );
      expect(find.text('Meinen Versuch ansehen lassen'), findsNothing);
      expect(fixture.writes, isEmpty);
    },
  );
  testWidgets(
    'practice requires deliberate notebook selection; cancelling is read-only',
    (tester) async {
      final fixture = Fixture();
      await fixture.mount(tester, selected: 'exam', tab: 'review');
      await tap(tester, find.text('Mit passendem Heftstoff üben'));
      expect(fixture.writes, isEmpty);
      await tap(tester, find.text('Abbrechen'));
      expect(fixture.writes, isEmpty);
      await tap(tester, find.text('Mit passendem Heftstoff üben'));
      await tap(tester, find.text('Bestätigter Heftstoff'));
      await tap(tester, find.text('Übungen bewusst vorbereiten'));
      expect(fixture.writes, hasLength(1));
      expect(jsonDecode(fixture.writes.single.body)['material_ids'], [
        sourceId,
      ]);
      expect(find.text('Job practice-job'), findsOneWidget);
    },
  );
  testWidgets(
    'source change retains a separate old draft without applying it',
    (tester) async {
      final fixture = Fixture();
      await fixture.mount(tester, selected: 'exam', tab: 'review');
      final field = find.widgetWithText(TextField, 'Dein Verbesserungsversuch');
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Mein alter Versuch');
      fixture.report = {
        ...fixture.report,
        'context_revision': 'b' * 64,
        'analysis_id': 'new-analysis',
      };
      await tap(tester, find.text('Gespeicherten Stand laden'));
      expect(
        find.text(
          'Dein vorheriger Entwurf · Quelle geändert, nicht übernommen',
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(fixture.writes, isEmpty);
    },
  );
  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('review remains operable at $size and $scale text', (
        tester,
      ) async {
        final fixture = Fixture();
        await fixture.mount(
          tester,
          selected: 'exam',
          tab: 'review',
          size: size,
          scale: scale,
        );
        final field = find.widgetWithText(
          TextField,
          'Dein Verbesserungsversuch',
        );
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, 'Eigener Versuch');
        await tester.pump();
        await tap(tester, find.text('Entwurf speichern'));
        expect(fixture.writes, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  }
  test(
    'exact local date serialization does not encode midnight as a UTC instant',
    () {
      expect(examDate(DateTime(2027, 3, 28)), '2027-03-28');
      expect(examDate(DateTime(2027, 10, 31)), '2027-10-31');
    },
  );
}
