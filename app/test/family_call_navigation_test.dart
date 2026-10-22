import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/family_call_media.dart';
import 'package:schulpilot/family_call_service.dart';
import 'package:schulpilot/main.dart';
import 'package:schulpilot/unit_screen.dart';

const _callId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _newerCallId = 'cccccccccccccccccccccccccccccccc';
const _childId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _unitId = 'dddddddddddddddddddddddddddddddd';

http.Response _reply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

Json _call(String id, String status, {String role = 'child'}) => {
  'id': id,
  'child_id': _childId,
  'child_name': 'Künstliches Testkind',
  'status': status,
  'role': role,
  'is_participant': status == 'accepted' || role == 'child',
  'server_now': 1000,
  'ring_expires': 1045,
  'valid_until': 1090,
};

Json _unit() => {
  'id': _unitId,
  'child_id': _childId,
  'subject': 'Deutsch',
  'topic': 'Künstliche Aufgabenprobe',
  'status': 'active',
  'synthetic': true,
  'introduction_seen': true,
  'explanation': 'Dies ist ausschließlich ein künstlicher Test.',
  'active_seconds_approx': 0,
  'break_recommended': false,
  'questions': [
    {
      'id': 'draft-question',
      'type': 'short',
      'prompt': 'Schreibe ein Wort, das mit B beginnt.',
      'attempts': <Json>[],
      'hints_used': 0,
      'hints': <String>[],
      'explanation': 'Eine feste künstliche Aufgabe für den Navigationstest.',
    },
  ],
  'coaching': null,
};

class _RecordingMedia extends FamilyCallMedia {
  int prepared = 0;
  bool closed = false;
  @override
  bool get microphoneEnabled => true;
  @override
  bool get cameraEnabled => true;
  @override
  bool get sharingScreen => false;
  @override
  bool get hasRemoteCamera => true;
  @override
  bool get hasRemoteScreen => false;
  @override
  String get connectionState => 'connected';
  @override
  Future<void> prepare({required bool camera}) async => prepared++;
  @override
  Future<void> connect(List<dynamic> iceServers) async {}
  @override
  Future<Json> offer() async => {'sdp': 'artificial-offer'};
  @override
  Future<Json> answer(Json offer) async => {'sdp': 'artificial-answer'};
  @override
  Future<void> receiveAnswer(Json answer) async {}
  @override
  Future<void> receiveIce(Json candidate) async {}
  @override
  Future<void> toggleMicrophone() async {}
  @override
  Future<bool> toggleCamera() async => false;
  @override
  Future<void> startScreen() async {}
  @override
  Future<void> stopScreen() async {}
  @override
  Widget video({required bool remote, bool screen = false}) =>
      const Text('Künstliche Videovorschau');
  @override
  Future<void> close() async => closed = true;
}

