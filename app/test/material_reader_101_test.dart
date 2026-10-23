import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ideas100_source_tools.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/material_screen.dart';

import 'child_local_tools_ux88_test.dart' as f;
import 'child_sources_input_ux87_test.dart' as source;

const firstParagraph =
    'Ein wörtlicher Anfang bleibt im sichtbaren Lesebereich.';
const sourceText =
    '# Künstliche Quelle\n\n$firstParagraph\n\n## Zweiter Abschnitt\n\nEin weiterer wörtlicher Anfang.\n\nUnveränderter Schluss.';
Finder input(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Finder closeReader() => find.byWidgetPredicate(
  (w) => w is IconButton && w.tooltip == 'Zurück zur Heftseite',
);
Finder closeCompare() => find.byWidgetPredicate(
  (w) => w is IconButton && w.tooltip == 'Vergleich schließen',
);
Future<void> tap(WidgetTester t, Finder target) async {
  await Scrollable.ensureVisible(t.element(target), alignment: .5);
  await t.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await t.tap(target);
  await t.pumpAndSettle();
}

List<LearningContent> takeDocumentContent(WidgetTester t) => t
    .widgetList<LearningContent>(
      find.descendant(
        of: find.byKey(const ValueKey('source-reader-document')),
        matching: find.byType(LearningContent),
      ),
    )
    .toList();

class Fixture {
  final requests = <http.Request>[];
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              if (r.method != 'GET') {
                throw StateError(
                  'Reading cannot write or start an AI request.',
                );
              }
              if (r.url.path.endsWith('/image')) {
                return http.Response.bytes(
                  image.encodePng(image.Image(width: 4, height: 4)),
                  200,
                );
              }
              return http.Response(
                jsonEncode({}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          )..token = 'synthetic-session',
        )
        ..familyId = 'synthetic-family'
        ..user = {
          'id': 'synthetic-child',
          'role': 'child',
          'child_id': 'child',
        };
  late var data = source.page('reading', saved: false)
    ..['synthetic'] = false
    ..['has_image'] = true
    ..['content'] = sourceText
    ..['uncertainties'] = ['wörtlicher Anfang'];
  late StateSetter update;
  late GoRouter router;
  Future<void> mount(
    WidgetTester t, {
    double width = 390,
    double height = 844,
    double scale = 1,
  }) async {
    router = await f.show(
      t,
      StatefulBuilder(
        builder: (_, setter) {
          update = setter;
          return MaterialReview(
            state,
            data,
            onRefresh: () {},
            simpleChild: true,
            showUnitAction: false,
          );
        },
      ),
      size: Size(width, height),
      scale: scale,
    );
    await t.pumpAndSettle();
  }

  Future<void> open(WidgetTester t, String kind) async {
    if (kind == 'reader') {
      await tap(t, find.text('Im Seitentext nachsehen'));
      return;
    }
    if (kind == 'correction') {
      await tap(t, find.text('Etwas verbessern'));
      await t.enterText(
        input('Text auf der Seite'),
        'Mein eigener Korrekturentwurf bleibt unverändert.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
    }
    await tap(t, find.byTooltip('Weitere Seitentextwerkzeuge'));
    await tap(
      t,
      find.text(
        kind == 'photo'
            ? 'Foto und Text vergleichen'
            : 'Korrektur mit gespeichertem Text vergleichen',
      ),
    );
  }
}

void main() {
  for (final view in [
    (320.0, 568.0, 1.0),
    (320.0, 568.0, 2.0),
    (390.0, 844.0, 1.0),
    (390.0, 844.0, 2.0),
    (1440.0, 900.0, 1.0),
    (1440.0, 900.0, 2.0),
  ]) {
    testWidgets(
      '101 actual reader prioritizes source and keeps close fixed at $view',
      (t) async {
        final fixture = Fixture();
        await fixture.mount(t, width: view.$1, height: view.$2, scale: view.$3);
        expect(find.byTooltip('Weitere Seitentextwerkzeuge'), findsOneWidget);
        expect(find.text('Foto und Text vergleichen'), findsNothing);
        await fixture.open(t, 'reader');
        expect(closeReader().hitTestable(), findsOneWidget);
        expect(t.getSize(closeReader()).shortestSide, greaterThanOrEqualTo(48));
        expect(find.byType(LearningHeadingIndex), findsNothing);
        expect(input('Wort oder Textstelle finden'), findsNothing);
        expect(find.text('24 px'), findsNothing);
        final document = find.byKey(const ValueKey('source-reader-document'));
        final paragraph = find.descendant(
          of: document,
          matching: find.text(firstParagraph),
        );
        expect(paragraph, findsOneWidget);
        expect(
          t.getTopLeft(paragraph).dy,
          greaterThanOrEqualTo(t.getTopLeft(document).dy),
        );
        expect(
          t.getTopLeft(paragraph).dy,
          lessThan(t.getBottomLeft(document).dy),
        );
        await t.drag(document, const Offset(0, -450));
        await t.pumpAndSettle();
        expect(closeReader().hitTestable(), findsOneWidget);
        await t.tap(closeReader());
        await t.pumpAndSettle();
        expect(find.byType(Ideas100SourceReader), findsNothing);
        expect(fixture.requests.every((r) => r.method == 'GET'), isTrue);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final view in [(320.0, 568.0, 2.0), (1440.0, 900.0, 1.0)]) {
    testWidgets(
      '101 search contents and typography are deliberate and keep source intact at $view',
      (t) async {
        final fixture = Fixture();
        await fixture.mount(t, width: view.$1, height: view.$2, scale: view.$3);
        await fixture.open(t, 'reader');
        await tap(t, find.byKey(const ValueKey('source-reader-search')));
        await t.enterText(
          input('Wort oder Textstelle finden'),
          'wörtlicher Anfang',
        );
        await t.pumpAndSettle();
        expect(find.text('Treffer 1 von 2'), findsOneWidget);
        final previous = find.byTooltip('Vorheriger Texttreffer'),
            next = find.byTooltip('Nächster Texttreffer');
        expect(t.getCenter(previous).dy, t.getCenter(next).dy);
        await tap(t, next);
        expect(find.text('Treffer 2 von 2'), findsOneWidget);
        expect(find.text('Unveränderter Schluss.'), findsOneWidget);
        await t.enterText(
          input('Wort oder Textstelle finden'),
          'nicht-vorhanden',
        );
        await t.pumpAndSettle();
        expect(find.text('Kein Treffer'), findsOneWidget);
        expect(
          find.text('Keine passende Textstelle gefunden.'),
          findsOneWidget,
        );
        await tap(t, find.byKey(const ValueKey('source-reader-type')));
        await tap(t, find.text('24 px'));
        await tap(t, find.byTooltip('Zeilenabstand 1.8'));
        final content = find.descendant(
          of: find.byKey(const ValueKey('source-reader-document')),
          matching: find.byType(LearningContent),
        );
        expect(
          t
              .widgetList<LearningContent>(content)
              .every((w) => w.style?.fontSize == 24 && w.style?.height == 1.8),
          isTrue,
        );
        expect(closeReader().hitTestable(), findsOneWidget);
        await tap(t, find.byKey(const ValueKey('source-reader-contents')));
        await tap(
          t,
          find.byKey(
            ValueKey(
              'learning-heading-${learningHeadings(sourceText).last.sectionIndex}',
            ),
          ),
        );
        expect(find.byType(LearningHeadingIndex), findsNothing);
        expect(closeReader().hitTestable(), findsOneWidget);
        expect(fixture.requests.every((r) => r.method == 'GET'), isTrue);
        expect(t.takeException(), isNull);
      },
    );
    for (final kind in ['photo', 'correction']) {
      testWidgets(
        '101 $kind comparison has fixed close and real labelled panes at $view',
        (t) async {
          final fixture = Fixture();
          await fixture.mount(
            t,
            width: view.$1,
            height: view.$2,
            scale: view.$3,
          );
          await fixture.open(t, kind);
          expect(closeCompare().hitTestable(), findsOneWidget);
          final first = kind == 'photo'
              ? 'Dein Heftfoto'
              : 'Gespeicherter Seitentext';
          final second = kind == 'photo'
              ? 'Aktueller Seitentext'
              : 'Dein Korrekturentwurf';
          if (view.$1 < 720) {
            expect(find.text(first), findsOneWidget);
            expect(find.text(second), findsNothing);
            await tap(
              t,
              find.widgetWithText(
                OutlinedButton,
                kind == 'photo' ? 'Text' : 'Entwurf',
              ),
            );
            expect(find.text(second), findsOneWidget);
          } else {
            expect(find.text(first), findsOneWidget);
            expect(find.text(second), findsOneWidget);
            expect(
              t.getTopLeft(find.text(first)).dy,
              t.getTopLeft(find.text(second)).dy,
            );
          }
          expect(closeCompare().hitTestable(), findsOneWidget);
          await t.tap(closeCompare());
          await t.pumpAndSettle();
          if (kind == 'correction') {
            expect(
              t.widget<TextField>(input('Text auf der Seite')).controller!.text,
              'Mein eigener Korrekturentwurf bleibt unverändert.',
            );
          }
          expect(fixture.requests.every((r) => r.method == 'GET'), isTrue);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  for (final kind in ['reader', 'photo', 'correction']) {
    for (final change in [
      'account',
      'family',
      'token',
      'source',
      'route',
      'lifecycle',
    ]) {
      testWidgets(
        '101 $kind is discarded on $change and old close cannot pop a new dialog',
        (t) async {
          final fixture = Fixture();
          await fixture.mount(t);
          await fixture.open(t, kind);
          final close = t
              .widget<IconButton>(
                kind == 'reader' ? closeReader() : closeCompare(),
              )
              .onPressed!;
          if (change == 'account') {
            fixture.state.user = {...fixture.state.user!};
          }
          if (change == 'family') fixture.state.familyId = 'other-family';
          if (change == 'token') fixture.state.api.token = 'other-session';
          if (['account', 'family', 'token'].contains(change)) {
            fixture.state.refreshState();
          }
          if (change == 'source') {
            fixture.update(
              () => fixture.data = {...fixture.data, 'revision': 2},
            );
          }
          if (change == 'route') fixture.router.go('/material/new-source');
          if (change == 'lifecycle') {
            t.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            await t.pumpAndSettle();
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
            t.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          }
          await t.pumpAndSettle();
          expect(closeReader(), findsNothing);
          expect(closeCompare(), findsNothing);
          final ctx = t.element(find.byType(Scaffold).first);
          final next = showDialog<void>(
            context: ctx,
            builder: (_) =>
                const AlertDialog(title: Text('Neue unabhängige Ansicht')),
          );
          await t.pumpAndSettle();
          close();
          await t.pumpAndSettle();
          expect(find.text('Neue unabhängige Ansicht'), findsOneWidget);
          Navigator.of(t.element(find.text('Neue unabhängige Ansicht'))).pop();
          await next;
          await t.pumpAndSettle();
          expect(fixture.requests.every((r) => r.method == 'GET'), isTrue);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    '101 exact saved source blocks retain an unprefixed OCR heading in reader and index',
    (t) async {
      final fixture = Fixture();
      final blocks = [
        {'kind': 'heading', 'text': 'Wörtliche Überschrift aus der Quelle'},
        {'kind': 'paragraph', 'text': 'Der exakt gespeicherte Absatz.'},
        {'kind': 'code', 'text': 'x = 2\ny = 3'},
      ];
      fixture.data['content'] = blocks.map((b) => b['text']).join('\n\n');
      fixture.data['source_blocks'] = blocks;
      await fixture.mount(t);
      await fixture.open(t, 'reader');
      final reader = t.widget<Ideas100SourceReader>(
        find.byType(Ideas100SourceReader),
      );
      expect(reader.blocks, blocks);
      expect(identical(reader.blocks, blocks), isFalse);
      expect(
        LearningContent(reader.text, blocks: reader.blocks).sections,
        blocks,
      );
      await tap(t, find.byKey(const ValueKey('source-reader-contents')));
      final index = t.widget<LearningHeadingIndex>(
        find.byType(LearningHeadingIndex),
      );
      expect(index.headings.map((h) => h.label), [
        'Wörtliche Überschrift aus der Quelle',
      ]);
      await tap(t, find.byKey(const ValueKey('learning-heading-0')));
      expect(find.byType(LearningHeadingIndex), findsNothing);
      expect(takeDocumentContent(t).first.sections.first['kind'], 'heading');
      expect(fixture.requests.every((r) => r.method == 'GET'), isTrue);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    '101 mismatched source blocks cannot add a heading or unseen source text',
    (t) async {
      final fixture = Fixture();
      fixture.data['content'] = 'Nur der gespeicherte lesbare Originalabsatz.';
      fixture.data['source_blocks'] = [
        {'kind': 'heading', 'text': 'Nicht belegte fremde Überschrift'},
      ];
      await fixture.mount(t);
      await fixture.open(t, 'reader');
      expect(
        takeDocumentContent(t).single.sections.single['text'],
        fixture.data['content'],
      );
      await tap(t, find.byKey(const ValueKey('source-reader-contents')));
      expect(find.byType(LearningHeadingIndex), findsNothing);
      expect(find.text('Keine Überschriften im Seitentext.'), findsOneWidget);
      expect(find.text('Nicht belegte fremde Überschrift'), findsNothing);
      expect(fixture.requests.every((r) => r.method == 'GET'), isTrue);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    '101 a corrected draft never inherits the original OCR block structure',
    (t) async {
      final fixture = Fixture();
      fixture.data['content'] = 'Originale Überschrift\n\nOriginaler Absatz.';
      fixture.data['source_blocks'] = [
        {'kind': 'heading', 'text': 'Originale Überschrift'},
        {'kind': 'paragraph', 'text': 'Originaler Absatz.'},
      ];
      await fixture.mount(t);
      await tap(t, find.text('Etwas verbessern'));
      await t.enterText(
        input('Text auf der Seite'),
        'Mein eigener neuer Entwurf.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await fixture.open(t, 'reader');
      final reader = t.widget<Ideas100SourceReader>(
        find.byType(Ideas100SourceReader),
      );
      expect(reader.text, 'Mein eigener neuer Entwurf.');
      expect(reader.blocks, isNull);
      await tap(t, find.byKey(const ValueKey('source-reader-contents')));
      expect(find.byType(LearningHeadingIndex), findsNothing);
      await t.tap(closeReader());
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(input('Text auf der Seite')).controller!.text,
        'Mein eigener neuer Entwurf.',
      );
      expect(fixture.requests.every((r) => r.method == 'GET'), isTrue);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    '101 a changed source-block snapshot closes its old reader even without a revision change',
    (t) async {
      final fixture = Fixture();
      await fixture.mount(t);
      await fixture.open(t, 'reader');
      fixture.update(
        () => fixture.data = {
          ...fixture.data,
          'source_blocks': [
            {'kind': 'paragraph', 'text': sourceText},
          ],
        },
      );
      await t.pumpAndSettle();
      expect(find.byType(Ideas100SourceReader), findsNothing);
      expect(fixture.requests.every((r) => r.method == 'GET'), isTrue);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    '101 search retains a usable viewport with a real keyboard inset at 320px and 200 percent',
    (t) async {
      final fixture = Fixture();
      await fixture.mount(t, width: 320, height: 568, scale: 2);
      await fixture.open(t, 'reader');
      await tap(t, find.byKey(const ValueKey('source-reader-search')));
      await t.showKeyboard(input('Wort oder Textstelle finden'));
      t.view.viewInsets = const FakeViewPadding(bottom: 360);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      final panel = find.byKey(const ValueKey('source-reader-tool-panel'));
      expect(t.getSize(panel).height, greaterThan(0));
      final editable = find.descendant(
        of: input('Wort oder Textstelle finden'),
        matching: find.byType(EditableText),
      );
      await Scrollable.ensureVisible(t.element(editable), alignment: .5);
      await t.pumpAndSettle();
      expect(editable.hitTestable(), findsOneWidget);
      await t.enterText(
        input('Wort oder Textstelle finden'),
        'wörtlicher Anfang',
      );
      await t.pumpAndSettle();
      expect(find.text('Treffer 1 von 2'), findsOneWidget);
      expect(closeReader().hitTestable(), findsOneWidget);
      expect(
        t.getSize(find.byKey(const ValueKey('source-reader-document'))).height,
        greaterThan(0),
      );
      expect(t.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      expect(fixture.requests.every((r) => r.method == 'GET'), isTrue);
      expect(t.takeException(), isNull);
    },
  );
}
