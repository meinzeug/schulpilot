import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/ui.dart';

Future<void> showTools(
  WidgetTester tester,
  List<String> opened, {
  Brightness brightness = Brightness.light,
  double scale = 2,
  double width = 320,
  bool goalRequired = true,
}) async {
  tester.view.physicalSize = Size(width, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ChildTodayTools(
            learningTime: ChildTodayProgress(
              activeMinutes: 18,
              goalMinutes: 15,
              goalRequired: goalRequired,
              goalMet: true,
              completed: 2,
              description: goalRequired
                  ? 'Tagesziel geschafft · Heute ca. 18 von 15 Min. aktiv'
                  : 'Heute ca. 18 Min. aktiv · ohne festes Lernziel',
              onOpen: () => opened.add('time'),
            ),
            pageSummary: '12 gespeicherte Seiten',
            latestMessage: 'Deine künstliche Beispielnachricht bleibt eine kurze Vorschau.',
            onPlan: () => opened.add('plan'),
            onMessages: () => opened.add('messages'),
            onHelp: () => opened.add('help'),
            onNotebooks: () => opened.add('notebooks'),
            onInfo: () => opened.add('info'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const actions = {
  'Mein Plan': 'plan',
  'Nachrichten & Wünsche': 'messages',
  'Ich brauche Hilfe': 'help',
  'Meine Heftseiten': 'notebooks',
};

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Independent Today tools at 320px and 200% stay readable in $brightness',
      (tester) async {
        final opened = <String>[];
        await showTools(tester, opened, brightness: brightness);
        expect(find.text('Für deinen Tag'), findsOneWidget);
        expect(find.byKey(const ValueKey('today-tools')), findsOneWidget);
        for (final title in actions.keys) {
          final text = find.text(title);
          await tester.ensureVisible(text);
          await tester.pumpAndSettle();
          final target = find
              .ancestor(of: text, matching: find.byType(InkWell))
              .first;
          final rect = tester.getRect(target);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
          expect(tester.takeException(), isNull);
        }
        final info = find.byKey(const ValueKey('today-learning-info'));
        expect(tester.getSize(info).shortestSide, greaterThanOrEqualTo(48));
        expect(find.text('Letzte Nachricht von deinen Eltern'), findsNothing);
        expect(opened, isEmpty);
      },
    );
  }

  testWidgets(
    'Independent Today semantics invoke each complete tool exactly once',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final opened = <String>[];
        await showTools(tester, opened);
        for (final entry in actions.entries) {
          await tester.ensureVisible(find.text(entry.key));
          await tester.pumpAndSettle();
          final target = find.bySemanticsLabel(
            RegExp('^${RegExp.escape(entry.key)}(?:\\n|\$)'),
          );
          expect(target, findsOneWidget);
          final node = tester.getSemantics(target);
          final data = node.getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          expect(data.role, isNot(ui.SemanticsRole.loadingSpinner));
          tester.binding.performSemanticsAction(
            ui.SemanticsActionEvent(
              type: ui.SemanticsAction.tap,
              viewId: tester.view.viewId,
              nodeId: node.id,
            ),
          );
          await tester.pumpAndSettle();
          expect(opened.last, entry.value);
        }
        expect(opened, actions.values.toList());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'Independent Today keyboard reaches a visible focused plan action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final opened = <String>[];
        await showTools(tester, opened, width: 700, scale: 1);
        final target = find.bySemanticsLabel(RegExp(r'^Mein Plan(?:\n|$)'));
        var focused = false;
        for (var attempt = 0; attempt < 8; attempt++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          if (tester
                  .getSemantics(target)
                  .getSemanticsData()
                  .flagsCollection
                  .isFocused ==
              ui.Tristate.isTrue) {
            focused = true;
            break;
          }
        }
        expect(focused, isTrue);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Material &&
                widget.shape is RoundedRectangleBorder &&
                (widget.shape! as RoundedRectangleBorder).side.width == 2.5,
          ),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(opened, ['plan']);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'Independent Today free-day time stays explicit and does not invent a target',
    (tester) async {
      final opened = <String>[];
      await showTools(tester, opened, goalRequired: false);
      expect(find.text('ohne festes Lernziel'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Mindestziel erreicht'), findsNothing);
      expect(find.text('ca. 18 Min.'), findsOneWidget);
      expect(opened, isEmpty);
    },
  );
}
