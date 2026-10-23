import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/auth_screens.dart';
import 'package:schulpilot/notebook_cover.dart';
import 'package:schulpilot/public_trial.dart';
import 'package:schulpilot/ui.dart';

import 'notebook_test.dart' as books;

Future<List<http.Request>> openPublic(
  WidgetTester tester,
  String path,
  Size size,
  double scale,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final requests = <http.Request>[];
  final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        requests.add(request);
        expectSync(request.method, 'GET');
        return books.jsonReply(
          request.url.path.endsWith('/store/catalog')
              ? {
                  'enabled': false,
                  'plans': [],
                  'trial': {'enabled': false},
                }
              : {'available': false},
        );
      }),
    ),
  );
  final router = GoRouter(
    initialLocation: path,
    routes: [
      GoRoute(path: '/', builder: (_, _) => LandingScreen(state)),
      for (final mode in ['login', 'register', 'recovery'])
        GoRoute(
          path: '/$mode',
          builder: (_, route) =>
              AuthScreen(state, mode: mode, linkUri: route.uri),
        ),
      GoRoute(
        path: '/app',
        builder: (_, _) => const Scaffold(body: Text('Lernraum')),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    state.familyCalls.dispose();
    state.inbox.dispose();
  });
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return requests;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final viewport in [
    (320.0, 1.0),
    (390.0, 1.0),
    (320.0, 2.0),
    (1440.0, 1.0),
  ]) {
    testWidgets(
      '102 subject covers remain compact and fully actionable at $viewport',
      (tester) async {
        final (_, _, calls) = await books.open(
          tester,
          shelf: true,
          width: viewport.$1,
          textScale: viewport.$2,
          shelfView: {'list': false, 'own_only': true},
        );
        final cover = find.byType(NotebookCover).first;
        final card = find
            .ancestor(of: cover, matching: find.byType(Material))
            .first;
        expect(
          tester.getSize(card).height,
          lessThanOrEqualTo(viewport.$2 > 1 ? 280 : 200),
        );
        expect(tester.getSize(card).shortestSide, greaterThanOrEqualTo(48));
        expect(find.text('Mathematik'), findsWidgets);
        expect(find.text('47 Seiten'), findsWidgets);
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(calls.any((r) => r.url.path.contains('/materials')), true);
        expect(calls.every((r) => r.method == 'GET'), true);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final mode in ['login', 'register', 'recovery']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('102 $mode keeps a wide usable form at 320px and ${scale}x', (
        tester,
      ) async {
        final calls = await openPublic(
          tester,
          '/$mode',
          const Size(320, 568),
          scale,
        );
        final field = find.byType(TextField).first;
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        expect(field.hitTestable(), findsOneWidget);
        expect(tester.getSize(field).width, greaterThanOrEqualTo(240));
        expect(calls.every((r) => r.method == 'GET'), true);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final sample in [
    (Size(320, 568), 1.0),
    (Size(390, 844), 2.0),
    (Size(1440, 1000), 1.0),
  ]) {
    testWidgets(
      '102 public introduction keeps its actual action readable at $sample',
      (tester) async {
        final calls = await openPublic(tester, '/', sample.$1, sample.$2);
        final title = tester.widget<Text>(
          find.text('Lernen, das zum\nSchulalltag passt.'),
        );
        expect(
          title.style!.fontSize,
          lessThanOrEqualTo(sample.$1.width < 980 ? 24 : 28),
        );
        final action = find.widgetWithText(
          FilledButton,
          'Elternkonto erstellen',
        );
        if (sample.$2 == 1) {
          expect(tester.getTopLeft(action).dy, lessThan(sample.$1.height));
        }
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        expect(calls.every((r) => r.method == 'GET'), true);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    '102 compact trial card keeps all terms and only its deliberate action',
    (tester) async {
      var starts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: TrialOfferCard(
                offer: const PublicTrialOffer(
                  available: true,
                  children: 2,
                  calls: 12,
                ),
                onStart: () => starts++,
              ),
            ),
          ),
        ),
      );
      expect(
        find.text(
          'Keine Zahlungsdaten. Keine automatische Bestellung oder Verlängerung.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Start nach E-Mail-Bestätigung'),
        findsOneWidget,
      );
      expect(starts, 0);
      final action = find.widgetWithText(
        FilledButton,
        '30 Tage kostenlos testen',
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    },
  );
}
