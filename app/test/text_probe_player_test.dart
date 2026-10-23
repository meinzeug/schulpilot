import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/text_probe_player.dart';
import 'package:schulpilot/ui.dart';

// Shared synthetic backend fixture, projected by the production disclosure path.
// No question answer or private source excerpt is passed to the renderer.
Json presentation() => Json.from(
  jsonDecode(
    File('../testdata/text_probes_v1.json').readAsStringSync(),
  )['cases'][0]['public_presentation_hint1'],
);
Json block() => Json.from(presentation()['blocks'][0]);
const toggle = ValueKey('text-probe-toggle');
const second = ValueKey('text-probe-variant-second');
const group = ValueKey('text-probe-group-time');
const loupe = ValueKey('text-probe-loupe');
const compare = ValueKey('text-probe-compare-toggle');
const reset = ValueKey('text-probe-reset');

AppState actor(List<http.Request> calls) =>
    AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            calls.add(request);
            throw StateError('Text exploration must remain local.');
          }),
        )..token = 'synthetic-session',
      )
      ..user = {'id': 'synthetic-child', 'role': 'child'}
      ..familyId = 'synthetic-family';

Widget host(
  Widget child, {
  double scale = 1,
  bool reduced = false,
  GlobalKey<NavigatorState>? navigator,
}) => MaterialApp(
  navigatorKey: navigator,
  theme: appTheme(brightness: Brightness.dark),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduced,
    ),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

