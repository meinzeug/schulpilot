// Artificial saved renderer/API fixtures only. No real learner data or provider.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/fraction_composition_widget.dart';
import 'package:schulpilot/fraction_explorer.dart';
import 'package:schulpilot/learning_explanation.dart';

import 'learning_room_test.dart' as room;
import 'saved_visual_explanation_107_test.dart' as visual;

Json composition({
  int wholes = 1,
  int rest = 1,
  int denominator = 4,
  int version = 1,
}) => {
  'id': 'composition-step',
  'reference': {'id': 'math.fraction.wholes_remainder', 'version': version},
  'disclosure': 'solution',
  'text': 'Die gespeicherte Lösung bündelt Ganze und Rest.',
  'presentation': {
    'version': 1,
    'evidence_kind': 'knowledge',
    'blocks': [
      for (final n in [
        for (var i = 0; i < wholes; i++) denominator,
        if (rest > 0) rest,
      ])
        {
          'kind': 'fraction',
          'title': n == denominator ? 'Ein Ganzes' : 'Verbleibender Bruchteil',
          'disclosure': 'solution',
          'numbers': [n, denominator],
          'labels': <String>[],
          'connections': <dynamic>[],
          'marks': <dynamic>[],
          'unit': '',
          'variant': '',
        },
    ],
  },
};

Widget explanation(Json step, {AppState? state, Object source = 'source'}) =>
    LearningExplanation(
      text: 'Unveränderter gespeicherter Erklärungstext.',
      steps: [step],
      state: state,
      sourceKey: source,
    );

Finder part(int index) =>
    find.byKey(ValueKey('fraction-composition-part-$index'));

class CompositionRound extends room.SavedRound {
  final explanationRequests = <http.Request>[];
  final readRequests = <http.Request>[];
  Completer<http.Response>? delayed;
  String responseId = 'second';

  CompositionRound()
    : super(
        questions: [
          room.question('first'),
          room.question('second'),
          room.question('future'),
        ],
      ) {
    final questions = value['questions'] as List;
    for (final q in questions.take(2)) {
      q['attempts'] = <Json>[
        {'answer': '1 1/4', 'outcome': 'correct', 'assisted': false},
      ];
    }
    questions[1]['prompt'] = 'Schreibe 5/4 als gemischte Zahl.';
    value['subject'] = 'Mathematik';
    value['topic'] = 'Ganze und Rest';
    value['supports_question_explanation'] = true;
    value['learning_session'] = {
      'source_signature': 'a' * 64,
      'action': {'reason_code': 'entry_probe_followup'},
    };
    value['pending_feedback'] = {
      'attempt_id': 'saved-second-attempt',
      'question_id': 'second',
      'answer': '1 1/4',
      'outcome': 'correct',
      'assisted': false,
      'explanation': 'Die Lösungsgrafik zeigt ein Ganzes und ein Viertel.',
    };
  }

  http.Response solution() => room.jsonReply({
    'question_id': responseId,
    'explanation': 'Gespeicherte Erklärung für Aufgabe zwei.',
    'explanation_visual_status': 'ready',
    'explanation_steps': [composition()],
  });

  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/visual-position')) {
      readRequests.add(request);
      expect(request.method, 'GET');
      return room.jsonReply({
        'source_signature': 'a' * 64,
        'revision': 1,
        'position': null,
      });
    }
    if (request.url.path.endsWith('/explanation')) {
      explanationRequests.add(request);
      calls.add('${request.method} ${request.url.path}');
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {'question_id': 'second'});
      return delayed == null ? solution() : delayed!.future;
    }
    return super.handle(request);
  }
}

Future<void> expandWhy(WidgetTester tester) async {
  await room.tapText(tester, 'Warum das stimmt');
  await tester.ensureVisible(
    find.byKey(const ValueKey('feedback-question-explanation')),
  );
  await tester.pumpAndSettle();
}

