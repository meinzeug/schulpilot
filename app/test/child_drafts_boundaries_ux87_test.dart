import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/language_workshop.dart';
import 'package:schulpilot/learning_tips.dart';
import 'package:schulpilot/material_screen.dart';

import 'child_context_forms_ux_test.dart' as form;
import 'child_sources_input_ux87_test.dart' as src;
import 'learning_tips_test.dart' as tips;
import 'learning_tips_return_test.dart' show returnedTip;

http.Response reply(Object v) => http.Response(
  jsonEncode(v),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
AppState account(Future<http.Response> Function(http.Request) h) => AppState(
  api: Api(base: 'https://example.invalid/api', client: MockClient(h)),
)..user = {'id': 'own', 'role': 'child', 'child_id': 'child'};
Future<void> tap(WidgetTester t, Finder f) async {
  await t.pumpAndSettle();
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Widget material(AppState s, Json data) => MaterialReview(
  s,
  data,
  onRefresh: () {},
  showUnitAction: false,
  simpleChild: true,
);
Future<http.Response> photoResponse(http.Request r) async =>
    r.url.path.endsWith('/image')
    ? http.Response.bytes(
        image.encodePng(image.Image(width: 2, height: 2)),
        200,
      )
    : reply({});
Json notebook({int revision = 1}) =>
    src.page('page')..addAll({'synthetic': false, 'revision': revision});
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'K065 a local correction resumes only for the same session and source',
    (t) async {
      final s = account(photoResponse);
      await t.pumpWidget(
        form.home(SingleChildScrollView(child: material(s, notebook()))),
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Etwas verbessern'));
      await t.enterText(
        form.field('Text auf der Seite'),
        'Eigene unbestätigte Korrektur',
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await t.pumpWidget(
        form.home(SingleChildScrollView(child: material(s, notebook()))),
      );
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(form.field('Text auf der Seite')).controller!.text,
        'Eigene unbestätigte Korrektur',
      );
      expect(find.textContaining('wieder aufgenommen'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      s.user = {...s.user!};
      s.refreshState();
      await t.pumpWidget(
        form.home(SingleChildScrollView(child: material(s, notebook()))),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('wieder aufgenommen'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K065 a revision conflict remains a conflict after closing and reopening the correction',
    (t) async {
      final s = account(photoResponse);
      final data = ValueNotifier<Json>(notebook());
      addTearDown(data.dispose);
      Widget page() => form.home(
        ValueListenableBuilder<Json>(
          valueListenable: data,
          builder: (_, value, _) =>
              SingleChildScrollView(child: material(s, value)),
        ),
      );
      await t.pumpWidget(page());
      await t.pumpAndSettle();
      await tap(t, find.text('Etwas verbessern'));
      await t.enterText(
        form.field('Text auf der Seite'),
        'Alte eigene Korrektur',
      );
      data.value = notebook(revision: 2);
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await t.pumpWidget(page());
      await t.pumpAndSettle();
      expect(find.text('Gespeicherte Seite laden'), findsOneWidget);
      expect(find.text('Alte eigene Korrektur'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K066 an oversized correction is preserved with a local limit error and sends no confirmation',
    (t) async {
      final calls = <http.Request>[];
      final s = account((r) async {
        calls.add(r);
        return photoResponse(r);
      });
      await t.pumpWidget(
        form.home(SingleChildScrollView(child: material(s, notebook()))),
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Etwas verbessern'));
      final long = List.filled(24001, 'a').join();
      await t.enterText(form.field('Text auf der Seite'), long);
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await tap(t, find.text('Stimmt, weiter'));
      expect(find.textContaining('24.000 Zeichen'), findsOneWidget);
      expect(
        t.widget<TextField>(form.field('Text auf der Seite')).controller!.text,
        long,
      );
      expect(calls.where((r) => r.method != 'GET'), isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K105 switching accounts closes a private task-preview route without confirming',
    (t) async {
      final requests = <http.Request>[];
      final s = account((r) async {
        requests.add(r);
        if (r.url.path.endsWith('/task-preview')) {
          return reply({
            'items': [
              {
                'key': 'a' * 24,
                'classification': 'homework',
                'text': 'Private künstliche Aufgabe',
              },
            ],
            'duplicates': [],
          });
        }
        return photoResponse(r);
      });
      final data = notebook()..['supports_task_confirmation'] = true;
      await t.pumpWidget(
        form.home(SingleChildScrollView(child: material(s, data))),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Stimmt, weiter'));
      await t.tap(find.text('Stimmt, weiter'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Was ist wirklich aufgegeben?'), findsOneWidget);
      s.user = {...s.user!};
      s.refreshState();
      await t.pumpAndSettle();
      expect(find.text('Was ist wirklich aufgegeben?'), findsNothing);
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K087 web-style explicit opening starts no URL before the second real click',
    (t) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      var launches = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') launches++;
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      bool? opened;
      await t.pumpWidget(
        src.home(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                opened = await openSofatutor(
                  context,
                  'https://www.sofatutor.com/mathematik/videos/test',
                  deferToExplicitClick: true,
                );
              },
              child: const Text('Vorbereiten'),
            ),
          ),
        ),
      );
      await tap(t, find.text('Vorbereiten'));
      expect(launches, 0);
      expect(opened, isNull);
      await tap(t, find.text('Jetzt bei Sofatutor öffnen'));
      expect(launches, 1);
      expect(opened, isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P91 successful explicit fallback reports an open attempt instead of false',
    (t) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      var launches = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launches++;
          return launches > 1;
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      bool? opened;
      await t.pumpWidget(
        src.home(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                opened = await openSofatutor(
                  context,
                  'https://www.sofatutor.com/mathematik/videos/test',
                );
              },
              child: const Text('Öffnen'),
            ),
          ),
        ),
      );
      await tap(t, find.text('Öffnen'));
      expect(launches, 1);
      await tap(t, find.text('Noch einmal öffnen'));
      expect(launches, 2);
      expect(opened, isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K089 a changed resource during check eligibility never posts a new check',
    (t) async {
      final pending = Completer<http.Response>();
      var posts = 0;
      final s = account((r) async {
        if (r.method == 'POST') posts++;
        if (r.url.path.endsWith('/learning-session')) return pending.future;
        return reply(returnedTip()..['media_return']['check_available'] = true);
      });
      Widget panel(String id) => src.home(
        LearningTips(
          s,
          childId: 'child',
          kind: 'unit',
          resourceId: id,
          initiallyExpanded: true,
        ),
      );
      await t.pumpWidget(panel('first'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Mit 2 neuen Aufgaben prüfen'));
      await t.tap(find.text('Mit 2 neuen Aufgaben prüfen'));
      await t.pump();
      await t.pumpWidget(panel('second'));
      await t.pump();
      pending.complete(
        reply({'revision': 1, 'can_request_support_check': true}),
      );
      await t.pumpAndSettle();
      expect(posts, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P89 a twelve-item preview explicitly labels further available resources',
    (t) async {
      final s = account(
        (_) async => reply(
          tips.tips()
            ..['recommended'] = List.generate(12, (i) => tips.content(i)),
        ),
      );
      await t.pumpWidget(
        src.home(
          LearningTips(
            s,
            childId: 'child',
            kind: 'material',
            resourceId: 'page',
            initiallyExpanded: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Weitere anzeigen'));
      expect(
        find.text(
          'Hier siehst du höchstens 12 Lerntipps. Wähle ein Thema, um gezielter zu suchen.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TipContentCard), findsNWidgets(12));
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K045 mode default changes purpose, while a personally edited goal survives',
    (t) async {
      final s = account(
        (r) async => reply(
          r.url.path.contains('vocabulary')
              ? {'items': <Json>[]}
              : r.url.path.contains('materials')
              ? {'items': <Json>[]}
              : {'projects': <Json>[], 'has_more': false},
        ),
      );
      await t.pumpWidget(form.home(LanguageWorkshop(s, childId: 'child')));
      await t.pumpAndSettle();
      final mode = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Was möchtest du üben?',
      );
      t.widget<DropdownButtonFormField<String>>(mode).onChanged!('summary');
      await t.pump();
      expect(
        t
            .widget<TextField>(form.field('Dein konkretes Lernziel'))
            .controller!
            .text,
        workshopGoal('summary'),
      );
      await t.enterText(
        form.field('Dein konkretes Lernziel'),
        'Mein eigenes Ziel',
      );
      t.widget<DropdownButtonFormField<String>>(mode).onChanged!('translation');
      await t.pump();
      expect(
        t
            .widget<TextField>(form.field('Dein konkretes Lernziel'))
            .controller!
            .text,
        'Mein eigenes Ziel',
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K043 workshop text and validated choices resume without new generation',
    (t) async {
      final requests = <http.Request>[];
      final s = account((r) async {
        requests.add(r);
        return reply(
          r.url.path.contains('vocabulary')
              ? {
                  'items': [
                    {'id': 'one', 'word': 'apple'},
                  ],
                }
              : r.url.path.contains('materials')
              ? {'items': <Json>[]}
              : {'projects': <Json>[], 'has_more': false},
        );
      });
      Widget page() => form.home(LanguageWorkshop(s, childId: 'child'));
      await t.pumpWidget(page());
      await t.pumpAndSettle();
      await t.enterText(
        form.field('Dein konkretes Lernziel'),
        'Mein selbst geschriebenes Lernziel',
      );
      await tap(t, find.widgetWithText(FilterChip, 'apple'));
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await t.pumpWidget(page());
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(form.field('Dein konkretes Lernziel'))
            .controller!
            .text,
        'Mein selbst geschriebenes Lernziel',
      );
      expect(
        t.widget<FilterChip>(find.widgetWithText(FilterChip, 'apple')).selected,
        isTrue,
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K042 later word and source pages remain reachable through bounded GETs',
    (t) async {
      final requests = <http.Request>[];
      final s = account((r) async {
        requests.add(r);
        return reply(
          r.url.path.contains('vocabulary')
              ? {
                  'items': [
                    {
                      'id': r.url.queryParameters['page'] == '2'
                          ? 'later'
                          : 'first',
                      'word': r.url.queryParameters['page'] == '2'
                          ? 'later word'
                          : 'first word',
                    },
                  ],
                  'pagination': {'total': 51},
                }
              : r.url.path.contains('materials')
              ? {
                  'items': <Json>[],
                  'pagination': {'total': 51},
                }
              : {'projects': <Json>[], 'has_more': false},
        );
      });
      await t.pumpWidget(form.home(LanguageWorkshop(s, childId: 'child')));
      await t.pumpAndSettle();
      await tap(t, find.byTooltip('Weitere Wörter'));
      expect(find.text('later word'), findsOneWidget);
      await tap(t, find.byTooltip('Weitere Heftseiten'));
      expect(
        requests.any(
          (r) =>
              r.url.path.endsWith('/materials') &&
              r.url.queryParameters['page'] == '2',
        ),
        isTrue,
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P86 applying an explicit empty topic selection sends an empty revision-bound PUT',
    (t) async {
      final writes = <http.Request>[];
      final s = account((r) async {
        if (r.method == 'PUT') {
          writes.add(r);
          return reply(tips.tips()..['topics'] = []);
        }
        if (r.url.path.endsWith('/topics')) {
          return reply({
            'items': <Json>[],
            'total': 0,
            'subject': {'title': 'Mathematik'},
          });
        }
        return reply(tips.tips());
      });
      await t.pumpWidget(
        src.home(
          LearningTips(
            s,
            childId: 'child',
            kind: 'material',
            resourceId: 'page',
            initiallyExpanded: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Thema auswählen'));
      t
          .widget<InputChip>(find.widgetWithText(InputChip, 'Brüche addieren'))
          .onDeleted!();
      await t.pump();
      await tap(t, find.text('Keine Themen übernehmen'));
      expect(writes, hasLength(1));
      expect(jsonDecode(writes.single.body), {
        'revision': 1,
        'topic_ids': [],
        'confirmed': true,
      });
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K065 closing a correction then logging out clears its private RAM entry immediately',
    (t) async {
      final s = account(photoResponse);
      await t.pumpWidget(
        form.home(SingleChildScrollView(child: material(s, notebook()))),
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Etwas verbessern'));
      await t.enterText(
        form.field('Text auf der Seite'),
        'Private lokale Korrektur',
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(
        s.collectionViews.keys.where((k) => k.startsWith('source_correction:')),
        isNotEmpty,
      );
      await s.clear(expectedUser: s.user);
      expect(s.collectionViews, isEmpty);
      expect(s.user, isNull);
    },
  );
  testWidgets(
    'K105 a newer source revision closes only the old private task-preview route',
    (t) async {
      final s = account((r) async {
        if (r.url.path.endsWith('/task-preview')) {
          return reply({
            'items': [
              {
                'key': 'a' * 24,
                'classification': 'homework',
                'text': 'Alte Aufgabe',
              },
            ],
            'duplicates': [],
          });
        }
        return photoResponse(r);
      });
      final source = ValueNotifier<Json>(
        notebook()..['supports_task_confirmation'] = true,
      );
      addTearDown(source.dispose);
      await t.pumpWidget(
        form.home(
          ValueListenableBuilder<Json>(
            valueListenable: source,
            builder: (_, d, _) => SingleChildScrollView(child: material(s, d)),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Stimmt, weiter'));
      await t.tap(find.text('Stimmt, weiter'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Was ist wirklich aufgegeben?'), findsOneWidget);
      source.value = notebook(revision: 2)
        ..['supports_task_confirmation'] = true;
      await t.pumpAndSettle();
      expect(find.text('Was ist wirklich aufgegeben?'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
}
