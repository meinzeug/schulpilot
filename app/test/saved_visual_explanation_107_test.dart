import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/fraction_explorer.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/learning_graphic_scope.dart';
import 'package:schulpilot/learning_path_view.dart';
import 'package:schulpilot/saved_visual_explanation.dart';
import 'package:schulpilot/visual_preparation_card.dart';
import 'package:schulpilot/ui.dart';

Json explanationStep(String id, int n, int d) => {
  'id': id,
  'text': '$n von $d gleich großen Teilen.',
  'disclosure': 'given',
  'reference': {'id': 'math.fraction.part_whole', 'version': 1},
  'presentation': {
    'version': 1,
    'evidence_kind': 'knowledge',
    'blocks': [
      {
        'kind': 'fraction',
        'title': '$n/$d',
        'disclosure': 'given',
        'labels': <String>[],
        'numbers': [n, d],
        'connections': <dynamic>[],
        'variant': '',
        'unit': '',
      },
    ],
  },
};
final steps = [explanationStep('e1', 1, 2), explanationStep('e2', 2, 3)];
http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
AppState app(FutureOr<http.Response> Function(http.Request) handler) =>
    AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async => await handler(request)),
        ),
      )
      ..user = {
        'id': 'reader',
        'role': 'child',
        'child_id': 'child',
        'display_name': 'Künstliches Testkind',
        'families': <Json>[],
      };
Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 844),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget view(AppState state, {Object source = 'source', List<Json>? values}) =>
    SavedVisualExplanation(
      state: state,
      unitId: 'unit',
      text: 'Alte gespeicherte Erklärung.',
      steps: values ?? steps,
      sourceKey: source,
    );
