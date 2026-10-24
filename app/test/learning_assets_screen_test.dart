import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_assets_screen.dart';
import 'package:schulpilot/schulbuddy.dart';
import 'package:schulpilot/ui.dart';

Json catalogue() => {
  'subjects': ['Mathematik', 'Deutsch'],
  'subject_definitions': [
    {'key': 'mathematics', 'title': 'Mathematik'},
    {'key': 'german', 'title': 'Deutsch'},
  ],
  'recipes': [
    {'id': 'math.fraction', 'version': 1, 'purpose': 'Bruchteile darstellen'},
  ],
  'foundations': [
    {
      'reference_id': 'foundation-fractions',
      'subject_key': 'mathematics',
      'content': 'Brüche zeigen Teile eines Ganzen.',
      'recommended_recipe_ids': ['math.fraction'],
    },
  ],
  'topics': [],
};

Json saved({String status = 'ready'}) => {
  'id': 'saved-instance',
  'child_id': 'child',
  'title': 'Öffentlicher Thementitel',
  'subject': 'Mathematik',
  'build': {
    'status': status,
    'factual_status': 'unassessed',
    'notice': 'KI kann Fehler machen. Erkunden wird nicht bewertet.',
    'asset': status != 'ready'
        ? null
        : {
            'title': 'Bruchteile entdecken',
            'text': 'Ein Teil von vier gleich großen Teilen ist markiert.',
            'presentation': {
              'version': 1,
              'blocks': [
                {
                  'kind': 'fraction',
                  'title': 'Ein Viertel',
                  'numbers': [1, 4],
                  'labels': [],
                  'disclosure': 'given',
                },
              ],
            },
            'explorations': [
              {'prompt': 'Wie viele Teile bleiben unmarkiert?'},
            ],
          },
  },
};

