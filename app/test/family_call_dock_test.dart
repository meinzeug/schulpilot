import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/family_call_screen.dart';
import 'package:schulpilot/family_call_service.dart';
import 'package:schulpilot/ui.dart';

import 'family_call_test.dart' show FakeMedia, metadata, response, callId;

class _Media extends FakeMedia {
  final mounted = <String, int>{};
  final peak = <String, int>{};
  @override
  Widget video({required bool remote, bool screen = false}) {
    final kind = screen
        ? 'screen'
        : remote
        ? 'remote'
        : 'local';
    return _Video(this, kind, key: ValueKey('artificial-video-$kind'));
  }
}

class _Video extends StatefulWidget {
  final _Media media;
  final String kind;
  const _Video(this.media, this.kind, {super.key});
  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  @override
  void initState() {
    super.initState();
    final count = (widget.media.mounted[widget.kind] ?? 0) + 1;
    widget.media.mounted[widget.kind] = count;
    if (count > (widget.media.peak[widget.kind] ?? 0)) {
      widget.media.peak[widget.kind] = count;
    }
  }

  @override
  void dispose() {
    widget.media.mounted[widget.kind] = widget.media.mounted[widget.kind]! - 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('Künstliches ${widget.kind}');
}

class _Task extends StatefulWidget {
  final AppState state;
  const _Task(this.state);
  @override
  State<_Task> createState() => _TaskState();
}

class _TaskState extends State<_Task> {
  final draft = TextEditingController();
  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          const Text('Künstliche Aufgabe'),
          TextField(key: const ValueKey('task-draft'), controller: draft),
          const Text('Deine gespeicherte Rückmeldung bleibt hier.'),
          FilledButton(
            onPressed: () =>
                showFamilyHelp(context, widget.state, sendMessage: () async {}),
            child: const Text('Eltern fragen'),
          ),
        ],
      ),
    ),
  );
}