void viewport(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tap(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String sentence(WidgetTester tester, int index) => tester
    .widget<Text>(find.byKey(ValueKey('text-probe-sentence-$index')))
    .textSpan!
    .toPlainText();
Color markerColor(WidgetTester tester) =>
    (tester
                .widget<Container>(
                  find.byKey(const ValueKey('text-probe-marker-time')),
                )
                .decoration
            as BoxDecoration)
        .color!;
Future<void> close(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(const SizedBox.shrink());
  state.dispose();
}

void main() {
  testWidgets(
    'source-bound variants preserve groups, magnify in context and compare locally',
    (tester) async {
      viewport(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      final data = block();
      final original = jsonEncode(data);
      expect(original, isNot(contains('source_excerpt')));
      await tester.pumpWidget(host(SubjectGraphic(data, state: state)));
      await tester.pumpAndSettle();
      expect(sentence(tester, 0), 'heute lernt Mika');
      expect(find.byKey(group), findsNothing);
      await tap(tester, toggle);
      final color = markerColor(tester);
      await tap(tester, group);
      expect(find.byKey(loupe), findsOneWidget);
      expect(find.text('Position 1 von 3 in Textprobe 1.'), findsOneWidget);
      final span =
          tester
                  .widget<Text>(
                    find.byKey(const ValueKey('text-probe-sentence-0')),
                  )
                  .textSpan!
              as TextSpan;
      expect(
        (span.children!.first as TextSpan).style!.decoration,
        TextDecoration.underline,
      );
      await tap(tester, second);
      expect(sentence(tester, 1), 'Mika lernt heute');
      expect(markerColor(tester), color);
      expect(find.text('Position 3 von 3 in Textprobe 2.'), findsOneWidget);
      expect(find.text('Textgruppe 1: Position 1 → 3'), findsOneWidget);
      expect(find.text('Textgruppe 3: Position 3 → 1'), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('text-probe-group-person')))
            .dy,
        lessThan(tester.getTopLeft(find.byKey(group)).dy),
      );
      await tap(tester, compare);
      expect(find.byKey(const ValueKey('text-probe-compare')), findsOneWidget);
      expect(sentence(tester, 0), 'heute lernt Mika');
      expect(sentence(tester, 1), 'Mika lernt heute');
      final stale = tester
          .widget<OutlinedButton>(find.byKey(second))
          .onPressed!;
      await tap(tester, reset);
      stale();
      await tester.pump();
      expect(find.byKey(loupe), findsNothing);
      expect(find.byKey(const ValueKey('text-probe-compare')), findsNothing);
      expect(sentence(tester, 0), 'heute lernt Mika');
      expect(jsonEncode(data), original);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await close(tester, state);
    },
  );

  testWidgets(
    'group selection supports keyboard and visible focus without colour-only meaning',
    (tester) async {
      viewport(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      await tester.pumpWidget(host(TextProbePlayer(block(), state: state)));
      await tap(tester, toggle);
      final button = find.byKey(group);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final text = find.descendant(of: button, matching: find.text('heute'));
      Focus.of(tester.element(text)).requestFocus();
      await tester.pump();
      final style = tester.widget<OutlinedButton>(button).style!;
      expect(style.side!.resolve({WidgetState.focused})!.width, 2.5);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(loupe), findsOneWidget);
      expect(find.text('Textgruppe 1'), findsOneWidget);
      expect(find.text('Position 1 von 3 in Textprobe 1.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byKey(loupe), findsNothing);
      expect(calls, isEmpty);
      await close(tester, state);
    },
  );

  for (final width in [320.0, 390.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'full text exploration is readable at $width px and ${scale}x',
        (tester) async {
          viewport(tester, width);
          final calls = <http.Request>[];
          final state = actor(calls);
          final data = block();
          data['text_probe']['segments'][0]['text'] =
              'heute am frühen Morgen vor dem Unterricht';
          await tester.pumpWidget(
            host(
              TextProbePlayer(data, state: state),
              scale: scale,
              reduced: true,
            ),
          );
          await tap(tester, toggle);
          for (final key in [
            group,
            const ValueKey('text-probe-group-verb'),
            const ValueKey('text-probe-group-person'),
            second,
            compare,
            reset,
          ]) {
            await tap(tester, key);
            final rect = tester.getRect(find.byKey(key));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            expect(tester.takeException(), isNull);
          }
          expect(calls, isEmpty);
          await close(tester, state);
        },
      );
    }
  }

  for (final change in ['same-id login', 'family', 'session', 'logout']) {
    testWidgets('$change removes old text and rejects captured controls', (
      tester,
    ) async {
      viewport(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      await tester.pumpWidget(host(TextProbePlayer(block(), state: state)));
      await tap(tester, toggle);
      await tap(tester, group);
      final lateVariant = tester
          .widget<OutlinedButton>(find.byKey(second))
          .onPressed!;
      final lateGroup = tester
          .widget<OutlinedButton>(find.byKey(group))
          .onPressed!;
      switch (change) {
        case 'same-id login':
          state.user = Json.from(state.user!);
        case 'family':
          state.familyId = 'other-family';
        case 'session':
          state.api.token = 'replacement-session';
        case 'logout':
          state.user = null;
      }
      state.refreshState();
      await tester.pumpAndSettle();
      lateVariant();
      lateGroup();
      await tester.pump();
      expect(find.byKey(toggle), findsNothing);
      expect(find.byKey(loupe), findsNothing);
      expect(find.byKey(const ValueKey('text-probe-sentence-0')), findsNothing);
      expect(find.textContaining('heute'), findsNothing);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await close(tester, state);
    });
  }

  testWidgets(
    'new source resets exploration and rejects the previous source callback',
    (tester) async {
      viewport(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      await tester.pumpWidget(host(TextProbePlayer(block(), state: state)));
      await tap(tester, toggle);
      await tap(tester, group);
      final stale = tester
          .widget<OutlinedButton>(find.byKey(second))
          .onPressed!;
      final replacement = block();
      replacement['text_probe']['segments'][0]['text'] = 'morgen';
      await tester.pumpWidget(host(TextProbePlayer(replacement, state: state)));
      await tester.pumpAndSettle();
      stale();
      await tester.pump();
      expect(sentence(tester, 0), 'morgen lernt Mika');
      expect(find.byKey(group), findsNothing);
      expect(find.byKey(loupe), findsNothing);
      expect(calls, isEmpty);
      await close(tester, state);
    },
  );

  testWidgets('byte-identical next question disposes all local exploration', (
    tester,
  ) async {
    viewport(tester, 390);
    final calls = <http.Request>[];
    final state = actor(calls);
    await tester.pumpWidget(
      host(
        SubjectPresentation(
          presentation(),
          key: const ValueKey('question-a/hint1'),
          stages: const {'hint1'},
          state: state,
        ),
      ),
    );
    await tap(tester, toggle);
    await tap(tester, group);
    final stale = tester.widget<OutlinedButton>(find.byKey(second)).onPressed!;
    await tester.pumpWidget(
      host(
        SubjectPresentation(
          presentation(),
          key: const ValueKey('question-b/hint1'),
          stages: const {'hint1'},
          state: state,
        ),
      ),
    );
    await tester.pumpAndSettle();
    stale();
    await tester.pump();
    expect(find.byKey(group), findsNothing);
    expect(find.byKey(loupe), findsNothing);
    expect(sentence(tester, 0), 'heute lernt Mika');
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
    await close(tester, state);
  });

  testWidgets('covered route and app background reset local inspection', (
    tester,
  ) async {
    viewport(tester, 390);
    final calls = <http.Request>[];
    final state = actor(calls);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      host(TextProbePlayer(block(), state: state), navigator: nav),
    );
    await tap(tester, toggle);
    await tap(tester, group);
    final stale = tester.widget<OutlinedButton>(find.byKey(second)).onPressed!;
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')),
      ),
    );
    await tester.pumpAndSettle();
    stale();
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(loupe), findsNothing);
    expect(find.byKey(group), findsNothing);
    await tap(tester, toggle);
    await tap(tester, group);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(group), findsNothing);
    expect(sentence(tester, 0), 'heute lernt Mika');
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
    await close(tester, state);
  });

  testWidgets(
    'given, unopened stages and missing account expose no text probe',
    (tester) async {
      viewport(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      final forged = block()..['disclosure'] = 'given';
      await tester.pumpWidget(host(TextProbePlayer(forged, state: state)));
      expect(find.text('Textgruppen'), findsNothing);
      expect(find.byKey(toggle), findsNothing);
      await tester.pumpWidget(
        host(
          SubjectPresentation(
            presentation(),
            stages: const {'given'},
            state: state,
          ),
        ),
      );
      expect(find.byType(TextProbePlayer), findsNothing);
      await tester.pumpWidget(host(TextProbePlayer(block())));
      expect(find.byKey(toggle), findsNothing);
      expect(find.byKey(const ValueKey('text-probe-sentence-0')), findsNothing);
      expect(calls, isEmpty);
      await close(tester, state);
    },
  );

  testWidgets('stage filtering keeps later hints and solutions closed', (
    tester,
  ) async {
    viewport(tester, 390);
    final calls = <http.Request>[];
    final state = actor(calls);
    final laterHint = block()..['disclosure'] = 'hint2';
    laterHint['title'] = 'Noch geschlossener Hinweis';
    laterHint['text_probe']['segments'][0]['text'] = 'später';
    final solution = block()..['disclosure'] = 'solution';
    solution['title'] = 'Noch geschlossene Lösung';
    final data = presentation()..['blocks'] = [block(), laterHint, solution];
    await tester.pumpWidget(
      host(SubjectPresentation(data, stages: const {'hint1'}, state: state)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextProbePlayer), findsOneWidget);
    expect(find.text('Noch geschlossener Hinweis'), findsNothing);
    expect(find.text('Noch geschlossene Lösung'), findsNothing);
    await tap(tester, toggle);
    await tap(tester, second);
    expect(sentence(tester, 1), 'Mika lernt heute');
    expect(find.textContaining('später'), findsNothing);
    expect(calls, isEmpty);
    await close(tester, state);
  });

  testWidgets('Unicode scalar limits match source validation at 160 and 161', (
    tester,
  ) async {
    viewport(tester, 390);
    final calls = <http.Request>[];
    final state = actor(calls);
    final glyph = String.fromCharCode(0x1f600);
    final valid = block();
    valid['title'] = glyph * 160;
    valid['text_probe']['segments'][0]['text'] = glyph * 160;
    await tester.pumpWidget(host(TextProbePlayer(valid, state: state)));
    await tester.pumpAndSettle();
    expect(sentence(tester, 0), '${glyph * 160} lernt Mika');
    expect(find.text(glyph * 160), findsOneWidget);
    expect(
      find.text('Diese Textprobe ist hier nicht verfügbar.'),
      findsNothing,
    );
    final invalidTitle = block()..['title'] = glyph * 161;
    await tester.pumpWidget(host(TextProbePlayer(invalidTitle, state: state)));
    await tester.pumpAndSettle();
    expect(find.text(glyph * 161), findsNothing);
    expect(find.text('Text genau ansehen'), findsOneWidget);
    final invalidSegment = block();
    invalidSegment['text_probe']['segments'][0]['text'] = glyph * 161;
    await tester.pumpWidget(
      host(TextProbePlayer(invalidSegment, state: state)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Diese Textprobe ist hier nicht verfügbar.'),
      findsOneWidget,
    );
    expect(find.byKey(toggle), findsNothing);
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
    await close(tester, state);
  });

  testWidgets(
    'malformed or incomplete orders fail closed rather than inventing text',
    (tester) async {
      viewport(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      final invalid = <Json>[
        block()
          ..['text_probe']['variants'][1]['order'] = ['time', 'verb', 'time'],
        block()
          ..['text_probe']['variants'][1]['order'] = [
            'time',
            'verb',
            'missing',
          ],
        block()..['text_probe']['segments'][1]['id'] = 'time',
        block()..['text_probe']['version'] = 2,
        block()..['text_probe']['segments'][0]['text'] = 'x' * 161,
      ];
      for (var index = 0; index < invalid.length; index++) {
        await tester.pumpWidget(
          host(
            TextProbePlayer(invalid[index], key: ValueKey(index), state: state),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Diese Textprobe ist hier nicht verfügbar.'),
          findsOneWidget,
        );
        expect(find.byKey(toggle), findsNothing);
        expect(
          find.byKey(const ValueKey('text-probe-sentence-0')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      expect(calls, isEmpty);
      await close(tester, state);
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'public hint text probe opens in zoom without horizontal clipping at $width px',
      (tester) async {
        viewport(tester, width);
        final calls = <http.Request>[];
        final state = actor(calls);
        await tester.pumpWidget(
          host(
            SubjectPresentation(
              presentation(),
              stages: const {'hint1'},
              state: state,
            ),
            scale: 2,
          ),
        );
        final open = find.byTooltip('Grafik vergrößern');
        await tester.ensureVisible(open);
        await tester.pumpAndSettle();
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Zur Aufgabe zurück'), findsOneWidget);
        final button = find.descendant(
          of: find.byType(Dialog),
          matching: find.byKey(toggle),
        );
        Future<void> panTo(Finder target) async {
          final viewer = tester.getRect(find.byType(InteractiveViewer));
          final targetRect = tester.getRect(target);
          final gesture = await tester.startGesture(viewer.center);
          final delta = viewer.center.dy - targetRect.center.dy;
          // First cross the tap/scale gesture arena, then move continuously.
          await gesture.moveBy(Offset(0, delta.sign * 24));
          await tester.pump(const Duration(milliseconds: 16));
          await gesture.moveBy(Offset(0, delta));
          await tester.pump(const Duration(milliseconds: 300));
          await gesture.up();
          await tester.pumpAndSettle();
        }

        await panTo(button);
        final rect = tester.getRect(button);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(button.hitTestable(), findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final groupButton = find.descendant(
          of: find.byType(Dialog),
          matching: find.byKey(group),
        );
        await panTo(groupButton);
        expect(
          groupButton.hitTestable(),
          findsOneWidget,
          reason:
              'group=${tester.getRect(groupButton)}; viewer=${tester.getRect(find.byType(InteractiveViewer))}',
        );
        await tester.tap(groupButton);
        await tester.pumpAndSettle();
        expect(find.byKey(loupe), findsOneWidget);
        state.user = Json.from(state.user!);
        state.refreshState();
        await tester.pumpAndSettle();
        expect(find.byTooltip('Zur Aufgabe zurück'), findsNothing);
        expect(find.byKey(toggle), findsNothing);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
        await close(tester, state);
      },
    );
  }
}
