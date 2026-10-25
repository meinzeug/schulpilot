import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/language_comparison_widget.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/ui.dart';

Json block() => {
  'kind': 'forms',
  'variant': 'classification',
  'title': 'Originaltexte vergleichen',
  'disclosure': 'given',
  'labels': ['I  read books.\nL’école 😀', 'I  read comics.\nL’école 😀'],
  'numbers': [],
  'connections': [],
  'marks': [],
  'unit': '',
  'scene': null,
  'text_probe': null,
  'lab': null,
};

AppState actor(List<http.Request> calls) =>
    AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            calls.add(request);
            throw StateError('Original comparison must remain local.');
          }),
        )..token = 'synthetic-session',
      )
      ..user = {'id': 'synthetic-child', 'role': 'child'}
      ..familyId = 'synthetic-family';

Widget host(Widget body, {double scale = 1, GlobalKey<NavigatorState>? nav}) =>
    MaterialApp(
      navigatorKey: nav,
      theme: appTheme(brightness: Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: body),
        ),
      ),
    );

void viewport(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder mode(LanguageComparisonFocus value) =>
    find.byKey(ValueKey('language-comparison-${value.name}'));

Future<void> choose(WidgetTester tester, LanguageComparisonFocus value) async {
  final finder = mode(value);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Text original(WidgetTester tester, int index) => tester.widget<Text>(
  find.byKey(ValueKey('language-comparison-original-$index')),
);
TextSpan word(WidgetTester tester, String value) =>
    (original(tester, 0).textSpan! as TextSpan).children!
        .cast<TextSpan>()
        .firstWhere((span) => span.text == value);

Future<void> close(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(const SizedBox.shrink());
  state.dispose();
}

void main() {
  testWidgets(
    'all original characters stay unchanged while local word focus changes',
    (tester) async {
      viewport(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      final data = block();
      final before = jsonEncode(data);
      await tester.pumpWidget(host(SubjectGraphic(data, state: state)));
      await tester.pumpAndSettle();
      expect(find.byType(LanguageComparisonWidget), findsOneWidget);
      expect(word(tester, 'books').style!.backgroundColor, isNotNull);
      expect(word(tester, 'I').style, isNull);
      await choose(tester, LanguageComparisonFocus.commonWords);
      expect(word(tester, 'books').style, isNull);
      expect(word(tester, 'I').style!.decoration, TextDecoration.underline);
      expect(word(tester, 'L’école').style!.backgroundColor, isNotNull);
      expect(find.textContaining('gleicher Schreibweise'), findsOneWidget);
      await choose(tester, LanguageComparisonFocus.none);
      expect(
        (original(tester, 0).textSpan! as TextSpan).children!
            .cast<TextSpan>()
            .every((span) => span.style == null),
        isTrue,
      );
      for (var index = 0; index < 2; index++) {
        expect(
          original(tester, index).textSpan!.toPlainText(),
          data['labels'][index],
        );
        expect(original(tester, index).semanticsLabel, data['labels'][index]);
      }
      expect(jsonEncode(data), before);
      expect(calls, isEmpty);
      await close(tester, state);
    },
  );

  testWidgets(
    'word equality is exact and case-sensitive, with a keyboard-operable focus',
    (tester) async {
      viewport(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      final data = block()..['labels'] = ['Sun shines.', 'sun shines.'];
      await tester.pumpWidget(
        host(LanguageComparisonWidget(data, state: state)),
      );
      final button = mode(LanguageComparisonFocus.commonWords);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      Focus.of(
        tester.element(
          find.descendant(of: button, matching: find.text('Gleiche Wörter')),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(word(tester, 'Sun').style, isNull);
      expect(
        word(tester, 'shines').style!.decoration,
        TextDecoration.underline,
      );
      expect(calls, isEmpty);
      await close(tester, state);
    },
  );

  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'four complete examples and 48px controls fit $width at ${scale}x',
        (tester) async {
          viewport(tester, width);
          final calls = <http.Request>[];
          final state = actor(calls);
          final data = block()
            ..['labels'] = [
              'I read books in the morning, and I keep every original word.',
              'I read comics in the evening, and I keep every original word.',
              'You read books in the morning, and you keep every original word.',
              'They read stories in the evening, and they keep every original word.',
            ];
          await tester.pumpWidget(
            host(SubjectGraphic(data, state: state), scale: scale),
          );
          await tester.pumpAndSettle();
          for (final value in LanguageComparisonFocus.values) {
            await choose(tester, value);
            final rect = tester.getRect(mode(value));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
          }
          for (var index = 0; index < 4; index++) {
            final finder = find.byKey(
              ValueKey('language-comparison-original-$index'),
            );
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
            expect(
              original(tester, index).textSpan!.toPlainText(),
              data['labels'][index],
            );
            expect(original(tester, index).maxLines, isNull);
            final rect = tester.getRect(finder);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
          }
          expect(tester.takeException(), isNull);
          expect(calls, isEmpty);
          await close(tester, state);
        },
      );
    }
  }

  for (final change in ['same-id login', 'family', 'session', 'logout']) {
    testWidgets(
      '$change hides private originals and refuses captured callbacks',
      (tester) async {
        viewport(tester, 390);
        final calls = <http.Request>[];
        final state = actor(calls);
        await tester.pumpWidget(
          host(LanguageComparisonWidget(block(), state: state)),
        );
        final callback = tester
            .widget<OutlinedButton>(mode(LanguageComparisonFocus.none))
            .onPressed!;
        switch (change) {
          case 'same-id login':
            state.user = Json.from(state.user!);
          case 'family':
            state.familyId = 'other-family';
          case 'session':
            state.api.token = 'other-session';
          case 'logout':
            state.user = null;
        }
        state.refreshState();
        await tester.pumpAndSettle();
        callback();
        await tester.pump();
        expect(find.byKey(const ValueKey('language-comparison')), findsNothing);
        expect(find.textContaining('books'), findsNothing);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
        await close(tester, state);
      },
    );
  }

  testWidgets(
    'source replacement resets focus, ordinary rebuild preserves it, old callbacks expire',
    (tester) async {
      viewport(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      final data = block();
      await tester.pumpWidget(
        host(LanguageComparisonWidget(data, state: state)),
      );
      await choose(tester, LanguageComparisonFocus.none);
      await tester.pumpWidget(
        host(LanguageComparisonWidget(Json.from(data), state: state)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alle Originaltexte ohne Markierung.'), findsOneWidget);
      final stale = tester
          .widget<OutlinedButton>(mode(LanguageComparisonFocus.none))
          .onPressed!;
      final next = block()
        ..['labels'] = ['I keep the source.', 'We keep the source.'];
      await tester.pumpWidget(
        host(LanguageComparisonWidget(next, state: state)),
      );
      await tester.pumpAndSettle();
      stale();
      await tester.pump();
      expect(find.textContaining('nicht in allen Beispielen'), findsOneWidget);
      expect(original(tester, 0).textSpan!.toPlainText(), next['labels'][0]);
      expect(calls, isEmpty);
      await close(tester, state);
    },
  );

  testWidgets('replacement AppState never rebinds an old private block', (
    tester,
  ) async {
    viewport(tester, 390);
    final calls = <http.Request>[];
    final first = actor(calls), next = actor(calls);
    await tester.pumpWidget(
      host(LanguageComparisonWidget(block(), state: first)),
    );
    await tester.pumpWidget(
      host(LanguageComparisonWidget(block(), state: next)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('language-comparison')), findsNothing);
    expect(find.textContaining('books'), findsNothing);
    expect(calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    first.dispose();
    next.dispose();
  });

  testWidgets(
    'cover and lifecycle changes invalidate old controls without requests',
    (tester) async {
      viewport(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        host(LanguageComparisonWidget(block(), state: state), nav: nav),
      );
      await choose(tester, LanguageComparisonFocus.commonWords);
      final stale = tester
          .widget<OutlinedButton>(mode(LanguageComparisonFocus.none))
          .onPressed!;
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other page')),
        ),
      );
      await tester.pumpAndSettle();
      stale();
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      stale();
      await tester.pump();
      expect(find.textContaining('gleicher Schreibweise'), findsOneWidget);
      final previous = tester
          .widget<OutlinedButton>(mode(LanguageComparisonFocus.none))
          .onPressed!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.textContaining('books'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      previous();
      await tester.pump();
      expect(find.textContaining('gleicher Schreibweise'), findsOneWidget);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await close(tester, state);
    },
  );

  testWidgets(
    'given intro works while unopened stages and missing account hide examples',
    (tester) async {
      viewport(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      final given = block();
      final later = block()..['disclosure'] = 'hint2';
      later['title'] = 'Private later title';
      final presentation = {
        'version': 1,
        'evidence_kind': 'knowledge',
        'blocks': [given, later],
      };
      await tester.pumpWidget(
        host(
          SubjectPresentation(
            presentation,
            stages: const {'given'},
            state: state,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LanguageComparisonWidget), findsOneWidget);
      expect(original(tester, 0).textSpan!.toPlainText(), given['labels'][0]);
      expect(find.text('Private later title'), findsNothing);
      await tester.pumpWidget(host(LanguageComparisonWidget(given)));
      await tester.pumpAndSettle();
      expect(find.textContaining('books'), findsNothing);
      expect(calls, isEmpty);
      await close(tester, state);
    },
  );

  testWidgets(
    'invalid counts, duplicates and scalar bounds show no original content',
    (tester) async {
      viewport(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      for (final labels in [
        <String>[],
        ['same', 'same'],
        ['same', ' same '],
        ['a', 'b', 'c', 'd', 'e'],
        ['😀' * 161, 'safe'],
      ]) {
        await tester.pumpWidget(
          host(
            LanguageComparisonWidget(
              block()..['labels'] = labels,
              state: state,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('language-comparison-original-0')),
          findsNothing,
        );
      }
      await tester.pumpWidget(
        host(
          LanguageComparisonWidget(
            block()..['labels'] = ['😀' * 160, 'safe'],
            state: state,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(original(tester, 0).textSpan!.toPlainText(), '😀' * 160);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await close(tester, state);
    },
  );
}
