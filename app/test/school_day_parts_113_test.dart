import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';

import 'school_day_background_test.dart' as background;

Future<void> openParts(
  WidgetTester tester,
  background.PreparationServer server, {
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final navigation = background.router(server.state());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    navigation.dispose();
  });
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: navigation,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
  await background.settleUi(tester);
}

background.PreparationServer partsServer(Json preparation) =>
    background.PreparationServer(
      stage: 'review',
      pages: [background.source(1, confirmed: true)],
      preparation: preparation,
    );

LinearProgressIndicator progress(WidgetTester tester) =>
    tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('school-day-preparation-progress')),
    );

void expectNoWrites(background.PreparationServer server) {
  expect(server.requests, isNotEmpty);
  expect(
    server.requests.every((request) => request.startsWith('GET ')),
    isTrue,
  );
  expect(server.submissions, 0);
  expect(server.starts, 0);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Package parts stay readable at $width px and $scale text', (
        tester,
      ) async {
        final server = partsServer({
          'status': 'processing',
          'phase': 'package',
          'total_parts': 7,
          'completed_parts': 2,
          'active_part': 2,
        });
        await openParts(tester, server, width: width, textScale: scale);
        expect(find.text('Dein Lernpaket entsteht'), findsOneWidget);
        expect(find.text('Teil 3 von 7'), findsOneWidget);
        expect(progress(tester).value, closeTo(2 / 7, .00001));
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('school-day-part-status')),
              )
              .semanticsLabel,
          'Teil 3 von 7. 2 von 7 Teilen gespeichert.',
        );
        expect(find.textContaining('package_outputs'), findsNothing);
        expectNoWrites(server);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Polling advances saved part counts without submitting work', (
    tester,
  ) async {
    final server = partsServer({
      'status': 'processing',
      'phase': 'package',
      'total_parts': 3,
      'completed_parts': 0,
      'active_part': 0,
    });
    await openParts(tester, server);
    expect(find.text('Teil 1 von 3'), findsOneWidget);
    expect(progress(tester).value, 0);
    final reads = server.reads;
    server.preparation = {
      'status': 'processing',
      'phase': 'package',
      'total_parts': 3,
      'completed_parts': 1,
      'active_part': 1,
    };
    await tester.pump(const Duration(seconds: 3));
    await background.settleUi(tester);
    expect(server.reads, greaterThan(reads));
    expect(find.text('Teil 2 von 3'), findsOneWidget);
    expect(progress(tester).value, closeTo(1 / 3, .00001));
    expectNoWrites(server);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A failed part preserves saved count and retries only on click', (
    tester,
  ) async {
    final server = partsServer({
      'status': 'failed',
      'phase': 'package',
      'can_retry': true,
      'total_parts': 3,
      'completed_parts': 1,
      'active_part': 1,
      'error_code': 'invalid_output',
      'error': 'Private synthetic diagnostic must not be printed',
    });
    await openParts(tester, server, width: 320, textScale: 2);
    expect(find.text('1 von 3 Teilen gespeichert'), findsOneWidget);
    expect(progress(tester).value, closeTo(1 / 3, .00001));
    expect(find.text('Fehlenden Teil erneut vorbereiten'), findsOneWidget);
    expect(find.textContaining('Private synthetic diagnostic'), findsNothing);
    expectNoWrites(server);
    await background.tapText(tester, 'Fehlenden Teil erneut vorbereiten');
    expect(server.submissions, 1);
    expect(server.keys, hasLength(1));
    expect(server.starts, 0);
    expect(server.requests.where((request) => !request.startsWith('GET ')), [
      'POST /api/school-days/day/prepare',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Exhausted part retry keeps the existing home action', (
    tester,
  ) async {
    final server = partsServer({
      'status': 'blocked',
      'phase': 'package',
      'can_retry': false,
      'total_parts': 4,
      'completed_parts': 2,
      'active_part': 2,
      'error_code': 'quota_exhausted',
    });
    await openParts(tester, server);
    expect(find.text('2 von 4 Teilen gespeichert'), findsOneWidget);
    expect(find.text('Fehlenden Teil erneut vorbereiten'), findsNothing);
    expect(find.text('Erneut vorbereiten'), findsNothing);
    expect(find.text('Zur Startseite'), findsOneWidget);
    expectNoWrites(server);
    expect(tester.takeException(), isNull);
  });

  for (final phase in ['package', 'extract']) {
    testWidgets('Legacy $phase status has no invented part progress', (
      tester,
    ) async {
      final server = partsServer({
        'status': 'processing',
        'phase': phase,
        'total_pages': 3,
        'completed_pages': 1,
      });
      await openParts(tester, server);
      expect(
        find.byKey(const ValueKey('school-day-part-status')),
        findsNothing,
      );
      expect(
        progress(tester).value,
        phase == 'package' ? isNull : closeTo(1 / 3, .00001),
      );
      expectNoWrites(server);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Legacy failure retains the original explicit retry label', (
    tester,
  ) async {
    final server = partsServer({
      'status': 'failed',
      'phase': 'package',
      'can_retry': true,
      'error_code': 'invalid_output',
    });
    await openParts(tester, server);
    expect(find.text('Erneut vorbereiten'), findsOneWidget);
    expect(find.text('Fehlenden Teil erneut vorbereiten'), findsNothing);
    expect(find.byKey(const ValueKey('school-day-part-status')), findsNothing);
    expectNoWrites(server);
  });

  const malformed = <Json>[
    {'total_parts': 0, 'completed_parts': 0, 'active_part': null},
    {'total_parts': 25, 'completed_parts': 1, 'active_part': 1},
    {'total_parts': 3.0, 'completed_parts': 1, 'active_part': 1},
    {'total_parts': 3, 'completed_parts': -1, 'active_part': 1},
    {'total_parts': 3, 'completed_parts': 4, 'active_part': 1},
    {'total_parts': 3, 'completed_parts': 1.0, 'active_part': 1},
    {'total_parts': 3, 'completed_parts': 1, 'active_part': -1},
    {'total_parts': 3, 'completed_parts': 1, 'active_part': 3},
    {'total_parts': 3, 'completed_parts': 1, 'active_part': true},
    {'total_parts': '3', 'completed_parts': 1, 'active_part': 1},
  ];
  for (var index = 0; index < malformed.length; index++) {
    testWidgets('Malformed bounded part metadata $index uses legacy fallback', (
      tester,
    ) async {
      final server = partsServer({
        'status': 'processing',
        'phase': 'package',
        ...malformed[index],
      });
      await openParts(tester, server);
      expect(
        find.byKey(const ValueKey('school-day-part-status')),
        findsNothing,
      );
      expect(progress(tester).value, isNull);
      expectNoWrites(server);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Between parts and aggregate finalization stay within total', (
    tester,
  ) async {
    final server = partsServer({
      'status': 'processing',
      'phase': 'package',
      'total_parts': 24,
      'completed_parts': 24,
      'active_part': null,
    });
    await openParts(tester, server);
    expect(find.text('Teil 24 von 24'), findsOneWidget);
    expect(progress(tester).value, 1);
    expectNoWrites(server);
    expect(tester.takeException(), isNull);
  });
}
