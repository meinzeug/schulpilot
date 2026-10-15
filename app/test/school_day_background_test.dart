import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/school_day_screen.dart';
import 'package:schulpilot/ui.dart';

http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json source(int number, {bool confirmed = false, String status = 'review'}) => {
  'id': 'page$number',
  'child_id': 'child',
  'school_day_id': 'day',
  'page_number': number,
  'subject': 'Mathematik',
  'topic': 'Künstliche Bruchaufgabe $number',
  'content': 'Eigener künstlicher Testtext $number.',
  'homework': <String>[],
  'uncertainties': confirmed ? <String>[] : ['Bitte die Zahl prüfen.'],
  'confirmed': confirmed,
  'status': confirmed ? 'confirmed' : status,
  'synthetic': true,
  'fixture_id': null,
};

class PreparationServer {
  List<Json> pages;
  String stage;
  Json preparation;
  bool archived = false, realUploads = false, aiAvailable = true;
  int reads = 0, starts = 0, submissions = 0, savedForLater = 0, postponed = 0;
  int minutes = 8;
  final requests = <String>[];
  final keys = <String>[];
  List<Json> units = [];
  Json? todayOverride;
  Completer<http.Response>? delayedRead;
  PreparationServer({
    List<Json>? pages,
    this.stage = 'collecting',
    Json? preparation,
  }) : pages = pages ?? [source(1, status: 'uploaded')],
       preparation = preparation ?? {'status': 'idle', 'phase': null};

  Json get day => {
    'id': 'day',
    'child_id': 'child',
    'date': '2026-10-15',
    'stage': stage,
    'revision': 1,
    'read_only': archived,
    'allow_uploads': !archived,
    'max_pages': 24,
    'pages': pages,
    'confirmed_count': pages.where((p) => p['confirmed'] == true).length,
    'synthetic': !realUploads,
    'active_job': null,
    'last_error': null,
    'preparation': {
      'completed_pages': 0,
      'total_pages': pages.length,
      'job': null,
      'error': null,
      'can_retry': false,
      ...preparation,
    },
    'units': units,
    'plan': {'groups': [], 'notices': [], 'estimated_minutes': minutes},
  };

  Future<http.Response> handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    if (request.method == 'GET' &&
        (request.url.path.endsWith('/school-day/today') ||
            request.url.path.endsWith('/school-days/day'))) {
      reads++;
      if (delayedRead != null) return delayedRead!.future;
      return response(
        request.url.path.endsWith('/today')
            ? {'day': todayOverride ?? day}
            : day,
      );
    }
    if (request.url.path.endsWith('/prepare')) {
      expect(request.method, 'POST');
      expect(request.body, isEmpty);
      expect(request.headers['Idempotency-Key'], isNotEmpty);
      keys.add(request.headers['Idempotency-Key']!);
      submissions++;
      stage = 'review';
      preparation = {
        'status': 'processing',
        'phase': pages.every((p) => p['confirmed'] == true)
            ? 'package'
            : 'extract',
        'job': {
          'id': 'job$submissions',
          'kind': 'preparation',
          'status': 'queued',
        },
      };
      return response({'preparation': day['preparation']}, 202);
    }
    if (request.url.path.endsWith('/save-for-later')) {
      savedForLater++;
      return response({});
    }
    if (request.url.path.endsWith('/postpone')) {
      expect(request.method, 'POST');
      expect(request.body, isEmpty);
      postponed++;
      preparation = {'status': 'postponed', 'phase': 'review'};
      return response(day);
    }
    if (request.url.path.endsWith('/confirm')) {
      final body = jsonDecode(request.body) as Json;
      expect(body['uncertainties_resolved'], true);
      final page = pages.firstWhere(
        (p) => p['id'] == request.url.pathSegments[2],
      );
      page['confirmed'] = true;
      page['status'] = 'confirmed';
      page['uncertainties'] = <String>[];
      return response(page);
    }
    if (request.url.path.endsWith('/units/ready-unit/start')) {
      starts++;
      return response({});
    }
    if (request.url.path.endsWith('/status')) {
      return response({'real_data_enabled': true, 'ai_available': aiAvailable});
    }
    throw StateError('Unexpected synthetic test request');
  }

  AppState state() =>
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient(handle),
          ),
        )
        ..user = {
          'id': 'kid',
          'role': 'child',
          'child_id': 'child',
          'synthetic': true,
        };

  void requireReview() {
    stage = 'review';
    preparation = {'status': 'needs_review', 'phase': 'review'};
    for (final page in pages) {
      page['status'] = 'review';
    }
  }

  void ready() {
    stage = 'ready';
    preparation = {'status': 'ready', 'phase': 'complete'};
    units = [
      {
        'id': 'ready-unit',
        'status': 'ready',
        'subject': 'Mathematik',
        'topic': 'Künstliche Lernrunde',
      },
    ];
  }
}