void main() {
  testWidgets('107 enlarged graphic keeps phase and saves it after returning', (
    tester,
  ) async {
    final writes = <Json>[];
    final state = app((request) {
      if (request.method == 'PUT') {
        writes.add(Json.from(jsonDecode(request.body)));
      }
      return reply({
        'source_signature': 'a' * 64,
        'revision': request.method == 'PUT' ? 2 : 1,
        'position': null,
      });
    });
    addTearDown(state.dispose);
    await mount(tester, view(state));
    await tester.ensureVisible(find.byKey(const ValueKey('open-graphic-zoom')));
    await tester.tap(find.byKey(const ValueKey('open-graphic-zoom')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Nenner').hitTestable());
    await tester.tap(find.text('Nenner').hitTestable());
    await tester.pumpAndSettle();
    expect(
      writes,
      isEmpty,
      reason: 'The underlying route waits for its own authorized return.',
    );
    await tester.tap(find.byTooltip('Zur Aufgabe zurück'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nenner 2: Das Ganze ist in 2 gleich große Teile geteilt.'),
      findsOneWidget,
    );
    expect(
      writes.single['position']['graphic_phase'],
      'fraction-circle-denominator',
    );
  });

  testWidgets(
    '107 curated foundation is visibly separate from photographed source',
    (tester) async {
      final own = explanationStep('e1', 1, 2)
        ..['source_refs'] = [
          {
            'source_kind': 'curated_foundation',
            'label': 'Eigenes kuratiertes Zusatzwissen',
          },
        ];
      await mount(
        tester,
        LearningExplanation(text: 'Legacy', steps: [own], sourceKey: 'own'),
      );
      expect(
        find.text('Zusatzwissen · eigene kuratierte Grundlagenregel'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '107 one actual step pairs saved text and its graphic, never all graphics',
    (tester) async {
      final positions = <Json>[];
      await mount(
        tester,
        LearningExplanation(
          text: 'Legacy',
          steps: steps,
          sourceKey: 'a',
          onPositionChanged: positions.add,
        ),
      );
      expect(
        tester
            .widget<FractionExplorer>(find.byType(FractionExplorer))
            .denominator,
        2,
      );
      expect(
        tester.widget<LearningReader>(find.byType(LearningReader)).text,
        '1 von 2 gleich großen Teilen.',
      );
      await tester.ensureVisible(find.text('Nächster Schritt'));
      await tester.tap(find.text('Nächster Schritt'));
      await tester.pumpAndSettle();
      expect(find.byType(FractionExplorer), findsOneWidget);
      expect(
        tester
            .widget<FractionExplorer>(find.byType(FractionExplorer))
            .denominator,
        3,
      );
      expect(
        tester.widget<LearningReader>(find.byType(LearningReader)).text,
        '2 von 3 gleich großen Teilen.',
      );
      expect(positions.single['explanation_step_id'], 'e2');
    },
  );
  testWidgets('107 legacy text reads without a visual position request', (
    tester,
  ) async {
    final calls = <String>[];
    final state = app((r) {
      calls.add(r.method);
      return reply({});
    });
    addTearDown(state.dispose);
    await mount(tester, view(state, values: []));
    expect(find.byType(LearningReader), findsOneWidget);
    expect(calls, isEmpty);
  });
  for (final size in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '107 saved step is readable at $size $scale without overflow',
        (tester) async {
          await mount(
            tester,
            LearningExplanation(text: 'Legacy', steps: steps, sourceKey: 'a'),
            width: size,
            scale: scale,
          );
          expect(find.byType(FractionExplorer), findsOneWidget);
          await tester.ensureVisible(find.text('Nächster Schritt'));
          await tester.tap(find.text('Nächster Schritt'));
          await tester.pumpAndSettle();
          expect(find.text('Schritt 2 von 2'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    '107 stored reading position restores step and fraction phase without writes',
    (tester) async {
      final calls = <String>[];
      final state = app((r) {
        calls.add(r.method);
        return reply({
          'source_signature': 'a' * 64,
          'revision': 4,
          'position': {
            'explanation_kind': 'intro',
            'question_id': null,
            'explanation_step_id': 'e2',
            'graphic_index': 0,
            'graphic_phase': 'fraction-bar-numerator',
          },
        });
      });
      addTearDown(state.dispose);
      await mount(tester, view(state));
      expect(find.text('Schritt 2 von 2'), findsOneWidget);
      expect(
        tester
            .widget<FractionExplorer>(find.byType(FractionExplorer))
            .numerator,
        2,
      );
      expect(find.text('Zähler 2: 2 Teile sind markiert.'), findsOneWidget);
      expect(calls, ['GET']);
    },
  );
  testWidgets('107 explicit step change saves only technical CAS position', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = app((r) {
      calls.add(r);
      return reply({
        'source_signature': 'a' * 64,
        'revision': r.method == 'PUT' ? 2 : 1,
        'position': null,
      });
    });
    addTearDown(state.dispose);
    await mount(tester, view(state));
    await tester.ensureVisible(find.text('Nächster Schritt'));
    await tester.tap(find.text('Nächster Schritt'));
    await tester.pumpAndSettle();
    final put = calls.singleWhere((r) => r.method == 'PUT');
    final body = jsonDecode(put.body) as Map;
    expect(put.url.path, '/api/units/unit/visual-position');
    expect(put.headers['X-Schulpilot-Account'], 'reader');
    expect(body['revision'], 1);
    expect(body['position']['explanation_step_id'], 'e2');
    expect(calls.every((r) => r.method == 'GET' || r.method == 'PUT'), isTrue);
    expect(body.keys.toSet(), {'source_signature', 'revision', 'position'});
  });
  testWidgets('107 server conflict cannot overwrite another device position', (
    tester,
  ) async {
    var puts = 0;
    final state = app((r) {
      if (r.method == 'PUT') {
        puts++;
        return reply({'detail': 'Changed'}, 409);
      }
      return reply({
        'source_signature': 'a' * 64,
        'revision': 1,
        'position': null,
      });
    });
    addTearDown(state.dispose);
    await mount(tester, view(state));
    await tester.ensureVisible(find.text('Nächster Schritt'));
    await tester.tap(find.text('Nächster Schritt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('anderen Gerät'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Vorheriger Erklärungsschritt'));
    await tester.tap(find.byTooltip('Vorheriger Erklärungsschritt'));
    await tester.pumpAndSettle();
    expect(puts, 1);
  });
  testWidgets('107 old source step callback is inert after replacement', (
    tester,
  ) async {
    final changes = <Json>[];
    await mount(
      tester,
      LearningExplanation(
        text: 'Legacy',
        steps: steps,
        sourceKey: 'old',
        onPositionChanged: changes.add,
      ),
    );
    final old = tester
        .widget<TextButton>(
          find
              .ancestor(
                of: find.text('Nächster Schritt'),
                matching: find.byWidgetPredicate((w) => w is TextButton),
              )
              .first,
        )
        .onPressed!;
    await mount(
      tester,
      LearningExplanation(
        text: 'Legacy',
        steps: steps,
        sourceKey: 'new',
        onPositionChanged: changes.add,
      ),
    );
    old();
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.text('Schritt 1 von 2'), findsOneWidget);
  });
  for (final change in ['account', 'token']) {
    testWidgets(
      '107 late position response ignored after $change replacement',
      (tester) async {
        final delayed = Completer<http.Response>();
        final calls = <String>[];
        final state = app((r) {
          calls.add(r.method);
          return delayed.future;
        });
        addTearDown(state.dispose);
        await mount(tester, view(state));
        if (change == 'account') {
          state.user = {...state.user!, 'id': 'different'};
        } else {
          state.api.token = 'different';
        }
        state.notifyListeners();
        delayed.complete(
          reply({
            'source_signature': 'a' * 64,
            'revision': 1,
            'position': {
              'question_id': null,
              'explanation_kind': 'intro',
              'explanation_step_id': 'e2',
              'graphic_index': 0,
              'graphic_phase': 'initial',
            },
          }),
        );
        await tester.pumpAndSettle();
        expect(find.text('Schritt 2 von 2'), findsNothing);
        expect(calls, ['GET']);
      },
    );
  }
  testWidgets(
    '107 fraction exploration reports finite phase and never evaluates',
    (tester) async {
      final phases = <String>[];
      await mount(
        tester,
        LearningGraphicScope(
          index: 0,
          phase: 'initial',
          onChanged: (_, phase) => phases.add(phase),
          child: const FractionExplorer(numerator: 1, denominator: 2),
        ),
      );
      await tester.ensureVisible(find.text('Nenner'));
      await tester.tap(find.text('Nenner'));
      await tester.pumpAndSettle();
      expect(phases, ['fraction-circle-denominator']);
      await tester.ensureVisible(find.byTooltip('Balkenmodell'));
      await tester.tap(find.byTooltip('Balkenmodell'));
      await tester.pumpAndSettle();
      expect(phases.last, 'fraction-bar-denominator');
    },
  );
  testWidgets(
    '107 graphic request remains explicit and does not answer or start round',
    (tester) async {
      final calls = <http.Request>[];
      var reloads = 0;
      final state = app((r) {
        calls.add(r);
        return reply({'id': 'job', 'status': 'queued'}, 202);
      });
      addTearDown(state.dispose);
      await mount(
        tester,
        VisualPreparationCard(
          state: state,
          unit: {
            'id': 'unit',
            'explanation_visual_status': 'legacy_text',
            'synthetic': false,
          },
          isCurrent: () => true,
          refresh: () async {
            reloads++;
          },
        ),
      );
      expect(calls, isEmpty);
      await tester.tap(find.text('Grafische Erklärung vorbereiten'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'POST');
      expect(calls.single.url.path, '/api/units/unit/visual-explanation');
      expect(calls.single.headers['Idempotency-Key'], isNotEmpty);
      expect(reloads, 1);
    },
  );
  testWidgets('107 no invented learning path is displayed without saved plan', (
    tester,
  ) async {
    await mount(tester, const LearningPathView());
    expect(find.text('Dein Lernweg'), findsNothing);
  });
  testWidgets(
    '107 mobile learning path separates position and independent evidence',
    (tester) async {
      await mount(
        tester,
        const LearningPathView(
          data: {
            'version': 1,
            'current_step_id': 'probe',
            'steps': [
              {
                'id': 'probe',
                'title': 'Voraussetzung prüfen',
                'status_label': 'Noch nicht geprüft',
                'question_ids': ['q1'],
                'evidence': {
                  'summary': 'Keine selbstständige Beobachtung gespeichert.',
                },
              },
            ],
          },
          currentQuestionId: 'q1',
        ),
      );
      await tester.tap(find.text('Dein Lernweg'));
      await tester.pumpAndSettle();
      expect(find.text('Voraussetzung prüfen'), findsOneWidget);
      expect(find.text('Noch nicht geprüft'), findsOneWidget);
      expect(
        find.textContaining('erst durch gespeicherte eigene Antworten'),
        findsOneWidget,
      );
    },
  );
}