class _Fixture {
  final String role;
  final requests = <String>[];
  final media = _RecordingMedia();
  String status;
  late final AppState state;
  _Fixture({this.role = 'child', this.status = 'accepted'}) {
    state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient(handle),
            ),
            familyCallFactory: (state) => FamilyCallService(
              state,
              nativeEnabled: false,
              mediaFactory: () => media,
            ),
          )
          ..user = {
            'id': 'artificial-$role-account',
            'display_name': 'Künstlicher Zugang',
            'role': role,
            'synthetic': true,
            if (role == 'child') 'child_id': _childId,
          };
  }

  Future<http.Response> handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    final path = request.url.path;
    if (path.endsWith('/notifications/inbox')) {
      return _reply({'items': [], 'unread': 0});
    }
    if (path.endsWith('/family-calls/active')) {
      return _reply({'calls': []});
    }
    if (path.endsWith('/units/$_unitId')) return _reply(_unit());
    if (path.endsWith('/heartbeat') && path.contains('/units/')) {
      return _reply({'status': 'active', 'active_seconds_approx': 0});
    }
    if (path.endsWith('/accept')) status = 'accepted';
    if (path.endsWith('/decline')) status = 'declined';
    if (path.endsWith('/ice')) return _reply({'ice_servers': []});
    if (path.endsWith('/signals')) {
      return _reply({'signals': [], 'cursor': 0});
    }
    return _reply(_call(_callId, status, role: role));
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      SchulpilotApp(state, initialLocation: '/unit/$_unitId'),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      state.inbox.dispose();
    });
  }

  String route(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(UnitScreen)))
          .routeInformationProvider
          .value
          .uri
          .path;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Native open keeps the actual task and its unsent draft mounted',
    (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      final task = tester.state(find.byType(UnitScreen));
      final answer = find.byKey(const ValueKey('answer-draft-question'));
      await tester.ensureVisible(answer);
      await tester.enterText(answer, 'Beispielentwurf');
      await tester.pump();
      fixture.state.familyCalls.onNativeIntent!(_callId, 'open');
      await tester.pumpAndSettle();
      expect(fixture.route(tester), '/unit/$_unitId');
      expect(tester.state(find.byType(UnitScreen)), same(task));
      expect(
        tester.widget<TextField>(answer).controller!.text,
        'Beispielentwurf',
      );
      expect(fixture.media.prepared, 0);
      expect(fixture.state.familyCalls.media, isNull);
      expect(
        fixture.requests.where((request) => request.contains('/accept')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Native answer still requires explicit parent acceptance', (
    tester,
  ) async {
    final fixture = _Fixture(role: 'parent', status: 'ringing');
    await fixture.open(tester);
    final task = tester.state(find.byType(UnitScreen));
    final calls = fixture.state.familyCalls;
    calls.onNativeIntent!(_callId, 'answer');
    await tester.pumpAndSettle();
    expect(find.text('Gemeinsam helfen'), findsOneWidget);
    expect(fixture.media.prepared, 0);
    expect(fixture.requests.where((r) => r.contains('/accept')), isEmpty);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Zurück'),
      ),
    );
    await tester.pumpAndSettle();
    expect(fixture.route(tester), '/unit/$_unitId');
    expect(tester.state(find.byType(UnitScreen)), same(task));
    expect(fixture.media.prepared, 0);
    calls.onNativeIntent!(_callId, 'answer');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Annehmen'),
      ),
    );
    await tester.pumpAndSettle();
    expect(fixture.media.prepared, 1);
    expect(
      fixture.requests.where(
        (r) => r == 'POST /api/family-calls/$_callId/accept',
      ),
      hasLength(1),
    );
    expect(fixture.route(tester), '/unit/$_unitId');
    expect(tester.state(find.byType(UnitScreen)), same(task));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Native decline leaves the task route intact and never captures',
    (tester) async {
      final fixture = _Fixture(role: 'parent', status: 'ringing');
      await fixture.open(tester);
      fixture.state.familyCalls.onNativeIntent!(_callId, 'decline');
      await tester.pumpAndSettle();
      expect(fixture.route(tester), '/unit/$_unitId');
      expect(fixture.media.prepared, 0);
      expect(
        fixture.requests.where(
          (r) => r == 'POST /api/family-calls/$_callId/decline',
        ),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Opening an old call cannot close an already live newer call', (
    tester,
  ) async {
    final fixture = _Fixture();
    final calls = fixture.state.familyCalls;
    calls.activate(fixture.state.user);
    await tester.pump();
    calls.call = _call(_newerCallId, 'accepted');
    calls.media = fixture.media;
    fixture.requests.clear();
    await expectLater(calls.open(_callId), throwsA(isA<ApiError>()));
    expect(calls.callId, _newerCallId);
    expect(calls.media, same(fixture.media));
    expect(fixture.media.closed, isFalse);
    expect(fixture.requests, isEmpty);
    await calls.clear();
    calls.dispose();
    fixture.state.inbox.dispose();
  });

  testWidgets(
    'A late older open response cannot overwrite the newer live call',
    (tester) async {
      final stale = Completer<http.Response>();
      final requests = <String>[];
      final media = _RecordingMedia();
      final state =
          AppState(
              api: Api(
                base: 'https://example.invalid/api',
                client: MockClient((request) async {
                  requests.add(request.url.path);
                  if (request.url.path.endsWith('/active')) {
                    return _reply({'calls': []});
                  }
                  if (request.url.path.endsWith('/$_callId')) {
                    return stale.future;
                  }
                  return _reply(_call(_newerCallId, 'accepted'));
                }),
              ),
              familyCallFactory: (state) =>
                  FamilyCallService(state, nativeEnabled: false),
            )
            ..user = {
              'id': 'artificial-child',
              'role': 'child',
              'child_id': _childId,
            };
      final calls = state.familyCalls;
      calls.activate(state.user);
      await tester.pump();
      final earlierOpen = calls.open(_callId);
      await tester.pump();
      await calls.open(_newerCallId);
      calls.media = media;
      stale.complete(_reply(_call(_callId, 'ringing')));
      await earlierOpen;
      expect(calls.callId, _newerCallId);
      expect(calls.media, same(media));
      expect(media.closed, isFalse);
      expect(requests.where((r) => r.endsWith('/$_callId')), hasLength(1));
      await calls.clear();
      calls.dispose();
      state.inbox.dispose();
    },
  );
}