GoRouter router(AppState state, {bool archived = false}) => GoRouter(
  initialLocation: '/after-school/child${archived ? '?day=day' : ''}',
  routes: [
    GoRoute(
      path: '/after-school/:id',
      builder: (_, route) => SchoolDayScreen(
        state,
        key: ValueKey('child:${route.uri.queryParameters['day'] ?? 'today'}'),
        childId: 'child',
        dayId: route.uri.queryParameters['day'],
      ),
    ),
    GoRoute(
      path: '/app',
      builder: (_, _) => const Scaffold(body: Text('Startseite')),
    ),
    GoRoute(
      path: '/away',
      builder: (_, _) => const Scaffold(body: Text('Andere Seite')),
    ),
    GoRoute(
      path: '/unit/:id',
      builder: (_, _) => const Scaffold(body: Text('Freiwillig gestartet')),
    ),
  ],
);

Future<void> settleUi(WidgetTester tester) async {
  // A running server preparation intentionally has an indeterminate spinner;
  // pumpAndSettle would wait for that animation forever.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> tapText(WidgetTester tester, String label) async {
  final control = find.text(label);
  await tester.ensureVisible(control);
  await tester.tap(control);
  await settleUi(tester);
}

Future<void> reload(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Mehr'));
  await settleUi(tester);
  await tapText(tester, 'Neu laden');
}

