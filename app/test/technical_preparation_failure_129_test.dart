// Artificial local transport fixtures. No learner data, provider or real network.
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
import 'package:schulpilot/study_path_panel.dart';
import 'package:schulpilot/ui.dart';

import 'school_day_background_test.dart' as background;

const providerHttp =
    'KI-Anbieter meldet HTTP 400. Schlüssel, Modell, Freigabe oder Kontingent prüfen.';
const costFailure =
    'Material überschreitet die konfigurierte konservative Kostenreservierung. Material kürzen oder Preisobergrenze prüfen.';
const costBlocker =
    'Die KI-Verarbeitung muss zuerst geprüft werden. Bitte deine Eltern um Hilfe. Deine Fotos sind gespeichert.';
const technicalLimit =
    'Die Vorbereitung dieser Etappe muss technisch geprüft werden. Weitere Versuche sind vorerst gesperrt. Deine gespeicherten Runden bleiben verfügbar.';
const consent = 'Deine Eltern müssen zuerst der KI-Verarbeitung zustimmen.';
const quota =
    'Neue KI-Verarbeitung ist durch das Aufruf- oder Kostenlimit begrenzt.';

http.Response jsonReply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json failedPreparation({
  String code = 'cost_preflight',
  String error = costFailure,
  Json? blocker,
  bool retry = false,
}) => {
  'status': 'failed',
  'phase': 'package',
  'error_code': code,
  'error': error,
  'can_retry': retry,
  'retry_blocker': blocker,
  'total_parts': 7,
  'completed_parts': 2,
  'active_part': 2,
};

class LocalActionFailure extends background.PreparationServer {
  LocalActionFailure()
    : super(
        stage: 'review',
        pages: [background.source(1, status: 'uploaded')],
        preparation: {'status': 'needs_review', 'phase': 'review'},
      );
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/prepare')) {
      requests.add('${request.method} ${request.url.path}');
      submissions++;
      expect(request.method, 'POST');
      return jsonReply({'detail': providerHttp}, 400);
    }
    return super.handle(request);
  }
}

class FailureHarness {
  final AppState state;
  final GoRouter router;
  FailureHarness(this.state, this.router);

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    state.dispose();
  }
}

Future<FailureHarness> mountFailure(
  WidgetTester tester,
  AppState state,
  WidgetBuilder screen, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, _) => screen(context)),
      GoRoute(
        path: '/learn/:child',
        builder: (_, route) => Scaffold(
          body: Text(
            'Gespeicherte Runden für ${route.pathParameters['child']}',
          ),
        ),
      ),
      GoRoute(
        path: '/library/:child',
        builder: (_, route) => Scaffold(
          body: Text('Gespeicherte Hefte für ${route.pathParameters['child']}'),
        ),
      ),
      GoRoute(
        path: '/app',
        builder: (_, _) => const Scaffold(body: Text('Startseite')),
      ),
      GoRoute(
        path: '/other',
        builder: (_, _) => const Scaffold(body: Text('Andere Ansicht')),
      ),
    ],
  );
  final harness = FailureHarness(state, router);
  addTearDown(() => harness.close(tester));
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      theme: appTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<FailureHarness> mountDay(
  WidgetTester tester,
  background.PreparationServer server, {
  double width = 390,
  double scale = 1,
}) async {
  final state = server.state()..familyId = 'artificial-family';
  state.api.token = 'artificial-session';
  return mountFailure(
    tester,
    state,
    (_) => SchoolDayScreen(state, childId: 'child', dayId: 'day'),
    width: width,
    scale: scale,
  );
}

Future<void> click(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }
}

Json studyPath(String error, {bool canContinue = true, String? blocker}) => {
  'available': true,
  'id': 'day',
  'day_id': 'day',
  'total_questions': 6,
  'completed_questions': 2,
  'ready_questions': 2,
  'next_block_id': 'failed',
  'can_continue': canContinue,
  'technical_review_required': blocker == technicalLimit,
  'block_reason': blocker,
  'stale': false,
  'blocks': [
    {
      'id': 'completed',
      'title': 'Erfundene fertige Etappe',
      'label': 'Verstehen',
      'phase': 'understand',
      'status': 'completed',
      'unit_id': 'saved-unit',
      'question_count': 2,
    },
    {
      'id': 'ready',
      'title': 'Erfundene gespeicherte Etappe',
      'label': 'Anwenden',
      'phase': 'apply',
      'status': 'ready',
      'unit_id': 'ready-unit',
      'question_count': 2,
    },
    {
      'id': 'failed',
      'title': 'Erfundene nächste Etappe',
      'label': 'Erinnern',
      'phase': 'recall',
      'status': 'planned',
      'unit_id': null,
      'job_id': 'failed-job',
      'question_count': 2,
      'error': error,
    },
  ],
};

