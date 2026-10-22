import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_account.dart';
import 'package:schulpilot/child_photo_preview.dart';
import 'package:schulpilot/school_day_screen.dart';
import 'package:schulpilot/ui.dart';

import 'school_day_background_test.dart' as d;
import 'child_school_day_actions_ux88_test.dart' as old;
import 'child_local_tools_ux88_test.dart' as f;

Uint8List bytes(int value) => Uint8List.fromList(
  image.encodePng(image.Image(width: value, height: value)),
);
Future<GoRouter> showDay(
  WidgetTester tester,
  AppState state, {
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(320, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/after-school/child',
    routes: [
      GoRoute(
        path: '/after-school/:id',
        builder: (_, _) => SchoolDayScreen(state, childId: 'child'),
      ),
      for (final route in ['/material/:id', '/unit/:id'])
        GoRoute(
          path: route,
          builder: (_, r) => Scaffold(body: Text('Ziel ${r.uri.path}')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
  await d.settleUi(tester);
  return router;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'CK011 removing one local photo keeps its neighbour and other days',
    (tester) async {
      final server = d.PreparationServer(pages: []),
          state = d.PreparationServer(pages: []).state();
      final first = await state.pendingUploads.add(
        'kid',
        'child',
        'day',
        bytes(2),
      );
      final second = await state.pendingUploads.add(
        'kid',
        'child',
        'day',
        bytes(3),
      );
      final other = await state.pendingUploads.add(
        'kid',
        'child',
        'other',
        bytes(4),
      );
      await old.open(tester, state);
      await f.tap(tester, find.byTooltip('Vorgemerktes Foto 1 entfernen'));
      await old.tap(tester, 'Dieses Foto entfernen');
      final remaining = await state.pendingUploads.read('kid');
      expect(remaining.map((p) => p['key']), [second, other]);
      expect(remaining.any((p) => p['key'] == first), isFalse);
      expect(server.requests, isEmpty);
    },
  );
  testWidgets('CK012 local preview zoom and reset work without any upload', (
    tester,
  ) async {
    final state = f.account(
      (r) async => throw StateError('No network expected'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () =>
                  showChildPhotoPreview(ctx, state, photos: [bytes(2)]),
              child: Text('Foto ansehen'),
            ),
          ),
        ),
      ),
    );
    await f.tap(tester, find.text('Foto ansehen'));
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    await f.tap(tester, find.byTooltip('Lokales Foto vergrößern'));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 2);
    await f.tap(tester, find.text('Ganze Seite'));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal, character: '+');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'CK013 pending album shows actual position and obeys both boundaries',
    (tester) async {
      final state = f.account(
        (r) async => throw StateError('No network expected'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showChildPhotoPreview(
                  ctx,
                  state,
                  photos: [bytes(2), bytes(3)],
                  initialIndex: 0,
                ),
                child: Text('Foto ansehen'),
              ),
            ),
          ),
        ),
      );
      await f.tap(tester, find.text('Foto ansehen'));
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) =>
                    w is IconButton && w.tooltip == 'Voriges vorgemerktes Foto',
              ),
            )
            .onPressed,
        isNull,
      );
      await f.tap(
        tester,
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Nächstes vorgemerktes Foto',
        ),
      );
      expect(find.text('2 von 2'), findsOneWidget);
      final actual =
          tester.widget<Image>(find.byType(Image)).image as MemoryImage;
      expect(actual.bytes, bytes(3));
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) =>
                    w is IconButton &&
                    w.tooltip == 'Nächstes vorgemerktes Foto',
              ),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'CK014 collected page strip remains readable at 320px double text',
    (tester) async {
      final server = d.PreparationServer();
      await showDay(tester, server.state(), scale: 2);
      expect(find.text('Seite 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'CK015 saved text pages lead to their source instead of broken photo zoom',
    (tester) async {
      final server = d.PreparationServer(pages: [d.source(1, confirmed: true)]);
      server.pages[0]['has_image'] = false;
      await showDay(tester, server.state());
      await old.tap(tester, '1 gespeicherte Seite ansehen');
      await old.tap(tester, 'Seite 1');
      expect(find.text('Ziel /material/page1'), findsOneWidget);
      expect(server.requests.any((r) => r.endsWith('/image')), isFalse);
    },
  );
  testWidgets(
    'CK016 reorder menu uses real positions including already confirmed pages',
    (tester) async {
      final server = d.PreparationServer(
        pages: [d.source(1, confirmed: true), d.source(2)],
      );
      await showDay(tester, server.state());
      await f.tap(tester, find.byTooltip('Seite 2 bearbeiten'));
      expect(find.text('Nach vorn'), findsOneWidget);
      expect(find.text('Nach hinten'), findsNothing);
      expect(server.requests.every((r) => r.startsWith('GET ')), isTrue);
    },
  );
  testWidgets(
    'CK017 package search finds sources and restores the real loaded packet',
    (tester) async {
      final server = d.PreparationServer(
        stage: 'ready',
        pages: [d.source(1, confirmed: true), d.source(2, confirmed: true)],
      );
      server.units = [
        {
          'id': 'unit',
          'subject': 'Mathematik',
          'topic': 'Andere Runde',
          'status': 'completed',
        },
      ];
      await showDay(tester, server.state());
      await old.tap(tester, 'Was ist im Paket?');
      await tester.enterText(
        f.input('In diesem Tagespaket suchen'),
        'Bruchaufgabe 2',
      );
      await tester.pump();
      expect(find.text('Künstliche Bruchaufgabe 2'), findsOneWidget);
      expect(find.text('Künstliche Bruchaufgabe 1'), findsNothing);
      await tester.enterText(f.input('In diesem Tagespaket suchen'), 'Nichts');
      await tester.pump();
      await old.tap(tester, 'Alle Inhalte dieses Pakets zeigen');
      expect(find.text('Künstliche Bruchaufgabe 1'), findsOneWidget);
      expect(server.requests.every((r) => r.startsWith('GET ')), isTrue);
    },
  );
  testWidgets(
    'CK018 packet kind filter separates saved units and sources honestly',
    (tester) async {
      final server = d.PreparationServer(
        stage: 'ready',
        pages: [d.source(1, confirmed: true)],
      );
      server.units = [
        {
          'id': 'unit',
          'subject': 'Mathematik',
          'topic': 'Andere Runde',
          'status': 'completed',
        },
      ];
      await showDay(tester, server.state());
      await old.tap(tester, 'Was ist im Paket?');
      await f.tap(tester, find.widgetWithText(ChoiceChip, 'Lernrunden'));
      expect(
        find.text('0 Heftseiten · 1 Lernrunden in dieser Ansicht'),
        findsOneWidget,
      );
      await f.tap(tester, find.widgetWithText(ChoiceChip, 'Heftseiten'));
      expect(
        find.text('1 Heftseiten · 0 Lernrunden in dieser Ansicht'),
        findsOneWidget,
      );
      expect(find.text('Mathematik · Andere Runde'), findsNothing);
      expect(server.requests.every((r) => r.startsWith('GET ')), isTrue);
    },
  );
  testWidgets('CK019 import receipt links only a current saved source', (
    tester,
  ) async {
    final server = d.PreparationServer();
    final state = server.state();
    await state.pendingUploads.receipt('kid', 'receipt', {
      'child': 'child',
      'day': 'day',
      'name': 'Künstliches Foto',
      'stage': 'saved',
      'material_id': 'page1',
    });
    await showDay(tester, state);
    await old.tap(tester, 'Deine Fotoauswahl');
    await old.tap(tester, 'Gespeicherte Seite ansehen');
    expect(find.text('Ziel /material/page1'), findsOneWidget);
  });
  testWidgets(
    'CK020 receipt problem filter hides successes without retrying them',
    (tester) async {
      final server = d.PreparationServer();
      final state = server.state();
      await state.pendingUploads.receipt('kid', 'good', {
        'child': 'child',
        'day': 'day',
        'name': 'Gutes Foto',
        'stage': 'saved',
      });
      await state.pendingUploads.receipt('kid', 'bad', {
        'child': 'child',
        'day': 'day',
        'name': 'Unlesbares Foto',
        'stage': 'not_accepted',
        'reason': 'Bitte noch einmal auswählen.',
      });
      await showDay(tester, state);
      await old.tap(tester, 'Nur Fotos mit Problemen');
      expect(find.text('Unlesbares Foto'), findsOneWidget);
      expect(find.text('Gutes Foto'), findsNothing);
      expect(server.requests.every((r) => r.startsWith('GET ')), isTrue);
    },
  );
  testWidgets(
    'CK048 account finds own unsent photos across days and resumes the right day',
    (tester) async {
      final state = f.account((r) async => f.reply([]));
      await state.pendingUploads.add(
        'child-user',
        'child',
        'first-day',
        bytes(2),
      );
      await state.pendingUploads.add(
        'child-user',
        'child',
        'second-day',
        bytes(3),
      );
      await state.pendingUploads.add(
        'child-user',
        'sibling',
        'sibling-day',
        bytes(4),
      );
      await f.show(tester, ChildAccount(state));
      await f.tap(tester, find.text('Lokale Fotos'));
      expect(
        find.text('2 von höchstens 8 vorgemerkten Fotos auf diesem Gerät'),
        findsOneWidget,
      );
      await f.tap(tester, find.text('Zum zugehörigen Tag').last);
      expect(find.text('Ziel /after-school/child'), findsOneWidget);
    },
  );
}