void mobile(WidgetTester tester, [double width = 390]) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Photos hand off once and survive leaving before OCR finishes', (
    tester,
  ) async {
    mobile(tester);
    final server = PreparationServer();
    final state = server.state();
    final navigation = router(state);
    addTearDown(navigation.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: navigation),
    );
    await settleUi(tester);
    expect(server.submissions, 0);
    await tapText(tester, 'Fotos abgeben');
    expect(server.submissions, 1);
    expect(find.text('Wir lesen deine Heftseiten'), findsOneWidget);
    expect(
      server.requests.any(
        (r) => r.contains('/extract') || r.contains('/jobs/'),
      ),
      false,
    );
    await tapText(tester, 'Zur Startseite');
    expect(find.text('Startseite'), findsOneWidget);
    final readsAway = server.reads;
    server.requireReview();
    await tester.pump(const Duration(seconds: 12));
    expect(server.reads, readsAway);
    navigation.go('/after-school/child');
    await settleUi(tester);
    expect(find.text('Seite 1 prüfen'), findsOneWidget);
    expect(server.submissions, 1);
    expect(server.pages.single['confirmed'], false);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'Confirmation and package preparation never auto start on $width px',
      (tester) async {
        mobile(tester, width);
        final server = PreparationServer(
          pages: [source(1)],
          stage: 'review',
          preparation: {'status': 'needs_review', 'phase': 'review'},
        );
        final navigation = router(server.state());
        addTearDown(navigation.dispose);
        await tester.pumpWidget(
          MaterialApp.router(theme: appTheme(), routerConfig: navigation),
        );
        await settleUi(tester);
        expect(server.pages.single['confirmed'], false);
        await tapText(tester, 'Stimmt, weiter');
        expect(server.pages.single['confirmed'], false);
        final checkbox = find.byType(CheckboxListTile);
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await settleUi(tester);
        await tapText(tester, 'Stimmt, weiter');
        expect(server.pages.single['confirmed'], true);
        expect(server.submissions, 0);
        await tapText(tester, 'Im Hintergrund vorbereiten');
        expect(server.submissions, 1);
        expect(find.text('Dein Lernpaket entsteht'), findsOneWidget);
        server.ready();
        await tester.pump(const Duration(seconds: 3));
        await settleUi(tester);
        expect(find.text('Dein Lernpaket ist bereit'), findsOneWidget);
        expect(server.starts, 0);
        expect(
          navigation.routeInformationProvider.value.uri.path,
          '/after-school/child',
        );
        await tapText(tester, 'Jetzt lernen');
        expect(server.starts, 1);
        expect(find.text('Freiwillig gestartet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Persisted preparation stops reads in background and resumes without a POST',
    (tester) async {
      mobile(tester);
      final server = PreparationServer(
        stage: 'review',
        preparation: {'status': 'processing', 'phase': 'extract'},
      );
      final navigation = router(server.state());
      addTearDown(navigation.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: navigation),
      );
      await settleUi(tester);
      for (final lifecycle in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
      }
      await tester.pump();
      final backgroundReads = server.reads;
      server.requireReview();
      await tester.pump(const Duration(seconds: 12));
      expect(server.reads, backgroundReads);
      for (final lifecycle in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
      }
      await settleUi(tester);
      expect(find.text('Seite 1 prüfen'), findsOneWidget);
      expect(server.submissions, 0);
      expect(server.starts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Failed preparation only retries explicitly within the server bound',
    (tester) async {
      mobile(tester);
      final server = PreparationServer();
      final navigation = router(server.state());
      addTearDown(navigation.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: navigation),
      );
      await settleUi(tester);
      await tapText(tester, 'Fotos abgeben');
      server.preparation = {
        'status': 'failed',
        'phase': 'extract',
        'can_retry': true,
        'error': 'Künstlicher Anbieterfehler',
      };
      await tester.pump(const Duration(seconds: 3));
      await settleUi(tester);
      await reload(tester);
      expect(server.submissions, 1);
      await tapText(tester, 'Erneut vorbereiten');
      expect(server.submissions, 2);
      expect(server.keys.toSet(), hasLength(2));
      server.preparation = {
        'status': 'failed',
        'phase': 'extract',
        'can_retry': false,
        'error': 'Künstliche Wiederholungsgrenze',
      };
      await tester.pump(const Duration(seconds: 3));
      await settleUi(tester);
      expect(find.text('Erneut vorbereiten'), findsNothing);
      await reload(tester);
      expect(server.submissions, 2);
      expect(server.starts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A covered preparation route stops polling until it returns', (
    tester,
  ) async {
    mobile(tester);
    final server = PreparationServer(
      stage: 'review',
      preparation: {'status': 'processing', 'phase': 'extract'},
    );
    final navigation = router(server.state());
    addTearDown(navigation.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: navigation),
    );
    await settleUi(tester);
    unawaited(navigation.push('/away'));
    await settleUi(tester);
    final hiddenReads = server.reads;
    server.requireReview();
    await tester.pump(const Duration(seconds: 12));
    expect(server.reads, hiddenReads);
    navigation.pop();
    await settleUi(tester);
    expect(find.text('Seite 1 prüfen'), findsOneWidget);
    expect(server.submissions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'No remaining learning time keeps sources for later without AI or a start',
    (tester) async {
      mobile(tester);
      final server =
          PreparationServer(
              pages: [source(1, confirmed: true)],
              stage: 'review',
            )
            ..realUploads = true
            ..minutes = 0;
      final navigation = router(server.state());
      addTearDown(navigation.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: navigation),
      );
      await settleUi(tester);
      expect(find.text('Im Hintergrund vorbereiten'), findsNothing);
      await tapText(tester, 'Für später einplanen');
      expect(server.savedForLater, 1);
      expect(server.submissions, 0);
      expect(server.starts, 0);
      expect(server.pages.single['confirmed'], true);
      expect(find.text('Startseite'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Yesterday can still be confirmed and submitted without new photos',
    (tester) async {
      mobile(tester);
      final server = PreparationServer(
        pages: [source(1)],
        stage: 'review',
        preparation: {'status': 'needs_review', 'phase': 'review'},
      )..archived = true;
      final navigation = router(server.state(), archived: true);
      addTearDown(navigation.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: navigation),
      );
      await settleUi(tester);
      expect(find.text('Seite 1 prüfen'), findsOneWidget);
      expect(find.text('Noch eine Seite hinzufügen'), findsNothing);
      final checkbox = find.byType(CheckboxListTile);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await settleUi(tester);
      await tapText(tester, 'Stimmt, weiter');
      await tapText(tester, 'Im Hintergrund vorbereiten');
      expect(server.submissions, 1);
      expect(
        server.requests.any(
          (r) => r.contains('/stage') || r.contains('/materials?'),
        ),
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Photo selection is available during temporary AI unavailability',
    (tester) async {
      mobile(tester);
      const picker = MethodChannel('plugins.flutter.io/image_picker');
      var pickerCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
        call,
      ) async {
        expect(call.method, 'pickMultiImage');
        pickerCalls++;
        return <String>[];
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        ),
      );
      final server = PreparationServer(pages: [])
        ..realUploads = true
        ..aiAvailable = false;
      final navigation = router(server.state());
      addTearDown(navigation.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: navigation),
      );
      await settleUi(tester);
      await tapText(tester, 'Fotos auswählen');
      expect(pickerCalls, 1);
      expect(server.submissions, 0);
      expect(find.textContaining('gerade nicht erreichbar'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An unreadable archived page is kept while restarting with today photos',
    (tester) async {
      mobile(tester);
      final server =
          PreparationServer(
              pages: [source(1, status: 'unreadable')],
              stage: 'review',
              preparation: {'status': 'needs_photo', 'phase': 'review'},
            )
            ..archived = true
            ..units = [
              {
                'id': 'old-unit',
                'status': 'completed',
                'subject': 'Mathematik',
                'topic': 'Alte künstliche Runde',
              },
            ];
      final oldSources = jsonEncode(server.pages);
      final oldUnits = jsonEncode(server.units);
      final navigation = router(server.state(), archived: true);
      addTearDown(navigation.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: navigation),
      );
      await settleUi(tester);
      expect(find.text('Ersetzen'), findsNothing);
      await tapText(tester, 'Für später ablegen');
      expect(server.postponed, 1);
      expect(find.text('Für später abgelegt'), findsOneWidget);
      expect(find.text('Dein Lernpaket ist bereit'), findsNothing);
      expect(jsonEncode(server.pages), oldSources);
      expect(jsonEncode(server.units), oldUnits);
      server.todayOverride = {
        ...server.day,
        'id': 'today-day',
        'stage': 'collecting',
        'read_only': false,
        'allow_uploads': true,
        'pages': <Json>[],
        'confirmed_count': 0,
        'units': <Json>[],
        'preparation': {'status': 'idle', 'phase': null},
      };
      await tapText(tester, 'Heute neu fotografieren');
      expect(
        navigation.routeInformationProvider.value.uri.queryParameters['day'],
        isNull,
      );
      expect(find.text('Zeig mir deine Heftseiten'), findsOneWidget);
      expect(server.submissions, 0);
      expect(server.starts, 0);
      expect(jsonEncode(server.pages), oldSources);
      expect(jsonEncode(server.units), oldUnits);
      expect(server.requests.any((r) => r.startsWith('DELETE ')), false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A late response from a logged out child never restores its sources',
    (tester) async {
      mobile(tester);
      final server = PreparationServer()
        ..delayedRead = Completer<http.Response>();
      final state = server.state();
      final navigation = router(state);
      addTearDown(navigation.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: navigation),
      );
      await tester.pump();
      state.user = {
        'id': 'other-kid',
        'role': 'child',
        'child_id': 'other-child',
      };
      state.refreshState();
      server.delayedRead!.complete(response({'day': server.day}));
      await settleUi(tester);
      expect(find.text('Fotos abgeben'), findsNothing);
      expect(find.text('Künstliche Bruchaufgabe 1'), findsNothing);
      expect(server.submissions, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
