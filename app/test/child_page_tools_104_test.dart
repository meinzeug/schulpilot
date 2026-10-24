import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_messages.dart';
import 'package:schulpilot/collection_screen.dart';
import 'package:schulpilot/homework_screen.dart';
import 'package:schulpilot/language_workshop.dart';
import 'package:schulpilot/progress_screen.dart';
import 'package:schulpilot/school_day_history.dart';
import 'package:schulpilot/school_day_screen.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/vocabulary_screen.dart';

import 'child_hierarchy_103_test.dart' as hierarchy;
import 'child_local_tools_ux88_test.dart' as local;
import 'child_project_tools_ux88_test.dart' as projects;
import 'collection_screen_test.dart' as rounds;
import 'notebook_test.dart' as notebooks;
import 'page_tools_test_helpers.dart' as tools;
import 'progress_cards_ux88_test.dart' as progress;
import 'vocabulary_test.dart' as words;
import 'language_retry_test.dart' as language;

const pages = <({String name, String group, String control})>[
  (name: 'learning', group: 'learning-tools', control: 'Thema suchen'),
  (name: 'library', group: 'notebook-shelf-tools', control: 'Fach suchen'),
  (
    name: 'messages',
    group: 'child-message-tools',
    control: 'Nachrichten durchsuchen',
  ),
  (
    name: 'history',
    group: 'school-history-tools',
    control: 'Geladene Tagespakete durchsuchen',
  ),
  (
    name: 'progress',
    group: 'progress-tools',
    control: 'Fach oder Thema suchen',
  ),
  (
    name: 'homework',
    group: 'homework-photo-tools',
    control: 'Aufgabenfotos aktualisieren',
  ),
  (
    name: 'workshop',
    group: 'workshop-project-tools',
    control: 'Geladene Projekte durchsuchen',
  ),
  (name: 'words', group: 'vocabulary-tools', control: 'Wörter suchen'),
  (name: 'schoolday', group: 'school-day-tools', control: 'Neu laden'),
];

Finder control(String label) =>
    label == 'Neu laden' || label == 'Aufgabenfotos aktualisieren'
    ? find.text(label)
    : find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (widget.decoration?.labelText == label ||
                widget.decoration?.hintText == label),
      );

