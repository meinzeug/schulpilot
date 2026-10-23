import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/learning_room.dart';
import 'package:schulpilot/ui.dart';

const actionKey = ValueKey('layout-primary-action');
const contentKey = ValueKey('layout-content');
const answerKey = ValueKey('layout-answer');

void viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

Widget host(Widget child, double scale) => MaterialApp(
  theme: appTheme(brightness: Brightness.dark),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

Widget room({
  required ScrollController controller,
  int? total = 4,
  int? completed = 1,
  VoidCallback? action,
  VoidCallback? leave,
  VoidCallback? pause,
  VoidCallback? help,
  VoidCallback? assistant,
}) => LearningRoom(
  title: 'Wasserkreislauf und die unterschiedlichen Aggregatzustände',
  phase: 1,
  progress: 'Aufgabe 3 von 4',
  questionTotal: total,
  questionCompleted: completed,
  scrollController: controller,
  onLeave: leave ?? () {},
  onPause: pause ?? () {},
  onHelp: help ?? () {},
  assistant: IconButton(
    tooltip: 'Beispielassistent öffnen',
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    onPressed: assistant ?? () {},
    icon: const Icon(Icons.chat_bubble_outline_rounded),
  ),
  clock: const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Text('Heute 0:00 / 20:00', style: TextStyle(fontSize: 12)),
  ),
  primaryAction: FilledButton(
    key: actionKey,
    onPressed: action ?? () {},
    style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
    child: const Text('Antwort prüfen'),
  ),
  child: Column(
    key: contentKey,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Ordne die Begriffe ihrem passenden Aggregatzustand zu.',
        style: TextStyle(fontSize: 18, height: 1.4),
      ),
      const SizedBox(height: 20),
      const TextField(
        key: answerKey,
        decoration: InputDecoration(labelText: 'Deine Antwort'),
      ),
      const SizedBox(height: 600),
      const Text('Ende der vorhandenen Aufgabe'),
    ],
  ),
);

void main() {
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'compact room at $width px/$scale keeps one honest progress and all actions',
        (tester) async {
          viewport(tester, Size(width, 844));
          final controller = ScrollController();
          var submitted = 0, left = 0, paused = 0, helped = 0, opened = 0;
          await tester.pumpWidget(
            host(
              room(
                controller: controller,
                action: () => submitted++,
                leave: () => left++,
                pause: () => paused++,
                help: () => helped++,
                assistant: () => opened++,
              ),
              scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Bearbeitet 1 von 4'), findsOneWidget);
          expect(find.text('Üben · Aufgabe 3 von 4'), findsOneWidget);
          final bar = tester.widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('learning-question-progress')),
          );
          // The third displayed question does not make three completed answers.
          expect(bar.value, .25);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(
            tester.getSize(find.byKey(contentKey)).width,
            lessThanOrEqualTo(668),
          );
          for (final tooltip in [
            'Lernrunde verlassen',
            'Pause machen',
            'Beispielassistent öffnen',
          ]) {
            final control = find.byTooltip(tooltip);
            expect(control.hitTestable(), findsOneWidget);
            expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
            expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
            await tester.tap(control);
          }
          final primary = find.byKey(actionKey);
          expect(primary.hitTestable(), findsOneWidget);
          expect(tester.getSize(primary).height, greaterThanOrEqualTo(48));
          if (width >= 720) {
            expect(tester.getSize(primary).width, 320);
            expect(
              tester.getRect(primary).right,
              closeTo((width + 700) / 2 - 16, .1),
            );
          } else if (scale == 2) {
            expect(tester.getSize(primary).width, width - 32);
          }
          await tester.tap(primary);
          await tester.tap(find.byKey(const ValueKey('learning-help')));
          expect((submitted, left, paused, helped, opened), (1, 1, 1, 1, 1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        },
      );

      testWidgets(
        'compact today card at $width px/$scale preserves full content and its action',
        (tester) async {
          viewport(tester, Size(width, 844));
          var opened = 0;
          const title =
              'Wasserkreislauf und die unterschiedlichen Aggregatzustände';
          const subtitle =
              'Eine vorhandene Beispielrunde in Geographie mit vollständig lesbaren Hinweisen.';
          await tester.pumpWidget(
            host(
              Scaffold(
                body: SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ChildTodayHero(
                          eyebrow: 'Dein nächster Schritt',
                          title: title,
                          subtitle: subtitle,
                          action: ActionButton(
                            label: 'Runde öffnen',
                            icon: Icons.play_arrow_rounded,
                            onPressed: () async => opened++,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.widget<Text>(find.text(title)).maxLines, isNull);
          expect(tester.widget<Text>(find.text(subtitle)).maxLines, isNull);
          expect(find.text('Verstehen · Üben · Rückblick'), findsOneWidget);
          final button = find.widgetWithText(FilledButton, 'Runde öffnen');
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(opened, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'keyboard and 200 percent leave the action above the inset and the answer scrollable',
    (tester) async {
      viewport(tester, const Size(320, 844));
      final controller = ScrollController();
      await tester.pumpWidget(host(room(controller: controller), 2));
      await tester.ensureVisible(find.byKey(answerKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(answerKey));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(answerKey));
      await tester.pumpAndSettle();
      final primary = tester.getRect(find.byKey(actionKey));
      final answer = tester.getRect(find.byKey(answerKey));
      expect(primary.bottom, lessThanOrEqualTo(844 - 280));
      expect(answer.center.dy, lessThan(primary.top));
      expect(find.byKey(actionKey).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'legacy phase context stays readable without fabricated question totals',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final controller = ScrollController();
      await tester.pumpWidget(
        host(room(controller: controller, total: null, completed: null), 1),
      );
      expect(find.text('Üben · Aufgabe 3 von 4'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('learning-question-progress')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('learning-question-count')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
