import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/lab_recipe.dart';
import 'package:schulpilot/lab_view.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/saved_visual_explanation.dart';
import 'package:schulpilot/schulbuddy.dart';
import 'package:schulpilot/subject_graphic.dart';

import 'force_lab_109_test.dart' as force;
import 'saved_visual_explanation_107_test.dart' as saved;
import 'sentence_shift_lab_109_test.dart' as sentence;

Json physicsView() => LabView.forceState(3, 1.5, 750);
Json sentenceView() => LabView.sentenceState(2, 'book', true);
Json step(Json source) => {
  'id': 'e1',
  'text': 'Ein eigenes, begrenztes Modell erkunden.',
  'disclosure': 'given',
  'presentation': {
    'version': 1,
    'evidence_kind': 'knowledge',
    'blocks': [force.copy(source)..['disclosure'] = 'given'],
  },
};
Json position(Json value) => {
  'explanation_kind': 'intro',
  'question_id': null,
  'explanation_step_id': 'e1',
  'graphic_index': 0,
  'graphic_phase': 'initial',
  'lab_view': value,
};
Json buddyView(WidgetTester tester) {
  final contexts = tester.widgetList<SchulbuddyPageContext>(
    find.byType(SchulbuddyPageContext),
  );
  return Json.from(
    jsonDecode(contexts.last.contextValue.references['lab_view']!),
  );
}

class PositionFixture {
  final calls = <http.Request>[];
  Json? stored;
  int revision = 7;
  late final state = saved.app((request) {
    calls.add(request);
    expectSync(request.url.path, '/api/units/unit/visual-position');
    if (request.method == 'PUT') {
      final body = Json.from(jsonDecode(request.body));
      expectSync(body.keys.toSet(), {
        'source_signature',
        'revision',
        'position',
      });
      expectSync(body['revision'], revision);
      expectSync(request.headers['X-Schulpilot-Account'], 'reader');
      stored = Json.from(body['position']);
      revision++;
    } else {
      expectSync(request.method, 'GET');
    }
    return saved.reply({
      'source_signature': 'a' * 64,
      'revision': revision,
      'position': stored,
    });
  })..api.token = 'synthetic-session';

  Future<void> show(
    WidgetTester tester,
    Json block, {
    Object source = 'a',
  }) async {
    await saved.mount(
      tester,
      SavedVisualExplanation(
        state: state,
        unitId: 'unit',
        text: 'Gespeicherte Erklärung.',
        steps: [step(block)],
        sourceKey: source,
      ),
    );
  }

  List<http.Request> get writes =>
      calls.where((r) => r.method == 'PUT').toList();
}