class _Fixture {
  final media = _Media();
  final navigator = GlobalKey<NavigatorState>();
  late final AppState state;
  late final GoRouter router;
  final String role;
  String status = 'ringing';
  int starts = 0;
  bool closed = false;
  _Fixture({this.role = 'child'}) {
    state =
        AppState(
            familyCallFactory: (state) => FamilyCallService(
              state,
              nativeEnabled: false,
              mediaFactory: () => media,
            ),
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient((request) async {
                final path = request.url.path;
                if (path.endsWith('/active')) return response({'calls': []});
                if (path.endsWith('/config')) {
                  return response({'available': true});
                }
                if (path.endsWith('/ice')) return response({'ice_servers': []});
                if (path.endsWith('/family-calls') &&
                    request.method == 'POST') {
                  starts++;
                }
                if (path.endsWith('/end')) status = 'ended';
                if (path.endsWith('/accept')) status = 'accepted';
                if (path.endsWith('/signals')) {
                  return response(
                    request.method == 'POST'
                        ? {'sequence': 2}
                        : {
                            'signals':
                                request.url.queryParameters['after'] == '0'
                                ? [
                                    {
                                      'sequence': 1,
                                      'kind': role == 'child'
                                          ? 'answer'
                                          : 'offer',
                                      'payload': {'sdp': 'artificial'},
                                    },
                                  ]
                                : [],
                            'cursor': 1,
                          },
                  );
                }
                return response(metadata(status, role: role));
              }),
            ),
          )
          ..user = {
            'id': 'artificial-$role',
            'role': role,
            if (role == 'child') 'child_id': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          };
    router = GoRouter(
      navigatorKey: navigator,
      initialLocation: '/task',
      routes: [
        GoRoute(path: '/task', builder: (_, _) => _Task(state)),
        GoRoute(
          path: '/family-call/:id',
          builder: (_, _) => FamilyCallScreen(state, callId: callId),
        ),
      ],
    );
  }

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 850),
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(brightness: brightness),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: ListenableBuilder(
            listenable: router.routeInformationProvider,
            builder: (_, _) => FamilyCallHost(
              state,
              navigatorKey: navigator,
              currentPath: router.routeInformationProvider.value.uri.path,
              openCall: (id) => router.push('/family-call/$id'),
              child: child!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async => close(tester));
  }

  Future<void> close(WidgetTester tester) async {
    if (closed) return;
    closed = true;
    await tester.pumpWidget(const SizedBox());
    await state.familyCalls.clear();
    state.familyCalls.dispose();
    state.inbox.dispose();
    router.dispose();
  }

  Future<void> connect(WidgetTester tester) async {
    final calls = state.familyCalls;
    calls.activate(state.user);
    await tester.pump();
    if (role == 'child') {
      await calls.start();
      status = 'accepted';
      await calls.refresh();
    } else {
      await calls.open(callId);
      await calls.join();
      await calls.refresh();
    }
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'RR042 saved screen consent cannot capture after family change before rebuild',
    (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      await fixture.connect(tester);
      await tester.tap(find.byKey(const ValueKey('call-dock-screen')));
      await tester.pumpAndSettle();
      final saved = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('call-dock-share-confirm')),
          )
          .onPressed!;
      fixture.state.familyId = 'another-family';
      saved();
      await tester.pumpAndSettle();
      expect(fixture.media.sharingScreen, isFalse);
      expect(fixture.router.routeInformationProvider.value.uri.path, '/task');
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'Navigator semantics keep dock actions and dialog consent visible',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final fixture = _Fixture();
      try {
        await fixture.open(tester);
        await fixture.connect(tester);
        String tree() => tester
            .binding
            .renderViews
            .single
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!
            .toStringDeep();
        for (final label in [
          'Mikrofon ausschalten',
          'Kamera ausschalten',
          'Meinen Bildschirm teilen',
          'Gespräch beenden',
          'Künstliche Aufgabe',
        ]) {
          expect(tree(), contains(label));
        }
        await tester.tap(find.byKey(const ValueKey('call-dock-screen')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('call-dock-screen')));
        await tester.pumpAndSettle();
        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason: 'A second dock tap must not stack consent dialogs.',
        );
        expect(tree(), contains('Deine Aufgabe live zeigen'));
        expect(tree(), contains('Gespräch beenden'));
        expect(tree(), isNot(contains('Künstliche Aufgabe')));
        expect(fixture.media.sharingScreen, isFalse);
        final staleConfirm = tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('call-dock-share-confirm')),
            )
            .onPressed!;
        await tester.tap(find.byKey(const ValueKey('call-dock-end')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('call-dock-share-confirm')),
          findsNothing,
        );
        staleConfirm();
        await tester.pumpAndSettle();
        expect(fixture.media.sharingScreen, isFalse);
        expect(fixture.router.routeInformationProvider.value.uri.path, '/task');
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'Help starts inline and preserves the task, draft and feedback through end',
    (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      final task = tester.state<_TaskState>(find.byType(_Task));
      await tester.enterText(
        find.byKey(const ValueKey('task-draft')),
        'Mein eigener Anfang',
      );
      await tester.tap(find.text('Eltern fragen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eltern live dazuholen'));
      await tester.pumpAndSettle();
      expect(fixture.router.routeInformationProvider.value.uri.path, '/task');
      expect(tester.state(find.byType(_Task)), same(task));
      expect(task.draft.text, 'Mein eigener Anfang');
      expect(
        find.text('Deine gespeicherte Rückmeldung bleibt hier.'),
        findsOneWidget,
      );
      expect(fixture.starts, 1);
      expect(find.byKey(const ValueKey('family-call-dock')), findsOneWidget);
      await fixture.state.familyCalls.end();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(_Task)), same(task));
      expect(task.draft.text, 'Mein eigener Anfang');
      expect(find.byKey(const ValueKey('family-call-dock')), findsNothing);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'Compact dock controls media and keeps explicit screen consent on the same task',
    (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      await fixture.connect(tester);
      final task = tester.state(find.byType(_Task));
      await tester.tap(find.byKey(const ValueKey('call-dock-microphone')));
      await tester.pumpAndSettle();
      expect(fixture.media.microphoneEnabled, isFalse);
      await tester.tap(find.byKey(const ValueKey('call-dock-camera')));
      await tester.pumpAndSettle();
      expect(fixture.media.cameraEnabled, isFalse);
      await tester.tap(find.byKey(const ValueKey('call-dock-screen')));
      await tester.pumpAndSettle();
      expect(find.text('Deine Aufgabe live zeigen'), findsOneWidget);
      expect(fixture.media.sharingScreen, isFalse);
      await tester.tap(find.byKey(const ValueKey('call-dock-share-confirm')));
      await tester.pumpAndSettle();
      expect(fixture.media.sharingScreen, isTrue);
      expect(find.text('Dein Bildschirm wird geteilt'), findsOneWidget);
      expect(find.byTooltip('Bildschirmfreigabe stoppen'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('call-dock-screen')));
      await tester.pumpAndSettle();
      expect(fixture.media.sharingScreen, isFalse);
      expect(tester.state(find.byType(_Task)), same(task));
      expect(fixture.router.routeInformationProvider.value.uri.path, '/task');
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  for (final role in ['child', 'parent']) {
    testWidgets('$role full screen and back never mount a renderer twice', (
      tester,
    ) async {
      final fixture = _Fixture(role: role);
      fixture.media.remoteScreen = role == 'parent';
      await fixture.open(tester);
      await fixture.connect(tester);
      final task = tester.state(find.byType(_Task));
      await tester.tap(find.byKey(const ValueKey('call-dock-expand')));
      await tester.pumpAndSettle();
      expect(fixture.media.mounted, {
        'remote': 1,
        'local': 1,
        if (role == 'parent') 'screen': 1,
      });
      await tester.ensureVisible(
        find.byKey(const ValueKey('call-dock-fullscreen')),
      );
      await tester.tap(find.byKey(const ValueKey('call-dock-fullscreen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('family-call-dock')), findsNothing);
      expect(fixture.media.peak.values.every((peak) => peak == 1), isTrue);
      fixture.router.pop();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(_Task)), same(task));
      expect(fixture.media.mounted, {
        'remote': 1,
        'local': 1,
        if (role == 'parent') 'screen': 1,
      });
      expect(fixture.media.peak.values.every((peak) => peak == 1), isTrue);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 568), const Size(640, 320)]) {
      testWidgets(
        'Dock remains usable at $size, 2x text, keyboard and $brightness',
        (tester) async {
          final fixture = _Fixture();
          await fixture.open(
            tester,
            size: size,
            scale: 2,
            brightness: brightness,
          );
          await fixture.connect(tester);
          final task = tester.state<_TaskState>(find.byType(_Task));
          if (size.height >= 420) {
            await tester.tap(find.byKey(const ValueKey('call-dock-expand')));
            await tester.pumpAndSettle();
          }
          tester.view.viewInsets = FakeViewPadding(
            bottom: size.height > 400 ? 220 : 100,
          );
          await tester.pumpAndSettle();
          for (final key in ['microphone', 'camera', 'screen', 'end']) {
            final control = find.byKey(ValueKey('call-dock-$key'));
            expect(control, findsOneWidget);
            expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
            expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
          }
          expect(find.byKey(const ValueKey('call-dock-details')), findsNothing);
          await tester.enterText(
            find.byKey(const ValueKey('task-draft')),
            'Mein Entwurf',
          );
          expect(task.draft.text, 'Mein Entwurf');
          expect(tester.state(find.byType(_Task)), same(task));
          expect(tester.takeException(), isNull);
          await fixture.close(tester);
        },
      );
    }
  }

  testWidgets(
    'Collapsed errors remain readable without navigation and old accounts reveal no call',
    (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      await fixture.connect(tester);
      final calls = fixture.state.familyCalls;
      calls.error = 'Künstlich: Die Bildschirmfreigabe ist gestoppt.';
      calls.notifyListeners();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verbindung prüfen'));
      await tester.pumpAndSettle();
      expect(
        find.text('Künstlich: Die Bildschirmfreigabe ist gestoppt.'),
        findsOneWidget,
      );
      fixture.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      fixture.state.user = {...fixture.state.user!};
      fixture.state.refreshState();
      calls.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('family-call-dock')), findsNothing);
      expect(fixture.router.routeInformationProvider.value.uri.path, '/task');
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );
}
