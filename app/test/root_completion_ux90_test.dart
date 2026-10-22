import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/language_workshop.dart';

import 'vocabulary_test.dart' as words;
import 'root_vocabulary_ux90_test.dart' as vocab;
import 'root_word_review_ux90_test.dart' as review;
import 'root_collections_ux90_test.dart' as collections;
import 'root_workshop_ux90_test.dart' as workshop;
import 'child_local_tools_ux88_test.dart' as local;
import 'language_retry_test.dart' as project;

Future<void> visible(WidgetTester t, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      finder,
      150,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
  }
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await visible(t, finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> browser(
  WidgetTester t,
  List<http.Request> calls,
  Future<http.Response> Function(http.Request) handler,
) async {
  await words.open(t, calls, respond: handler, width: 390);
  await vocab.tools(t);
  await tap(t, find.text('Alle Sammlungen finden'));
}

http.Response collectionPage(http.Request q, {int total = 41, String? name}) =>
    words.reply({
      'items': [
        collections.group(
          'one',
          name ?? 'Sammlung auf Seite ${q.url.queryParameters['page']}',
          37,
        ),
      ],
      'pagination': {
        'page': int.parse(q.url.queryParameters['page'] ?? '1'),
        'page_size': 20,
        'total': total,
      },
      'filters': {
        'locale': q.url.queryParameters['locale'],
        'search': q.url.queryParameters['search'] ?? '',
        'sort': q.url.queryParameters['sort'] ?? 'name',
      },
    });
Future<http.Response> collectionHandler(http.Request q) async =>
    q.method == 'GET' && q.url.path.endsWith('/collections')
    ? collectionPage(q)
    : collections.regular(q);
void main() {
  testWidgets(
    'RQ023 pending word confirmation cannot be dismissed or sent twice',
    (t) async {
      final calls = <http.Request>[];
      final pending = Completer<http.Response>();
      await review.open(
        t,
        calls,
        handle: (q) async => q.url.path.endsWith('/confirm')
            ? pending.future
            : review.regular(q),
      );
      await tap(t, find.text('Stimmt').first);
      await visible(t, find.text('Stimmt, Wörter speichern'));
      await t.tap(find.text('Stimmt, Wörter speichern'));
      await t.pump();
      final context = t.element(find.text('Stimmen deine Wörter?'));
      await Navigator.of(context).maybePop();
      await t.pump();
      expect(find.text('Stimmen deine Wörter?'), findsOneWidget);
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Später prüfen'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Speichern …'),
            )
            .onPressed,
        isNull,
      );
      expect(calls.where((q) => q.url.path.endsWith('/confirm')), hasLength(1));
      pending.complete(words.reply({'status': 'confirmed'}));
      await t.pumpAndSettle();
      expect(find.text('Stimmen deine Wörter?'), findsNothing);
    },
  );
  testWidgets(
    'RQ024 an explicitly selected empty meaning remains local and editable before confirmation',
    (t) async {
      final calls = <http.Request>[];
      final data = review.review();
      data['pairs'][0]['meaning'] = '';
      await review.open(
        t,
        calls,
        handle: (q) async => q.url.path.endsWith('/imports')
            ? words.reply({
                'imports': [data],
              })
            : q.url.path.endsWith('/imports/import')
            ? words.reply(data)
            : review.regular(q),
      );
      await tap(t, find.text('Stimmt').first);
      await tap(t, find.text('Stimmt, Wörter speichern'));
      expect(
        find.text(
          'Bitte Wort und Bedeutung ergänzen, bevor du dieses Paar bestätigst.',
        ),
        findsOneWidget,
      );
      expect(calls.where((q) => q.method == 'POST'), isEmpty);
      expect(find.text('Stimmen deine Wörter?'), findsOneWidget);
    },
  );
  testWidgets(
    'RQ025 unexpected vocabulary errors show a neutral retry message instead of exception text',
    (t) async {
      final calls = <http.Request>[];
      await words.open(
        t,
        calls,
        respond: (q) async {
          if (q.url.path.endsWith('/vocabulary')) {
            return http.Response(
              '["PRIVATE-SYNTHETIC-DIAGNOSTIC"]',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return words.reply({'imports': []});
        },
      );
      expect(
        find.text(
          'Die Wörter konnten gerade nicht geladen werden. Bitte versuche es erneut.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE-SYNTHETIC-DIAGNOSTIC'), findsNothing);
      expect(calls.where((q) => q.method != 'GET'), isEmpty);
    },
  );
  testWidgets(
    'RQ058 collection removal scope contains the actual selected word count',
    (t) async {
      final calls = <http.Request>[];
      await words.open(
        t,
        calls,
        respond: (q) async => q.url.path.endsWith('/vocabulary')
            ? words.reply({
                ...collections.listing(),
                'collections': [collections.group('one', 'Schulwörter', 37)],
              })
            : collections.regular(q),
      );
      await collections.choose(t);
      await vocab.tools(t);
      await tap(t, find.text('Sammlung entfernen'));
      expect(
        find.textContaining('„Schulwörter“ enthält 37 Wörter.'),
        findsOneWidget,
      );
      expect(calls.where((q) => q.method == 'DELETE'), isEmpty);
    },
  );
  testWidgets(
    'RQ059 workshop alphabet choice actually reorders reverse supplied words locally',
    (t) async {
      final calls = <http.Request>[];
      final state = local.account((q) async {
        calls.add(q);
        if (q.url.path.endsWith('/vocabulary')) {
          return local.reply({
            'items': [
              {'id': 'z', 'word': 'zebra', 'meaning': 'Zebra'},
              {'id': 'a', 'word': 'apple', 'meaning': 'Apfel'},
            ],
            'pagination': {'total': 2},
          });
        }
        if (q.url.path.endsWith('/materials')) {
          return local.reply({
            'items': [],
            'pagination': {'total': 0},
          });
        }
        return local.reply({'projects': [], 'has_more': false});
      });
      await local.show(t, LanguageWorkshop(state, childId: 'child'));
      await tap(t, workshop.picker('Geladene Wörter ordnen'));
      await tap(t, find.text('Alphabetisch auf dieser Seite').last);
      final chips = t
          .widgetList<FilterChip>(find.byType(FilterChip))
          .map((w) => (w.label as Text).data)
          .where((s) => ['apple', 'zebra'].contains(s))
          .toList();
      expect(chips, ['apple', 'zebra']);
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ084 collection browser next and previous use server pages without writes',
    (t) async {
      final calls = <http.Request>[];
      await browser(t, calls, collectionHandler);
      await tap(t, find.byTooltip('Weitere Sammlungen'));
      expect(calls.last.url.queryParameters['page'], '2');
      expect(find.text('Sammlung auf Seite 2'), findsOneWidget);
      await tap(t, find.byTooltip('Vorherige Sammlungen'));
      expect(calls.last.url.queryParameters['page'], '1');
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ085 collection search keeps the submitted snapshot while new text is typed',
    (t) async {
      final calls = <http.Request>[];
      final pending = Completer<http.Response>();
      http.Request? submitted;
      await browser(t, calls, (q) async {
        if (q.url.path.endsWith('/collections') &&
            q.url.queryParameters['search'] == 'erster') {
          submitted = q;
          return pending.future;
        }
        return collectionHandler(q);
      });
      final field = vocab.input('Alle Sammlungen dieser Sprache durchsuchen');
      await t.enterText(field, 'erster');
      await visible(t, find.text('Sammlungen suchen'));
      await t.tap(find.text('Sammlungen suchen'));
      await t.pump();
      await t.enterText(field, 'zweiter');
      expect(submitted, isNotNull);
      pending.complete(
        collectionPage(submitted!, name: 'Erster gespeicherter Treffer'),
      );
      await t.pumpAndSettle();
      expect(find.text('Erster gespeicherter Treffer'), findsOneWidget);
      expect(t.widget<TextField>(field).controller!.text, 'zweiter');
      expect(
        find.textContaining('auf dem Server noch nicht verfügbar'),
        findsNothing,
      );
      expect(
        calls.where((q) => q.url.queryParameters['search'] == 'zweiter'),
        isEmpty,
      );
    },
  );
  testWidgets(
    'RQ086 collection sort submits a fresh first-page request with real criterion',
    (t) async {
      final calls = <http.Request>[];
      await browser(t, calls, collectionHandler);
      await tap(t, collections.picker('Sammlungen ordnen'));
      await tap(t, find.text('Zuletzt angelegt').last);
      expect(calls.last.url.queryParameters['sort'], 'newest');
      expect(calls.last.url.queryParameters['page'], '1');
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ101 saved own project draft is copied exactly after explicit clipboard action',
    (t) async {
      final calls = <http.Request>[];
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'];
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final state = local.account((q) async {
        calls.add(q);
        return local.reply({
          ...project.project(true),
          'draft': 'My own synthetic school text.',
        });
      });
      await local.show(
        t,
        LanguageWorkshop(state, childId: 'child', projectId: 'project'),
      );
      await tap(t, find.text('Mein gespeicherter Versuch'));
      expect(copied, isNull);
      await tap(t, find.text('Eigenen Versuch kopieren'));
      expect(copied, 'My own synthetic school text.');
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ104 confirmed import archive exposes its exact historical pairs without correcting current words',
    (t) async {
      final calls = <http.Request>[];
      final data = review.review()..['status'] = 'confirmed';
      await words.open(
        t,
        calls,
        parent: true,
        respond: (q) async => q.url.path.endsWith('/imports')
            ? words.reply({
                'imports': [data],
                'pagination': {'page': 1, 'page_size': 20, 'total': 1},
                'filters': {
                  'status': q.url.queryParameters['status'],
                  'search': q.url.queryParameters['search'] ?? '',
                },
                'supports_import_browser': true,
              })
            : q.url.path.endsWith('/imports/import')
            ? words.reply(data)
            : review.regular(q),
      );
      await tap(t, find.text('Alle Wortlisten finden'));
      await tap(t, collections.picker('Stand der Wortlisten'));
      await tap(t, find.text('Bereits übernommen').last);
      await tap(t, find.text('Meine offenen Vorschläge').last);
      expect(find.text('apple = Apfel'), findsOneWidget);
      expect(find.text('dog = Hund'), findsOneWidget);
      expect(
        find.textContaining(
          'Spätere Wortkorrekturen siehst du im aktuellen Wortschatz',
        ),
        findsOneWidget,
      );
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  for (final scenario in [('RQ105', 'status'), ('RQ106', 'search')]) {
    testWidgets(
      '${scenario.$1} import archive criterion is an actual bounded metadata GET',
      (t) async {
        final calls = <http.Request>[];
        await words.open(
          t,
          calls,
          parent: true,
          respond: (q) async {
            if (q.url.path.endsWith('/imports') &&
                q.url.queryParameters['status'] != null) {
              return words.reply({
                'imports': [],
                'pagination': {'page': 1, 'page_size': 20, 'total': 0},
                'filters': {
                  'status': q.url.queryParameters['status'],
                  'search': q.url.queryParameters['search'] ?? '',
                },
                'supports_import_browser': true,
              });
            }
            return review.regular(q);
          },
        );
        await tap(t, find.text('Alle Wortlisten finden'));
        if (scenario.$2 == 'status') {
          await tap(t, collections.picker('Stand der Wortlisten'));
          await tap(t, find.text('Bereits übernommen').last);
          expect(calls.last.url.queryParameters['status'], 'confirmed');
        } else {
          await t.enterText(
            vocab.input('Gespeicherte Wortlisten durchsuchen'),
            'Alte Schulwörter',
          );
          await tap(t, find.text('Wortlisten suchen'));
          expect(calls.last.url.queryParameters['search'], 'Alte Schulwörter');
        }
        expect(calls.last.url.queryParameters['compact'], 'true');
        expect(calls.last.url.queryParameters['page'], '1');
        expect(calls.every((q) => q.method == 'GET'), isTrue);
      },
    );
  }
  testWidgets(
    'RQ107 deleted selected workshop word is explained after authorized revalidation',
    (t) async {
      final calls = <http.Request>[];
      var removed = false;
      final state = local.account((q) async {
        calls.add(q);
        if (q.url.path.endsWith('/vocabulary')) {
          return local.reply({
            'items': [
              if (!removed) {'id': 'w1', 'word': 'word1', 'meaning': 'Wort1'},
              {'id': 'w2', 'word': 'word2', 'meaning': 'Wort2'},
            ],
            'pagination': {'total': removed ? 1 : 2},
          });
        }
        if (q.url.path.endsWith('/materials')) {
          return local.reply({
            'items': [],
            'pagination': {'total': 0},
          });
        }
        return local.reply({'projects': [], 'has_more': false});
      });
      await local.show(t, LanguageWorkshop(state, childId: 'child'));
      await tap(t, find.widgetWithText(FilterChip, 'word1'));
      await tap(t, find.text('Mein eigener Text oder Entwurf'));
      await t.enterText(
        local.input('Schreibe zuerst deinen Versuch'),
        'My retained synthetic draft.',
      );
      t.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      removed = true;
      await local.show(t, LanguageWorkshop(state, childId: 'child'));
      expect(
        find.textContaining('1 ausgewählte Wörter sind nicht mehr'),
        findsOneWidget,
      );
      await tap(t, find.text('Mein eigener Text oder Entwurf'));
      expect(
        t
            .widget<TextField>(local.input('Schreibe zuerst deinen Versuch'))
            .controller!
            .text,
        'My retained synthetic draft.',
      );
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets('RQ108 saved project displays its actual creation timestamp', (
    t,
  ) async {
    final calls = <http.Request>[];
    final state = local.account((q) async {
      calls.add(q);
      return local.reply({...project.project(true), 'created': 1792663200});
    });
    await local.show(
      t,
      LanguageWorkshop(state, childId: 'child', projectId: 'project'),
    );
    expect(find.text('Gespeichert am 22.10.2026 10:00'), findsOneWidget);
    expect(calls.every((q) => q.method == 'GET'), isTrue);
  });
}