void main() {
  test('109 finite force view preserves exact source values or explicit slider ticks', () {
    const original = ForceLabModel(massKg: 2.3, acceleration: 1.1);
    final source = LabView.forceState(2.3, 1.1, 50);
    expect(LabView.force(source, original), source);
    expect(LabView.force(jsonEncode(physicsView()), original), physicsView());
    expect(LabView.encoded(physicsView()).runes.length, lessThan(512));
    for (final changed in [
      {...source, 'mass_kg': 2.4},
      {...source, 'acceleration_m_s2': 1.2},
      {...source, 'time_ms': 51},
      {...source, 'time_ms': 2500},
      {...source, 'time_ms': 50.0},
      {...source, 'version': 1.0},
      {...source, 'mass_kg': double.nan},
      {...source, 'acceleration_m_s2': double.infinity},
      {...source, 'x': 123},
    ]) {
      expect(LabView.force(changed, original), isNull, reason: '$changed');
    }
  });

  test(
    '109 sentence view accepts only known orders groups and strict booleans',
    () {
      expect(LabView.sentence(jsonEncode(sentenceView())), sentenceView());
      for (final changed in [
        {...sentenceView(), 'order_id': 'arbitrary'},
        {...sentenceView(), 'selected_group': 'am'},
        {...sentenceView(), 'split_example': 1},
        {...sentenceView(), 'recipe_version': 2},
        {...sentenceView(), 'recipe_id': 'physics.force_motion'},
        {...sentenceView(), 'sentence': 'free text'},
      ]) {
        expect(LabView.sentence(changed), isNull);
      }
      expect(LabView.sentence('not-json'), isNull);
      expect(LabView.decode('x' * 513), isNull);
    },
  );

  test('109 saved lab view must match the current disclosed recipe', () {
    expect(LabView.checked(physicsView(), force.forceBlock()), physicsView());
    expect(
      LabView.checked(sentenceView(), sentence.sentenceBlock()),
      sentenceView(),
    );
    expect(LabView.checked(sentenceView(), force.forceBlock()), isNull);
    expect(LabView.checked(physicsView(), sentence.sentenceBlock()), isNull);
    expect(
      LabView.checked(physicsView(), {...force.forceBlock(), 'kind': 'scene'}),
      isNull,
    );
  });

  testWidgets(
    '109 actual public backend fixture renders both labs and hides unopened blocks',
    (tester) async {
      final file = File('../testdata/learning_labs_v1.json');
      final data = Json.from(jsonDecode(file.readAsStringSync()));
      expect(data['provider_calls'], 0);
      expect(data['synthetic_contract'], isTrue);
      final fixture = force.Fixture();
      for (final item in data['cases'] as List) {
        await fixture.show(
          tester,
          child: SubjectPresentation(
            Json.from(item['public_presentation']),
            state: fixture.state,
          ),
        );
        expect(
          find.textContaining('Dieses Labor ist hier noch nicht verfügbar'),
          findsNothing,
        );
        expect(find.textContaining('Zurücksetzen'), findsOneWidget);
        await fixture.show(
          tester,
          child: SubjectPresentation(
            Json.from(item['hidden_public_presentation']),
            state: fixture.state,
          ),
        );
        expect(find.byType(Slider), findsNothing);
        expect(find.textContaining('Zurücksetzen'), findsNothing);
      }
      expect(fixture.calls, isEmpty);
      await fixture.close(tester);
    },
  );

  testWidgets(
    '109 initial lab publication only updates RAM and never saves a position',
    (tester) async {
      final f = PositionFixture();
      addTearDown(f.state.dispose);
      await f.show(tester, force.forceBlock());
      expect(buddyView(tester), LabView.forceState(2, 2, 0));
      expect(f.calls.map((r) => r.method), ['GET']);
      expect(f.writes, isEmpty);
    },
  );

  testWidgets(
    '109 saved force parameters and time restore with no learning or write call',
    (tester) async {
      final f = PositionFixture()..stored = position(physicsView());
      addTearDown(f.state.dispose);
      await f.show(tester, force.forceBlock());
      expect(tester.widget<Slider>(force.key('force-lab-mass')).value, 3);
      expect(
        tester.widget<Slider>(force.key('force-lab-acceleration')).value,
        1.5,
      );
      expect(tester.widget<Slider>(force.key('force-lab-time')).value, .375);
      expect(buddyView(tester), physicsView());
      expect(f.calls.map((r) => r.method), ['GET']);
    },
  );

  testWidgets(
    '109 saved sentence order selection and split restore without writes',
    (tester) async {
      final f = PositionFixture()..stored = position(sentenceView());
      addTearDown(f.state.dispose);
      await f.show(tester, sentence.sentenceBlock());
      expect(sentence.visibleOrder(tester), [
        'book',
        'verb',
        'mira',
        'morning',
      ]);
      expect(find.text('Getrennt: „am“ | „Morgen“'), findsOneWidget);
      expect(buddyView(tester), sentenceView());
      expect(f.calls.map((r) => r.method), ['GET']);
    },
  );

  testWidgets(
    '109 explicit force controls save canonical technical CAS snapshots',
    (tester) async {
      final f = PositionFixture();
      addTearDown(f.state.dispose);
      await f.show(tester, force.forceBlock());
      tester.widget<Slider>(force.key('force-lab-mass')).onChanged!(4);
      await tester.pumpAndSettle();
      tester.widget<Slider>(force.key('force-lab-time')).onChanged!(.5);
      await tester.pumpAndSettle();
      expect(f.writes.length, 2);
      expect(f.stored!['lab_view'], LabView.forceState(4, 2, 1000));
      expect(buddyView(tester), f.stored!['lab_view']);
      expect(
        f.calls.every((r) => r.url.path.endsWith('/visual-position')),
        isTrue,
      );
      expect(
        f.calls.every((r) => r.method == 'GET' || r.method == 'PUT'),
        isTrue,
      );
    },
  );

  testWidgets(
    '109 animation ticks update Tutor RAM with no per-frame position writes',
    (tester) async {
      final f = PositionFixture();
      addTearDown(f.state.dispose);
      await f.show(tester, force.forceBlock());
      await force.tap(tester, force.key('force-lab-play'));
      final afterStart = f.writes.length;
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(buddyView(tester)['time_ms'], greaterThan(0));
      expect(f.writes.length, afterStart);
      await tester.ensureVisible(force.key('force-lab-play'));
      await tester.tap(force.key('force-lab-play').hitTestable());
      await tester.pumpAndSettle();
      expect(f.writes.length, afterStart + 1);
      expect(f.stored!['lab_view'], buddyView(tester));
    },
  );

  testWidgets(
    '109 background pauses animation and saves last finite view only on authorized resume',
    (tester) async {
      final f = PositionFixture();
      addTearDown(f.state.dispose);
      await f.show(tester, force.forceBlock());
      await force.tap(tester, force.key('force-lab-play'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      final before = f.writes.length;
      await force.background(tester, false);
      expect(f.writes.length, before);
      await force.background(tester, true);
      await tester.pumpAndSettle();
      expect(f.writes.length, before + 1);
      expect((f.stored!['lab_view'] as Map)['time_ms'], greaterThan(0));
      final paused = tester.widget<Slider>(force.key('force-lab-time')).value;
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.widget<Slider>(force.key('force-lab-time')).value, paused);
    },
  );

  testWidgets(
    '109 sentence reset synchronizes visible groups stored view and Tutor context',
    (tester) async {
      final f = PositionFixture()..stored = position(sentenceView());
      addTearDown(f.state.dispose);
      await f.show(tester, sentence.sentenceBlock());
      await force.tap(tester, force.key('sentence-shift-reset'));
      expect(sentence.visibleOrder(tester), [
        'mira',
        'verb',
        'morning',
        'book',
      ]);
      expect(find.text('Getrennt: „am“ | „Morgen“'), findsNothing);
      expect(buddyView(tester), LabView.sentenceState(0, 'morning', false));
      expect(f.stored!['lab_view'], buddyView(tester));
      expect(f.writes, hasLength(1));
    },
  );

  testWidgets(
    '109 enlarged lab keeps its changed finite state and saves after returning',
    (tester) async {
      final f = PositionFixture()..stored = position(sentenceView());
      addTearDown(f.state.dispose);
      await f.show(tester, sentence.sentenceBlock());
      await force.tap(tester, force.key('open-graphic-zoom'));
      await tester.pumpAndSettle();
      tester
          .widget<ChoiceChip>(force.key('sentence-shift-order:1').last)
          .onSelected!(true);
      await tester.pumpAndSettle();
      expect(buddyView(tester)['order_id'], 'time_mira_book');
      expect(f.writes, isEmpty, reason: 'The underlying route is covered.');
      await tester.tap(find.byTooltip('Zur Aufgabe zurück'));
      await tester.pumpAndSettle();
      expect(f.stored!['lab_view']['order_id'], 'time_mira_book');
      expect(buddyView(tester)['order_id'], 'time_mira_book');
      expect(f.writes, hasLength(1));
    },
  );

  for (final change in ['account', 'token', 'source']) {
    testWidgets('109 old lab callback cannot save after $change replacement', (
      tester,
    ) async {
      final f = PositionFixture();
      addTearDown(f.state.dispose);
      await f.show(tester, force.forceBlock());
      final old = tester.widget<Slider>(force.key('force-lab-mass')).onChanged!;
      if (change == 'account') {
        f.state.user = {...f.state.user!, 'id': 'other'};
        f.state.notifyListeners();
        await tester.pumpAndSettle();
      } else if (change == 'token') {
        f.state.api.token = 'replacement';
        f.state.notifyListeners();
        await tester.pumpAndSettle();
      } else {
        await f.show(tester, force.forceBlock(), source: 'different-source');
      }
      old(8);
      await tester.pumpAndSettle();
      expect(f.writes, isEmpty);
    });
  }

  testWidgets(
    '109 a replaced explanation discards old recipe state instead of reusing it',
    (tester) async {
      final f = force.Fixture();
      final changed = <Json>[];
      await f.show(
        tester,
        child: LearningExplanation(
          state: f.state,
          text: 'Explanation',
          steps: [step(force.forceBlock())],
          unitId: 'unit',
          sourceKey: 'first',
          initialPosition: position(physicsView()),
          onPositionChanged: changed.add,
        ),
      );
      expect(buddyView(tester), physicsView());
      await f.show(
        tester,
        child: LearningExplanation(
          state: f.state,
          text: 'Explanation',
          steps: [step(sentence.sentenceBlock())],
          unitId: 'unit',
          sourceKey: 'second',
          onPositionChanged: changed.add,
        ),
      );
      expect(buddyView(tester), LabView.sentenceState(0, 'morning', false));
      expect(changed, isEmpty);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );
}
