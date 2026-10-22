import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/family_call_screen.dart';
import 'package:schulpilot/main.dart';
import 'package:schulpilot/push_transport.dart';

import 'family_call_test.dart' as f;

const otherCall = 'cccccccccccccccccccccccccccccccc';
final states = <AppState>[];
final mainOwned = <AppState>{};
final routers = <GoRouter>[];
void scenario(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PushTransport.channel,
            (_) async => <String, dynamic>{},
          );
      try {
        await body(tester);
      } finally {
        for (final state in states) {
          await state.familyCalls.clear();
        }
        await tester.pumpWidget(const SizedBox());
        for (final state in states) {
          if (!mainOwned.contains(state)) state.familyCalls.dispose();
          state.inbox.dispose();
        }
        states.clear();
        mainOwned.clear();
        for (final router in routers) {
          router.dispose();
        }
        routers.clear();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(PushTransport.channel, null);
      }
    });
AppState stateFor(
  Future<http.Response> Function(http.Request) handle, {
  String role = 'parent',
}) {
  final state = f.makeState((request) async {
    if (request.url.path.endsWith('/active')) return f.response({'calls': []});
    if (request.url.path.endsWith('/inbox')) {
      return f.response({'items': [], 'unread': 0});
    }
    return handle(request);
  }, role: role);
  states.add(state);
  return state;
}

