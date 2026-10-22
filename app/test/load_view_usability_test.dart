import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';

Widget _page(Future<String> Function() load, {Object? revision}) => MaterialApp(
  theme: appTheme(),
  home: Scaffold(
    body: LoadView<String>(
      revision: revision,
      load: load,
      builder: (value, refresh) => Column(
        children: [
          Text(value),
          TextButton(onPressed: refresh, child: const Text('Aktualisieren')),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('a new revision never offers the old context while loading', (
    tester,
  ) async {
    final next = Completer<String>();
    await tester.pumpWidget(
      _page(() async => 'Erstes Kind', revision: 'first'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Erstes Kind'), findsOneWidget);

    await tester.pumpWidget(_page(() => next.future, revision: 'second'));
    expect(find.text('Erstes Kind'), findsNothing);
    expect(find.text('Aktualisieren'), findsNothing);
    expect(find.text('Wird geladen …'), findsOneWidget);
    next.complete('Zweites Kind');
    await tester.pumpAndSettle();
    expect(find.text('Zweites Kind'), findsOneWidget);
    expect(find.text('Erstes Kind'), findsNothing);
  });

  testWidgets('failed loads explain recovery and retry only on explicit tap', (
    tester,
  ) async {
    var requests = 0;
    final retry = Completer<String>();
    await tester.pumpWidget(
      _page(() {
        requests++;
        return requests == 1
            ? Future.error(StateError('internal-private-diagnostic'))
            : retry.future;
      }),
    );
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.textContaining('internal-private-diagnostic'), findsNothing);
    expect(find.text('Das Laden hat nicht geklappt'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(requests, 1);

    await tester.tap(find.text('Erneut laden'));
    await tester.pump();
    expect(requests, 2);
    expect(find.text('Erneut laden'), findsNothing);
    expect(find.text('Wird geladen …'), findsOneWidget);
    retry.complete('Gespeicherter Stand');
    await tester.pumpAndSettle();
    expect(find.text('Gespeicherter Stand'), findsOneWidget);
  });

  testWidgets('late results cannot replace a newer revision', (tester) async {
    final first = Completer<String>();
    final second = Completer<String>();
    await tester.pumpWidget(_page(() => first.future, revision: 1));
    await tester.pumpWidget(_page(() => second.future, revision: 2));
    second.complete('Aktueller Filter');
    await tester.pumpAndSettle();
    first.complete('Überholter Filter');
    await tester.pumpAndSettle();
    expect(find.text('Aktueller Filter'), findsOneWidget);
    expect(find.text('Überholter Filter'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'actionable API error fits 320px at large text in $brightness',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: LoadView<String>(
                  load: () =>
                      Future.error(ApiError('Bitte prüfe die Verbindung.')),
                  builder: (_, _) => const Text('Unreachable'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Bitte prüfe die Verbindung.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