class Fixture {
  final calls = <http.Request>[];
  final List<Json> history;
  Completer<http.Response>? postWait;
  bool failPost = false;
  bool paged = false;
  Completer<http.Response>? pageWait;
  String prepareStatus = 'ready';
  int buddyOpens = 0;
  late final AppState state;
  late GoRouter router;
  Fixture({this.history = const []}) {
    state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient(handle),
            ),
          )
          ..user = {
            'id': 'synthetic-child',
            'role': 'child',
            'child_id': 'child',
            'display_name': 'Beispiel',
          }
          ..familyId = 'family';
    state.api.token = 'synthetic-session';
  }
  http.Response reply(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json'},
  );
  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    final path = request.url.path;
    if (path == '/api/learning-assets/catalogue') {
      if (request.url.queryParameters['page'] == '2' && pageWait != null) {
        return pageWait!.future;
      }
      return reply({
        ...catalogue(),
        if (paged) ...{
          'topics': [
            {
              'id': 'topic-${request.url.queryParameters['page'] ?? '1'}',
              'title': 'Öffentliches Katalogthema',
              'subject': 'Mathematik',
              'recommended_recipe_ids': ['math.fraction'],
            },
          ],
          'pagination': {
            'page': int.parse(request.url.queryParameters['page'] ?? '1'),
            'has_more': request.url.queryParameters['page'] != '2',
          },
        },
      });
    }
    if (path == '/api/children/child/learning-assets') {
      return reply({'items': history});
    }
    if (path.endsWith('/learning-assets/prepare')) {
      if (postWait != null) return postWait!.future;
      if (failPost) {
        return reply({
          'detail': 'Verbindung unklar. Gespeicherten Stand laden.',
        }, 503);
      }
      return reply(saved(status: prepareStatus), 202);
    }
    if (path == '/api/learning-asset-instances/saved-instance') {
      return reply(saved(status: prepareStatus));
    }
    if (path.endsWith('/notifications')) {
      return reply({'items': [], 'unread_count': 0});
    }
    return reply({});
  }

  List<http.Request> get writes =>
      calls.where((e) => e.method != 'GET').toList();
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    bool buddyScope = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.binding.setSurfaceSize(size);
    router = GoRouter(
      initialLocation: '/discover/child',
      routes: [
        GoRoute(
          path: '/discover/:id',
          builder: (_, route) =>
              LearningAssetsScreen(state, childId: route.pathParameters['id']!),
        ),
        GoRoute(
          path: '/app',
          builder: (_, _) => const Scaffold(body: Text('Heute')),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: buddyScope
              ? SchulbuddyScope(
                  open: () async {
                    buddyOpens++;
                  },
                  child: child!,
                )
              : child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('asset-source:Mathematik:null')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brüche zeigen Teile eines Ganzen.').last);
    await tester.pumpAndSettle();
  }

  Future<void> prepare(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Thema entdecken');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'opened public example keeps the same buddy context in graphic zoom',
    (tester) async {
      final f = Fixture(history: [saved()]);
      await f.mount(tester, buddyScope: true);
      final item = find.text('Bruchteile entdecken');
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
      Json fields() => tester
          .widgetList<SchulbuddyPageContext>(find.byType(SchulbuddyPageContext))
          .last
          .contextValue
          .fields;
      expect(fields(), {
        'page_kind': 'learn',
        'child_id': 'child',
        'learning_asset_instance_id': 'saved-instance',
      });
      final zoom = find.byTooltip('Grafik vergrößern');
      await tester.ensureVisible(zoom);
      await tester.tap(zoom);
      await tester.pumpAndSettle();
      expect(fields()['learning_asset_instance_id'], 'saved-instance');
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(SchulbuddyButton),
        ),
        findsOneWidget,
      );
      final buddy = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SchulbuddyButton),
      );
      expect(buddy.hitTestable(), findsOneWidget);
      final bounds = tester.getRect(buddy);
      expect(bounds.right, lessThanOrEqualTo(390));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(844));
      await tester.tap(buddy);
      await tester.pumpAndSettle();
      expect(f.buddyOpens, 1);
      expect(f.writes, isEmpty);
      await tester.tap(find.byTooltip('Zur Aufgabe zurück'));
      await tester.pumpAndSettle();
      expect(fields()['learning_asset_instance_id'], 'saved-instance');
    },
  );

  testWidgets('failed preparation shows its status and never restarts itself', (
    tester,
  ) async {
    final f = Fixture(history: [saved(status: 'failed')])
      ..prepareStatus = 'failed';
    await f.mount(tester);
    final item = find.text('Öffentlicher Thementitel');
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Die Vorbereitung hat nicht geklappt.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 9));
    expect(f.writes, isEmpty);
  });

  testWidgets('paused and covered page does not poll or generate on resume', (
    tester,
  ) async {
    final f = Fixture()..prepareStatus = 'queued';
    await f.mount(tester);
    await f.choose(tester);
    await f.prepare(tester);
    await tester.pump();
    int reads() => f.calls
        .where(
          (e) =>
              e.url.path.endsWith('/learning-asset-instances/saved-instance'),
        )
        .length;
    // Cover while foreground, then background the app, as an actual user can.
    unawaited(f.router.push('/app'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 6));
    expect(reads(), 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 6));
    expect(reads(), 0);
    f.router.pop();
    await tester.pump();
    f.prepareStatus = 'ready';
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(reads(), 1);
    expect(f.writes, hasLength(1));
    expect(find.text('Bruchteile entdecken'), findsOneWidget);
  });

  testWidgets(
    'initial subject is server filtered and further topics are a read',
    (tester) async {
      final f = Fixture()..paged = true;
      await f.mount(tester);
      expect(
        f.calls.where(
          (e) => e.url.queryParameters['topic_subject'] == 'Mathematik',
        ),
        isNotEmpty,
      );
      final more = find.text('Weitere Themen laden');
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(
        f.calls.where((e) => e.url.queryParameters['page'] == '2'),
        hasLength(1),
      );
      expect(find.text('Weitere Themen laden'), findsNothing);
      expect(f.writes, isEmpty);
    },
  );

  testWidgets(
    'late topic page does not leave controls busy after preparation',
    (tester) async {
      final f = Fixture()
        ..paged = true
        ..pageWait = Completer<http.Response>();
      await f.mount(tester);
      await f.choose(tester);
      final more = find.text('Weitere Themen laden');
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pump();
      await f.prepare(tester);
      await tester.pumpAndSettle();
      f.pageWait!.complete(
        f.reply({
          ...catalogue(),
          'topics': [],
          'pagination': {'page': 2, 'has_more': false},
        }),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Anderes Thema auswählen'));
      await tester.pumpAndSettle();
      expect(find.text('Themen werden geladen …'), findsNothing);
      expect(find.text('Weitere Themen laden'), findsOneWidget);
      expect(f.writes, hasLength(1));
    },
  );

  testWidgets(
    'opening and selecting only read; one explicit public preparation',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(f.writes, isEmpty);
      await f.choose(tester);
      expect(f.writes, isEmpty);
      await f.prepare(tester);
      await tester.pumpAndSettle();
      expect(f.writes, hasLength(1));
      final call = f.writes.single;
      expect(call.headers['X-Schulpilot-Account'], 'synthetic-child');
      expect(
        call.headers['Idempotency-Key'],
        matches(r'^asset-[0-9]+-[0-9]+$'),
      );
      expect(jsonDecode(call.body), {
        'subject': 'Mathematik',
        'recipe_id': 'math.fraction',
        'recipe_version': 1,
        'foundation_ids': ['foundation-fractions'],
        'catalog_topic_id': null,
        'locale': 'de-DE',
        'level_band': 'lower_secondary',
      });
      expect(find.text('Bruchteile entdecken'), findsOneWidget);
      expect(find.text('KI-Erklärung · unbewertetes Erkunden'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved reusable content opens through GET without preparing', (
    tester,
  ) async {
    final f = Fixture(history: [saved()]);
    await f.mount(tester);
    final item = find.text('Bruchteile entdecken');
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(f.writes, isEmpty);
    expect(
      f.calls.where(
        (e) => e.url.path.endsWith('/learning-asset-instances/saved-instance'),
      ),
      hasLength(1),
    );
    expect(find.text('KI-Erklärung · unbewertetes Erkunden'), findsOneWidget);
  });

  testWidgets('pending status polling never repeats POST', (tester) async {
    final f = Fixture()..prepareStatus = 'queued';
    await f.mount(tester);
    await f.choose(tester);
    await f.prepare(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(f.writes, hasLength(1));
    expect(
      f.calls.where(
        (e) => e.url.path.endsWith('/learning-asset-instances/saved-instance'),
      ),
      isNotEmpty,
    );
    f.prepareStatus = 'ready';
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Bruchteile entdecken'), findsOneWidget);
    expect(f.writes, hasLength(1));
  });

  testWidgets('unclear preparation can only be repeated with same key', (
    tester,
  ) async {
    final f = Fixture()..failPost = true;
    await f.mount(tester);
    await f.choose(tester);
    await f.prepare(tester);
    await tester.pumpAndSettle();
    expect(f.writes, hasLength(1));
    f.failPost = false;
    await f.prepare(tester);
    await tester.pumpAndSettle();
    expect(f.writes, hasLength(2));
    expect(
      f.writes[0].headers['Idempotency-Key'],
      f.writes[1].headers['Idempotency-Key'],
    );
  });

  testWidgets('account switch cannot display an old pending response', (
    tester,
  ) async {
    final f = Fixture()..postWait = Completer<http.Response>();
    await f.mount(tester);
    await f.choose(tester);
    await f.prepare(tester);
    f.state.user = {'id': 'other-child', 'role': 'child', 'child_id': 'other'};
    f.state.api.token = 'new-session';
    // The old response is also rejected without relying on a router rebuild.
    f.postWait!.complete(f.reply(saved(), 202));
    await tester.pumpAndSettle();
    expect(find.text('Bruchteile entdecken'), findsNothing);
    expect(f.writes, hasLength(1));
  });

  for (final width in [320.0, 390.0, 800.0, 1280.0]) {
    testWidgets(
      'readable selection and graphic at width $width and 200 percent',
      (tester) async {
        final f = Fixture(history: [saved()]);
        await f.mount(tester, size: Size(width, 1000), scale: 2);
        expect(tester.takeException(), isNull);
        final item = find.text('Bruchteile entdecken');
        await tester.ensureVisible(item);
        await tester.tap(item);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(f.writes, isEmpty);
      },
    );
  }
}
