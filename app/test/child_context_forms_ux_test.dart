import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsAction;

import 'package:image/image.dart' as image;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/language_workshop.dart';
import 'package:schulpilot/learning_preparation_screen.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/school_day_history.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
AppState account(MockClient client) => AppState(
  api: Api(base: 'https://example.invalid/api', client: client),
)..user = {'id': 'child-user', 'role': 'child', 'child_id': 'child'};
Widget home(Widget child) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: child),
      ),
    ],
  );
  addTearDown(router.dispose);
  return MaterialApp.router(theme: appTheme(), routerConfig: router);
}

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Json word(String id, String name) => {'id': id, 'word': name};
Json page(String id, String text, {int revision = 1}) => {
  'id': id,
  'child_id': 'child',
  'subject': 'Mathematik',
  'topic': 'Künstliches Thema',
  'content': text,
  'homework': [],
  'uncertainties': [],
  'revision': revision,
  'confirmed': false,
  'status': 'review',
  'synthetic': true,
};
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('K046 K048 history is single-flight and merges overlapping pages', (
    tester,
  ) async {
    final next = Completer<http.Response>();
    var gets = 0;
    Json day(String id) => {
      'id': id,
      'date': id == 'one' ? '2026-10-20' : '2026-10-19',
      'subjects': ['Mathematik'],
      'page_count': 1,
      'completed_units': 0,
      'unit_count': 1,
    };
    final state = account(
      MockClient((r) async {
        gets++;
        return r.url.hasQuery
            ? next.future
            : reply({
                'days': [day('one')],
                'next_before': 'one',
              });
      }),
    );
    await tester.pumpWidget(home(SchoolDayHistory(state, childId: 'child')));
    await tester.pumpAndSettle();
    final button = tester.widget<ActionButton>(find.byType(ActionButton));
    button.onPressed();
    button.onPressed();
    await flush(tester);
    expect(gets, 2);
    next.complete(
      reply({
        'days': [day('one'), day('two')],
        'next_before': null,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ActionPanel), findsNWidgets(2));
    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      for (var index = 0; index < 2; index++) {
        final card = find.byType(ActionPanel).at(index);
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        final data = tester.getSemantics(card).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(
          data.label,
          contains(
            'Tagespaket vom ${index == 0 ? '20.10.2026' : '19.10.2026'} öffnen',
          ),
        );
      }
    } finally {
      semantics.dispose();
    }
    expect(gets, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'K032 K047 history rejects old child results and same-ID re-login',
    (tester) async {
      final old = Completer<http.Response>();
      final target = ValueNotifier('old');
      addTearDown(target.dispose);
      final state = account(
        MockClient(
          (r) async => r.url.path.contains('/old/')
              ? old.future
              : reply({
                  'days': [
                    {
                      'id': 'newday',
                      'date': '2026-10-21',
                      'subjects': ['Neues Fach'],
                      'page_count': 1,
                      'unit_count': 0,
                      'completed_units': 0,
                    },
                  ],
                  'next_before': null,
                }),
        ),
      );
      await tester.pumpWidget(
        home(
          ValueListenableBuilder<String>(
            valueListenable: target,
            builder: (_, id, _) => SchoolDayHistory(state, childId: id),
          ),
        ),
      );
      await tester.pump();
      target.value = 'new';
      await tester.pumpAndSettle();
      old.complete(
        reply({
          'days': [
            {
              'id': 'private',
              'date': '2026-10-10',
              'subjects': ['Altes Fach'],
              'page_count': 1,
              'unit_count': 0,
              'completed_units': 0,
            },
          ],
          'next_before': null,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Altes Fach'), findsNothing);
      expect(find.textContaining('Neues Fach'), findsOneWidget);
      state.user = {...state.user!};
      state.notifyListeners();
      await tester.pump();
      expect(find.textContaining('Neues Fach'), findsNothing);
    },
  );
  testWidgets('K049 K050 day dates and loading status are child-readable', (
    tester,
  ) async {
    final waiting = Completer<http.Response>();
    final state = account(MockClient((_) async => waiting.future));
    await tester.pumpWidget(home(SchoolDayHistory(state, childId: 'child')));
    await tester.pump();
    expect(find.text('Schultage werden geladen …'), findsOneWidget);
    waiting.complete(
      reply({
        'days': [
          {
            'id': 'day',
            'date': '2026-10-20',
            'subjects': [],
            'page_count': 0,
            'unit_count': 0,
            'completed_units': 0,
          },
        ],
        'next_before': null,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026-10-20'), findsNothing);
    expect(find.text(schoolDate('2026-10-20')), findsOneWidget);
  });
  testWidgets('K052 preparation hides private job immediately after re-login', (
    tester,
  ) async {
    final state = account(
      MockClient(
        (_) async => reply({
          'kind': 'unit',
          'status': 'failed',
          'error': 'Privater synthetischer Jobfehler',
        }),
      ),
    );
    await tester.pumpWidget(
      home(LearningPreparationScreen(state, childId: 'child', jobId: 'job')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Privater synthetischer Jobfehler'), findsOneWidget);
    state.user = {...state.user!};
    state.notifyListeners();
    await tester.pump();
    expect(find.text('Privater synthetischer Jobfehler'), findsNothing);
  });
  testWidgets(
    'K053 failed preparation offers saved rounds without new generation',
    (tester) async {
      final requests = <http.Request>[];
      final state = account(
        MockClient((r) async {
          requests.add(r);
          return reply({
            'kind': 'unit',
            'status': 'failed',
            'error': 'Nicht vorbereitet',
          });
        }),
      );
      await tester.pumpWidget(
        home(LearningPreparationScreen(state, childId: 'child', jobId: 'job')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gespeicherte Runden ansehen'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets('K054 queued preparation names the actual waiting state', (
    tester,
  ) async {
    final state = account(
      MockClient((_) async => reply({'kind': 'unit', 'status': 'queued'})),
    );
    await tester.pumpWidget(
      home(LearningPreparationScreen(state, childId: 'child', jobId: 'job')),
    );
    await flush(tester);
    expect(
      find.text('Deine Vorbereitung wartet auf ihren Start.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('K055 material controllers follow a different saved source', (
    tester,
  ) async {
    final source = ValueNotifier<Json>(page('one', 'Erster Text'));
    addTearDown(source.dispose);
    final state = account(MockClient((_) async => reply({})));
    await tester.pumpWidget(
      home(
        ValueListenableBuilder<Json>(
          valueListenable: source,
          builder: (_, data, _) => SingleChildScrollView(
            child: MaterialReview(
              state,
              data,
              simpleChild: true,
              showUnitAction: false,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Erster Text'), findsOneWidget);
    source.value = page('two', 'Zweiter Text');
    await tester.pumpAndSettle();
    expect(find.text('Erster Text'), findsNothing);
    expect(find.text('Zweiter Text'), findsOneWidget);
  });
  testWidgets('K055 an unedited material adopts a newer confirmed revision', (
    tester,
  ) async {
    final source = ValueNotifier<Json>(page('one', 'Erste Fassung'));
    addTearDown(source.dispose);
    final state = account(MockClient((_) async => reply({})));
    await tester.pumpWidget(
      home(
        ValueListenableBuilder<Json>(
          valueListenable: source,
          builder: (_, data, _) => SingleChildScrollView(
            child: MaterialReview(
              state,
              data,
              simpleChild: true,
              showUnitAction: false,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    source.value = page('one', 'Neue Fassung', revision: 2);
    await tester.pumpAndSettle();
    expect(find.text('Erste Fassung'), findsNothing);
    expect(find.text('Neue Fassung'), findsOneWidget);
  });
  testWidgets('K035 workshop goal immediately updates enabled creation state', (
    tester,
  ) async {
    final state = account(
      MockClient(
        (r) async => reply(
          r.url.path.endsWith('/vocabulary')
              ? {
                  'items': [word('one', 'school')],
                }
              : r.url.path.endsWith('/materials')
              ? {'items': []}
              : {'projects': [], 'has_more': false},
        ),
      ),
    );
    await tester.pumpWidget(home(LanguageWorkshop(state, childId: 'child')));
    await tester.pumpAndSettle();
    await tap(tester, find.text('school'));
    await tester.enterText(field('Dein konkretes Lernziel'), '');
    await tester.pump();
    FilledButton button() => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Mein Lernprojekt vorbereiten'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button().onPressed, isNull);
    expect(
      find.text('Beschreibe dein Lernziel mit mindestens 3 Zeichen.'),
      findsOneWidget,
    );
    await tester.enterText(
      field('Dein konkretes Lernziel'),
      'Eigene Wörter üben',
    );
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });
  testWidgets(
    'K034 a language change does not expose old words as new choices',
    (tester) async {
      final french = Completer<http.Response>();
      final state = account(
        MockClient((r) async {
          if (r.url.path.endsWith('/vocabulary')) {
            return r.url.queryParameters['locale'] == 'fr-FR'
                ? french.future
                : reply({
                    'items': [word('one', 'school')],
                  });
          }
          return reply(
            r.url.path.endsWith('/materials')
                ? {'items': []}
                : {'projects': [], 'has_more': false},
          );
        }),
      );
      await tester.pumpWidget(home(LanguageWorkshop(state, childId: 'child')));
      await tester.pumpAndSettle();
      expect(find.text('school'), findsOneWidget);
      tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .first
          .onChanged!('fr-FR');
      await flush(tester);
      expect(find.text('school'), findsNothing);
      french.complete(
        reply({
          'items': [word('two', 'école')],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('école'), findsOneWidget);
    },
  );
  testWidgets(
    'K036 writing mode reveals existing draft editor on mode change',
    (tester) async {
      final state = account(
        MockClient(
          (r) async => reply(
            r.url.path.endsWith('/vocabulary') ||
                    r.url.path.endsWith('/materials')
                ? {'items': []}
                : {'projects': [], 'has_more': false},
          ),
        ),
      );
      await tester.pumpWidget(home(LanguageWorkshop(state, childId: 'child')));
      await tester.pumpAndSettle();
      expect(field('Schreibe zuerst deinen Versuch'), findsNothing);
      tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .elementAt(1)
          .onChanged!('writing_feedback');
      await tester.pumpAndSettle();
      expect(field('Schreibe zuerst deinen Versuch'), findsOneWidget);
    },
  );
  testWidgets(
    'K037 K040 project response uses rich content and empty continuation cannot send',
    (tester) async {
      final requests = <http.Request>[];
      final state = account(
        MockClient((r) async {
          requests.add(r);
          return reply({
            'id': 'project',
            'mode': 'dialog',
            'target_locale': 'en-GB',
            'status': 'ready',
            'goal': 'Eigene Wörter üben',
            'step': 1,
            'can_continue': true,
            'result': {
              'response': '## Deine Lernhilfe\n\nEin eigener Satz.',
              'criteria': [],
            },
          });
        }),
      );
      await tester.pumpWidget(
        home(LanguageWorkshop(state, childId: 'child', projectId: 'project')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('## Deine Lernhilfe\n\nEin eigener Satz.'),
        findsNothing,
      );
      expect(find.text('Deine Lernhilfe'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Nächster Gesprächsschritt'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await tester.enterText(
        field('Schreibe selbst weiter'),
        'My own sentence.',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Nächster Gesprächsschritt'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'K055 a local correction survives a newer source until explicit reload',
    (tester) async {
      final source = ValueNotifier<Json>({
        ...page('one', 'Erste Fassung'),
        'synthetic': false,
      });
      addTearDown(source.dispose);
      final bytes = image.encodePng(image.Image(width: 2, height: 2));
      final requests = <http.Request>[];
      final state = account(
        MockClient((request) async {
          requests.add(request);
          return request.url.path.endsWith('/image')
              ? http.Response.bytes(bytes, 200)
              : reply({});
        }),
      );
      await tester.pumpWidget(
        home(
          ValueListenableBuilder<Json>(
            valueListenable: source,
            builder: (_, data, _) => SingleChildScrollView(
              child: MaterialReview(
                state,
                data,
                simpleChild: true,
                showUnitAction: false,
                onRefresh: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Etwas verbessern'));
      await tester.enterText(
        field('Text auf der Seite'),
        'Meine eigene OCR-Korrektur',
      );
      await tester.pump();
      source.value = {
        ...page('one', 'Neu gespeicherte Fassung', revision: 2),
        'synthetic': false,
      };
      await tester.pumpAndSettle();
      expect(find.text('Meine eigene OCR-Korrektur'), findsOneWidget);
      expect(find.textContaining('inzwischen geändert'), findsOneWidget);
      expect(find.text('Stimmt, weiter'), findsNothing);
      await tap(tester, find.text('Gespeicherte Seite laden'));
      expect(find.text('Meine eigene OCR-Korrektur'), findsNothing);
      expect(find.text('Neu gespeicherte Fassung'), findsWidgets);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'a material response arriving after new same-ID login is hidden',
    (tester) async {
      final pending = Completer<http.Response>();
      final state = account(MockClient((_) async => pending.future));
      await tester.pumpWidget(home(MaterialScreen(state, materialId: 'one')));
      await tester.pump();
      state.user = {...state.user!};
      state.notifyListeners();
      await tester.pump();
      pending.complete(
        reply(page('one', 'Privater Text der vorherigen Sitzung')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Privater Text der vorherigen Sitzung'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'K033 changing project restores separate draft and rejects the old continue callback',
    (tester) async {
      final selectedProject = ValueNotifier('one');
      addTearDown(selectedProject.dispose);
      var posts = 0;
      final state = account(
        MockClient((request) async {
          if (request.method == 'POST') posts++;
          final id = request.url.pathSegments.last;
          return reply({
            'id': id,
            'mode': 'dialog',
            'target_locale': 'en-GB',
            'status': 'ready',
            'goal': 'Projekt $id',
            'step': 1,
            'can_continue': true,
            'result': {'response': 'Lernhilfe $id', 'criteria': []},
          });
        }),
      );
      await tester.pumpWidget(
        home(
          ValueListenableBuilder<String>(
            valueListenable: selectedProject,
            builder: (_, id, _) =>
                LanguageWorkshop(state, childId: 'child', projectId: id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        field('Schreibe selbst weiter'),
        'Eigener Text für das erste Projekt',
      );
      await tester.pump();
      final stale = tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Nächster Gesprächsschritt'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed!;
      selectedProject.value = 'two';
      await tester.pumpAndSettle();
      stale();
      await tester.pumpAndSettle();
      expect(find.text('Projekt two'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(field('Schreibe selbst weiter'))
            .controller!
            .text,
        isEmpty,
      );
      expect(posts, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'K038 selecting an eleventh workshop word gives a bounded useful response',
    (tester) async {
      var posts = 0;
      final state = account(
        MockClient((request) async {
          if (request.method == 'POST') posts++;
          return reply(
            request.url.path.endsWith('/vocabulary')
                ? {
                    'items': [
                      for (var i = 1; i <= 11; i++) word('word$i', 'Wort $i'),
                    ],
                  }
                : request.url.path.endsWith('/materials')
                ? {'items': []}
                : {'projects': [], 'has_more': false},
          );
        }),
      );
      await tester.pumpWidget(home(LanguageWorkshop(state, childId: 'child')));
      await tester.pumpAndSettle();
      expect(
        find.text('Wähle zuerst mindestens ein bestätigtes Wort aus.'),
        findsOneWidget,
      );
      for (var i = 0; i < 10; i++) {
        tester
            .widgetList<FilterChip>(find.byType(FilterChip))
            .elementAt(i)
            .onSelected!(true);
        await tester.pump();
      }
      tester.widgetList<FilterChip>(find.byType(FilterChip)).last.onSelected!(
        true,
      );
      await tester.pump();
      expect(
        find.textContaining('10 von höchstens 10 ausgewählt'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Du hast schon 10 Wörter ausgewählt.'),
        findsOneWidget,
      );
      expect(
        tester.widgetList<FilterChip>(find.byType(FilterChip)).last.selected,
        isFalse,
      );
      expect(posts, 0);
    },
  );
  testWidgets(
    'K041 pending workshop explains saved continuation without generating again',
    (tester) async {
      final requests = <http.Request>[];
      final state = account(
        MockClient((request) async {
          requests.add(request);
          return reply({
            'id': 'project',
            'mode': 'dialog',
            'target_locale': 'en-GB',
            'status': 'queued',
            'goal': 'Gespeichertes Projekt',
            'step': 1,
            'can_continue': false,
          });
        }),
      );
      await tester.pumpWidget(
        home(LanguageWorkshop(state, childId: 'child', projectId: 'project')),
      );
      await flush(tester);
      expect(
        find.text(
          'Dein Lernprojekt bleibt gespeichert. Du kannst später hier weitermachen.',
        ),
        findsOneWidget,
      );
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
