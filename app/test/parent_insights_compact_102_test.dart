import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/parent_insights_panel.dart';
import 'package:schulpilot/ui.dart';

import 'parent_insights_test.dart' show insight, response;

class CompactInsightsFixture {
  final requests = <http.Request>[];
  final childId = ValueNotifier('child-a');
  late final AppState state;
  Json data = insight();
  bool failReview = false;

  CompactInsightsFixture() {
    state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient((request) async {
                requests.add(request);
                if (request.method == 'POST' && failReview) {
                  return response({
                    'detail': 'Künstliche Anfrage noch offen.',
                  }, 503);
                }
                return response(data);
              }),
            ),
          )
          ..user = {'id': 'parent', 'role': 'parent'}
          ..familyId = 'family';
  }

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool compact = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() {
      state.inbox.dispose();
      state.dispose();
      childId.dispose();
    });
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
            child: ValueListenableBuilder<String>(
              valueListenable: childId,
              builder: (context, child, _) =>
                  ParentInsightsPanel(state, childId: child, compact: compact),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder compactDetails() => find.byKey(
  const ValueKey('parent-insights-compact-details'),
  skipOffstage: false,
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final configuration in [(320.0, 2.0), (390.0, 1.0), (1440.0, 1.0)]) {
    testWidgets(
      '102 compact insights collapse details without writes at $configuration',
      (tester) async {
        final f = CompactInsightsFixture();
        await f.mount(tester, width: configuration.$1, scale: configuration.$2);
        expect(find.text('KI-Lernkompass'), findsOneWidget);
        expect(
          find.textContaining('Neuere Übungsbelege vorhanden'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Stand ${reviewDate(1792569000)}'),
          findsOneWidget,
        );
        expect(find.text('Regelmäßig mit KI auswerten'), findsNothing);
        expect(find.text('Jetzt mit KI auswerten'), findsNothing);
        expect(tester.widget<ExcludeFocus>(compactDetails()).excluding, isTrue);
        final initialRequests = f.requests.length;

        await tapVisible(tester, find.text('KI-Lernkompass'));
        expect(find.text('Regelmäßig mit KI auswerten'), findsOneWidget);
        expect(find.text('Jetzt mit KI auswerten'), findsOneWidget);
        expect(find.textContaining('Unterstützung war nötig.'), findsOneWidget);
        expect(find.byTooltip('Lernkompass neu laden'), findsOneWidget);
        expect(
          tester.widget<ExcludeFocus>(compactDetails()).excluding,
          isFalse,
        );
        expect(tester.takeException(), isNull);

        await tapVisible(tester, find.text('KI-Lernkompass'));
        expect(find.text('Regelmäßig mit KI auswerten'), findsNothing);
        expect(tester.widget<ExcludeFocus>(compactDetails()).excluding, isTrue);
        expect(f.requests.length, initialRequests);
        expect(f.requests.every((request) => request.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('102 normal insight detail page stays open', (tester) async {
    final f = CompactInsightsFixture();
    await f.mount(tester, compact: false);
    expect(find.text('KI-Lernkompass'), findsOneWidget);
    expect(find.text('Regelmäßig mit KI auswerten'), findsOneWidget);
    expect(find.text('Der vorgeschlagene Lernweg'), findsOneWidget);
    expect(compactDetails(), findsNothing);
    expect(f.requests.every((request) => request.method == 'GET'), isTrue);
  });

  testWidgets('102 compact insight toggle retains an unconfirmed request', (
    tester,
  ) async {
    final f = CompactInsightsFixture()..failReview = true;
    await f.mount(tester);
    await tapVisible(tester, find.text('KI-Lernkompass'));
    await tapVisible(tester, find.text('Jetzt mit KI auswerten'));
    expect(find.text('Anfrage abgleichen'), findsOneWidget);
    expect(find.textContaining('Anfrage noch nicht bestätigt'), findsOneWidget);
    final firstPost = f.requests.singleWhere(
      (request) => request.method == 'POST',
    );
    final requestKey = firstPost.headers['Idempotency-Key'];
    expect(requestKey, isNotEmpty);
    final beforeToggle = f.requests.length;

    await tapVisible(tester, find.text('KI-Lernkompass'));
    expect(find.text('Anfrage abgleichen'), findsNothing);
    expect(find.textContaining('Anfrage noch nicht bestätigt'), findsOneWidget);
    await tapVisible(tester, find.text('KI-Lernkompass'));
    expect(find.text('Anfrage abgleichen'), findsOneWidget);
    expect(f.requests.length, beforeToggle);

    await tapVisible(tester, find.text('Anfrage abgleichen'));
    final posts = f.requests
        .where((request) => request.method == 'POST')
        .toList();
    expect(posts, hasLength(2));
    expect(posts.last.headers['Idempotency-Key'], requestKey);
    expect(posts.last.url.path, '/api/children/child-a/parent-insights/review');
  });

  testWidgets(
    '102 compact insight expansion resets on child and identity changes',
    (tester) async {
      final f = CompactInsightsFixture();
      await f.mount(tester);
      await tapVisible(tester, find.text('KI-Lernkompass'));
      final oldExpansion = tester
          .widget<ExpansionTile>(
            find.byKey(const ValueKey('parent-insights-compact-child-a')),
          )
          .onExpansionChanged!;
      expect(find.text('Jetzt mit KI auswerten'), findsOneWidget);

      f.childId.value = 'child-b';
      await tester.pumpAndSettle();
      expect(find.text('Jetzt mit KI auswerten'), findsNothing);
      expect(tester.widget<ExcludeFocus>(compactDetails()).excluding, isTrue);
      expect(f.requests.last.url.path, '/api/children/child-b/parent-insights');
      oldExpansion(true);
      await tester.pumpAndSettle();
      expect(find.text('Jetzt mit KI auswerten'), findsNothing);
      expect(tester.widget<ExcludeFocus>(compactDetails()).excluding, isTrue);

      await tapVisible(tester, find.text('KI-Lernkompass'));
      final beforeScopeChange = f.requests.length;
      f.state.familyId = 'other-family';
      f.state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('KI-Lernkompass'), findsNothing);
      expect(find.text('Regelmäßig mit KI auswerten'), findsNothing);
      expect(f.requests.length, beforeScopeChange);
      expect(f.requests.every((request) => request.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    '102 compact insight details disappear after account replacement',
    (tester) async {
      final f = CompactInsightsFixture();
      await f.mount(tester);
      await tapVisible(tester, find.text('KI-Lernkompass'));
      expect(find.text('Regelmäßig mit KI auswerten'), findsOneWidget);
      final requestCount = f.requests.length;
      f.state.user = Json.from(f.state.user!);
      f.state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('KI-Lernkompass'), findsNothing);
      expect(find.text('Regelmäßig mit KI auswerten'), findsNothing);
      expect(f.requests.length, requestCount);
      expect(f.requests.every((request) => request.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    '102 closed compact insights keep failed status and saved date visible',
    (tester) async {
      final f = CompactInsightsFixture();
      f.data['latest_attempt'] = {
        'status': 'failed',
        'error': 'Künstlicher Abbruch.',
      };
      await f.mount(tester);
      expect(
        find.textContaining('Letzter Auswertungsversuch offen'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Stand ${reviewDate(1792569000)}'),
        findsOneWidget,
      );
      expect(find.text('Bewusst erneut auswerten'), findsNothing);
      await tapVisible(tester, find.text('KI-Lernkompass'));
      expect(find.text('Künstlicher Abbruch.'), findsOneWidget);
      expect(find.text('Bewusst erneut auswerten'), findsOneWidget);
      expect(f.requests.every((request) => request.method == 'GET'), isTrue);
    },
  );
}
