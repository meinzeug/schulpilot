import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/matching_answer_board.dart';
import 'package:schulpilot/ui.dart';

class _Harness extends StatefulWidget {
  final List<String> choices;
  final double scale;
  const _Harness({
    super.key,
    this.choices = const ['Katze', 'weich'],
    this.scale = 1,
  });

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  Object source = Object();
  bool disabled = false;
  final matches = <String, String>{};
  final drops = <(String, String)>[];
  final chosen = <String>[];

  void newSession() => setState(() => source = Object());
  void lock() => setState(() => disabled = true);

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: appTheme(brightness: Brightness.dark),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(widget.scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MatchingAnswerBoard(
                questionId: 'matching',
                sourceKey: source,
                options: const ['Nomen', 'Adjektiv'],
                choices: widget.choices,
                matches: Map.unmodifiable(matches),
                disabled: disabled,
                onChoose: chosen.add,
                onDrop: (option, value) => setState(() {
                  drops.add((option, value));
                  matches[option] = value;
                }),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<GlobalKey<_HarnessState>> _open(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  List<String> choices = const ['Katze', 'weich'],
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(_Harness(key: key, choices: choices, scale: scale));
  await tester.pumpAndSettle();
  return key;
}

Finder choice(int index) =>
    find.byKey(ValueKey('match-choice-matching-$index'));
Finder target(String label) => find.byKey(ValueKey('match-matching-$label'));

Future<TestGesture> startDrag(WidgetTester tester, int index) async {
  final gesture = await tester.startGesture(tester.getCenter(choice(index)));
  await tester.pump(const Duration(milliseconds: 300));
  return gesture;
}

Future<void> dropOn(
  WidgetTester tester,
  TestGesture gesture,
  String label,
) async {
  await gesture.moveTo(tester.getCenter(target(label)));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'real drag updates only its controlled pair and choices remain reusable',
    (tester) async {
      final key = await _open(tester);
      await dropOn(tester, await startDrag(tester, 0), 'Nomen');
      expect(key.currentState!.matches, {'Nomen': 'Katze'});
      expect(choice(0), findsOneWidget);
      await dropOn(tester, await startDrag(tester, 0), 'Adjektiv');
      expect(key.currentState!.matches, {
        'Nomen': 'Katze',
        'Adjektiv': 'Katze',
      });
      expect(key.currentState!.drops, [
        ('Nomen', 'Katze'),
        ('Adjektiv', 'Katze'),
      ]);
      expect(key.currentState!.chosen, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a cancelled touch movement leaves all pairs untouched', (
    tester,
  ) async {
    final key = await _open(tester);
    final gesture = await tester.startGesture(tester.getCenter(choice(0)));
    await gesture.moveBy(const Offset(0, 70));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(key.currentState!.matches, isEmpty);
    expect(key.currentState!.drops, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an in-flight drag from an older session with the same question is rejected',
    (tester) async {
      final key = await _open(tester);
      final gesture = await startDrag(tester, 0);
      key.currentState!.newSession();
      await tester.pump();
      await dropOn(tester, gesture, 'Nomen');
      expect(key.currentState!.matches, isEmpty);
      expect(key.currentState!.drops, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('locking a board rejects an already started drag', (
    tester,
  ) async {
    final key = await _open(tester);
    final gesture = await startDrag(tester, 0);
    key.currentState!.lock();
    await tester.pump();
    await dropOn(tester, gesture, 'Nomen');
    expect(key.currentState!.matches, isEmpty);
    expect(key.currentState!.drops, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'full-row fallback supports keyboard activation without assigning an answer',
    (tester) async {
      final key = await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(key.currentState!.chosen, ['Nomen']);
      expect(key.currentState!.drops, isEmpty);
    },
  );

  testWidgets('320px and 200 percent keep full labels and a tappable fallback', (
    tester,
  ) async {
    const longChoice =
        'Begriff mit einem sehr langen gemeinsamen Anfang und der Bedeutung Gegenstand';
    final key = await _open(
      tester,
      size: const Size(320, 568),
      choices: const [
        longChoice,
        'Eine zweite vollständige Antwortmöglichkeit',
      ],
      scale: 2,
    );
    expect(tester.widget<Text>(find.text(longChoice)).maxLines, isNull);
    await tester.ensureVisible(target('Nomen'));
    await tester.pumpAndSettle();
    expect(tester.getSize(target('Nomen')).height, greaterThanOrEqualTo(48));
    await tester.tap(target('Nomen'));
    expect(key.currentState!.chosen, ['Nomen']);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'a long mobile choice bank scrolls at the drag edge and stops after drop',
    (tester) async {
      final key = await _open(
        tester,
        size: const Size(320, 568),
        choices: List.generate(
          10,
          (i) => 'Vollständige Antwortmöglichkeit Nummer $i',
        ),
      );
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final gesture = await startDrag(tester, 0);
      await gesture.moveTo(const Offset(160, 560));
      for (
        var i = 0;
        i < 120 && target('Nomen').hitTestable().evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(scrollable.position.pixels, greaterThan(0));
      expect(target('Nomen').hitTestable(), findsOneWidget);
      await dropOn(tester, gesture, 'Nomen');
      expect(
        key.currentState!.matches['Nomen'],
        'Vollständige Antwortmöglichkeit Nummer 0',
      );
      final stopped = scrollable.position.pixels;
      await tester.pump(const Duration(milliseconds: 500));
      expect(scrollable.position.pixels, stopped);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing session stops a long-board edge scroll and rejects its drag',
    (tester) async {
      final key = await _open(
        tester,
        size: const Size(320, 568),
        choices: List.generate(
          10,
          (i) => 'Vollständige Antwortmöglichkeit Nummer $i',
        ),
      );
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final gesture = await startDrag(tester, 0);
      await gesture.moveTo(const Offset(160, 560));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(scrollable.position.pixels, greaterThan(0));
      key.currentState!.newSession();
      await tester.pumpAndSettle();
      final stopped = scrollable.position.pixels;
      await tester.pump(const Duration(milliseconds: 500));
      expect(scrollable.position.pixels, stopped);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(key.currentState!.drops, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
