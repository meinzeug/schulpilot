import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';

import 'exams_screen_test.dart' as f;

class BatchFixture extends f.Fixture {
  BatchFixture() {
    report = {
      ...report,
      'can_analyze_more': true,
      'pages': [
        {
          'id': 'page1',
          'title': 'Erstes künstliches Foto',
          'revision': 1,
          'confirmed': true,
          'content': 'Ein künstlicher bestätigter Aufgabentext.',
        },
        {
          'id': 'page2',
          'title': 'Zweites künstliches Foto',
          'revision': 1,
          'confirmed': true,
          'content': 'Ein zweiter künstlicher bestätigter Aufgabentext.',
        },
        {
          'id': 'unconfirmed',
          'title': 'Noch nicht geprüft',
          'revision': 1,
          'confirmed': false,
          'content': 'Ungeprüft.',
        },
        {
          'id': 'empty',
          'title': 'Leere Seite',
          'revision': 1,
          'confirmed': true,
          'content': '',
        },
      ],
      'analysis_batch': {
        'id': 'old-batch',
        'status': 'ready',
        'page_ids': ['page1'],
        'added_tasks': 1,
      },
      'analysis_batches': [],
      'tasks': [
        for (final task in (report['tasks'] as List))
          {
            ...Json.from(task),
            'draft': {
              'text': 'Gespeicherte eigene Berichtigung',
              'revision': 1,
              'updated': 1,
            },
          },
      ],
    };
  }
  int jobs = 0;
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'POST' &&
        request.url.path.endsWith('/review/analyze')) {
      calls.add(request);
      jobs++;
      report = {
        ...report,
        'can_analyze': false,
        'can_analyze_more': false,
        'analysis_batch': {
          'id': 'batch-$jobs',
          'status': 'queued',
          'page_ids': jsonDecode(request.body)['page_ids'],
          'added_tasks': 0,
        },
      };
      return f.reply({
        'id': 'job-$jobs',
        'status': 'queued',
        'batch_id': 'batch-$jobs',
      }, 202);
    }
    return super.handle(request);
  }

  void finish({bool failed = false}) {
    final old = Json.from(report['analysis_batch']);
    report = {
      ...report,
      'can_analyze_more': true,
      'analysis_batch': {
        ...old,
        'status': failed ? 'failed' : 'ready',
        'error': failed ? 'Künstlicher Auszug fehlgeschlagen' : null,
        'added_tasks': failed ? 0 : 1,
      },
      if (!failed)
        'tasks': [
          ...report['tasks'],
          {
            ...Json.from((report['tasks'] as List).first),
            'id': 'new-task-$jobs',
            'question': 'Eine weitere künstliche Aufgabe.',
          },
        ],
    };
  }
}

Finder draft() => find.widgetWithText(TextField, 'Dein Verbesserungsversuch');
Future<void> openChoice(WidgetTester tester) =>
    f.tap(tester, find.text('Weiteren kleinen KI-Auszug wählen'));
