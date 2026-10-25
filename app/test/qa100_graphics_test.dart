import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/fraction_explorer.dart';
import 'package:schulpilot/graphic_zoom.dart';
import 'package:schulpilot/language_comparison_widget.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/learning_graphic_scope.dart';
import 'package:schulpilot/schulbuddy.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/ui.dart';

// Entirely invented fixtures. No private unit, photo, source, answer or provider.
Json language([List<String>? labels]) => {
  'kind': 'forms',
  'variant': 'classification',
  'title': 'Beispiele vergleichen',
  'disclosure': 'given',
  'labels': labels ?? ['I read books.', 'We read books.'],
  'numbers': [],
  'connections': [],
  'marks': [],
  'unit': '',
  'scene': null,
  'text_probe': null,
  'lab': null,
};
Json fraction() => {
  'kind': 'fraction',
  'variant': '',
  'title': 'Eigene Bruchprobe',
  'disclosure': 'given',
  'labels': [],
  'numbers': [3, 8],
  'connections': [],
  'marks': [],
  'unit': '',
};

class Harness {
  final calls = <http.Request>[];
  final nav = GlobalKey<NavigatorState>();
  late final AppState state =
      AppState(
          api: Api(
            base: 'https://synthetic.invalid/api',
            client: MockClient((request) async {
              calls.add(request);
              if (request.method == 'GET' &&
                  request.url.path.endsWith('/schulbuddy/context')) {
                return http.Response(
                  jsonEncode({
                    'context_key': 'synthetic-visible-graphic',
                    'available': true,
                    'label': 'Erfundene Darstellungsprobe',
                    'starters': [],
                    'history': [],
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                );
              }
              throw StateError(
                'No requests except the explicit synthetic context GET.',
              );
            }),
          )..token = 'invented-session',
        )
        ..user = {'id': 'invented-child', 'role': 'child'}
        ..familyId = 'invented-family';

  Future<void> mount(
    WidgetTester t,
    Widget child, {
    double width = 390,
    double scale = 1,
    bool reduced = true,
    bool buddy = false,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 844);
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: appTheme(brightness: Brightness.dark),
        builder: (context, page) {
          final body = MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduced,
            ),
            child: page!,
          );
          return buddy
              ? SchulbuddyHost(
                  state: state,
                  navigatorKey: nav,
                  location: '/learn/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  child: body,
                )
              : body;
        },
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Widget words(Json data) => SubjectGraphic(data, state: state);
  Widget parts([int n = 3, int d = 8]) =>
      FractionExplorer(numerator: n, denominator: d, state: state);
  Widget zoom(Json data) => GraphicZoom(
    state: state,
    block: data,
    render: (value) => SubjectGraphic(value, state: state),
  );
}

Finder mode(String id) => find.byKey(ValueKey('language-comparison-$id'));
Finder original(int index) =>
    find.byKey(ValueKey('language-comparison-original-$index'));
Text originalText(WidgetTester t, int index) => t.widget<Text>(original(index));
List<TextSpan> spans(WidgetTester t, int index) =>
    (originalText(t, index).textSpan! as TextSpan).children!.cast<TextSpan>();
TextSpan word(WidgetTester t, String text, [int index = 0]) =>
    spans(t, index).firstWhere((value) => value.text == text);
Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await t.tap(finder);
  await t.pumpAndSettle();
}

FractionModelPainter painter(WidgetTester t) => t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((value) => value.painter)
    .whereType<FractionModelPainter>()
    .single;
