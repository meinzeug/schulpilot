import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/schulbuddy.dart';
import 'package:schulpilot/ui.dart';

const childId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    firstId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    nextId = 'cccccccccccccccccccccccccccccccc';
http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json contextData(String label, {List<Json> history = const []}) => {
  'context_key': label,
  'label': label,
  'available': true,
  'starters': [],
  'history': history,
  'notice': 'Künstlicher Kontext ohne echten Modellaufruf.',
};

class CurrentPageFixture {
  final calls = <http.Request>[];
  final selected = ValueNotifier(
    const SchulbuddyContext('notebooks', {
      'child_id': childId,
      'material_id': firstId,
    }, 'revision:1'),
  );
  final Future<http.Response> Function(http.Request)? respond;
  late final AppState state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        calls.add(request);
        if (respond != null) return respond!(request);
        if (request.url.path.endsWith('/schulbuddy/context')) {
          return reply(
            contextData(
              request.url.queryParameters['material_id'] == firstId
                  ? 'Seite A'
                  : 'Seite B',
            ),
          );
        }
        return reply({});
      }),
    ),
  )..user = {'id': 'synthetic-child', 'role': 'child', 'child_id': childId};
  late GoRouter router;
  CurrentPageFixture({this.respond});
  Future<void> mount(WidgetTester tester) async {
    final navigator = GlobalKey<NavigatorState>();
    router = GoRouter(
      navigatorKey: navigator,
      initialLocation: '/library/$childId/subject/mathe',
      routes: [
        GoRoute(
          path: '/library/:child/subject/:subject',
          builder: (_, _) => ValueListenableBuilder<SchulbuddyContext>(
            valueListenable: selected,
            builder: (_, value, _) => SchulbuddyPageContext(
              contextValue: value,
              child: const Scaffold(
                body: Column(
                  children: [
                    SchulbuddyButton(),
                    Text('Künstliche aktuelle Heftseite'),
                  ],
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: SchulbuddyButton()),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      selected.dispose();
    });
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (_, child) => ListenableBuilder(
          listenable: router.routeInformationProvider,
          builder: (_, _) => SchulbuddyHost(
            state: state,
            navigatorKey: navigator,
            location: router.routeInformationProvider.value.uri.toString(),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<http.Request> get contexts => calls
      .where((call) => call.url.path.endsWith('/schulbuddy/context'))
      .toList();
  List<http.Request> get writes =>
      calls.where((call) => call.method != 'GET').toList();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder question() =>
    find.widgetWithText(TextField, 'Deine Frage an Schulbuddy');
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('exam URI accepts only bounded IDs and never forwards arbitrary query text', () {
    final state = AppState()..user = {'role': 'child', 'child_id': childId};
    final value = SchulbuddyContext.fromLocation(
      state,
      '/exams/$childId?exam=$firstId&session=$nextId&tab=review&answer=private&note=secret',
    );
    expect(value.fields, {
      'page_kind': 'exams',
      'child_id': childId,
      'exam_id': firstId,
      'exam_session_id': nextId,
      'exam_tab': 'review',
    });
    expect(
      SchulbuddyContext.fromLocation(
        state,
        '/exams/$childId?exam=invalid&session=unsafe',
      ).references.containsKey('exam_id'),
      isFalse,
    );
    state.user = {'role': 'admin'};
    expect(
      SchulbuddyContext.fromLocation(
        state,
        '/exams/$childId?exam=$firstId',
      ).fields,
      {'page_kind': 'admin'},
    );
  });
  test('local source revision separates drafts without adding client source text to API fields', () {
    const first = SchulbuddyContext('notebooks', {
      'material_id': firstId,
    }, 'revision:1');
    const second = SchulbuddyContext('notebooks', {
      'material_id': firstId,
    }, 'revision:2');
    expect(first.key, isNot(second.key));
    expect(first.fields, second.fields);
    expect(first.path, second.path);
    expect(first.path, isNot(contains('revision')));
  });
  testWidgets(
    'actual album selection is used immediately on each opening and old draft is retained',
    (tester) async {
      final fixture = CurrentPageFixture();
      await fixture.mount(tester);
      await tap(tester, find.byTooltip('Schulbuddy öffnen'));
      expect(fixture.contexts.last.url.queryParameters['material_id'], firstId);
      await tester.enterText(question(), 'Frage nur zu Seite A');
      await tap(tester, find.byTooltip('Schulbuddy schließen'));
      fixture.selected.value = const SchulbuddyContext('notebooks', {
        'child_id': childId,
        'material_id': nextId,
      }, 'revision:1');
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Schulbuddy öffnen'));
      expect(fixture.contexts.last.url.queryParameters['material_id'], nextId);
      expect(tester.widget<TextField>(question()).controller!.text, isEmpty);
      await tap(tester, find.byTooltip('Schulbuddy schließen'));
      fixture.selected.value = const SchulbuddyContext('notebooks', {
        'child_id': childId,
        'material_id': firstId,
      }, 'revision:1');
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Schulbuddy öffnen'));
      expect(
        tester.widget<TextField>(question()).controller!.text,
        'Frage nur zu Seite A',
      );
      expect(fixture.writes, isEmpty);
    },
  );
  testWidgets(
    'an active chat follows local page change with explicit scope notice and no send',
    (tester) async {
      final fixture = CurrentPageFixture();
      await fixture.mount(tester);
      await tap(tester, find.byTooltip('Schulbuddy öffnen'));
      await tester.enterText(question(), 'Ungesendeter alter Entwurf');
      fixture.selected.value = const SchulbuddyContext('notebooks', {
        'child_id': childId,
        'material_id': nextId,
      }, 'revision:1');
      await tester.pumpAndSettle();
      expect(fixture.contexts.last.url.queryParameters['material_id'], nextId);
      expect(tester.widget<TextField>(question()).controller!.text, isEmpty);
      expect(
        find.text(
          'Neue Seite · Schulbuddy bezieht sich jetzt auf diesen Bereich. Frühere Entwürfe bleiben bei ihrer Quelle.',
        ),
        findsOneWidget,
      );
      expect(
        fixture.state.collectionViews.values.any(
          (value) => value['text'] == 'Ungesendeter alter Entwurf',
        ),
        isTrue,
      );
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'changing source revision keeps the previous draft outside the new source',
    (tester) async {
      final fixture = CurrentPageFixture();
      await fixture.mount(tester);
      await tap(tester, find.byTooltip('Schulbuddy öffnen'));
      await tester.enterText(question(), 'Entwurf zur alten Fassung');
      fixture.selected.value = const SchulbuddyContext('notebooks', {
        'child_id': childId,
        'material_id': firstId,
      }, 'revision:2');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(question()).controller!.text, isEmpty);
      expect(
        fixture.state.collectionViews.values.any(
          (value) => value['text'] == 'Entwurf zur alten Fassung',
        ),
        isTrue,
      );
      expect(fixture.writes, isEmpty);
    },
  );
  testWidgets(
    'foreign previous page registration does not override new settings route',
    (tester) async {
      final fixture = CurrentPageFixture();
      await fixture.mount(tester);
      await tap(tester, find.byTooltip('Schulbuddy öffnen'));
      await tap(tester, find.byTooltip('Schulbuddy schließen'));
      fixture.router.push('/settings');
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Schulbuddy öffnen'));
      expect(fixture.contexts.last.url.queryParameters['page_kind'], 'account');
      expect(
        fixture.contexts.last.url.queryParameters.containsKey('material_id'),
        isFalse,
      );
      expect(fixture.writes, isEmpty);
    },
  );
  testWidgets('old server exam validation falls back to navigation help only', (
    tester,
  ) async {
    final fixture = CurrentPageFixture(
      respond: (request) async {
        if (request.url.queryParameters['page_kind'] == 'exams') {
          return reply({'detail': 'Unknown old protocol'}, 422);
        }
        return reply(contextData('Bereichshilfe'));
      },
    );
    fixture.selected.value = const SchulbuddyContext('exams', {
      'child_id': childId,
      'exam_id': firstId,
      'exam_tab': 'review',
    });
    await fixture.mount(tester);
    await tap(tester, find.byTooltip('Schulbuddy öffnen'));
    expect(
      fixture.contexts.map(
        (request) => request.url.queryParameters['page_kind'],
      ),
      ['exams', 'notebooks'],
    );
    expect(
      fixture.contexts.last.url.queryParameters.containsKey('exam_id'),
      isFalse,
    );
    expect(
      find.text(
        'Dieser Server kennt hier nur Bereichshilfe. Öffne eine bestätigte Heftseite für eine fachliche Erklärung.',
      ),
      findsOneWidget,
    );
    expect(fixture.writes, isEmpty);
  });
  testWidgets(
    'pending chat revalidates after one second without adding a polling progress row',
    (tester) async {
      var reads = 0;
      final second = Completer<http.Response>();
      final fixture = CurrentPageFixture(
        respond: (request) async {
          if (++reads == 1) {
            return reply(
              contextData(
                'Seite A',
                history: [
                  {
                    'id': 'turn',
                    'status': 'queued',
                    'question': 'Künstliche Frage',
                  },
                ],
              ),
            );
          }
          return second.future;
        },
      );
      await fixture.mount(tester);
      await tap(tester, find.byTooltip('Schulbuddy öffnen'));
      expect(find.text('Schulbuddy denkt nach …'), findsOneWidget);
      expect(
        find.textContaining('Du kannst das Fenster schließen'),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(reads, 2);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      second.complete(
        reply(
          contextData(
            'Seite A',
            history: [
              {
                'id': 'turn',
                'status': 'ready',
                'question': 'Künstliche Frage',
                'answer': 'Ein kleiner neuer Schritt.',
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ein kleiner neuer Schritt.'), findsOneWidget);
      expect(fixture.writes, isEmpty);
    },
  );
}