Future<void> chooseSecond(WidgetTester tester) async {
  await f.tap(
    tester,
    find.widgetWithText(CheckboxListTile, 'Zweites künstliches Foto'),
  );
  await f.tap(tester, find.text('KI-Auszug bewusst anfordern'));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'a contradiction is visible separately from the original answer',
    (tester) async {
      final value = BatchFixture();
      value.report = {
        ...value.report,
        'tasks': [
          {
            ...Json.from((value.report['tasks'] as List).first),
            'original_answer': '6/8 = 2/4',
            'arithmetic_warnings': [
              {
                'message': 'Diese Gleichung stimmt rechnerisch nicht. Prüfe auch, ob sie richtig abgeschrieben wurde.',
              },
            ],
          },
        ],
      };
      await value.mount(tester, selected: 'exam', tab: 'review');
      expect(find.text('6/8 = 2/4'), findsOneWidget);
      expect(
        find.textContaining('Diese Gleichung stimmt rechnerisch nicht'),
        findsOneWidget,
      );
      expect(value.writes, isEmpty);
    },
  );
  testWidgets(
    'canceling an additional extract selects no sources and starts no job',
    (tester) async {
      final value = BatchFixture();
      await value.mount(tester, selected: 'exam', tab: 'review');
      await openChoice(tester);
      expect(
        find.widgetWithText(CheckboxListTile, 'Noch nicht geprüft'),
        findsNothing,
      );
      expect(
        find.widgetWithText(CheckboxListTile, 'Leere Seite'),
        findsNothing,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'KI-Auszug bewusst anfordern'),
            )
            .onPressed,
        isNull,
      );
      await f.tap(tester, find.text('Abbrechen'));
      expect(value.writes, isEmpty);
      expect(
        tester.widget<TextField>(draft()).controller!.text,
        'Gespeicherte eigene Berichtigung',
      );
    },
  );
  testWidgets(
    'initial extract explicitly selects only nonempty confirmed pages',
    (tester) async {
      final value = BatchFixture();
      value.report = {
        ...value.report,
        'can_analyze': true,
        'can_analyze_more': false,
      };
      await value.mount(tester, selected: 'exam', tab: 'review');
      await f.tap(tester, find.text('Einzelne Aufgaben besprechen lassen'));
      expect(value.writes, isEmpty);
      expect(find.text('Fotos für den KI-Auszug wählen'), findsOneWidget);
      expect(
        find.textContaining('ein kleiner KI-Auszug mit einzelnen Aufgaben'),
        findsOneWidget,
      );
      await f.tap(
        tester,
        find.widgetWithText(CheckboxListTile, 'Erstes künstliches Foto'),
      );
      await f.tap(tester, find.text('KI-Auszug bewusst anfordern'));
      expect(jsonDecode(value.writes.single.body), {
        'revision': 1,
        'context_revision': 'a' * 64,
        'page_ids': ['page2'],
        'append': false,
      });
      expect(value.writes.single.headers['Idempotency-Key'], isNotEmpty);
    },
  );
  testWidgets(
    'append preserves an unsaved correction and polls without another AI request',
    (tester) async {
      final value = BatchFixture();
      await value.mount(tester, selected: 'exam', tab: 'review');
      await tester.enterText(draft(), 'Mein noch nicht gespeicherter Versuch');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await openChoice(tester);
      await chooseSecond(tester);
      expect(value.writes, hasLength(1));
      expect(jsonDecode(value.writes.single.body), {
        'revision': 1,
        'context_revision': 'a' * 64,
        'page_ids': ['page2'],
        'append': true,
      });
      expect(
        find.text('Wie heißt ein Teil von zwei gleichen Teilen?'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(draft()).controller!.text,
        'Mein noch nicht gespeicherter Versuch',
      );
      value.finish();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(value.writes, hasLength(1));
      expect(
        tester.widget<TextField>(draft()).controller!.text,
        'Mein noch nicht gespeicherter Versuch',
      );
      final selector = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byType(DropdownButtonFormField<String>).last,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(selector.items, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed extra extract leaves the earlier report and correction usable',
    (tester) async {
      final value = BatchFixture();
      await value.mount(tester, selected: 'exam', tab: 'review');
      await openChoice(tester);
      await chooseSecond(tester);
      value.finish(failed: true);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Künstlicher Auszug fehlgeschlagen'), findsOneWidget);
      expect(
        find.text('Wie heißt ein Teil von zwei gleichen Teilen?'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(draft()).enabled, isTrue);
      expect(
        tester.widget<TextField>(draft()).controller!.text,
        'Gespeicherte eigene Berichtigung',
      );
      expect(value.writes, hasLength(1));
    },
  );
  testWidgets(
    'two deliberate extracts from the same photos receive distinct keys',
    (tester) async {
      final value = BatchFixture();
      await value.mount(tester, selected: 'exam', tab: 'review');
      await openChoice(tester);
      await chooseSecond(tester);
      value.finish();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await openChoice(tester);
      await chooseSecond(tester);
      expect(value.writes, hasLength(2));
      expect(value.writes[0].body, value.writes[1].body);
      expect(
        value.writes[0].headers['Idempotency-Key'],
        isNot(value.writes[1].headers['Idempotency-Key']),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'help evidence remains distinct from the analysis evidence without another request',
    (tester) async {
      final value = BatchFixture();
      value.report = {
        ...value.report,
        'turns': [
          {
            'id': 'help',
            'task_id': 'task',
            'status': 'ready',
            'action': 'hint',
            'reply': {
              'answer': 'Eine eigene künstliche Lernhilfe.',
              'sources': [
                {
                  'ref': 'p2',
                  'quote': 'Wörtlicher Beleg nur für diese Hilfe.',
                  'label': 'Zweites Foto',
                },
              ],
            },
          },
        ],
      };
      await value.mount(tester, selected: 'exam', tab: 'review');
      expect(find.text('Wörtlicher Beleg nur für diese Hilfe.'), findsNothing);
      final before = value.calls.length;
      await f.tap(tester, find.text('Belege zu dieser KI-Hilfe'));
      expect(
        find.text('Wörtlicher Beleg nur für diese Hilfe.'),
        findsOneWidget,
      );
      expect(value.calls.length, before);
      expect(value.writes, isEmpty);
    },
  );
  for (final change in ['account', 'token']) {
    testWidgets('extract selection cannot submit after $change replacement', (
      tester,
    ) async {
      final value = BatchFixture();
      await value.mount(tester, selected: 'exam', tab: 'review');
      await openChoice(tester);
      await f.tap(
        tester,
        find.widgetWithText(CheckboxListTile, 'Zweites künstliches Foto'),
      );
      final callback = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'KI-Auszug bewusst anfordern'),
          )
          .onPressed!;
      if (change == 'account') {
        value.state.user = {...value.state.user!, 'id': 'other'};
      }
      if (change == 'token') value.state.api.token = 'other';
      value.state.refreshState();
      await tester.pumpAndSettle();
      callback();
      await tester.pumpAndSettle();
      expect(value.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
