import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/parent_child_navigation.dart';
import 'package:schulpilot/parent_insights_panel.dart';
import 'package:schulpilot/parent_overview.dart';
import 'package:schulpilot/progress_screen.dart';
import 'package:schulpilot/ui.dart';

import 'progress_grades_test.dart' as fixture;

Json progress({String? subject, String? topic, bool empty = false}) {
  final evidence = empty
      ? {for (final entry in fixture.evidence().entries) entry.key: 0}
      : fixture.evidence();
  return {
    'child_name': 'Künstliches Testkind',
    'level': topic != null
        ? 'rounds'
        : subject != null
        ? 'topics'
        : 'subjects',
    'selected_totals': evidence,
    'totals': evidence,
    'items': [
      if (!empty)
        {
          ...evidence,
          'subject': subject ?? 'Mathematik',
          'topic': topic ?? 'Brüche',
          'topic_count': 1,
          'id': 'artificial-round',
          'last_activity': 1792220000,
          'status': 'paused',
        },
    ],
    'pagination': {'page': 1, 'pages': 1, 'total': empty ? 0 : 1},
  };
}

class _Fixture {
  final requests = <http.Request>[];
  final Future<http.Response> Function(http.Request) reply;
  late final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        requests.add(request);
        expectSync(request.method, 'GET');
        if (request.url.path.endsWith('/parent-insights')) {
          return fixture.reply({
            'settings': {'enabled': false, 'revision': 0},
            'topics': [],
            'totals': {},
            'history': [],
            'can_manage': false,
            'eligible': false,
          });
        }
        return reply(request);
      }),
    ),
  )..user = {'id': 'artificial-parent', 'role': 'parent', 'families': []};
  _Fixture(this.reply);

  Future<GoRouter> open(
    WidgetTester tester, {
    String location = '/progress/kid',
    double width = 390,
    double scale = 1,
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/progress/:child',
          builder: (_, route) => ProgressScreen(
            state,
            childId: route.pathParameters['child']!,
            initialSubject: route.uri.queryParameters['fach'],
            initialTopic: route.uri.queryParameters['thema'],
          ),
        ),
        GoRoute(
          path: '/unit/:id',
          builder: (_, _) => const Scaffold(body: Text('Gespeicherte Runde')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(brightness: brightness),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }
}

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1440.0]) {
      testWidgets(
        'Evidence and named result buttons precede AI at $width in $brightness',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final f = _Fixture((_) async => fixture.reply(progress()));
            await f.open(
              tester,
              width: width,
              scale: width == 320 ? 2 : 1,
              brightness: brightness,
            );
            final title = find.text('Der Lernstand im Detail');
            final evidence = find.byType(ParentPracticeSummary);
            final subject = find.text('Mathematik');
            final compass = find.byType(ParentInsightsPanel);
            expect(
              tester.getTopLeft(title).dy,
              lessThan(tester.getTopLeft(evidence).dy),
            );
            expect(
              tester.getTopLeft(evidence).dy,
              lessThan(tester.getTopLeft(subject).dy),
            );
            expect(
              tester.getTopLeft(subject).dy,
              lessThan(tester.getTopLeft(compass).dy),
            );
            final button = find.ancestor(
              of: subject,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.button == true,
              ),
            );
            await tester.ensureVisible(subject);
            await tester.pumpAndSettle();
            final card = tester.getSemantics(button).getSemanticsData();
            expect(card.flagsCollection.isButton, isTrue);
            expect(card.hasAction(SemanticsAction.tap), isTrue);
            expect(card.label, contains('Mathematik'));
            expect(find.text('1 von 1 Fach · Seite 1 von 1'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets(
    'An empty topic names its subject and resets directly to all evidence',
    (tester) async {
      final f = _Fixture((request) async {
        final subject = request.url.queryParameters['subject'];
        return fixture.reply(
          progress(
            subject: subject,
            topic: request.url.queryParameters['topic'],
            empty: subject != null,
          ),
        );
      });
      final router = await f.open(
        tester,
        location: '/progress/kid?fach=Mathematik&thema=Brüche',
      );
      expect(find.text('Fach: Mathematik'), findsOneWidget);
      expect(
        find.text(
          'Für „Mathematik · Brüche“ sind noch keine beantworteten Aufgaben gespeichert.',
        ),
        findsOneWidget,
      );
      final reset = find.text('Alle Fächer anzeigen');
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/progress/kid',
      );
      final reads = f.requests.where(
        (request) => request.url.path.endsWith('/learning-progress'),
      );
      expect(reads.length, 2);
      expect(reads.last.url.queryParameters.containsKey('subject'), isFalse);
      expect(reads.last.url.queryParameters.containsKey('topic'), isFalse);
      expect(find.text('Mathematik'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Parent refresh stays in the child header, preserves identity and prevents duplicate taps',
    (tester) async {
      final pending = Completer<http.Response>();
      var reads = 0;
      final f = _Fixture(
        (_) async => ++reads == 1 ? fixture.reply(progress()) : pending.future,
      );
      await f.open(tester);
      final refresh = find.byTooltip('Aktualisieren');
      expect(refresh, findsOneWidget);
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(reads, 2);
      expect(find.text('Künstliches Testkind'), findsOneWidget);
      expect(find.text('Lernstand wird geladen …'), findsOneWidget);
      final disabled = find.ancestor(
        of: find.byTooltip('Wird aktualisiert …'),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(disabled).onPressed, isNull);
      expect(find.byType(ParentPracticeSummary), findsNothing);
      pending.complete(fixture.reply(progress()));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.byTooltip('Aktualisieren'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A same-parent new session cannot inherit an in-flight progress response',
    (tester) async {
      final pending = Completer<http.Response>();
      final fresh = Completer<http.Response>();
      var reads = 0;
      final f = _Fixture(
        (_) async => switch (++reads) {
          1 => fixture.reply(progress()),
          2 => pending.future,
          _ => fresh.future,
        },
      );
      await f.open(tester);
      await tester.ensureVisible(find.byTooltip('Aktualisieren'));
      await tester.tap(find.byTooltip('Aktualisieren'));
      await tester.pump();
      f.state.user = {...f.state.user!};
      f.state.refreshState();
      await tester.pump();
      expect(find.text('Künstliches Testkind'), findsNothing);
      pending.complete(
        fixture.reply({
          ...progress(),
          'child_name': 'Veraltete private Identität',
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Veraltete private Identität'), findsNothing);
      expect(find.byType(ParentPracticeSummary), findsNothing);
      expect(reads, 3);
      fresh.complete(
        fixture.reply({
          ...progress(),
          'child_name': 'Neu berechtigte Identität',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Veraltete private Identität'), findsNothing);
      expect(find.text('Neu berechtigte Identität'), findsOneWidget);
      expect(find.byType(ParentPracticeSummary), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A denied refresh clears the formerly authorized child identity',
    (tester) async {
      var reads = 0;
      final f = _Fixture(
        (_) async => ++reads == 1
            ? fixture.reply(progress())
            : fixture.reply({'detail': 'Zugriff entzogen.'}, 403),
      );
      await f.open(tester);
      expect(find.text('Künstliches Testkind'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Aktualisieren'));
      await tester.tap(find.byTooltip('Aktualisieren'));
      await tester.pumpAndSettle();
      expect(find.text('Künstliches Testkind'), findsNothing);
      expect(find.byType(ParentPracticeSummary), findsNothing);
      expect(find.text('Zugriff entzogen.'), findsOneWidget);
      expect(reads, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A stale evidence-card callback cannot navigate in a new session',
    (tester) async {
      var fresh = false;
      final f = _Fixture((_) async {
        final data = progress();
        if (fresh) {
          data['child_name'] = 'Frisch berechtigtes Testkind';
          data['items'] = [
            {
              ...Json.from((data['items'] as List).single),
              'subject': 'Aktuelles Fach',
            },
          ];
        }
        return fixture.reply(data);
      });
      final router = await f.open(tester);
      final link = find.ancestor(
        of: find.text('Mathematik'),
        matching: find.byType(InkWell),
      );
      final oldTap = tester.widget<InkWell>(link).onTap!;
      final before = f.requests.length;
      fresh = true;
      f.state.user = {...f.state.user!};
      f.state.refreshState();
      // A callback queued before the next frame must still check its account.
      oldTap();
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/progress/kid',
      );
      expect(f.requests.length, before + 1);
      expect(
        f.requests.last.url.queryParameters.containsKey('subject'),
        isFalse,
      );
      expect(f.requests.last.url.queryParameters.containsKey('topic'), isFalse);
      expect(find.text('Mathematik'), findsNothing);
      expect(find.text('Aktuelles Fach'), findsOneWidget);
      expect(find.text('Frisch berechtigtes Testkind'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Changing children closes an old section menu before it can navigate to the former child',
    (tester) async {
      final child = ValueNotifier('first-child');
      addTearDown(child.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: ValueListenableBuilder<String>(
              valueListenable: child,
              builder: (_, id, _) => ParentChildNavigation(
                childId: id,
                childName: id,
                selected: 'progress',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Hausaufgaben').last.hitTestable(), findsOneWidget);
      child.value = 'second-child';
      await tester.pumpAndSettle();
      expect(find.text('first-child'), findsNothing);
      expect(find.text('second-child'), findsOneWidget);
      expect(find.text('Hausaufgaben').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