class StudyServer {
  Json value;
  final calls = <http.Request>[];
  StudyServer(this.value);
  AppState state({String role = 'child'}) =>
      AppState(
          api: Api(
            base: 'https://synthetic.invalid/api',
            client: MockClient((request) async {
              calls.add(request);
              if (request.method == 'POST') {
                expect(request.url.path, '/api/school-days/day/blocks/failed');
                expect(request.headers['Idempotency-Key'], isNotEmpty);
                value['blocks'][2]['status'] = 'generating';
                value['blocks'][2]['job_id'] = 'new-job';
                return jsonReply({'id': 'new-job', 'status': 'queued'});
              }
              if (request.url.path == '/api/jobs/new-job') {
                return jsonReply({'id': 'new-job', 'status': 'queued'});
              }
              expect(request.method, 'GET');
              expect(request.url.path, '/api/school-days/day/study-path');
              return jsonReply(value);
            }),
          )..token = 'artificial-session',
        )
        ..familyId = 'artificial-family'
        ..user = {'id': role, 'role': role, 'child_id': 'child'};
}

Future<FailureHarness> mountStudy(
  WidgetTester tester,
  StudyServer server, {
  String role = 'child',
  double width = 390,
  double scale = 1,
}) async {
  final state = server.state(role: role);
  return mountFailure(
    tester,
    state,
    (_) => Scaffold(
      body: SingleChildScrollView(child: StudyPathPanel(state, 'child', 'day')),
    ),
    width: width,
    scale: scale,
  );
}

