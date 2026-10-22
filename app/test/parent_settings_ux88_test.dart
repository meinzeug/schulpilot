import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/ui.dart';

import 'settings_safety_test.dart' as safe;

class Fixture {
  final requests = <http.Request>[];
  final parents = <Json>[
    {
      'id': 'member-me',
      'display_name': 'Gleicher Name',
      'permission': 'owner',
      'self': true,
    },
    {
      'id': 'member-other',
      'display_name': 'Gleicher Name',
      'permission': 'view',
      'self': false,
    },
  ];
  final children = <Json>[
    {
      'id': 'child-a',
      'display_name': 'Künstliches Kind A',
      'username': 'synthetic-child-a',
      'grade': 7,
      'subjects': ['Mathematik'],
      'school_type': 'Künstliche Schulform',
      'region': '',
    },
  ];
  final invites = <Json>[
    {
      'id': 'invite-a',
      'email': 'synthetic@example.invalid',
      'permission': 'view',
      'expires': 1792670400,
    },
  ];
  final devices = <Json>[
    {
      'id': 'parent-device-a',
      'device': 'Gleicher Browser',
      'current': false,
      'created': 1792497600,
      'seen': 1792670400,
    },
    {
      'id': 'parent-device-b',
      'device': 'Gleicher Browser',
      'current': true,
      'created': 1792324800,
      'seen': 1792584000,
    },
  ];
  Future<http.Response?> Function(http.Request)? respond;
  late final state = safe.stateFor((r) async {
    requests.add(r);
    final custom = await respond?.call(r);
    if (custom != null) return custom;
    if (r.method != 'GET') return safe.response({});
    if (r.url.path.endsWith('/auth/sessions')) return safe.response(devices);
    if (r.url.path.endsWith('/children/child-a/sessions')) {
      return safe.response([
        {
          'id': 'child-device-a',
          'device': 'Kinder Tablet',
          'created': 1792497600,
          'seen': 1792670400,
        },
      ]);
    }
    if (r.url.path.endsWith('/members')) {
      return safe.response(parents);
    }
    if (r.url.path.endsWith('/invitations')) {
      return safe.response(invites);
    }
    if (r.url.path.endsWith('/families/family-a')) {
      return safe.response({'children': children});
    }
    if (r.url.path.endsWith('/usage')) {
      return safe.response({
        'calls_remaining': 9,
        'calls_limit': 10,
        'plan': 'Künstlicher Tarif',
        'period': '2026-10',
        'budget_remaining_micros_usd': 1000000,
        'unknown_cost_calls': 0,
        'cost_notice': 'Künstliche Nutzungsangabe.',
      });
    }
    if (r.url.path.endsWith('/devices')) {
      return safe.response([]);
    }
    return safe.response({'available': false});
  });
  Future<GoRouter> mount(
    WidgetTester tester, {
    String section = 'account',
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/settings?section=$section',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, r) => SettingsScreen(
            state,
            initialSection: r.uri.queryParameters['section'],
          ),
        ),
        GoRoute(
          path: '/child/:id',
          builder: (_, r) => Scaffold(
            body: Text('Eigenes Lernziel ${r.pathParameters['id']}'),
          ),
        ),
        GoRoute(
          path: '/app',
          builder: (_, _) => const Scaffold(body: Text('Eigene Familie')),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(() {
      state.inbox.dispose();
      state.dispose();
    });
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Finder action(String label) => find.widgetWithText(ActionButton, label).first;
Finder confirm(String label) => find.widgetWithText(FilledButton, label).last;
void main() {
  testWidgets(
    'PP009 deep links open only a permitted settings section, no mutations',
    (tester) async {
      final f = Fixture();
      final router = await f.mount(tester, section: 'data');
      expect(find.text('Deine Familiendaten'), findsOneWidget);
      expect(find.text('Angemeldete Geräte'), findsNothing);
      router.go('/settings?section=family');
      await tester.pumpAndSettle();
      expect(find.text('Kinderzugänge verwalten'), findsOneWidget);
      router.go('/settings?section=unknown');
      await tester.pumpAndSettle();
      expect(find.text('Angemeldete Geräte'), findsOneWidget);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets(
    'PP009 a settings data link without a family falls back to account',
    (tester) async {
      final f = Fixture();
      f.state.familyId = null;
      await f.mount(tester, section: 'data');
      expect(find.text('Angemeldete Geräte'), findsOneWidget);
      expect(find.text('Deine Familiendaten'), findsNothing);
      expect(f.requests.any((r) => r.url.path.endsWith('/usage')), isFalse);
    },
  );
  testWidgets(
    'PP010 equal device names retain distinct created and seen times',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      expect(find.text('Gleicher Browser'), findsNWidgets(2));
      expect(find.textContaining('Angemeldet: 20.10.2026'), findsOneWidget);
      expect(find.textContaining('Zuletzt aktiv: 22.10.2026'), findsOneWidget);
      expect(find.textContaining('Zuletzt aktiv: 21.10.2026'), findsOneWidget);
    },
  );
  testWidgets(
    'PP011 other parent device needs exact confirmation; cancel sends nothing',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tap(tester, action('Gerät abmelden'));
      expect(find.text('Dieses Gerät abmelden?'), findsOneWidget);
      expect(
        find.textContaining('Gleicher Browser\nAngemeldet:'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(TextButton, 'Abbrechen'));
      expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
      await tap(tester, action('Gerät abmelden'));
      await tap(tester, confirm('Gerät abmelden'));
      final deleted = f.requests.where((r) => r.method == 'DELETE').single;
      expect(deleted.url.path, '/api/auth/sessions/parent-device-a');
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    },
  );
  testWidgets(
    'PP012 child device names child and device before exactly one removal',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, section: 'family');
      await tap(tester, action('Kindergerät abmelden'));
      expect(
        find.textContaining('Künstliches Kind A · Kinder Tablet'),
        findsOneWidget,
      );
      expect(find.textContaining('Zuletzt aktiv:'), findsWidgets);
      await tap(tester, find.widgetWithText(TextButton, 'Abbrechen'));
      expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
      await tap(tester, action('Kindergerät abmelden'));
      await tap(tester, confirm('Kindergerät abmelden'));
      expect(
        f.requests.where((r) => r.method == 'DELETE').single.url.path,
        '/api/children/child-a/sessions/child-device-a',
      );
    },
  );
  testWidgets('PP013 open invitation reveals its actual expiry', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester, section: 'family');
    expect(find.textContaining('Gültig bis 22.10.2026'), findsOneWidget);
    expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
  });
  testWidgets(
    'PP014 invitation removal confirms exact address and permission',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, section: 'family');
      await tap(tester, action('Einladung widerrufen'));
      expect(
        find.textContaining('synthetic@example.invalid mit Leserechten'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(TextButton, 'Abbrechen'));
      expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
      await tap(tester, action('Einladung widerrufen'));
      await tap(tester, confirm('Einladung widerrufen'));
      expect(
        f.requests.where((r) => r.method == 'DELETE').single.url.path,
        '/api/families/family-a/invitations/invite-a',
      );
    },
  );
  testWidgets(
    'PP015 backend self marker identifies one of equal parent names',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, section: 'family');
      expect(find.text('Gleicher Name · Dein Zugang'), findsOneWidget);
      expect(find.text('Gleicher Name'), findsOneWidget);
    },
  );
  testWidgets(
    'PP016 empty child list names the state and offers the family route',
    (tester) async {
      final f = Fixture();
      f.children.clear();
      await f.mount(tester, section: 'family');
      expect(
        find.text('Noch kein Kinderzugang in dieser Familie.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Zur Familienübersicht'));
      expect(find.text('Eigene Familie'), findsOneWidget);
    },
  );
  testWidgets('PP017 profile summary opens only the chosen child overview', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester, section: 'family');
    await tap(tester, find.text('Künstliches Kind A'));
    expect(find.text('Eigenes Lernziel child-a'), findsOneWidget);
    expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
  });
  testWidgets(
    'PP018 child profile shows known grade and school without inventing absent details',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, section: 'family');
      expect(find.text('Klasse 7'), findsOneWidget);
      expect(find.text('Künstliche Schulform'), findsOneWidget);
      expect(find.textContaining('Bundesland:'), findsNothing);
    },
  );
  testWidgets(
    'PP019 reset identifies the exact child before any password request',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, section: 'family');
      await tap(tester, action('Kinderpasswort erneuern'));
      expect(find.text('Kinderzugang: Künstliches Kind A'), findsOneWidget);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets('PP020 destructive child dialog shows exact name and login', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester, section: 'family');
    await tap(tester, action('Kinderkonto löschen'));
    expect(
      find.textContaining(
        'Künstliches Kind A · Benutzername: synthetic-child-a',
      ),
      findsOneWidget,
    );
    await tap(tester, find.text('Abbrechen'));
    expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
  });
  testWidgets(
    'PP021 password mismatch is local; exact repeated password alone is sent',
    (tester) async {
      final requests = <http.Request>[];
      final state = safe.stateFor((r) async {
        requests.add(r);
        return safe.response({});
      });
      await safe.mountDialog(
        tester,
        state,
        (c) => resetChildDialog(c, state, 'child-a', childName: 'Kind A'),
      );
      await tester.enterText(
        safe.field('Dein Elternpasswort'),
        'synthetic-parent-password',
      );
      await tester.enterText(
        safe.field('Neues Kinderpasswort'),
        ' synthetic-password ',
      );
      await tester.enterText(
        safe.field('Neues Kinderpasswort wiederholen'),
        'different-password',
      );
      await tap(tester, find.text('Passwort erneuern'));
      expect(
        find.text('Die neuen Passwörter müssen übereinstimmen.'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      await tester.enterText(
        safe.field('Neues Kinderpasswort wiederholen'),
        ' synthetic-password ',
      );
      await tap(tester, find.text('Passwort erneuern'));
      expect(
        jsonDecode(requests.single.body)['password'],
        ' synthetic-password ',
      );
      await safe.cleanup(tester, state);
    },
  );
  testWidgets(
    'PP022 password reveal is explicit, reversible and does not submit',
    (tester) async {
      final requests = <http.Request>[];
      final state = safe.stateFor((r) async {
        requests.add(r);
        return safe.response({});
      });
      await safe.mountDialog(tester, state, (c) async {
        await passwordDialog(c, 'Prüfen', 'Künstliche Änderung', state: state);
      });
      await tester.enterText(
        safe.field('Dein Elternpasswort'),
        ' exact-password ',
      );
      expect(
        tester.widget<TextField>(safe.field('Dein Elternpasswort')).obscureText,
        isTrue,
      );
      await tap(tester, find.byTooltip('Dein Elternpasswort anzeigen'));
      expect(
        tester.widget<TextField>(safe.field('Dein Elternpasswort')).obscureText,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(safe.field('Dein Elternpasswort'))
            .controller!
            .text,
        ' exact-password ',
      );
      await tap(tester, find.byTooltip('Dein Elternpasswort verbergen'));
      expect(
        tester.widget<TextField>(safe.field('Dein Elternpasswort')).obscureText,
        isTrue,
      );
      expect(requests, isEmpty);
      await safe.cleanup(tester, state);
    },
  );
  testWidgets(
    'PP023 overlong parent password is rejected without silent truncation',
    (tester) async {
      final requests = <http.Request>[];
      final state = safe.stateFor((r) async {
        requests.add(r);
        return safe.response({});
      });
      await safe.mountDialog(tester, state, (c) async {
        await passwordDialog(
          c,
          'Prüfen',
          'Künstliche Änderung',
          state: state,
          confirm: (password) async {
            await state.api.delete('/synthetic-check', {'password': password});
          },
        );
      });
      await tester.enterText(safe.field('Dein Elternpasswort'), 'a' * 129);
      await tap(tester, find.text('Mit Passwort bestätigen'));
      expect(find.text('Nutze höchstens 128 Zeichen.'), findsOneWidget);
      expect(requests, isEmpty);
      expect(
        tester
            .widget<TextField>(safe.field('Dein Elternpasswort'))
            .controller!
            .text
            .length,
        129,
      );
      await tester.enterText(safe.field('Dein Elternpasswort'), 'a' * 128);
      await tap(tester, find.text('Mit Passwort bestätigen'));
      expect(jsonDecode(requests.single.body)['password'], 'a' * 128);
      await safe.cleanup(tester, state);
    },
  );
  for (final email in ['kein-at', 'a@', 'a @example.invalid']) {
    testWidgets('PP024 malformed invitation email stays local: $email', (
      tester,
    ) async {
      final requests = <http.Request>[];
      final state = safe.stateFor((r) async {
        requests.add(r);
        return safe.response({});
      });
      await safe.mountDialog(tester, state, (c) => inviteDialog(c, state));
      await tester.enterText(safe.field('E-Mail des Elternteils'), email);
      await tap(tester, find.text('Einladung senden'));
      expect(
        find.text('Prüfe die E-Mail-Adresse, zum Beispiel name@anbieter.de.'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      await safe.cleanup(tester, state);
    });
  }
  testWidgets('PP025 invitation explains both existing role scopes', (
    tester,
  ) async {
    final state = safe.stateFor((_) async => safe.response({}));
    await safe.mountDialog(tester, state, (c) => inviteDialog(c, state));
    expect(
      find.textContaining(
        'Nur lesen: Lernstand, Pläne und Nachrichten ansehen.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Verwalten: zusätzlich Kinderangaben'),
      findsOneWidget,
    );
    await safe.cleanup(tester, state);
  });
  for (final label in [
    'Anzeigename',
    'Schulform (optional)',
    'Bundesland (optional)',
  ]) {
    testWidgets(
      'PP026 profile field preserves overlong $label without a request',
      (tester) async {
        final requests = <http.Request>[];
        final state = safe.stateFor((r) async {
          requests.add(r);
          return safe.response({});
        });
        await safe.mountDialog(
          tester,
          state,
          (c) => editChildDialog(c, state, Fixture().children.single),
        );
        await tester.enterText(safe.field(label), 'a' * 81);
        await tap(tester, find.text('Speichern'));
        expect(
          find.text('Nutze für $label höchstens 80 Zeichen.'),
          findsOneWidget,
        );
        expect(requests, isEmpty);
        expect(
          tester.widget<TextField>(safe.field(label)).controller!.text.length,
          81,
        );
        await safe.cleanup(tester, state);
      },
    );
  }
  testWidgets(
    'PP027 twenty-one subjects stay local, twenty are accepted unchanged',
    (tester) async {
      final requests = <http.Request>[];
      final state = safe.stateFor((r) async {
        requests.add(r);
        return safe.response({});
      });
      await safe.mountDialog(
        tester,
        state,
        (c) => editChildDialog(c, state, Fixture().children.single),
      );
      await tester.enterText(
        safe.field('Fächer (mit Komma trennen)'),
        List.generate(21, (i) => 'Fach $i').join(', '),
      );
      await tap(tester, find.text('Speichern'));
      expect(
        find.text('Du kannst höchstens 20 Fächer angeben.'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      final twenty = List.generate(20, (i) => 'Fach $i');
      await tester.enterText(
        safe.field('Fächer (mit Komma trennen)'),
        twenty.join(', '),
      );
      await tap(tester, find.text('Speichern'));
      expect(jsonDecode(requests.single.body)['subjects'], twenty);
      await safe.cleanup(tester, state);
    },
  );
  testWidgets('PP028 success feedback waits for confirmed completion', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final state = safe.stateFor((_) => pending.future);
    await safe.mountDialog(tester, state, (c) => inviteDialog(c, state));
    await tester.enterText(
      safe.field('E-Mail des Elternteils'),
      'synthetic@example.invalid',
    );
    await tester.tap(find.text('Einladung senden'));
    await tester.pump();
    expect(
      find.text('Einladung gesendet. Sie bleibt zwei Tage gültig.'),
      findsNothing,
    );
    pending.complete(safe.response({}));
    await tester.pumpAndSettle();
    expect(
      find.text('Einladung gesendet. Sie bleibt zwei Tage gültig.'),
      findsOneWidget,
    );
    await safe.cleanup(tester, state);
  });
  testWidgets(
    'PP029 successful empty invitations have an honest separate empty state',
    (tester) async {
      final f = Fixture();
      f.invites.clear();
      await f.mount(tester, section: 'family');
      expect(find.text('Offene Einladungen'), findsOneWidget);
      expect(find.text('Zurzeit ist keine Einladung offen.'), findsOneWidget);
      expect(find.textContaining('nicht geladen'), findsNothing);
    },
  );
  testWidgets(
    'PP031 covered parent setting callbacks never pop a newer independent dialog or submit',
    (tester) async {
      final requests = <http.Request>[];
      final state = safe.stateFor((r) async {
        requests.add(r);
        return safe.response({});
      });
      await safe.mountDialog(tester, state, (c) => inviteDialog(c, state));
      await tester.enterText(
        safe.field('E-Mail des Elternteils'),
        'synthetic@example.invalid',
      );
      final send = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Einladung senden'),
          )
          .onPressed!;
      final cancel = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Abbrechen'))
          .onPressed!;
      final ctx = tester.element(find.byType(AlertDialog));
      Navigator.of(ctx).push(
        DialogRoute<void>(
          context: ctx,
          builder: (_) =>
              const AlertDialog(title: Text('Neuere unabhängige Ansicht')),
        ),
      );
      await tester.pumpAndSettle();
      send();
      cancel();
      await tester.pumpAndSettle();
      expect(find.text('Neuere unabhängige Ansicht'), findsOneWidget);
      expect(requests, isEmpty);
      await safe.cleanup(tester, state);
    },
  );
  testWidgets(
    'PP031 successful parent setting removes only its own covered dialog',
    (tester) async {
      final pending = Completer<http.Response>();
      final state = safe.stateFor((_) => pending.future);
      await safe.mountDialog(tester, state, (c) => inviteDialog(c, state));
      await tester.enterText(
        safe.field('E-Mail des Elternteils'),
        'synthetic@example.invalid',
      );
      await tester.tap(find.text('Einladung senden'));
      await tester.pump();
      final ctx = tester.element(find.byType(AlertDialog));
      Navigator.of(ctx).push(
        DialogRoute<void>(
          context: ctx,
          builder: (_) =>
              const AlertDialog(title: Text('Neuere unabhängige Ansicht')),
        ),
      );
      await tester.pumpAndSettle();
      pending.complete(safe.response({}));
      await tester.pumpAndSettle();
      expect(find.text('Neuere unabhängige Ansicht'), findsOneWidget);
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      await safe.cleanup(tester, state);
    },
  );
}