Future<GoRouter> display(
  WidgetTester tester,
  AppState state, {
  String callId = f.callId,
}) async {
  final router = GoRouter(
    initialLocation: '/family-call/$callId',
    routes: [
      GoRoute(
        path: '/family-call/:id',
        builder: (_, route) =>
            FamilyCallScreen(state, callId: route.pathParameters['id']!),
      ),
      GoRoute(
        path: '/messages/:id',
        builder: (_, route) => Scaffold(
          body: Text('Eigene Nachrichten ${route.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: '/app',
        builder: (_, _) => const Scaffold(body: Text('Eigener Lernraum')),
      ),
    ],
  );
  routers.add(router);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

class ClosingMedia extends f.FakeMedia {
  final closedSignal = Completer<void>();
  @override
  Future<void> close() async {
    await closedSignal.future;
    await super.close();
  }
}

void main() {
  scenario(
    'RR037 a new same-ID session invalidates the old page request before it can display a call',
    (tester) async {
      final old = Completer<http.Response>();
      var reads = 0, writes = 0;
      final state = stateFor((request) async {
        if (request.method != 'GET') writes++;
        if (++reads == 1) return old.future;
        return f.response({
          ...f.metadata('ringing', role: 'parent'),
          'child_name': 'Neue Sitzung',
        });
      });
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => FamilyCallScreen(state, callId: f.callId),
          ),
        ],
      );
      routers.add(router);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      state.user = Map<String, dynamic>.from(state.user!);
      state.notifyListeners();
      await tester.pumpAndSettle();
      old.complete(
        f.response({
          ...f.metadata('ringing', role: 'parent'),
          'child_name': 'Alter privater Kontext',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Neue Sitzung ruft an.'), findsOneWidget);
      expect(find.textContaining('Alter privater Kontext'), findsNothing);
      expect(writes, 0);
      expect(state.familyCalls.media, isNull);
    },
  );

  scenario(
    'RR037 a superseded read cannot install call metadata after media shutdown awaits',
    (tester) async {
      final state = stateFor(
        (_) async => f.response(f.metadata('accepted')),
        role: 'child',
      );
      final calls = state.familyCalls;
      calls.activate(state.user);
      await tester.pump();
      final media = ClosingMedia();
      calls.media = media;
      var current = true;
      final opened = calls.open(f.callId, isCurrent: () => current);
      await tester.pump();
      current = false;
      media.closedSignal.complete();
      await opened;
      expect(calls.call, isNull);
    },
  );

  scenario(
    'RR038 loading a decline URL never declines or captures automatically',
    (tester) async {
      final writes = <http.Request>[];
      final state = stateFor((request) async {
        if (request.method != 'GET') writes.add(request);
        return f.response(f.metadata('ringing', role: 'parent'));
      });
      await tester.pumpWidget(
        SchulpilotApp(
          state,
          initialLocation: '/family-call/${f.callId}?action=decline',
        ),
      );
      mainOwned.add(state);
      await tester.pumpAndSettle();
      expect(state.familyCalls.live, isTrue);
      expect(state.familyCalls.media, isNull);
      expect(writes, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  scenario('RR039 a failed call page has an explicit read-only retry', (
    tester,
  ) async {
    var reads = 0, writes = 0;
    final state = stateFor((request) async {
      if (request.method != 'GET') writes++;
      if (++reads == 1) {
        return f.response({'detail': 'synthetic unavailable'}, 503);
      }
      return f.response(f.metadata('ringing', role: 'parent'));
    });
    await display(tester, state);
    await tester.ensureVisible(find.text('Anrufstatus erneut laden'));
    await tester.tap(find.text('Anrufstatus erneut laden'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Künstliches Testkind ruft an.'),
      findsOneWidget,
    );
    expect(reads, 2);
    expect(writes, 0);
    expect(state.familyCalls.media, isNull);
  });

  scenario(
    'RR040 an old call link offers the actual currently open conversation',
    (tester) async {
      var writes = 0;
      final state = stateFor((request) async {
        if (request.method != 'GET') writes++;
        return f.response({...f.metadata('accepted'), 'id': otherCall});
      }, role: 'child');
      state.familyCalls.activate(state.user);
      await tester.pump();
      state.familyCalls.call = {...f.metadata('accepted'), 'id': otherCall};
      final router = await display(tester, state);
      await tester.ensureVisible(find.text('Zum bereits geöffneten Gespräch'));
      await tester.tap(find.text('Zum bereits geöffneten Gespräch'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/family-call/$otherCall',
      );
      expect(state.familyCalls.callId, otherCall);
      expect(writes, 0);
    },
  );

  scenario(
    'RR041 parents can follow up a finished call in the correct child thread',
    (tester) async {
      var writes = 0;
      final state = stateFor((request) async {
        if (request.method != 'GET') writes++;
        return f.response(f.metadata('ended', role: 'parent'));
      });
      await display(tester, state);
      await tester.ensureVisible(
        find.text('Dem Kind eine Nachricht schreiben'),
      );
      await tester.tap(find.text('Dem Kind eine Nachricht schreiben'));
      await tester.pumpAndSettle();
      expect(
        find.text('Eigene Nachrichten bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        findsOneWidget,
      );
      expect(writes, 0);
    },
  );

  scenario(
    'RR042 an obsolete help sheet closes itself without popping a newer dialog',
    (tester) async {
      var messages = 0;
      final state = stateFor((_) async => f.response({}), role: 'child');
      late BuildContext home;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              home = context;
              return Scaffold(
                body: TextButton(
                  onPressed: () => unawaited(
                    showFamilyHelp(
                      context,
                      state,
                      sendMessage: () async {
                        messages++;
                      },
                    ),
                  ),
                  child: const Text('Hilfe holen'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Hilfe holen'));
      await tester.pumpAndSettle();
      final staleMessage = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Lieber eine Nachricht senden'),
          )
          .onPressed!;
      unawaited(
        showDialog<void>(
          context: home,
          builder: (_) =>
              const AlertDialog(title: Text('Neuer wichtiger Dialog')),
        ),
      );
      await tester.pumpAndSettle();
      staleMessage();
      await tester.pumpAndSettle();
      expect(find.text('Neuer wichtiger Dialog'), findsOneWidget);
      expect(messages, 0);
      state.user = Map<String, dynamic>.from(state.user!);
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Gemeinsam geht’s weiter.'), findsNothing);
      expect(find.text('Neuer wichtiger Dialog'), findsOneWidget);
      expect(messages, 0);
      Navigator.of(tester.element(find.text('Neuer wichtiger Dialog'))).pop();
      await tester.pumpAndSettle();
    },
  );

  scenario('RR043 a saved end control cannot hang up a newer conversation', (
    tester,
  ) async {
    var writes = 0;
    final state = stateFor((request) async {
      if (request.method != 'GET') writes++;
      return f.response(f.metadata('accepted'));
    }, role: 'child');
    await display(tester, state);
    final end = tester
        .widget<OutlinedButton>(find.byKey(const ValueKey('call-end-top')))
        .onPressed!;
    state.familyCalls.call = {...f.metadata('accepted'), 'id': otherCall};
    state.familyCalls.notifyListeners();
    await tester.pumpAndSettle();
    end();
    await tester.pumpAndSettle();
    expect(state.familyCalls.callId, otherCall);
    expect(writes, 0);
  });
}
