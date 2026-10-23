import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/collection_view_tools.dart';
import 'package:schulpilot/ui.dart';

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double width = 320,
  double scale = 2,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
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

void main() {
  test('own text undo preserves exact Unicode and semicolons; inactive bindings clear old values', () {
    final controller = TextEditingController();
    var active = true;
    final history = LocalTextHistory(controller, canRecord: () => active);
    controller.text = 'CO; x²';
    controller.text = 'Co; x2';
    history.undo();
    expect(controller.text, 'CO; x²');
    history.redo();
    expect(controller.text, 'Co; x2');
    active = false;
    controller.clear();
    expect(history.canUndo, isFalse);
    history.undo();
    expect(controller.text, isEmpty);
    history.dispose();
    controller.dispose();
  });
  test('own text history remains bounded and ignores cursor-only changes', () {
    final controller = TextEditingController();
    final history = LocalTextHistory(controller, canRecord: () => true);
    for (var i = 0; i < 100; i++) {
      controller.text = '$i';
    }
    controller.selection = const TextSelection.collapsed(offset: 0);
    for (var i = 0; i < 60; i++) {
      history.undo();
    }
    expect(history.canUndo, isFalse);
    expect(controller.text, '39');
    history.dispose();
    controller.dispose();
  });
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'comparison and exact line differences stay readable at $width and 200%',
      (tester) async {
        await mount(
          tester,
          const TextVersionComparison(
            local: 'Eigene erste Zeile\nCO; x²',
            saved: 'Eigene erste Zeile\nCo; x2',
          ),
          width: width,
        );
        expect(find.text('Auf diesem Gerät'), findsOneWidget);
        expect(find.text('Gespeicherter Stand'), findsOneWidget);
        expect(find.text('CO; x²'), findsOneWidget);
        expect(find.text('Co; x2'), findsOneWidget);
        expect(find.text('Zeile 1 · gleich'), findsNWidgets(2));
        expect(
          find.text('Zeile 2 · an dieser Position verschieden'),
          findsNWidgets(2),
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'phase/scale/single weight have no invented overall denominator at $width',
      (tester) async {
        await mount(
          tester,
          const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ImportPhaseTrack(2),
              GradeScaleGuide('grade_1_6'),
              GradeScaleGuide('points_0_15'),
              GradeWeightVisual(3),
            ],
          ),
          width: width,
        );
        expect(find.text('3 · Auswahl'), findsOneWidget);
        expect(find.textContaining('1: beste Note'), findsOneWidget);
        expect(find.textContaining('15: höchste Punktzahl'), findsOneWidget);
        expect(find.text('Gewichtung: 3-fach'), findsOneWidget);
        expect(
          find.textContaining('keinen Anteil an allen Noten'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('unknown scale never acquires an invented best/worst direction', (
    tester,
  ) async {
    await mount(tester, const GradeScaleGuide('unreported'));
    expect(find.textContaining('nicht eindeutig gemeldet'), findsOneWidget);
    expect(find.textContaining('beste'), findsNothing);
  });
  testWidgets('visible search marks escaped literal text only', (tester) async {
    await mount(
      tester,
      const VisibleSearchText('Eigener Text: x² + x²', query: 'x²'),
    );
    final rich = tester.widget<RichText>(
      find.descendant(
        of: find.byType(VisibleSearchText),
        matching: find.byType(RichText),
      ),
    );
    expect(rich.text.toPlainText(), 'Eigener Text: x² + x²');
    int marks(InlineSpan span) =>
        (span is TextSpan && span.style?.decoration == TextDecoration.underline
            ? 1
            : 0) +
        (span is TextSpan
            ? (span.children ?? const <InlineSpan>[]).fold<int>(
                0,
                (sum, child) => sum + marks(child),
              )
            : 0);
    expect(marks(rich.text), 2);
  });
  for (final change in ['account', 'family', 'token', 'background']) {
    testWidgets('private local modal closes on $change', (tester) async {
      final state = AppState()..user = {'id': 'synthetic', 'role': 'parent'};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PrivateLocalView(
                    state: state,
                    valid: () => true,
                    child: const AlertDialog(
                      content: Text('Künstlicher privater Vergleich'),
                    ),
                  ),
                ),
                child: const Text('Öffnen'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();
      expect(find.text('Künstlicher privater Vergleich'), findsOneWidget);
      switch (change) {
        case 'account':
          state.user = {...state.user!};
        case 'family':
          state.familyId = 'andere';
        case 'token':
          state.api.token = 'anderes-synthetisches-token';
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pumpAndSettle();
          expect(find.text('Künstlicher privater Vergleich'), findsNothing);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
      }
      state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Künstlicher privater Vergleich'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'a legitimate dropdown overlay stays usable and is removed with its private owner',
    (tester) async {
      final state = AppState()
        ..user = {'id': 'synthetic-parent', 'role': 'parent'};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PrivateLocalView(
                    state: state,
                    valid: () => true,
                    child: AlertDialog(
                      title: const Text('Gebundener Vergleich'),
                      content: DropdownButtonFormField<String>(
                        initialValue: 'a',
                        items: const [
                          DropdownMenuItem(
                            value: 'a',
                            child: Text('Künstlicher Wert A'),
                          ),
                          DropdownMenuItem(
                            value: 'b',
                            child: Text('Künstlicher Wert B'),
                          ),
                        ],
                        onChanged: (_) {},
                      ),
                    ),
                  ),
                ),
                child: const Text('Öffnen'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Gebundener Vergleich'), findsOneWidget);
      expect(
        find.text('Künstlicher Wert B').last.hitTestable(),
        findsOneWidget,
      );
      state.user = {...state.user!};
      state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Gebundener Vergleich'), findsNothing);
      expect(find.text('Künstlicher Wert B'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('inactive snapshot with the same text resets undo and explicit rebinding clears a silent controller assignment', () {
    final controller = TextEditingController(text: 'gleicher Text');
    var active = true;
    final history = LocalTextHistory(controller, canRecord: () => active);
    controller.text = 'anderer Text';
    history.undo();
    expect(history.canRedo, isTrue);
    active = false;
    controller.selection = const TextSelection.collapsed(offset: 0);
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
    active = true;
    controller.text = 'neuer Versuch';
    history.undo();
    controller.text = 'gleicher Text';
    history.reset();
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
    history.dispose();
    controller.dispose();
  });
}
