import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/parent_profile_dialog.dart';
import 'package:schulpilot/settings_screen.dart' show inviteDialog;
import 'package:schulpilot/ui.dart';

import 'parent_workflows_ux90_test.dart' show field, tap;
import 'parent_settings_ux88_test.dart' as settings;
import 'parent_messages_ux88_test.dart' as messages;

class Fixture {
  final requests = <http.Request>[];
  final Json child = {
    'id': 'synthetic-child',
    'display_name': 'Künstliches Kind A',
    'username': 'synthetic-child-a',
    'grade': 6,
    'subjects': ['Mathematik'],
    'school_type': '',
    'region': '',
    'profile_revision': 'a' * 64,
  };
  Future<http.Response?> Function(http.Request)? respond;
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              return await respond?.call(r) ??
                  http.Response(
                    jsonEncode({}),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  );
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-parent',
          'role': 'parent',
          'families': [
            {'id': 'synthetic-family', 'permission': 'owner'},
          ],
        }
        ..familyId = 'synthetic-family';
  Future<void> open(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() {
      state.inbox.dispose();
      state.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showParentProfileDialog(c, state, child),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tap(tester, find.text('Öffnen'));
  }

  http.Response response(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  testWidgets(
    'PK030 family access removal names precisely the selected parent',
    (tester) async {
      final f = settings.Fixture();
      f.parents[1]['display_name'] = 'Künstliches Elternteil B';
      await f.mount(tester, section: 'family');
      await messages.tap(tester, find.text('Rechte entziehen'));
      expect(
        find.textContaining('Künstliches Elternteil B verliert den Zugriff'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Kinderzugang und seine Lernbelege bleiben erhalten',
        ),
        findsOneWidget,
      );
      await messages.tap(tester, find.text('Abbrechen'));
      expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
    },
  );
  testWidgets(
    'PK031 profile editing identifies fixed child and login before edits',
    (tester) async {
      final f = Fixture();
      await f.open(tester);
      expect(find.text('Für Künstliches Kind A'), findsOneWidget);
      expect(find.text('Kinderzugang: synthetic-child-a'), findsOneWidget);
      await tester.enterText(field('Anzeigename'), 'Geänderter Entwurf');
      expect(find.text('Für Künstliches Kind A'), findsOneWidget);
      expect(f.requests, isEmpty);
    },
  );
  for (final value in ['Mathematik, mathematik', 'a' * 81]) {
    testWidgets('PK035 invalid subject list stays local: ${value.length}', (
      tester,
    ) async {
      final f = Fixture();
      await f.open(tester);
      await tester.enterText(field('Fächer (mit Komma trennen)'), value);
      await tap(tester, find.text('Speichern'));
      expect(f.requests, isEmpty);
      expect(
        find.text(
          value.length > 80
              ? 'Ein einzelner Fachname darf höchstens 80 Zeichen haben.'
              : 'Nenne jedes Fach nur einmal.',
        ),
        findsOneWidget,
      );
    });
  }
  testWidgets('PK034 exact profile revision accompanies the saved snapshot', (
    tester,
  ) async {
    final f = Fixture();
    await f.open(tester);
    await tester.enterText(field('Anzeigename'), 'Neuer Anzeigename');
    await tap(tester, find.text('Speichern'));
    expect(f.requests.single.method, 'PUT');
    expect(f.requests.single.headers['If-Match'], 'a' * 64);
    expect(
      (jsonDecode(f.requests.single.body) as Json)['display_name'],
      'Neuer Anzeigename',
    );
  });
  testWidgets(
    'PK034 conflict keeps draft and readonly comparison requires explicit adoption',
    (tester) async {
      final f = Fixture();
      var puts = 0;
      final fresh = {
        ...f.child,
        'display_name': 'Zwischenänderung',
        'region': 'Gespeichert',
        'profile_revision': 'b' * 64,
      };
      f.respond = (r) async => r.method == 'GET'
          ? f.response({
              'children': [fresh],
            })
          : ++puts == 1
          ? f.response({
              'detail': 'Diese Kinderangaben wurden inzwischen geändert.',
            }, 409)
          : f.response({});
      await f.open(tester);
      await tester.enterText(field('Anzeigename'), 'Mein Entwurf');
      await tap(tester, find.text('Speichern'));
      expect(
        tester.widget<TextField>(field('Anzeigename')).controller!.text,
        'Mein Entwurf',
      );
      await tap(tester, find.text('Gespeicherten Stand vergleichen'));
      expect(puts, 1);
      expect(
        find.textContaining(
          'Gespeichert: Zwischenänderung\nDein Entwurf: Mein Entwurf',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(field('Anzeigename')).controller!.text,
        'Mein Entwurf',
      );
      await tap(
        tester,
        find.text('Gespeicherten Stand in den Entwurf übernehmen'),
      );
      expect(puts, 1);
      expect(
        tester.widget<TextField>(field('Anzeigename')).controller!.text,
        'Zwischenänderung',
      );
      await tap(tester, find.text('Speichern'));
      expect(f.requests.last.headers['If-Match'], 'b' * 64);
      expect(puts, 2);
    },
  );
  testWidgets(
    'PK034 delayed comparison never enters a new login with the same id',
    (tester) async {
      final f = Fixture();
      final delayed = Completer<http.Response>();
      f.respond = (_) => delayed.future;
      await f.open(tester);
      await tester.enterText(
        field('Anzeigename'),
        'Privater künstlicher Entwurf',
      );
      await tester.ensureVisible(find.text('Gespeicherten Stand vergleichen'));
      await tester.tap(find.text('Gespeicherten Stand vergleichen'));
      await tester.pump();
      f.state.user = {...f.state.user!};
      f.state.refreshState();
      await tester.pumpAndSettle();
      delayed.complete(
        f.response({
          'children': [
            {...f.child, 'display_name': 'Späte private Daten'},
          ],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notwendige Lernangaben'), findsNothing);
      expect(find.textContaining('Späte private Daten'), findsNothing);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('PK009 profile discard preserves changed input on return', (
    tester,
  ) async {
    final f = Fixture();
    await f.open(tester);
    await tester.enterText(field('Anzeigename'), 'Mein Entwurf');
    await tap(tester, find.text('Abbrechen'));
    await tap(tester, find.text('Weiterbearbeiten'));
    expect(
      tester.widget<TextField>(field('Anzeigename')).controller!.text,
      'Mein Entwurf',
    );
    expect(f.requests, isEmpty);
  });
  testWidgets('PK034 profile comparison and actions fit320px200percent', (
    tester,
  ) async {
    final f = Fixture();
    f.respond = (_) async => f.response({
      'children': [
        {...f.child, 'display_name': 'Zwischenänderung'},
      ],
    });
    await f.open(tester, width: 320, scale: 2);
    await tap(tester, find.text('Gespeicherten Stand vergleichen'));
    await tap(
      tester,
      find.text('Gespeicherten Stand in den Entwurf übernehmen'),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'PK032 already valid invitation does not create another mail request',
    (tester) async {
      final f = Fixture();
      addTearDown(() {
        f.state.inbox.dispose();
        f.state.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => inviteDialog(
                  c,
                  f.state,
                  knownInvitations: [
                    {
                      'email': 'synthetic@example.invalid',
                      'permission': 'view',
                      'expires':
                          DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                    },
                  ],
                ),
                child: const Text('Einladen'),
              ),
            ),
          ),
        ),
      );
      await tap(tester, find.text('Einladen'));
      await tester.enterText(
        field('E-Mail des Elternteils'),
        'SYNTHETIC@example.invalid',
      );
      await tap(tester, find.text('Einladung senden'));
      expect(
        find.textContaining('bereits eine Einladung offen'),
        findsOneWidget,
      );
      expect(f.requests, isEmpty);
    },
  );
}
