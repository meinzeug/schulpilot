import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/ui.dart';

http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json parent() => {
  'id': 'synthetic-owner',
  'role': 'parent',
  'display_name': 'Künstlicher Elternzugang',
  'username': 'synthetic-parent',
  'families': [
    {'id': 'family-a', 'name': 'Kunstfamilie A', 'permission': 'owner'},
    {'id': 'family-b', 'name': 'Kunstfamilie B', 'permission': 'owner'},
  ],
};

AppState stateFor(Future<http.Response> Function(http.Request) handler) =>
    AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient(handler),
        ),
      )
      ..user = parent()
      ..familyId = 'family-a';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<void> mountDialog(
  WidgetTester tester,
  AppState state,
  Future<void> Function(BuildContext) open, {
  double scale = 1,
  double inset = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: inset),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => open(context),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Öffnen'));
  await tester.pumpAndSettle();
}

Future<void> cleanup(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(const SizedBox());
  state.inbox.dispose();
  state.dispose();
}

void main() {
  testWidgets(
    'invitation keeps server error and email in the dialog; empty email stays local',
    (tester) async {
      final requests = <http.Request>[];
      final state = stateFor((r) async {
        requests.add(r);
        return response({
          'detail': 'Für diese Adresse besteht bereits eine Einladung.',
        }, 409);
      });
      await mountDialog(tester, state, (ctx) => inviteDialog(ctx, state));
      await tester.tap(find.text('Einladung senden'));
      await tester.pumpAndSettle();
      expect(
        find.text('Gib die E-Mail-Adresse des Elternteils ein.'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      await tester.enterText(
        field('E-Mail des Elternteils'),
        '  synthetic@example.invalid  ',
      );
      await tester.tap(find.text('Einladung senden'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(
            'Für diese Adresse besteht bereits eine Einladung.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(field('E-Mail des Elternteils'))
            .controller!
            .text,
        '  synthetic@example.invalid  ',
      );
      expect(jsonDecode(requests.single.body), {
        'email': 'synthetic@example.invalid',
        'permission': 'view',
      });
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(requests, hasLength(1));
      await cleanup(tester, state);
    },
  );

  for (final change in ['family', 'same-id session']) {
    testWidgets(
      'old invitation closes and stale submit cannot send after $change change',
      (tester) async {
        final requests = <http.Request>[];
        final state = stateFor((r) async {
          requests.add(r);
          return response({});
        });
        await mountDialog(tester, state, (ctx) => inviteDialog(ctx, state));
        await tester.enterText(
          field('E-Mail des Elternteils'),
          'synthetic@example.invalid',
        );
        final oldSubmit = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Einladung senden'),
            )
            .onPressed!;
        if (change == 'family') {
          state.familyId = 'family-b';
        } else {
          state.user = parent();
        }
        state.refreshState();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        oldSubmit();
        await tester.pumpAndSettle();
        expect(requests, isEmpty);
        expect(tester.takeException(), isNull);
        await cleanup(tester, state);
      },
    );
  }

  for (final change in ['route removed', 'family changed and route removed']) {
    testWidgets(
      'queued validation reveal ignores disposed form after $change',
      (tester) async {
        final requests = <http.Request>[];
        final state = stateFor((request) async {
          requests.add(request);
          return response({});
        });
        await mountDialog(tester, state, (ctx) => inviteDialog(ctx, state));
        final context = tester.element(find.byType(AlertDialog));
        final navigator = Navigator.of(context);
        final route = ModalRoute.of(context)!;
        // validateGranularly schedules reveal() for the next frame. Remove
        // its form before that frame, without allowing the callback to run.
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Einladung senden'),
            )
            .onPressed!();
        if (change.startsWith('family')) {
          state.familyId = 'family-b';
          state.refreshState();
        }
        navigator.removeRoute(route);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(requests, isEmpty);
        expect(tester.takeException(), isNull);
        await cleanup(tester, state);
      },
    );
  }

  testWidgets(
    'pending invitation cannot be duplicated or dismissed; captured family is used',
    (tester) async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final state = stateFor((r) {
        requests.add(r);
        return pending.future;
      });
      await mountDialog(tester, state, (ctx) => inviteDialog(ctx, state));
      await tester.enterText(
        field('E-Mail des Elternteils'),
        'synthetic@example.invalid',
      );
      final oldSubmit = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Einladung senden'),
          )
          .onPressed!;
      oldSubmit();
      oldSubmit();
      await tester.pump();
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/api/families/family-a/invitations');
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Abbrechen'))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(field('E-Mail des Elternteils')).enabled,
        isFalse,
      );
      final context = tester.element(find.byType(AlertDialog));
      await Navigator.of(context).maybePop();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      pending.complete(response({}));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await cleanup(tester, state);
    },
  );

  testWidgets(
    'late invitation failure does not leak into replacement account',
    (tester) async {
      final pending = Completer<http.Response>();
      final state = stateFor((_) => pending.future);
      await mountDialog(tester, state, (ctx) => inviteDialog(ctx, state));
      await tester.enterText(
        field('E-Mail des Elternteils'),
        'synthetic@example.invalid',
      );
      await tester.tap(find.text('Einladung senden'));
      await tester.pump();
      state.user = {...parent(), 'id': 'replacement'};
      state.refreshState();
      await tester.pumpAndSettle();
      pending.complete(response({'detail': 'OLD PRIVATE FEEDBACK'}, 403));
      await tester.pumpAndSettle();
      expect(find.text('OLD PRIVATE FEEDBACK'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await cleanup(tester, state);
    },
  );

  testWidgets(
    'reset validates required parent password and twelve Unicode characters before request',
    (tester) async {
      final requests = <http.Request>[];
      final state = stateFor((r) async {
        requests.add(r);
        return response({});
      });
      await mountDialog(
        tester,
        state,
        (ctx) => resetChildDialog(ctx, state, 'synthetic-child'),
      );
      await tester.tap(find.text('Passwort erneuern'));
      await tester.pumpAndSettle();
      expect(find.text('Gib dein Elternpasswort ein.'), findsOneWidget);
      expect(find.text('Nutze mindestens 12 Zeichen.'), findsOneWidget);
      expect(requests, isEmpty);
      await tester.enterText(
        field('Dein Elternpasswort'),
        'synthetic-parent-password',
      );
      await tester.enterText(field('Neues Kinderpasswort'), '😀😀😀😀😀😀');
      await tester.tap(find.text('Passwort erneuern'));
      await tester.pumpAndSettle();
      expect(
        requests,
        isEmpty,
        reason: 'Six non-BMP characters are not twelve code points.',
      );
      await tester.enterText(
        field('Neues Kinderpasswort'),
        'synthetic-new-password',
      );
      await tester.enterText(
        field('Neues Kinderpasswort wiederholen'),
        'synthetic-new-password',
      );
      await tester.tap(find.text('Passwort erneuern'));
      await tester.pumpAndSettle();
      expect(requests.single.method, 'PUT');
      expect(
        requests.single.url.path,
        '/api/children/synthetic-child/password',
      );
      expect(jsonDecode(requests.single.body), {
        'parent_password': 'synthetic-parent-password',
        'password': 'synthetic-new-password',
      });
      await cleanup(tester, state);
    },
  );

  testWidgets(
    'child edit rejects invalid grade locally without substituting zero',
    (tester) async {
      final requests = <http.Request>[];
      final state = stateFor((r) async {
        requests.add(r);
        return response({});
      });
      await mountDialog(
        tester,
        state,
        (ctx) => editChildDialog(ctx, state, {
          'id': 'synthetic-child',
          'display_name': 'Künstliches Kind',
          'grade': 5,
          'subjects': ['Mathematik'],
          'school_type': '',
          'region': '',
        }),
      );
      await tester.enterText(field('Klassenstufe'), 'unbekannt');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(
        find.text('Nutze eine Klassenstufe von 1 bis 13.'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      await tester.enterText(field('Klassenstufe'), '6');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(jsonDecode(requests.single.body)['grade'], 6);
      await cleanup(tester, state);
    },
  );

  testWidgets(
    'destructive confirmation keeps failed password editable and cancellation sends nothing else',
    (tester) async {
      final requests = <http.Request>[];
      final state = stateFor((r) async {
        requests.add(r);
        return response({'detail': 'Elternpasswort ist nicht richtig.'}, 403);
      });
      await mountDialog(tester, state, (ctx) async {
        await passwordDialog(
          ctx,
          'Kunstkonto löschen?',
          'Nur künstliche Testdaten.',
          state: state,
          destructive: true,
          confirmLabel: 'Kinderkonto löschen',
          confirm: (value) async {
            await state.api.delete('/children/synthetic-child', {
              'password': value,
            });
          },
        );
      });
      await tester.tap(find.text('Kinderkonto löschen'));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      await tester.enterText(
        field('Dein Elternpasswort'),
        'synthetic-wrong-password',
      );
      await tester.tap(find.text('Kinderkonto löschen'));
      await tester.pumpAndSettle();
      expect(find.text('Elternpasswort ist nicht richtig.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      await cleanup(tester, state);
    },
  );

  for (final mode in ['invite', 'reset', 'delete']) {
    testWidgets(
      '$mode dialog stays scrollable at 320px, 160% and an open keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = stateFor((_) async => response({}));
        await mountDialog(
          tester,
          state,
          (ctx) async {
            if (mode == 'invite') {
              await inviteDialog(ctx, state);
            } else if (mode == 'reset') {
              await resetChildDialog(ctx, state, 'synthetic-child');
            } else {
              await passwordDialog(
                ctx,
                'Konto und eigene Familien löschen?',
                'Die künstlichen Familien werden gelöscht. Backups verfallen nach höchstens 14 Tagen.',
                state: state,
                destructive: true,
                confirmLabel: 'Konto und eigene Familien löschen',
              );
            }
          },
          scale: 1.6,
          inset: 280,
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(SingleChildScrollView),
          ),
          findsWidgets,
        );
        final cancel = find.widgetWithText(TextButton, 'Abbrechen');
        await tester.ensureVisible(cancel);
        expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(460));
        expect(tester.takeException(), isNull);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        await cleanup(tester, state);
      },
    );
  }

  testWidgets(
    'old account session list cannot remain interactive after replacement login',
    (tester) async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final state = stateFor((r) async {
        requests.add(r);
        if (r.url.path.endsWith('/auth/sessions')) {
          if (stateAccountId == 'replacement') return pending.future;
          return response([
            {
              'id': 'old-device',
              'device': 'OLD PRIVATE DEVICE',
              'current': false,
            },
          ]);
        }
        if (r.url.path.endsWith('/devices')) return response([]);
        return response({'available': false});
      });
      stateAccountId = 'original';
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => SettingsScreen(state))],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      for (final section in ['google', 'sessions']) {
        final loader = find.byWidgetPredicate(
          (widget) =>
              widget is LoadView && widget.key.toString().contains(section),
        );
        expect(loader, findsOneWidget);
        final diagnostic = tester.widget(loader).key.toString();
        expect(diagnostic, isNot(contains('Künstlicher Elternzugang')));
        expect(diagnostic, isNot(contains('synthetic-parent')));
      }
      final button = find.widgetWithText(ActionButton, 'Gerät abmelden');
      await tester.ensureVisible(button);
      final oldAction = tester.widget<ActionButton>(button).onPressed;
      stateAccountId = 'replacement';
      state.user = {...parent(), 'id': 'replacement'};
      state.refreshState();
      await tester.pump();
      expect(find.text('OLD PRIVATE DEVICE'), findsNothing);
      await oldAction();
      pending.complete(response([]));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      state.inbox.dispose();
      state.dispose();
    },
  );
}

String stateAccountId = 'original';