void main() {
  setUpAll(() async {
    for (final font in ['Nunito', 'SpaceGrotesk']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    '129 known technical categories do not swallow consent/access/quota',
    () {
      for (final code in [
        'invalid_output',
        'provider_timeout',
        'provider_unavailable',
        'cost_preflight',
      ]) {
        expect(isTechnicalPreparationFailure(null, code: code), isTrue);
      }
      for (final message in [
        providerHttp,
        costFailure,
        costBlocker,
        technicalLimit,
      ]) {
        expect(isTechnicalPreparationFailure(message), isTrue);
      }
      for (final code in [
        'quota_exhausted',
        'access_changed',
        'not_configured',
      ]) {
        expect(
          isTechnicalPreparationFailure(providerHttp, code: code),
          isFalse,
        );
      }
      for (final message in [
        consent,
        quota,
        'Bitte melde dich erneut an.',
        'HTTP 403: Familienberechtigung fehlt.',
      ]) {
        expect(isTechnicalPreparationFailure(message), isFalse);
      }
      expect(isTechnicalPreparationFailure(ApiError(consent, 403)), isFalse);
      expect(isTechnicalPreparationFailure(ApiError(quota, 429)), isFalse);
    },
  );

  for (final viewport in [(320.0, 2.0), (390.0, 2.0), (1280.0, 1.0)]) {
    testWidgets(
      '129 technical photo failure has a saved-round primary at $viewport',
      (tester) async {
        final server = background.PreparationServer(
          stage: 'review',
          preparation: failedPreparation(
            blocker: {'code': 'cost_preflight', 'message': costBlocker},
            retry: true, // An effective blocker still refuses any new request.
          ),
        );
        await mountDay(tester, server, width: viewport.$1, scale: viewport.$2);
        final primary = find.widgetWithText(
          ActionPanel,
          'Gespeicherte Runden ansehen',
        );
        expect(primary, findsOneWidget);
        expect(find.text('Hefte öffnen'), findsOneWidget);
        expect(find.text(costFailure), findsNothing);
        expect(find.text(costBlocker), findsNothing);
        expect(
          find.textContaining('Bitte deine Eltern um Hilfe'),
          findsNothing,
        );
        expect(find.textContaining('Deine Fotos'), findsWidgets);
        expect(find.text('Fehlenden Teil erneut vorbereiten'), findsNothing);
        expect(find.text('2 von 7 Teilen gespeichert'), findsOneWidget);
        expect(server.submissions, 0);
        await tester.ensureVisible(primary);
        expect(tester.getRect(primary).right, lessThanOrEqualTo(viewport.$1));
        expect(tester.takeException(), isNull);
        await click(tester, 'Gespeicherte Runden ansehen');
        expect(find.text('Gespeicherte Runden für child'), findsOneWidget);
        expect(
          server.requests.every((call) => call.startsWith('GET ')),
          isTrue,
        );
      },
    );

    testWidgets(
      '129 technical study failure has a saved-round primary at $viewport',
      (tester) async {
        final server = StudyServer(studyPath(providerHttp));
        final before = jsonEncode(server.value);
        await mountStudy(
          tester,
          server,
          width: viewport.$1,
          scale: viewport.$2,
        );
        final primary = find.widgetWithText(
          FilledButton,
          'Gespeicherte Runden ansehen',
        );
        expect(primary, findsOneWidget);
        expect(find.text(providerHttp), findsNothing);
        expect(find.text('Deine Fotos sind gespeichert.'), findsOneWidget);
        expect(find.text('Hefte öffnen'), findsOneWidget);
        expect(
          find.widgetWithText(OutlinedButton, 'Nächste Etappe'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Nächste Etappe'),
          findsNothing,
        );
        expect(find.text('2 von 6 Aufgaben bearbeitet'), findsOneWidget);
        await tester.ensureVisible(primary);
        expect(tester.getRect(primary).right, lessThanOrEqualTo(viewport.$1));
        expect(tester.takeException(), isNull);
        await click(tester, 'Gespeicherte Runden ansehen');
        expect(find.text('Gespeicherte Runden für child'), findsOneWidget);
        expect(server.calls.every((call) => call.method == 'GET'), isTrue);
        expect(jsonEncode(server.value), before);
      },
    );
  }

  testWidgets('129 photo failure opens saved notebooks with navigation only', (
    tester,
  ) async {
    final server = background.PreparationServer(
      stage: 'review',
      preparation: failedPreparation(),
    );
    await mountDay(tester, server);
    await click(tester, 'Hefte öffnen');
    expect(find.text('Gespeicherte Hefte für child'), findsOneWidget);
    expect(server.requests.every((call) => call.startsWith('GET ')), isTrue);
    expect(server.starts, 0);
    expect(server.submissions, 0);
  });

  testWidgets('129 study failure opens saved notebooks without preparation', (
    tester,
  ) async {
    final server = StudyServer(studyPath(costFailure));
    await mountStudy(tester, server);
    expect(find.text(costFailure), findsNothing);
    await click(tester, 'Hefte öffnen');
    expect(find.text('Gespeicherte Hefte für child'), findsOneWidget);
    expect(server.calls.every((call) => call.method == 'GET'), isTrue);
  });

  testWidgets('129 photo retry stays secondary and needs an explicit click', (
    tester,
  ) async {
    final server = background.PreparationServer(
      stage: 'review',
      preparation: failedPreparation(
        code: 'invalid_output',
        error: 'Die KI-Ausgabe ist unvollständig.',
        retry: true,
      ),
    );
    await mountDay(tester, server);
    expect(
      find.widgetWithText(OutlinedButton, 'Fehlenden Teil erneut vorbereiten'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 12));
    expect(server.submissions, 0);
    await click(tester, 'Fehlenden Teil erneut vorbereiten', settle: false);
    expect(server.submissions, 1);
    expect(server.starts, 0);
    expect(server.keys, hasLength(1));
  });

  testWidgets(
    '129 a study retry remains explicit and uses the normal endpoint',
    (tester) async {
      final server = StudyServer(studyPath(costFailure));
      await mountStudy(tester, server);
      await tester.pump(const Duration(seconds: 12));
      expect(server.calls.every((call) => call.method == 'GET'), isTrue);
      await click(tester, 'Nächste Etappe', settle: false);
      expect(server.calls.where((call) => call.method == 'POST'), hasLength(1));
      expect(
        find.text('Deine nächste Etappe wird vorbereitet.'),
        findsOneWidget,
      );
    },
  );

  for (final blocker in [
    ('quota_exhausted', quota),
    ('not_configured', consent),
    ('access_changed', 'Bitte melde dich erneut an.'),
  ]) {
    testWidgets(
      '129 ${blocker.$1} retains its own refusal and never offers retry',
      (tester) async {
        final server = background.PreparationServer(
          stage: 'review',
          preparation: failedPreparation(
            code: blocker.$1,
            error: providerHttp,
            blocker: {'code': blocker.$1, 'message': blocker.$2},
            retry: true,
          ),
        );
        await mountDay(tester, server);
        expect(find.text(blocker.$2), findsOneWidget);
        expect(find.text('Fehlenden Teil erneut vorbereiten'), findsNothing);
        expect(
          find.widgetWithText(ActionPanel, 'Gespeicherte Runden ansehen'),
          findsNothing,
        );
        await tester.pump(const Duration(seconds: 9));
        expect(server.submissions, 0);
        expect(server.starts, 0);
      },
    );
  }

  testWidgets(
    '129 exhausted study preparations offer saved content without another POST',
    (tester) async {
      final server = StudyServer(
        studyPath(providerHttp, canContinue: false, blocker: technicalLimit),
      );
      await mountStudy(tester, server);
      expect(find.textContaining('Bitte deine Eltern um Hilfe'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Gespeicherte Runden ansehen'),
        findsOneWidget,
      );
      expect(find.text('Nächste Etappe'), findsNothing);
      expect(find.text('Erneut vorbereiten'), findsNothing);
      await tester.pump(const Duration(seconds: 9));
      expect(server.calls.every((call) => call.method == 'GET'), isTrue);
    },
  );

  testWidgets('129 an effective study consent blocker keeps its own refusal', (
    tester,
  ) async {
    final server = StudyServer(studyPath(providerHttp, blocker: consent));
    await mountStudy(tester, server);
    expect(find.text(consent), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Gespeicherte Runden ansehen'),
      findsNothing,
    );
    expect(find.text('Hefte öffnen'), findsNothing);
    expect(find.text('Nächste Etappe'), findsNothing);
    await tester.pump(const Duration(seconds: 9));
    expect(server.calls.every((call) => call.method == 'GET'), isTrue);
  });

  testWidgets('129 a covered study action cannot leave its captured route', (
    tester,
  ) async {
    final server = StudyServer(studyPath(costFailure));
    final harness = await mountStudy(tester, server);
    final primary = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Gespeicherte Runden ansehen'),
    );
    final covered = showDialog<void>(
      context: tester.element(find.byType(StudyPathPanel)),
      builder: (_) =>
          const AlertDialog(content: Text('Andere Ansicht ist offen')),
    );
    await tester.pumpAndSettle();
    primary.onPressed!();
    await tester.pumpAndSettle();
    expect(harness.router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Andere Ansicht ist offen'), findsOneWidget);
    expect(server.calls.every((call) => call.method == 'GET'), isTrue);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    await covered;
  });

  testWidgets('129 parents retain the precise study diagnosis and counts', (
    tester,
  ) async {
    final server = StudyServer(
      studyPath(costFailure, canContinue: false, blocker: technicalLimit),
    );
    await mountStudy(tester, server, role: 'parent');
    expect(find.text(costFailure), findsOneWidget);
    expect(find.text(technicalLimit), findsOneWidget);
    expect(find.textContaining('Insgesamt geplant: 6'), findsOneWidget);
    expect(find.text('Hefte öffnen'), findsNothing);
    expect(server.calls.every((call) => call.method == 'GET'), isTrue);
  });

  testWidgets(
    '129 local provider refusal is scoped without exposing raw HTTP detail',
    (tester) async {
      final server = LocalActionFailure();
      await mountDay(tester, server);
      await click(tester, 'Im Hintergrund vorbereiten');
      expect(server.submissions, 1);
      expect(find.text(providerHttp), findsNothing);
      expect(
        find.widgetWithText(ActionPanel, 'Gespeicherte Runden ansehen'),
        findsOneWidget,
      );
      expect(find.text('Hefte öffnen'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(server.submissions, 1);
      expect(server.starts, 0);
    },
  );

  for (final screen in ['day', 'study']) {
    testWidgets('129 $screen stale navigation after a token change is inert', (
      tester,
    ) async {
      final dayServer = background.PreparationServer(
        stage: 'review',
        preparation: failedPreparation(),
      );
      final studyServer = StudyServer(studyPath(costFailure));
      final harness = screen == 'day'
          ? await mountDay(tester, dayServer)
          : await mountStudy(tester, studyServer);
      final VoidCallback staleAction;
      if (screen == 'day') {
        final primary = tester.widget<ActionPanel>(
          find.widgetWithText(ActionPanel, 'Gespeicherte Runden ansehen'),
        );
        staleAction = () {
          primary.onPressed!();
        };
      } else {
        final primary = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Gespeicherte Runden ansehen'),
        );
        staleAction = primary.onPressed!;
      }
      harness.state.api.token = 'replacement-session';
      harness.state.refreshState();
      await tester.pump();
      staleAction();
      await tester.pumpAndSettle();
      expect(harness.router.routeInformationProvider.value.uri.path, '/');
      expect(dayServer.submissions, 0);
      expect(studyServer.calls.every((call) => call.method == 'GET'), isTrue);
    });
  }

  testWidgets('129 resumed failed day only reloads saved status', (
    tester,
  ) async {
    final server = background.PreparationServer(
      stage: 'review',
      preparation: failedPreparation(),
    );
    await mountDay(tester, server);
    final reads = server.reads;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(server.reads, greaterThanOrEqualTo(reads));
    expect(
      find.widgetWithText(ActionPanel, 'Gespeicherte Runden ansehen'),
      findsOneWidget,
    );
    expect(server.requests.every((call) => call.startsWith('GET ')), isTrue);
    expect(server.submissions, 0);
    expect(server.starts, 0);
  });
}