Future<void> openWhySolution(WidgetTester tester) async {
  await expandWhy(tester);
  await tester.tap(find.byKey(const ValueKey('feedback-question-explanation')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    for (final font in ['Nunito', 'SpaceGrotesk']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('127 v1 groups five quarters without changing saved prose', (
    tester,
  ) async {
    final step = composition();
    final before = jsonEncode(step);
    await visual.mount(tester, explanation(step));
    expect(find.text('5 Viertel = 1 Ganzes + 1 Viertel'), findsOneWidget);
    expect(find.text(step['text']), findsOneWidget);
    expect(find.byType(FractionExplorer), findsNothing);
    final models = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<FractionModelPainter>()
        .toList();
    expect(models.map((p) => [p.numerator, p.denominator]), [
      [4, 4],
      [1, 4],
    ]);
    expect(jsonEncode(step), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('127 v2 displays the same bound values and singular grammar', (
    tester,
  ) async {
    await visual.mount(tester, explanation(composition(version: 2, rest: 3)));
    expect(find.text('7 Viertel = 1 Ganzes + 3 Viertel'), findsOneWidget);
    expect(part(0), findsOneWidget);
    expect(part(1), findsOneWidget);
  });

  testWidgets('127 exact wholes do not invent a zero remainder', (
    tester,
  ) async {
    await visual.mount(tester, explanation(composition(wholes: 2, rest: 0)));
    expect(find.text('8 Viertel = 2 Ganze'), findsOneWidget);
    expect(part(0), findsOneWidget);
    expect(part(1), findsOneWidget);
    expect(part(2), findsNothing);
  });

  for (final viewport in [
    (320.0, 2.0),
    (390.0, 2.0),
    (768.0, 1.0),
    (1280.0, 1.0),
  ]) {
    testWidgets(
      '127 unified whole and rest fit ${viewport.$1}/${viewport.$2}',
      (tester) async {
        await visual.mount(
          tester,
          explanation(composition()),
          width: viewport.$1,
          scale: viewport.$2,
        );
        expect(tester.takeException(), isNull);
        final whole = tester.getRect(part(0)), rest = tester.getRect(part(1));
        expect((whole.top - rest.top).abs(), lessThan(1));
        expect(whole.right, lessThanOrEqualTo(rest.left));
        expect(rest.right, lessThanOrEqualTo(viewport.$1));
        expect(whole.bottom, lessThan(844));
        expect(rest.bottom, lessThan(844));
        expect(
          tester
              .getSize(find.byKey(const ValueKey('fraction-composition')))
              .height,
          lessThan(600),
        );
      },
    );
  }

  testWidgets('127 three wholes and remainder stay one bounded group', (
    tester,
  ) async {
    await visual.mount(
      tester,
      explanation(composition(wholes: 3, rest: 2, denominator: 3)),
      width: 320,
      scale: 2,
    );
    expect(find.text('11 Drittel = 3 Ganze + 2 Drittel'), findsOneWidget);
    expect(part(3), findsOneWidget);
    expect(tester.getRect(part(3)).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  test(
    '127 rejects unbound recipes, disclosure and incoherent compositions',
    () {
      final examples = <Json>[
        composition()..['reference'] = {'id': 'other', 'version': 1},
        composition(version: 3),
        composition()..['disclosure'] = 'given',
        composition(wholes: 0),
        composition(wholes: 4),
        composition(denominator: 25),
        composition()..['presentation']['blocks'][1]['numbers'] = [1, 3],
        composition()..['presentation']['blocks'][0]['numbers'] = [3, 4],
        composition()..['presentation']['blocks'][0]['numbers'] = [true, 4],
        composition()..['presentation']['blocks'][1]['numbers'] = [1.5, 4],
        composition()..['presentation']['blocks'][1]['disclosure'] = 'given',
      ];
      for (final step in examples) {
        expect(FractionCompositionWidget.supports(step), isFalse);
      }
    },
  );

  testWidgets('127 introductory and other recipes keep existing explorer', (
    tester,
  ) async {
    final given = composition(rest: 0)..['disclosure'] = 'given';
    given['presentation']['blocks'][0]['disclosure'] = 'given';
    await visual.mount(tester, explanation(given));
    expect(find.byType(FractionExplorer), findsOneWidget);
    expect(find.byType(FractionCompositionWidget), findsNothing);
    final ordinary = composition()
      ..['reference'] = {'id': 'math.fraction.part_whole', 'version': 1};
    await visual.mount(tester, explanation(ordinary, source: 'ordinary'));
    expect(find.byType(FractionExplorer), findsNWidgets(2));
    expect(find.byType(FractionCompositionWidget), findsNothing);
  });

  testWidgets('127 accessible description preserves every displayed part', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await visual.mount(tester, explanation(composition()));
      expect(
        find.bySemanticsLabel('5 Viertel sind 1 Ganzes und 1 Viertel'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Ein Ganzes: 4 von 4 Teilen markiert.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('1 Viertel: 1 von 4 Teilen markiert.'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('127 group clears on token change without a network request', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = visual.app((request) {
      calls.add(request);
      throw StateError('The local renderer must not request anything.');
    });
    addTearDown(state.dispose);
    state.api.token = 'old';
    await visual.mount(tester, explanation(composition(), state: state));
    expect(find.text('5 Viertel = 1 Ganzes + 1 Viertel'), findsOneWidget);
    state.api.token = 'new';
    state.refreshState();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fraction-composition')), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('127 whole group zoom closes when the account changes', (
    tester,
  ) async {
    final state = visual.app((_) => throw StateError('No request allowed'));
    addTearDown(state.dispose);
    await visual.mount(tester, explanation(composition(), state: state));
    await tester.tap(find.byKey(const ValueKey('open-graphic-zoom')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Zur Aufgabe zurück'), findsOneWidget);
    state.user = {'id': 'other', 'role': 'child', 'child_id': 'other'};
    state.refreshState();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Zur Aufgabe zurück'), findsNothing);
    expect(find.byKey(const ValueKey('fraction-composition')), findsNothing);
  });

  testWidgets('127 deliberate grouping preserves quantity and exact pieces', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = visual.app((request) {
      calls.add(request);
      throw StateError('Grouping is purely local.');
    });
    addTearDown(state.dispose);
    final step = composition();
    final before = jsonEncode(step);
    await visual.mount(tester, explanation(step, state: state));
    final equation = find.text('5 Viertel = 1 Ganzes + 1 Viertel');
    expect(equation, findsOneWidget);
    expect(
      find.byKey(const ValueKey('fraction-composition-bundled')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Einzelteile ansehen'));
    await tester.tap(find.text('Einzelteile ansehen'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fraction-composition-bundled')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('fraction-composition-individual')),
      findsOneWidget,
    );
    for (var index = 0; index < 5; index++) {
      expect(
        find.byKey(ValueKey('fraction-composition-tile-$index')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('fraction-composition-tile-5')),
      findsNothing,
    );
    expect(find.text('Jedes Teil ist 1 Viertel.'), findsOneWidget);
    expect(equation, findsOneWidget);
    await tester.ensureVisible(find.text('Ganze bündeln'));
    await tester.tap(find.text('Ganze bündeln'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fraction-composition-individual')),
      findsNothing,
    );
    expect(part(0), findsOneWidget);
    expect(part(1), findsOneWidget);
    expect(equation, findsOneWidget);
    expect(jsonEncode(step), before);
    expect(calls, isEmpty);
  });

  testWidgets('127 maximum 95 parts remain equal compact tiles at 320/2x', (
    tester,
  ) async {
    await visual.mount(
      tester,
      explanation(composition(wholes: 3, rest: 23, denominator: 24)),
      width: 320,
      scale: 2,
    );
    await tester.ensureVisible(find.text('Einzelteile ansehen'));
    await tester.tap(find.text('Einzelteile ansehen'));
    await tester.pumpAndSettle();
    expect(
      find.text('95 Vierundzwanzigstel = 3 Ganze + 23 Vierundzwanzigstel'),
      findsOneWidget,
    );
    Size? first;
    for (var index = 0; index < 95; index++) {
      final tile = find.byKey(ValueKey('fraction-composition-tile-$index'));
      expect(tile, findsOneWidget);
      final size = tester.getSize(tile);
      first ??= size;
      expect(size, first);
      expect(size.width, inInclusiveRange(16, 32));
      expect(size.width, size.height);
      final box = tester.getRect(tile);
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(320));
    }
    expect(
      find.byKey(const ValueKey('fraction-composition-tile-95')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('127 reduced motion switches immediately at 320/2x', (
    tester,
  ) async {
    await visual.mount(
      tester,
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 844),
          textScaler: TextScaler.linear(2),
          disableAnimations: true,
        ),
        child: explanation(composition()),
      ),
      width: 320,
      scale: 2,
    );
    final toggle = find.byKey(const ValueKey('fraction-composition-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    final switcher = tester.widget<AnimatedSwitcher>(
      find.descendant(
        of: find.byKey(const ValueKey('fraction-composition')),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcher.duration, Duration.zero);
    expect(
      find.byKey(const ValueKey('fraction-composition-bundled')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('fraction-composition-individual')),
      findsOneWidget,
    );
    expect(find.text('Ganze bündeln'), findsOneWidget);
    expect(find.text('5 Viertel = 1 Ganzes + 1 Viertel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '127 changed source resets grouping and retains the new quantity',
    (tester) async {
      await visual.mount(tester, explanation(composition()));
      await tester.ensureVisible(find.text('Einzelteile ansehen'));
      await tester.tap(find.text('Einzelteile ansehen'));
      await tester.pumpAndSettle();
      expect(find.text('Ganze bündeln'), findsOneWidget);
      await visual.mount(
        tester,
        explanation(composition(rest: 3), source: 'new-source'),
      );
      expect(find.text('7 Viertel = 1 Ganzes + 3 Viertel'), findsOneWidget);
      expect(find.text('Einzelteile ansehen'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fraction-composition-individual')),
        findsNothing,
      );
      expect(part(1), findsOneWidget);
    },
  );

  testWidgets('127 grouping callback cannot act behind a foreign dialog', (
    tester,
  ) async {
    await visual.mount(tester, explanation(composition()));
    final toggle = find.byKey(const ValueKey('fraction-composition-toggle'));
    final action = tester.widget<OutlinedButton>(toggle).onPressed!;
    unawaited(
      showDialog<void>(
        context: tester.element(toggle),
        builder: (_) => const AlertDialog(title: Text('Andere Ansicht')),
      ),
    );
    await tester.pumpAndSettle();
    action();
    await tester.pumpAndSettle();
    expect(find.text('Andere Ansicht'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('fraction-composition-individual'),
        skipOffstage: false,
      ),
      findsNothing,
    );
  });

  testWidgets('127 why opens the answered question even on entry followup', (
    tester,
  ) async {
    final server = CompositionRound();
    final before = jsonEncode(server.value);
    final harness = await room.openRound(tester, server, textScale: 2);
    expect(find.byType(FractionCompositionWidget), findsNothing);
    expect(server.explanationRequests, isEmpty);
    await expandWhy(tester);
    expect(find.byType(FractionCompositionWidget), findsNothing);
    expect(server.explanationRequests, isEmpty);
    await tester.tap(
      find.byKey(const ValueKey('feedback-question-explanation')),
    );
    // perform() remains busy while its explicit explanation dialog is open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(server.explanationRequests, hasLength(1));
    expect(find.text('5 Viertel = 1 Ganzes + 1 Viertel'), findsOneWidget);
    expect(
      (tester.getRect(part(0)).top - tester.getRect(part(1)).top).abs(),
      lessThan(1),
    );
    expect(tester.getRect(part(0)).bottom, lessThan(844));
    expect(tester.getRect(part(1)).bottom, lessThan(844));
    expect(tester.takeException(), isNull);
    expect(find.text('Was bedeutet future?'), findsNothing);
    expect(server.answers, 0);
    expect(server.acknowledgements, 0);
    expect(jsonEncode(server.value), before);
    harness.router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Warum das stimmt'), findsOneWidget);
    expect(server.acknowledgements, 0);
    expect(jsonEncode(server.value), before);
  });

  testWidgets('127 late why response cannot cross a replaced token', (
    tester,
  ) async {
    final server = CompositionRound()..delayed = Completer<http.Response>();
    final harness = await room.openRound(tester, server);
    await expandWhy(tester);
    await tester.tap(
      find.byKey(const ValueKey('feedback-question-explanation')),
    );
    await tester.pump();
    expect(server.explanationRequests, hasLength(1));
    harness.state.api.token = 'replacement';
    harness.state.refreshState();
    server.delayed!.complete(server.solution());
    await tester.pumpAndSettle();
    expect(find.text('Kurz erklärt'), findsNothing);
    expect(find.byType(FractionCompositionWidget), findsNothing);
    expect(server.answers, 0);
    expect(server.acknowledgements, 0);
  });

  testWidgets('127 stale why callback is blocked behind a foreign dialog', (
    tester,
  ) async {
    final server = CompositionRound();
    await room.openRound(tester, server);
    await expandWhy(tester);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('feedback-question-explanation')),
    );
    final context = tester.element(
      find.byKey(const ValueKey('feedback-question-explanation')),
    );
    expect(context.mounted, isTrue);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Fremde Ansicht')),
      ),
    );
    await tester.pumpAndSettle();
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(server.explanationRequests, isEmpty);
    expect(find.text('Fremde Ansicht'), findsOneWidget);
  });

  testWidgets('127 wrong question receipt cannot display another solution', (
    tester,
  ) async {
    final server = CompositionRound()..responseId = 'future';
    await room.openRound(tester, server);
    await openWhySolution(tester);
    expect(server.explanationRequests, hasLength(1));
    expect(find.text('Kurz erklärt'), findsNothing);
    expect(find.byType(FractionCompositionWidget), findsNothing);
    expect(server.answers, 0);
    expect(server.acknowledgements, 0);
  });

  testWidgets('127 legacy backend preserves the saved why text', (
    tester,
  ) async {
    final server = CompositionRound();
    server.value.remove('supports_question_explanation');
    await room.openRound(tester, server);
    await room.tapText(tester, 'Warum das stimmt');
    expect(
      find.text('Die Lösungsgrafik zeigt ein Ganzes und ein Viertel.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('feedback-question-explanation')),
      findsNothing,
    );
    expect(server.explanationRequests, isEmpty);
  });
}
