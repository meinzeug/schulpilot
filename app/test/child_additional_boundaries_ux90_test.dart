import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_account.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/family_call_service.dart';
import 'package:schulpilot/material_actions.dart';
import 'package:schulpilot/ui.dart';

import 'child_local_tools_ux88_test.dart' as f;
import 'school_day_background_test.dart' as d;
import 'child_photos_day_ux90_test.dart' as photo;
import 'child_history_ux90_test.dart' as history;
import 'family_call_test.dart' as call;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'CK021 abandoning replacement keeps the unreadable original and never deletes first',
    (tester) async {
      final server = d.PreparationServer(
        pages: [d.source(1, status: 'unreadable')],
      )..realUploads = true;
      await photo.showDay(tester, server.state());
      await d.tapText(tester, 'Ersetzen');
      expect(find.text('Ersatzfoto auswählen'), findsOneWidget);
      expect(server.requests.where((r) => !r.startsWith('GET ')), isEmpty);
      await d.tapText(tester, 'Altes Foto behalten');
      expect(find.text('Seite 1'), findsOneWidget);
      expect(server.pages.length, 1);
      expect(server.requests.where((r) => !r.startsWith('GET ')), isEmpty);
    },
  );
  testWidgets(
    'CK026 deleting a saved round names exactly which subject and topic would be removed',
    (tester) async {
      final requests = <http.Request>[];
      final state = f.account((r) async {
        requests.add(r);
        return f.reply({'selection_token': 'token', 'answer_count': 3});
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => deleteLearningRound(ctx, state, {
                  'id': 'round',
                  'subject': 'Mathematik',
                  'topic': 'Brüche addieren',
                }),
                child: Text('Löschen prüfen'),
              ),
            ),
          ),
        ),
      );
      await f.tap(tester, find.text('Löschen prüfen'));
      expect(
        find.textContaining('„Mathematik · Brüche addieren“'),
        findsOneWidget,
      );
      expect(find.text('Lernrunde löschen'), findsOneWidget);
      await f.tap(tester, find.text('Abbrechen'));
      expect(requests.length, 1);
      expect(requests.single.url.path.endsWith('/delete-preview'), isTrue);
    },
  );
  testWidgets(
    'CK032 failed source processing asks parents with the exact existing material reference',
    (tester) async {
      const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final requests = <http.Request>[];
      final state = f.account((r) async {
        requests.add(r);
        if (r.method == 'POST') return f.reply({'id': 'message'});
        if (r.url.path.startsWith('/api/materials/')) {
          return f.reply({'id': id, 'child_id': 'child', 'topic': 'Mein Heft'});
        }
        return f.reply({
          'kind': 'extract',
          'material_id': id,
          'status': 'failed',
          'error': 'Foto war unlesbar.',
        });
      });
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                MaterialProcessingScreen(state, materialId: id, jobId: 'job'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      await f.tap(tester, find.text('Meine Eltern fragen'));
      await f.tap(tester, find.text('Lieber eine Nachricht senden'));
      expect(find.text('Zur gleichen Heftseite'), findsOneWidget);
      await f.tap(tester, find.text('Um Hilfe bitten'));
      expect(
        jsonDecode(
          requests.where((r) => r.method == 'POST').single.body,
        )['material_id'],
        id,
      );
      await tester.pumpWidget(SizedBox());
    },
  );
  testWidgets(
    'CK059 explicit history date jump uses the existing exclusive before boundary only',
    (tester) async {
      final requests = <http.Request>[];
      final state = f.account((r) async {
        requests.add(r);
        return f.reply({'days': [], 'next_before': null});
      });
      await history.open(tester, state);
      await f.tap(tester, find.text('Zu einem Datum'));
      await f.tap(tester, find.text('Tage anzeigen'));
      expect(
        requests.last.url.queryParameters['before'],
        DateFormat('yyyy-MM-dd').format(DateTime.now().add(Duration(days: 1))),
      );
      expect(requests.length, 2);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK071 local photo expiry is based on the real bounded storage timestamp',
    (tester) async {
      final server = d.PreparationServer(pages: []);
      final state = server.state();
      await state.pendingUploads.add('kid', 'child', 'day', photo.bytes(2));
      final stored = (await state.pendingUploads.read('kid')).single;
      final expires = DateFormat('dd.MM.yyyy · HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(stored['created'])
            .add(Duration(hours: 24))
            .toLocal(),
      );
      await photo.showDay(tester, state);
      expect(find.textContaining('Nur lokal bis: $expires'), findsOneWidget);
      expect(find.textContaining('Gib deine Fotos vorher ab'), findsOneWidget);
      expect(server.requests, isNotEmpty);
      expect(server.requests.every((r) => r.startsWith('GET ')), isTrue);
    },
  );
  testWidgets(
    'CK072 an old day GET cannot overwrite a later explicit stage change',
    (tester) async {
      final server = d.PreparationServer(
        stage: 'review',
        pages: [d.source(1, confirmed: true)],
      );
      final delayed = Completer<http.Response>();
      var held = false, reads = 0, stage = 'review';
      final state = f.account((r) async {
        if (r.method == 'PUT') {
          stage = 'collecting';
          return d.response({...server.day, 'stage': stage});
        }
        reads++;
        if (held) {
          held = false;
          return delayed.future;
        }
        return d.response({
          'day': {...server.day, 'stage': stage},
        });
      });
      await photo.showDay(tester, state);
      held = true;
      await f.tap(tester, find.byTooltip('Mehr'));
      await f.tap(tester, find.text('Neu laden'));
      final secondary = find.text('Noch eine Seite hinzufügen');
      await tester.ensureVisible(secondary);
      await tester.tap(secondary);
      await tester.pump();
      await tester.pump(Duration(milliseconds: 300));
      delayed.complete(
        d.response({
          'day': {...server.day, 'stage': 'review'},
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Zeig mir deine Heftseiten'), findsOneWidget);
      expect(reads, 3);
      expect(stage, 'collecting');
    },
  );
  testWidgets(
    'CK073 logout of other devices preserves this device and a newly appeared device',
    (tester) async {
      final removed = <String>[];
      var reads = 0;
      final state = f.account((r) async {
        if (r.method == 'DELETE') {
          removed.add(r.url.path.split('/').last);
          return f.reply({});
        }
        reads++;
        return f.reply([
          {'id': 'this', 'device': 'Mein Handy', 'current': true},
          if (!removed.contains('old'))
            {'id': 'old', 'device': 'Altes Tablet', 'current': false},
          if (reads > 1)
            {'id': 'new', 'device': 'Neues Gerät', 'current': false},
        ]);
      });
      await f.show(tester, ChildAccount(state));
      await f.tap(tester, find.text('Andere Geräte gemeinsam abmelden'));
      expect(find.text('• Altes Tablet'), findsOneWidget);
      await f.tap(tester, find.text('Andere Geräte abmelden'));
      expect(removed, ['old']);
      expect(state.user, isNotNull);
      expect(find.text('Neues Gerät'), findsOneWidget);
    },
  );
  testWidgets(
    'CK074 live help carries the exact current learning reference into the mocked call',
    (tester) async {
      const child = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          unit = '11111111111111111111111111111111';
      final requests = <http.Request>[];
      final media = call.FakeMedia();
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((r) async {
            requests.add(r);
            if (r.url.path.endsWith('/config')) {
              return f.reply({'available': true});
            }
            if (r.url.path.endsWith('/active')) return f.reply({'calls': []});
            return f.reply(
              call.metadata(r.url.path.endsWith('/end') ? 'ended' : 'ringing'),
            );
          }),
        ),
        familyCallFactory: (state) => FamilyCallService(
          state,
          mediaFactory: () => media,
          nativeEnabled: false,
          pollInterval: Duration(hours: 1),
        ),
      )..user = {'id': 'child-user', 'role': 'child', 'child_id': child};
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showHomeHelp(
                  ctx,
                  state,
                  childId: child,
                  unitId: unit,
                  refresh: () {},
                ),
                child: Text('Hilfe öffnen'),
              ),
            ),
          ),
        ),
      );
      await f.tap(tester, find.text('Hilfe öffnen'));
      await f.tap(tester, find.text('Meine Eltern fragen'));
      await f.tap(tester, find.text('Eltern live dazuholen'));
      final body = jsonDecode(
        requests
            .where(
              (r) => r.method == 'POST' && r.url.path.endsWith('/family-calls'),
            )
            .single
            .body,
      );
      expect(body['context_kind'], 'learning');
      expect(body['context_id'], unit);
      expect(media.prepared, 1);
      await state.familyCalls.clear();
      state.familyCalls.dispose();
      await tester.pumpWidget(SizedBox());
    },
  );
}
