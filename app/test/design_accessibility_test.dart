import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/ui.dart';

double contrast(Color foreground, Color background) {
  final visible = Color.alphaBlend(foreground, background);
  final a = visible.computeLuminance();
  final b = background.computeLuminance();
  return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
}

void main() {
  test(
    'Text and meaningful controls keep contrast on every shared surface',
    () {
      final theme = appTheme();
      final scheme = theme.colorScheme;
      for (final background in [
        theme.scaffoldBackgroundColor,
        scheme.surface,
        scheme.surfaceContainerLow,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
        for (final tone in PanelTone.values) panelColor(tone),
      ]) {
        for (final foreground in [ink, muted, teal]) {
          expect(
            contrast(foreground, background),
            greaterThanOrEqualTo(4.5),
            reason: 'Text $foreground on $background',
          );
        }
      }
      for (final pair in [
        (scheme.onPrimary, scheme.primary),
        (scheme.onSecondary, scheme.secondary),
        (scheme.onError, scheme.error),
        (successInk, successSurface),
        (warningInk, warningSurface),
        (dangerInk, dangerSurface),
        (cyanInk, cyanSurface),
        (ink, electric),
        (electric, ink),
        (Colors.white, const Color(0xFF31235E)),
        (const Color(0xFFD4D4EE), const Color(0xFF31235E)),
        (const Color(0xFFBBC9E0), const Color(0xFF354B70)),
      ]) {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
      for (final background in [Colors.white, surfaceLow, cream, mint]) {
        expect(contrast(controlBorder, background), greaterThanOrEqualTo(3));
      }
      for (final selected in [false, true]) {
        final states = selected ? {WidgetState.selected} : <WidgetState>{};
        final nav = theme.navigationBarTheme;
        expect(
          contrast(
            nav.labelTextStyle!.resolve(states)!.color!,
            nav.backgroundColor!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(
            nav.iconTheme!.resolve(states)!.color!,
            selected ? nav.indicatorColor! : nav.backgroundColor!,
          ),
          greaterThanOrEqualTo(3),
        );
      }
      expect(
        contrast(theme.tabBarTheme.labelColor!, Colors.white),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(theme.tabBarTheme.unselectedLabelColor!, Colors.white),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  testWidgets(
    'Actual button and field focus is visible, high contrast and keeps values',
    (tester) async {
      final filledFocus = FocusNode();
      final outlinedFocus = FocusNode();
      final fieldFocus = FocusNode();
      final controller = TextEditingController();
      addTearDown(filledFocus.dispose);
      addTearDown(outlinedFocus.dispose);
      addTearDown(fieldFocus.dispose);
      addTearDown(controller.dispose);
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  TextField(
                    focusNode: fieldFocus,
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Deine Antwort',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    focusNode: filledFocus,
                    onPressed: () => presses++,
                    child: const Text('Prüfen'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    focusNode: outlinedFocus,
                    onPressed: () {},
                    child: const Text('Hinweis'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Material materialFor(String label) => tester.widget<Material>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Material))
            .first,
      );
      filledFocus.requestFocus();
      await tester.pumpAndSettle();
      final primary = materialFor('Prüfen');
      final primarySide = (primary.shape! as OutlinedBorder).side;
      expect(primarySide.width, greaterThanOrEqualTo(2));
      expect(
        contrast(primarySide.color, primary.color!),
        greaterThanOrEqualTo(3),
      );
      outlinedFocus.requestFocus();
      await tester.pumpAndSettle();
      final secondary = materialFor('Hinweis');
      final secondarySide = (secondary.shape! as OutlinedBorder).side;
      expect(secondarySide.width, greaterThanOrEqualTo(2));
      expect(
        contrast(secondarySide.color, secondary.color!),
        greaterThanOrEqualTo(3),
      );
      await tester.enterText(find.byType(TextField), 'Eine eigene Antwort');
      fieldFocus.requestFocus();
      await tester.pumpAndSettle();
      final decoration = tester.widget<InputDecorator>(
        find.byType(InputDecorator),
      );
      expect(decoration.isFocused, isTrue);
      final inputTheme = Theme.of(tester.element(find.byType(TextField)))
          .inputDecorationTheme;
      expect(
        inputTheme.focusedBorder!.borderSide.width,
        greaterThanOrEqualTo(2),
      );
      expect(
        contrast(
          inputTheme.focusedBorder!.borderSide.color,
          inputTheme.fillColor!,
        ),
        greaterThanOrEqualTo(3),
      );
      await tester.tap(find.text('Prüfen'));
      expect(presses, 1);
      expect(controller.text, 'Eine eigene Antwort');
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [
    const Size(320, 844),
    const Size(390, 844),
    const Size(1440, 1000),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Surfaces, feedback and expanded details work at $size / text $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              theme: appTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FocusCard(
                        eyebrow: 'Heute',
                        title: 'Deine nächste Runde',
                        subtitle: 'Eine Aufgabe nach der anderen.',
                        action: FilledButton(
                          onPressed: () {},
                          child: const Text('Los geht’s'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            heading('Dein Lernstoff'),
                            const Text('Verstehe, was du heute gelernt hast.'),
                            const SizedBox(height: 12),
                            const SurfaceInset(
                              child: Text(
                                'Lernzeit und nächste Wiederholung',
                                style: TextStyle(color: muted),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const ExpansionTile(
                              title: Text('Mehr ansehen'),
                              children: [Text('Eine gespeicherte Erklärung.')],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Panel(
                        tone: PanelTone.success,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Richtig!',
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 12),
                            SurfaceInset(
                              tone: PanelTone.neutral,
                              child: Text('Deine eigene Antwort'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Notice(
                        'Diese Bewertung ist noch offen.',
                        warning: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Mehr ansehen'));
          await tester.tap(find.text('Mehr ansehen'));
          await tester.pumpAndSettle();
          expect(find.text('Eine gespeicherte Erklärung.'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Richtig!'));
          await tester.pumpAndSettle();
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantics.dispose();
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