Future<AppState> mountPage(
  WidgetTester tester,
  String name,
  List<http.Request> calls, {
  double width = 390,
  double scale = 1,
  bool queued = false,
}) async {
  final state = name == 'workshop'
      ? projects.account(calls)
      : local.account((request) async {
          calls.add(request);
          expect(request.method, 'GET');
          if (name == 'learning') {
            return rounds.reply(rounds.listing(learning: true, total: 3));
          }
          if (name == 'library') {
            return notebooks.jsonReply(notebooks.subjects());
          }
          if (name == 'progress') return progress.reply(progress.data(request));
          if (name == 'workshop-detail') {
            return local.reply({
              ...language.project(false),
              'status': 'queued',
              'error': null,
            });
          }
          if (name == 'history') {
            return local.reply({
              'days': [
                {
                  'id': 'saved-day',
                  'date': '2026-10-20',
                  'subjects': ['Mathematik'],
                  'page_count': 1,
                  'unit_count': 1,
                  'completed_units': 0,
                  'stage': 'ready',
                },
              ],
              'next_before': null,
            });
          }
          if (name == 'homework') {
            return local.reply({
              'photos': [
                {
                  'id': 'saved-photo',
                  'revision': 1,
                  'topic': 'Brüche',
                  'confirmed': false,
                },
              ],
              'next_cursor': null,
            });
          }
          if (name == 'words') {
            if (request.url.path.endsWith('/imports')) {
              return words.reply({
                'imports': queued
                    ? [
                        {
                          'id': 'artificial-import',
                          'status': 'queued',
                          'row_count': 0,
                        },
                      ]
                    : [],
                'open_total': queued ? 1 : 0,
              });
            }
            return words.reply(words.listing());
          }
          if (name == 'schoolday') {
            return local.reply({
              'day': {
                'id': 'saved-day',
                'date': '2026-10-20',
                'stage': 'collecting',
                'max_pages': 24,
                'pages': [],
                'units': [],
                'confirmed_count': 0,
                'synthetic': true,
                'active_job': queued
                    ? {'id': 'artificial-job', 'kind': 'school_day_package'}
                    : null,
              },
            });
          }
          return local.reply({});
        });
  final page = switch (name) {
    'learning' => CollectionScreen(state, childId: 'child', learning: true),
    'library' => CollectionScreen(state, childId: 'child'),
    'messages' => PageFrame(
      state: state,
      title: 'Familie',
      showTitle: false,
      child: ChildMessagesHub(
        state,
        data: local.mailData(),
        onCompose: (_, _) async {},
        onWriteMessage: () async {},
      ),
    ),
    'history' => SchoolDayHistory(state, childId: 'child'),
    'progress' => ProgressScreen(state, childId: 'child'),
    'homework' => HomeworkScreen(state, childId: 'child'),
    'workshop' => LanguageWorkshop(state, childId: 'child'),
    'workshop-detail' => LanguageWorkshop(
      state,
      childId: 'child',
      projectId: 'project',
    ),
    'words' => VocabularyScreen(state, childId: 'child'),
    _ => SchoolDayScreen(state, childId: 'child'),
  };
  await hierarchy.mountPage(
    tester,
    state,
    TickerMode(enabled: !queued, child: page),
    size: Size(width, 844),
    scale: scale,
  );
  return state;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final sample in [(390.0, 1.0), (320.0, 2.0)]) {
    for (final page in pages) {
      testWidgets(
        '104 ${page.name} has one deliberate tools entry at $sample',
        (tester) async {
          final calls = <http.Request>[];
          await mountPage(
            tester,
            page.name,
            calls,
            width: sample.$1,
            scale: sample.$2,
          );
          final before = calls.length;
          expect(control(page.control), findsNothing);
          expect(
            find.byKey(const ValueKey('page-tools-button')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('child-mobile-filter-toggle')),
            findsNothing,
          );
          final headerButton = find.byKey(const ValueKey('page-tools-button'));
          expect(tester.getSize(headerButton).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(headerButton).height, greaterThanOrEqualTo(48));
          await tools.openPageTools(tester, page.group);
          expect(control(page.control), findsOneWidget);
          final close = find.byKey(ValueKey('page-tools-close:${page.group}'));
          await tester.ensureVisible(close);
          await tester.pumpAndSettle();
          expect(close.hitTestable(), findsOneWidget);
          await tools.closePageTools(tester, page.group);
          expect(control(page.control), findsNothing);
          expect(
            calls.length,
            before,
            reason: 'Opening/closing tools is local',
          );
          expect(calls.every((request) => request.method == 'GET'), isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final name in ['words', 'schoolday', 'workshop-detail']) {
    testWidgets(
      '104 $name resumes only its existing GET status poll after options close',
      (tester) async {
        final calls = <http.Request>[];
        await mountPage(tester, name, calls, queued: true);
        final before = calls.length;
        await local.tap(
          tester,
          find.byKey(const ValueKey('page-tools-button')),
        );
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        expect(
          calls.length,
          before,
          reason: 'Even a menu held beyond the poll interval makes no request',
        );
        await local.tap(tester, find.byTooltip('Seitenoptionen schließen'));
        expect(
          calls.length,
          before,
          reason: 'Cancel makes no immediate request',
        );
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        expect(calls.length, before + (name == 'words' ? 2 : 1));
        expect(calls.every((request) => request.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    '104 learning keyboard search opens the registered field without a request',
    (tester) async {
      final calls = <http.Request>[];
      await mountPage(tester, 'learning', calls);
      final before = calls.length;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(control('Thema suchen'));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(calls.length, before);
      await tools.closePageTools(tester, 'learning-tools');
      expect(field.focusNode!.hasFocus, isFalse);
    },
  );

  testWidgets(
    '104 an old child options selection cannot reopen a group after token rotation',
    (tester) async {
      final calls = <http.Request>[];
      final state = await mountPage(tester, 'words', calls);
      final before = calls.length;
      await local.tap(tester, find.byKey(const ValueKey('page-tools-button')));
      final oldSelection = tester
          .widget<ListTile>(
            find.byKey(const ValueKey('page-tools-choice:vocabulary-tools')),
          )
          .onTap!;
      state.api.token = 'replacement-test-token';
      state.refreshState();
      await tester.pumpAndSettle();
      oldSelection();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-tools-menu')), findsNothing);
      expect(control('Wörter suchen'), findsNothing);
      expect(calls.length, before);
      expect(calls.every((request) => request.method == 'GET'), isTrue);
    },
  );
}
