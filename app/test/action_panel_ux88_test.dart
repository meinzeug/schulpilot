import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/ui.dart';

Future<void> display(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(320, 900),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('RR001 moving a keyed card never activates its action', (
    tester,
  ) async {
    var opens = 0;
    final key = GlobalKey();
    Widget page(bool left) {
      final card = ActionPanel(
        key: key,
        actionLabel: 'Öffnen',
        onPressed: () => opens++,
        child: const Text('Gespeicherte Karte'),
      );
      return MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Row(
            children: [
              Expanded(child: left ? card : const SizedBox()),
              Expanded(child: left ? const SizedBox() : card),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(page(true));
    await tester.pumpWidget(page(false));
    await tester.pumpAndSettle();
    expect(opens, 0);
    await tester.tap(find.text('Gespeicherte Karte'));
    await tester.pump();
    expect(opens, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'RR001 summary body and explicit destination both open the card',
    (tester) async {
      var opens = 0;
      await display(
        tester,
        ActionPanel(
          actionLabel: 'Alle gespeicherten Aufgaben ansehen',
          onPressed: () => opens++,
          child: const Text('24 beantwortete Aufgaben'),
        ),
      );
      await tester.tap(find.text('24 beantwortete Aufgaben'));
      await tester.pump();
      expect(opens, 1);
      await tester.tap(find.text('Alle gespeicherten Aufgaben ansehen'));
      await tester.pump();
      expect(opens, 2);
    },
  );

  testWidgets('RR001 keyboard opens once and focus is actually rendered', (
    tester,
  ) async {
    var opens = 0;
    await display(
      tester,
      ActionPanel(
        actionLabel: 'Aufgaben ansehen',
        onPressed: () => opens++,
        child: const Text('Gespeicherte Belege'),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final card = tester.widget<Card>(find.byType(Card));
    expect((card.shape! as RoundedRectangleBorder).side.width, 2.5);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opens, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(opens, 2);
  });

  testWidgets('RR001 semantics expose one named card action', (tester) async {
    final semantics = tester.ensureSemantics();
    await display(
      tester,
      ActionPanel(
        actionLabel: 'Hausaufgaben ansehen',
        onPressed: () {},
        child: const Text('Drei Fotos'),
      ),
    );
    expect(
      find.bySemanticsLabel(
        RegExp('Drei Fotos.*Hausaufgaben ansehen', dotAll: true),
      ),
      findsOneWidget,
    );
    final node = tester.getSemantics(find.byType(ActionPanel));
    expect(
      node,
      matchesSemantics(
        isButton: true,
        isFocusable: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        label: 'Drei Fotos\nHausaufgaben ansehen',
      ),
    );
    semantics.dispose();
  });

  testWidgets(
    'RR001 saved callbacks cannot activate disabled or removed cards',
    (tester) async {
      var opens = 0;
      Widget card(bool enabled) => ActionPanel(
        key: const ValueKey('same'),
        actionLabel: 'Plan ansehen',
        enabled: enabled,
        onPressed: () => opens++,
        child: const Text('Dein Kurzplan'),
      );
      await display(tester, card(true));
      final saved = tester.widget<InkWell>(find.byType(InkWell)).onTap!;
      saved();
      saved();
      expect(opens, 1);
      await tester.pump();
      await display(tester, card(false));
      saved();
      expect(opens, 1);
      await display(tester, const Text('Anderer Bereich'));
      saved();
      expect(opens, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('RR001 readable destination at320px200percent $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      await display(
        tester,
        ActionPanel(
          actionLabel: 'Gespeicherte Lernrunden und Antwortbelege ansehen',
          onPressed: () {},
          child: const Text(
            'Hier siehst du, welche Aufgaben schon beantwortet wurden.',
          ),
        ),
        brightness: brightness,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      final style = tester
          .widget<Text>(
            find.text('Gespeicherte Lernrunden und Antwortbelege ansehen'),
          )
          .style!;
      final background = tester.widget<Card>(find.byType(Card)).color!;
      final luminances = [
        style.color!.computeLuminance(),
        background.computeLuminance(),
      ]..sort();
      expect(
        (luminances.last + .05) / (luminances.first + .05),
        greaterThanOrEqualTo(4.5),
      );
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
}
