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
import 'package:schulpilot/subject_graphic.dart';
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
  Json? catalogueOverride;
  String? fullNotice;
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
        ...(catalogueOverride ?? catalogue()),
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
      return reply(currentSaved(), 202);
    }
    if (path == '/api/learning-asset-instances/saved-instance') {
      return reply(currentSaved());
    }
    if (path.endsWith('/notifications')) {
      return reply({'items': [], 'unread_count': 0});
    }
    return reply({});
  }

  Json currentSaved() {
    final result = saved(status: prepareStatus);
    if (fullNotice != null) result['build']['notice'] = fullNotice;
    return result;
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
    'opening a prepared asset resets the scrolled selection without hiding title or close',
    (tester) async {
      final f = Fixture()..paged = true;
      await f.mount(tester, size: const Size(390, 568));
      await f.choose(tester);
      final prepare = find.widgetWithText(FilledButton, 'Thema entdecken');
      await tester.ensureVisible(prepare);
      await tester.pumpAndSettle();
      ScrollController scroll() => tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('workspace-scroll')),
          )
          .controller!;
      final selectionScroll = scroll();
      expect(
        selectionScroll.offset,
        greaterThan(0),
        reason: 'This reproduces a real scrolled selection.',
      );
      await tester.tap(prepare);
      await tester.pumpAndSettle();
      final assetScroll = scroll();
      expect(assetScroll, isNot(same(selectionScroll)));
      expect(assetScroll.offset, 0);
      final title = find.text('Bruchteile entdecken');
      final close = find.byTooltip('Anderes Thema auswählen');
      expect(tester.getTopLeft(title).dy, greaterThanOrEqualTo(0));
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.getRect(close).top, greaterThanOrEqualTo(0));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(scroll().offset, 0);
      expect(find.text('Themen entdecken').hitTestable(), findsOneWidget);
      expect(f.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'same instance refresh and zoom preserve its scroll controller and exploration',
    (tester) async {
      final f = Fixture(history: [saved()]);
      await f.mount(tester, size: const Size(390, 568));
      final item = find.text('Bruchteile entdecken');
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
      final denominator = find.widgetWithText(ChoiceChip, 'Nenner');
      await tester.ensureVisible(denominator);
      await tester.tap(denominator);
      await tester.pumpAndSettle();
      ScrollController scroll() => tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('workspace-scroll')),
          )
          .controller!;
      final original = scroll(), offset = scroll().offset;
      expect(offset, greaterThan(0));
      expect(tester.widget<ChoiceChip>(denominator).selected, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(scroll(), same(original));
      expect(scroll().offset, offset);
      expect(tester.widget<ChoiceChip>(denominator).selected, isTrue);
      final zoom = find.byTooltip('Grafik vergrößern');
      await tester.ensureVisible(zoom);
      await tester.pumpAndSettle();
      final zoomOffset = scroll().offset;
      await tester.tap(zoom);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zur Aufgabe zurück'));
      await tester.pumpAndSettle();
      expect(scroll(), same(original));
      expect(scroll().offset, zoomOffset);
      expect(tester.widget<ChoiceChip>(denominator).selected, isTrue);
      expect(f.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'opened asset prioritizes its graphic at $width px and ${scale}x text',
        (tester) async {
          final f = Fixture(history: [saved()]);
          await f.mount(tester, size: Size(width, 844), scale: scale);
          expect(find.text('Themen entdecken'), findsOneWidget);
          expect(
            find.ancestor(
              of: find.text('Was möchtest du verstehen?'),
              matching: find.byType(Panel),
            ),
            findsOneWidget,
          );
          final savedItem = find.text('Bruchteile entdecken');
          await tester.ensureVisible(savedItem);
          await tester.tap(savedItem);
          await tester.pumpAndSettle();
          final close = find.byTooltip('Anderes Thema auswählen');
          await tester.ensureVisible(close);
          await tester.pumpAndSettle();
          expect(find.text('Themen entdecken'), findsNothing);
          expect(find.text('Bruchteile entdecken'), findsOneWidget);
          final graphic = find.byType(SubjectPresentation);
          expect(graphic, findsOneWidget);
          expect(
            find.ancestor(of: graphic, matching: find.byType(Panel)),
            findsNothing,
          );
          expect(
            tester.widget<SubjectPresentation>(graphic).data,
            saved()['build']['asset']['presentation'],
          );
          expect(find.byTooltip('Grafik vergrößern'), findsOneWidget);
          expect(
            find.text(
              'KI-Beispiel · fachlich ungeprüft; keine Leistungsbewertung',
            ),
            findsOneWidget,
          );
          final bounds = tester.getRect(close);
          expect(close.hitTestable(), findsOneWidget);
          expect(bounds.width, greaterThanOrEqualTo(48));
          expect(bounds.height, greaterThanOrEqualTo(48));
          if (width < 720) {
            expect(
              tester.getSize(graphic).width,
              greaterThanOrEqualTo(width - 40),
            );
            if (scale == 1) {
              expect(tester.getTopLeft(graphic).dy, lessThan(220));
            }
          }
          expect(f.writes, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'full original AI notice stays deliberately accessible without any write',
    (tester) async {
      const original =
          'KI-Beispiele können Fehler enthalten. Diese ausführliche gespeicherte Erklärung bleibt vollständig zugänglich. '
          'Die technische Prüfung ist keine unabhängige fachliche Freigabe. Erkunden bewertet keine Leistung.';
      final f = Fixture(history: [saved()])..fullNotice = original;
      await f.mount(tester);
      final item = find.text('Bruchteile entdecken');
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(find.text(original), findsNothing);
      expect(
        find.text('KI-Beispiel · fachlich ungeprüft; keine Leistungsbewertung'),
        findsOneWidget,
      );
      final details = find.text('Vollständiger KI-Hinweis');
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text(original), findsOneWidget);
      await tester.ensureVisible(find.text(original));
      await tester.pumpAndSettle();
      expect(find.text(original).hitTestable(), findsOneWidget);
      expect(f.writes, isEmpty);
      final reads = f.calls.length;
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text(original), findsNothing);
      expect(f.calls, hasLength(reads));
    },
  );
  testWidgets(
    'closing an open asset restores the selection panel without a request',
    (tester) async {
      final f = Fixture(history: [saved()]);
      await f.mount(tester);
      await f.choose(tester);
      final item = find.text('Bruchteile entdecken');
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
      final before = f.calls.length;
      final close = find.byTooltip('Anderes Thema auswählen');
      await tester.ensureVisible(close);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text('Themen entdecken'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Was möchtest du verstehen?'),
          matching: find.byType(Panel),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(
                const ValueKey(
                  'asset-source:Mathematik:f:foundation-fractions',
                ),
              ),
            )
            .initialValue,
        'f:foundation-fractions',
      );
      expect(f.calls, hasLength(before));
      expect(f.writes, isEmpty);
    },
  );
  testWidgets(
    'recipe radios use short kind names and a friendly unknown fallback',
    (tester) async {
      final data = catalogue();
      data['recipes'] = [
        {
          'id': 'math.fraction',
          'version': 1,
          'kind': 'fraction',
          'purpose': 'INTERNAL_FRACTION_RULE_TEXT',
        },
        {
          'id': 'scene.example',
          'version': 1,
          'kind': 'scene',
          'purpose': 'INTERNAL_SCENE_RULE_TEXT',
        },
        {
          'id': 'future.example',
          'version': 1,
          'kind': 'future',
          'purpose': 'INTERNAL_UNKNOWN_RULE_TEXT',
        },
      ];
      data['foundations'][0]['recommended_recipe_ids'] = [
        'math.fraction',
        'scene.example',
        'future.example',
      ];
      final f = Fixture()..catalogueOverride = data;
      await f.mount(tester);
      await f.choose(tester);
      final controls = find.text('Darstellung und Stufe');
      await tester.ensureVisible(controls);
      await tester.tap(controls);
      await tester.pumpAndSettle();
      for (final title in ['Bruchmodell', 'Interaktive Szene', 'Fachgrafik']) {
        expect(
          find.widgetWithText(RadioListTile<String>, title),
          findsOneWidget,
        );
      }
      expect(find.textContaining('INTERNAL_'), findsNothing);
      expect(find.text('future.example'), findsNothing);
      expect(f.writes, isEmpty);
    },
  );
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
      expect(
        find.text('KI-Beispiel · fachlich ungeprüft; keine Leistungsbewertung'),
        findsOneWidget,
      );
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
    expect(
      find.text('KI-Beispiel · fachlich ungeprüft; keine Leistungsbewertung'),
      findsOneWidget,
    );
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