void scenario(
  String id,
  String name,
  Future<void> Function(WidgetTester, Harness) run, {
  bool allowContext = false,
}) {
  testWidgets('$id $name', (t) async {
    final h = Harness();
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    try {
      await run(t, h);
      expect(h.calls.where((r) => r.method != 'GET'), isEmpty);
      if (!allowContext) expect(h.calls, isEmpty);
      expect(t.takeException(), isNull);
    } finally {
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      h.state.dispose();
    }
  });
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  scenario('QG01', 'four original strings keep every character and order', (
    t,
    h,
  ) async {
    final labels = [
      'I  read.\nToday!',
      'We read; today.',
      'They read — today.',
      'You read today 😀',
    ];
    await h.mount(t, h.words(language(labels)));
    for (var i = 0; i < labels.length; i++) {
      expect(originalText(t, i).textSpan!.toPlainText(), labels[i]);
      expect(originalText(t, i).semanticsLabel, labels[i]);
      expect(originalText(t, i).maxLines, isNull);
    }
  });
  scenario(
    'QG02',
    'common words require all three examples rather than a pair',
    (t, h) async {
      await h.mount(
        t,
        h.words(
          language(['I read books.', 'We read books.', 'They read comics.']),
        ),
      );
      await tap(t, mode('commonWords'));
      expect(word(t, 'read').style!.decoration, TextDecoration.underline);
      expect(word(t, 'books').style, isNull);
    },
  );
  scenario(
    'QG03',
    'differences highlight only non-common words with two cues',
    (t, h) async {
      await h.mount(t, h.words(language()));
      expect(word(t, 'I').style!.backgroundColor, isNotNull);
      expect(word(t, 'I').style!.decoration, TextDecoration.underline);
      expect(word(t, 'read').style, isNull);
    },
  );
  scenario('QG04', 'case remains meaningful to the exact word comparison', (
    t,
    h,
  ) async {
    await h.mount(t, h.words(language(['Sun shines.', 'sun shines.'])));
    await tap(t, mode('commonWords'));
    expect(word(t, 'Sun').style, isNull);
    expect(word(t, 'shines').style!.decoration, TextDecoration.underline);
  });
  scenario('QG05', 'apostrophes umlauts punctuation and emoji are preserved', (
    t,
    h,
  ) async {
    final labels = ['L’école: schöne Wörter! 😀', 'L’école: andere Wörter? 😀'];
    await h.mount(t, h.words(language(labels)));
    await tap(t, mode('commonWords'));
    expect(word(t, 'L’école').style!.decoration, TextDecoration.underline);
    for (var i = 0; i < 2; i++) {
      expect(originalText(t, i).textSpan!.toPlainText(), labels[i]);
    }
  });
  scenario(
    'QG06',
    'neutral focus removes every highlight without changing data',
    (t, h) async {
      final data = language(), before = jsonEncode(language());
      await h.mount(t, h.words(data));
      await tap(t, mode('none'));
      expect(spans(t, 0).every((value) => value.style == null), isTrue);
      expect(jsonEncode(data), before);
      await tap(t, mode('differences'));
      expect(word(t, 'I').style!.backgroundColor, isNotNull);
    },
  );
  scenario('QG07', 'keyboard Enter activates a focus control', (t, h) async {
    await h.mount(t, h.words(language()));
    await t.ensureVisible(mode('commonWords'));
    await t.pumpAndSettle();
    Focus.of(
      t.element(
        find.descendant(
          of: mode('commonWords'),
          matching: find.text('Gleiche Wörter'),
        ),
      ),
    ).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(word(t, 'read').style!.decoration, TextDecoration.underline);
  });
  scenario('QG08', '320px at 200 percent retains full text and 48px controls', (
    t,
    h,
  ) async {
    await h.mount(
      t,
      h.words(
        language([
          'I read every original word in this sentence.',
          'We read every original word in this sentence.',
        ]),
      ),
      width: 320,
      scale: 2,
    );
    for (final id in ['differences', 'commonWords', 'none']) {
      await tap(t, mode(id));
      final rect = t.getRect(mode(id));
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
    await t.ensureVisible(original(1));
    await t.pumpAndSettle();
    expect(originalText(t, 1).maxLines, isNull);
  });
  scenario(
    'QG09',
    'given graphics do not leak undisclosed hint and solution blocks',
    (t, h) async {
      final hidden = language()
        ..['title'] = 'Hidden synthetic solution'
        ..['disclosure'] = 'solution';
      await h.mount(
        t,
        SubjectPresentation(
          {
            'version': 1,
            'blocks': [language(), hidden],
          },
          state: h.state,
          stages: const {'given'},
        ),
      );
      expect(find.byType(LanguageComparisonWidget), findsOneWidget);
      expect(find.text('Hidden synthetic solution'), findsNothing);
    },
  );
  scenario('QG10', 'invalid duplicate and overlong originals fail closed', (
    t,
    h,
  ) async {
    await h.mount(t, h.words(language(['same', 'same'])));
    expect(original(0), findsNothing);
    await h.mount(t, h.words(language(['😀' * 161, 'Other'])));
    expect(original(0), findsNothing);
  });
  scenario(
    'QG11',
    'source replacement expires old language callbacks and resets focus',
    (t, h) async {
      await h.mount(t, h.words(language()));
      await tap(t, mode('none'));
      final stale = t.widget<OutlinedButton>(mode('none')).onPressed!;
      await h.mount(
        t,
        h.words(language(['New first sentence.', 'New second sentence.'])),
      );
      stale();
      await t.pump();
      expect(find.textContaining('nicht in allen Beispielen'), findsOneWidget);
    },
  );
  scenario(
    'QG12',
    'same-user new session evicts original texts and stale controls',
    (t, h) async {
      await h.mount(t, h.words(language()));
      final stale = t.widget<OutlinedButton>(mode('none')).onPressed!;
      h.state.api.token = 'new-invented-session';
      h.state.refreshState();
      await t.pumpAndSettle();
      stale();
      await t.pump();
      expect(original(0), findsNothing);
    },
  );
  scenario(
    'QG13',
    'fraction painter and semantic description agree on quantities',
    (t, h) async {
      final semantics = t.ensureSemantics();
      try {
        await h.mount(t, h.parts());
        final p = painter(t);
        expect(p.numerator, 3);
        expect(p.denominator, 8);
        const label =
            '3 von 8 gleich großen Teilen sind markiert. '
            'Kreismodell. Ein Ganzes. 3 von 8 gleich großen Teilen sind markiert.';
        final image = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == label,
        );
        expect(image, findsOneWidget);
        expect(
          t.getSemantics(image),
          matchesSemantics(label: label, isImage: true),
        );
      } finally {
        semantics.dispose();
      }
    },
  );
  scenario('QG14', 'switching circle and bar changes representation only', (
    t,
    h,
  ) async {
    await h.mount(t, h.parts());
    await tap(t, find.byTooltip('Balkenmodell'));
    expect(painter(t).bars, isTrue);
    expect(painter(t).numerator, 3);
    expect(painter(t).denominator, 8);
    await tap(t, find.byTooltip('Kreismodell'));
    expect(painter(t).bars, isFalse);
  });
  scenario('QG15', 'denominator focus explains the exact subdivision', (
    t,
    h,
  ) async {
    await h.mount(t, h.parts());
    await tap(t, find.byKey(const ValueKey('fraction-focus-denominator')));
    expect(painter(t).focus, 'denominator');
    expect(
      find.text('Nenner 8: Das Ganze ist in 8 gleich große Teile geteilt.'),
      findsOneWidget,
    );
  });
  scenario('QG16', 'numerator focus names marked rather than all parts', (
    t,
    h,
  ) async {
    await h.mount(t, h.parts());
    await tap(t, find.byKey(const ValueKey('fraction-focus-numerator')));
    expect(painter(t).focus, 'numerator');
    expect(find.text('Zähler 3: 3 Teile sind markiert.'), findsOneWidget);
  });
  scenario('QG17', 'whole focus restores the complete reference model', (
    t,
    h,
  ) async {
    await h.mount(t, h.parts());
    await tap(t, find.byKey(const ValueKey('fraction-focus-numerator')));
    await tap(t, find.byKey(const ValueKey('fraction-focus-whole')));
    expect(painter(t).focus, 'whole');
    expect(
      find.text('Ein Ganzes. 3 von 8 gleich großen Teilen sind markiert.'),
      findsOneWidget,
    );
  });
  scenario(
    'QG18',
    'zero and complete fractions remain exact at allowed boundaries',
    (t, h) async {
      await h.mount(t, h.parts(0, 1));
      expect(painter(t).numerator, 0);
      expect(painter(t).denominator, 1);
      await h.mount(t, h.parts(24, 24));
      expect(painter(t).numerator, 24);
      expect(painter(t).denominator, 24);
    },
  );
  scenario('QG19', 'reduced movement has a final static focused frame', (
    t,
    h,
  ) async {
    await h.mount(t, h.parts(), reduced: true);
    await tap(t, find.byKey(const ValueKey('fraction-focus-denominator')));
    await t.pump(const Duration(seconds: 2));
    expect(t.binding.hasScheduledFrame, isFalse);
    expect(painter(t).focus, 'denominator');
  });
  scenario(
    'QG20',
    'finite graphic bus reports the actual bar numerator phase',
    (t, h) async {
      final events = <(int, String)>[];
      await h.mount(
        t,
        LearningGraphicScope(
          index: 0,
          phase: 'initial',
          onChanged: (i, p) => events.add((i, p)),
          child: h.parts(),
        ),
      );
      await tap(t, find.byTooltip('Balkenmodell'));
      await tap(t, find.byKey(const ValueKey('fraction-focus-numerator')));
      expect(events.last, (0, 'fraction-bar-numerator'));
    },
  );
  scenario(
    'QG21',
    'changed fraction resets representation and selected focus',
    (t, h) async {
      await h.mount(t, h.parts());
      await tap(t, find.byTooltip('Balkenmodell'));
      await tap(t, find.byKey(const ValueKey('fraction-focus-numerator')));
      await h.mount(t, h.parts(1, 4));
      expect(painter(t).bars, isFalse);
      expect(painter(t).focus, 'whole');
      expect(painter(t).denominator, 4);
    },
  );
  scenario(
    'QG22',
    'account replacement removes private fraction and old selection',
    (t, h) async {
      await h.mount(t, h.parts());
      final old = t
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('fraction-focus-numerator')),
          )
          .onSelected!;
      h.state.user = {'id': 'different-invented-child', 'role': 'child'};
      h.state.refreshState();
      await t.pumpAndSettle();
      old(true);
      await t.pump();
      expect(find.byKey(const ValueKey('fraction-explorer')), findsNothing);
    },
  );
  scenario('QG23', 'zoom receives the same immutable graphic data', (
    t,
    h,
  ) async {
    final data = fraction(), before = jsonEncode(fraction());
    await h.mount(t, h.zoom(data), width: 1280);
    await tap(t, find.byKey(const ValueKey('open-graphic-zoom')));
    expect(painter(t).numerator, 3);
    expect(painter(t).denominator, 8);
    await tap(t, find.byTooltip('Balkenmodell'));
    expect(jsonEncode(data), before);
    await tap(t, find.byTooltip('Zur Aufgabe zurück'));
  });
  scenario('QG24', 'zoom buttons scale and reset without changing the model', (
    t,
    h,
  ) async {
    await h.mount(t, h.zoom(fraction()));
    await tap(t, find.byKey(const ValueKey('open-graphic-zoom')));
    final viewer = t.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    await tap(t, find.byTooltip('Grafik vergrößern'));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1.25);
    await tap(t, find.byTooltip('Ansicht zurücksetzen'));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
    expect(painter(t).numerator, 3);
    await tap(t, find.byTooltip('Zur Aufgabe zurück'));
  });
  scenario('QG25', 'stale zoom close cannot pop an overlaid foreign dialog', (
    t,
    h,
  ) async {
    await h.mount(t, h.zoom(fraction()));
    await tap(t, find.byKey(const ValueKey('open-graphic-zoom')));
    final old = t
        .widget<IconButton>(
          find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == 'Zur Aufgabe zurück',
          ),
        )
        .onPressed!;
    h.nav.currentState!.push(
      DialogRoute<void>(
        context: t.element(find.byType(InteractiveViewer)),
        builder: (_) => const AlertDialog(content: Text('Foreign dialog')),
      ),
    );
    await t.pumpAndSettle();
    old();
    await t.pumpAndSettle();
    expect(find.text('Foreign dialog'), findsOneWidget);
    h.nav.currentState!.pop();
    await t.pumpAndSettle();
    await tap(t, find.byTooltip('Zur Aufgabe zurück'));
  });
  scenario('QG26', 'session revocation closes an already open private zoom', (
    t,
    h,
  ) async {
    await h.mount(t, h.zoom(fraction()));
    await tap(t, find.byKey(const ValueKey('open-graphic-zoom')));
    final staleZoom = t
        .widget<IconButton>(
          find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == 'Grafik vergrößern',
          ),
        )
        .onPressed!;
    h.state.api.token = 'revoked-and-replaced-session';
    h.state.refreshState();
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    staleZoom();
    await t.pump();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('Eigene Bruchprobe'), findsNothing);
  });
  scenario(
    'QG27',
    'language zoom at 320px and 200 percent has no horizontal control discovery',
    (t, h) async {
      await h.mount(t, h.zoom(language()), width: 320, scale: 2);
      await tap(t, find.byKey(const ValueKey('open-graphic-zoom')));
      final viewport = t.getRect(find.byType(InteractiveViewer));
      for (final id in ['differences', 'commonWords', 'none']) {
        final rect = t.getRect(mode(id));
        expect(rect.left, greaterThanOrEqualTo(viewport.left));
        expect(rect.right, lessThanOrEqualTo(viewport.right));
        expect(rect.height, greaterThanOrEqualTo(48));
        await tap(t, mode(id));
      }
      final viewer = t.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.transformationController!.value.getTranslation().x, 0);
      expect(originalText(t, 0).textSpan!.toPlainText(), 'I read books.');
      await tap(t, find.byTooltip('Zur Aufgabe zurück'));
    },
  );
  scenario('QG28', 'changed source graphic removes the old open zoom', (
    t,
    h,
  ) async {
    await h.mount(t, h.zoom(fraction()));
    await tap(t, find.byKey(const ValueKey('open-graphic-zoom')));
    await h.mount(
      t,
      h.zoom(fraction()..['title'] = 'Different invented source'),
    );
    expect(find.byType(InteractiveViewer), findsNothing);
  });
  scenario(
    'QG29',
    'background fraction interaction cannot publish a new phase',
    (t, h) async {
      final events = <(int, String)>[];
      await h.mount(
        t,
        LearningGraphicScope(
          index: 0,
          phase: 'initial',
          onChanged: (i, p) => events.add((i, p)),
          child: h.parts(),
        ),
        reduced: false,
      );
      final old = t
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('fraction-focus-numerator')),
          )
          .onSelected!;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      old(true);
      await t.pump();
      expect(events, isEmpty);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
    },
  );
  scenario(
    'QG30',
    'Tutor opens only context GET for the actual visible graphic phase',
    (t, h) async {
      final block = fraction();
      final step = {
        'id': 'synthetic-step',
        'text': 'Eigene kurze Erklärung.',
        'disclosure': 'given',
        'presentation': {
          'version': 1,
          'blocks': [block],
        },
      };
      await h.mount(
        t,
        LearningExplanation(
          text: 'Eigene Erklärung.',
          steps: [step],
          state: h.state,
          unitId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          questionId: 'synthetic-question',
          sourceKey: 'synthetic-v1',
        ),
        buddy: true,
      );
      await tap(t, find.byTooltip('Balkenmodell'));
      await tap(t, find.byKey(const ValueKey('fraction-focus-numerator')));
      await tap(t, find.byTooltip('Schulbuddy öffnen'));
      expect(h.calls.length, 1);
      final query = h.calls.single.url.queryParameters;
      expect(query['explanation_step_id'], 'synthetic-step');
      expect(query['graphic_index'], '0');
      expect(query['graphic_phase'], 'fraction-bar-numerator');
      expect(query['question_id'], 'synthetic-question');
      await tap(t, find.byTooltip('Schulbuddy schließen'));
    },
    allowContext: true,
  );
  scenario(
    'QG31',
    'actual compact presentation survives own zoom and rejects foreign/session callbacks',
    (t, h) async {
      final data = {
        'version': 1,
        'blocks': [
          language(['I play football.', 'She plays football.']),
          fraction(),
        ],
      };
      await h.mount(
        t,
        SubjectPresentation(data, state: h.state, stages: const {'given'}),
        width: 320,
        scale: 2,
      );
      final openers = find.byKey(const ValueKey('open-graphic-zoom'));
      expect(openers, findsNWidgets(2));
      // Control: the existing fraction compact entry also stays mounted.
      await tap(t, openers.last);
      final viewerFinder = find.byType(InteractiveViewer);
      expect(viewerFinder, findsOneWidget);
      expect(
        find.descendant(
          of: viewerFinder,
          matching: find.byType(FractionExplorer),
        ),
        findsOneWidget,
      );
      await tap(t, find.byTooltip('Zur Aufgabe zurück'));
      final formsOpen = find.descendant(
        of: find.byType(LanguageComparisonWidget),
        matching: find.byKey(const ValueKey('open-graphic-zoom')),
      );
      final staleOpen = t.widget<IconButton>(formsOpen).onPressed!;
      await tap(t, formsOpen);
      expect(
        viewerFinder,
        findsOneWidget,
        reason: 'The production compact launcher survives its own route cover.',
      );
      final viewer = t.widget<InteractiveViewer>(viewerFinder);
      final staleClose = t
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Zur Aufgabe zurück',
            ),
          )
          .onPressed!;
      final staleScale = t
          .widget<IconButton>(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Grafik vergrößern',
              ),
            ),
          )
          .onPressed!;
      h.nav.currentState!.push(
        DialogRoute<void>(
          context: t.element(viewerFinder),
          builder: (_) =>
              const AlertDialog(content: Text('Foreign compact overlay')),
        ),
      );
      await t.pumpAndSettle();
      staleClose();
      staleScale();
      await t.pumpAndSettle();
      expect(find.text('Foreign compact overlay'), findsOneWidget);
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
      h.nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(viewerFinder, findsOneWidget);
      final common = find.descendant(
        of: viewerFinder,
        matching: mode('commonWords'),
      );
      expect(t.getRect(common).right, lessThanOrEqualTo(320));
      await tap(t, common);
      final savedOriginal = t.widget<Text>(
        find.descendant(of: viewerFinder, matching: original(0)),
      );
      expect(savedOriginal.textSpan!.toPlainText(), 'I play football.');
      h.state.api.token = 'another-invented-session';
      h.state.refreshState();
      await t.pumpAndSettle();
      expect(viewerFinder, findsNothing);
      staleOpen();
      staleClose();
      await t.pumpAndSettle();
      expect(viewerFinder, findsNothing);
      expect(find.textContaining('I play football.'), findsNothing);
    },
  );
}
