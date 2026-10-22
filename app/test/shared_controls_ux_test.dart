import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/ui.dart';

Future<void> mount(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a rapid repeated activation starts one pending action', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<void>();
    await mount(
      tester,
      ActionButton(
        label: 'Änderungen speichern',
        onPressed: () async {
          calls++;
          await pending.future;
        },
      ),
    );
    final press = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed!;
    press();
    press();
    await tester.pump();
    expect(calls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('saved action respects newly disabled and removed controls', (
    tester,
  ) async {
    var calls = 0;
    Widget button(bool enabled) => ActionButton(
      key: const ValueKey('saved-action'),
      label: 'Ausführen',
      enabled: enabled,
      onPressed: () async {
        calls++;
      },
    );
    await mount(tester, button(true));
    final press = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed!;
    await mount(tester, button(false));
    press();
    await tester.pump();
    expect(calls, 0);
    await mount(tester, const Text('Andere Seite'));
    press();
    await tester.pump();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending action semantics retain the action purpose', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final pending = Completer<void>();
    await mount(
      tester,
      ActionButton(label: 'Einladung senden', onPressed: () => pending.future),
    );
    await tester.tap(find.text('Einladung senden'));
    await tester.pump();
    expect(
      find.bySemanticsLabel('Einladung senden: Bitte warten …'),
      findsOneWidget,
    );
    expect(find.text('Bitte warten …'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets(
    'a synchronous loader failure is recoverable without internal details',
    (tester) async {
      var calls = 0;
      await mount(
        tester,
        LoadView<String>(
          load: () {
            if (++calls == 1) throw StateError('synthetic internal diagnostic');
            return Future.value('Gespeicherter Inhalt');
          },
          builder: (data, _) => Text(data),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Das Laden hat nicht geklappt'), findsOneWidget);
      expect(find.textContaining('synthetic internal'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Erneut laden'));
      await tester.pumpAndSettle();
      expect(find.text('Gespeicherter Inhalt'), findsOneWidget);
      expect(calls, 2);
    },
  );

  testWidgets('saved refresh starts once and becomes harmless after leaving', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<String>();
    VoidCallback? refresh;
    await mount(
      tester,
      LoadView<String>(
        load: () =>
            ++calls == 1 ? Future.value('Erster Stand') : pending.future,
        builder: (data, retry) {
          refresh = retry;
          return Text(data);
        },
      ),
    );
    await tester.pumpAndSettle();
    refresh!();
    refresh!();
    await tester.pump();
    expect(calls, 2);
    await mount(tester, const Text('Verlassen'));
    refresh!();
    pending.complete('Später Stand');
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Später Stand'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completed null data has a readable end state and explicit retry',
    (tester) async {
      var calls = 0;
      await mount(
        tester,
        LoadView<String?>(
          load: () async {
            calls++;
            return null;
          },
          builder: (data, _) => Text(data ?? 'unused'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('Hier sind gerade keine Daten verfügbar.'),
        findsOneWidget,
      );
      expect(calls, 1);
      await tester.tap(find.text('Erneut laden'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );

  testWidgets(
    'long confirmation is readable at 320px and twice the text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  confirmed = await confirmDialog(
                    context,
                    'Künstliche Auswahl entfernen?',
                    List.filled(15, 'Nur künstliche Beispieldaten.').join(' '),
                    confirmLabel: 'Auswahl entfernen',
                    destructive: true,
                  );
                },
                child: const Text('Prüfen'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Auswahl entfernen'));
      await tester.tap(find.text('Auswahl entfernen'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    },
  );

  testWidgets('feedback can be dismissed and leaves time to read', (
    tester,
  ) async {
    await mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => toast(context, 'Die Änderung wurde gespeichert.'),
          child: const Text('Melden'),
        ),
      ),
    );
    await tester.tap(find.text('Melden'));
    await tester.pumpAndSettle();
    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.showCloseIcon, isTrue);
    expect(snack.duration, const Duration(seconds: 8));
  });
}
