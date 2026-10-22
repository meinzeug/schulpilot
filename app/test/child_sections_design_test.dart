import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:go_router/go_router.dart';
import 'package:schulpilot/child_account.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_messages.dart';
import 'package:schulpilot/child_section_ui.dart';
import 'package:schulpilot/ui.dart';

import 'vocabulary_test.dart' as words;

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'Child mailbox separates wishes and resolved help at $width and 200%',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = AppState()
          ..user = {
            'id': 'synthetic',
            'role': 'child',
            'child_id': 'child',
            'families': [],
          };
        final composed = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1000),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ChildMessagesHub(
                      state,
                      data: {
                        'child': {'id': 'child'},
                        'messages': [
                          {
                            'id': 'reply',
                            'kind': 'reply',
                            'sender_role': 'parent',
                            'resolved': false,
                            'body': 'Wir schauen gemeinsam darauf.',
                          },
                          {
                            'id': 'help',
                            'kind': 'help',
                            'sender_role': 'child',
                            'resolved': false,
                            'body': 'Kannst du mir helfen?',
                          },
                          {
                            'id': 'wish',
                            'kind': 'interest',
                            'sender_role': 'child',
                            'resolved': false,
                            'body': 'Ich möchte Planeten verstehen.',
                          },
                          {
                            'id': 'removed-context',
                            'kind': 'reply',
                            'sender_role': 'parent',
                            'resolved': false,
                            'body': 'Ein alter Materialverweis.',
                            'context_unavailable': true,
                            'context': {'unit_id': 'removed-round'},
                          },
                          {
                            'id': 'done',
                            'kind': 'help',
                            'sender_role': 'child',
                            'resolved': true,
                            'body': 'Diese Frage ist besprochen.',
                          },
                        ],
                      },
                      onCompose: (kind, _) async => composed.add(kind),
                      onWriteMessage: () async => composed.add('message'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Wir schauen gemeinsam darauf.'), findsOneWidget);
        expect(find.text('Kannst du mir helfen?'), findsOneWidget);
        expect(
          find.text('Der zugehörige Lernstoff ist nicht mehr verfügbar.'),
          findsOneWidget,
        );
        expect(find.text('Dazu ansehen'), findsNothing);
        expect(find.text('Ich möchte Planeten verstehen.'), findsNothing);
        expect(find.text('Diese Frage ist besprochen.'), findsNothing);
        await words.tap(tester, find.text('Meine Wünsche'));
        expect(find.text('Ich möchte Planeten verstehen.'), findsOneWidget);
        expect(find.text('Wir schauen gemeinsam darauf.'), findsNothing);
        expect(composed, isEmpty);
        await words.tap(tester, find.text('Das interessiert mich'));
        expect(composed, ['interest']);
        await words.tap(tester, find.text('Besprochen'));
        expect(find.text('Diese Frage ist besprochen.'), findsOneWidget);
        expect(find.text('Kannst du mir helfen?'), findsNothing);
        await words.tap(tester, find.text('Eltern live dazuholen'));
        expect(composed, ['interest', 'help']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.inbox.dispose();
        state.dispose();
      },
    );
  }

  for (final parent in [false, true]) {
    for (final status in ['not_started', 'paused']) {
      testWidgets(
        'A saved word round opens with one child start and read-only parent access ($parent, $status)',
        (tester) async {
          final requests = <http.Request>[];
          final data = words.listing();
          data['open_rounds'] = [
            {
              'id': 'saved-word-round',
              'topic': 'Gespeicherter Wortschatz',
              'status': status,
            },
          ];
          await words.open(
            tester,
            requests,
            width: 390,
            parent: parent,
            wordListing: data,
          );
          expect(requests.every((request) => request.method == 'GET'), isTrue);
          await words.tap(tester, find.text('Gespeicherter Wortschatz'));
          expect(find.text('Gespeicherte Wörterrunde'), findsOneWidget);
          expect(
            requests
                .where((request) => request.method == 'POST')
                .map((request) => request.url.path)
                .toList(),
            parent ? <String>[] : ['/api/units/saved-word-round/start'],
          );
          expect(
            requests.where((request) => request.url.path.endsWith('/rounds')),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Late current-device logout cannot clear a different child account',
    (tester) async {
      final deleting = Completer<http.Response>();
      final state =
          AppState(
              api: Api(
                base: 'https://example.invalid/api',
                client: MockClient((request) async {
                  if (request.method == 'DELETE') return deleting.future;
                  if (request.url.path.endsWith('/auth/sessions')) {
                    return http.Response(
                      jsonEncode([
                        {
                          'id': 'old-session',
                          'device': 'Künstliches Gerät',
                          'current': true,
                        },
                      ]),
                      200,
                      headers: {'content-type': 'application/json'},
                    );
                  }
                  return http.Response(
                    '{"items":[],"unread_count":0}',
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }),
              ),
            )
            ..user = {
              'id': 'old-child',
              'role': 'child',
              'child_id': 'old-profile',
              'display_name': 'Künstliches Konto',
            };
      final router = GoRouter(
        initialLocation: '/account',
        routes: [
          GoRoute(path: '/account', builder: (_, _) => ChildAccount(state)),
          GoRoute(
            path: '/login',
            builder: (_, _) => const Scaffold(body: Text('Anmelden-Ziel')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Hier abmelden'));
      await tester.tap(find.text('Hier abmelden'));
      await tester.pump();
      state.user = {
        'id': 'new-child',
        'role': 'child',
        'child_id': 'new-profile',
        'display_name': 'Anderes künstliches Konto',
      };
      state.refreshState();
      await tester.pump();
      deleting.complete(http.Response('{}', 200));
      await tester.pumpAndSettle();
      expect(state.user?['id'], 'new-child');
      expect(find.text('Anmelden-Ziel'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.inbox.dispose();
      state.dispose();
    },
  );

  testWidgets('Word review navigation does not reveal words or create rounds', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await words.open(tester, requests, width: 390);
    expect(find.text('Apfel'), findsOneWidget);
    await words.tap(tester, find.text('Prüfen'));
    expect(find.text('Apfel'), findsNothing);
    expect(
      find.text(
        'Alles geprüft. Neue Wortpaare kannst du im Wortschatz hinzufügen.',
      ),
      findsOneWidget,
    );
    await words.tap(tester, find.text('Wortschatz'));
    expect(find.text('Apfel'), findsOneWidget);
    expect(find.text('apple'), findsNothing);
    expect(requests.every((request) => request.method == 'GET'), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'Shared child controls use the $brightness palette at double text size',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness: brightness),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ChildSectionHero(
                          eyebrow: 'Lernen',
                          title: 'Dein nächster Schritt',
                          description: 'Ein kurzer Schritt mit deinem bestätigten Stoff.',
                          icon: Icons.auto_stories_rounded,
                        ),
                        const SizedBox(height: 20),
                        ChildSectionTabs(
                          tabs: const [
                            (
                              id: 'open',
                              label: 'Offen',
                              icon: Icons.play_arrow_rounded,
                            ),
                            (
                              id: 'done',
                              label: 'Erledigt',
                              icon: Icons.task_alt_rounded,
                            ),
                          ],
                          selected: 'open',
                          onSelected: (_) {},
                        ),
                        const SizedBox(height: 20),
                        ChildActionTile(
                          key: const ValueKey('palette-tile'),
                          title: 'Deine Runde',
                          subtitle: 'Hier kannst du weiterlernen.',
                          icon: Icons.play_circle_fill_rounded,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final palette = tester.element(find.byType(ChildSectionHero)).palette;
        expect(palette.isDark, brightness == Brightness.dark);
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byKey(const ValueKey('palette-tile')),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, palette.panelSurface);
        for (final label in ['Offen', 'Erledigt']) {
          final button = tester.widget<OutlinedButton>(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byType(OutlinedButton),
                )
                .first,
          );
          final background = button.style!.backgroundColor!.resolve({})!;
          final foreground = DefaultTextStyle.of(
            tester.element(find.text(label)),
          ).style.color!;
          final a = background.computeLuminance(),
              b = foreground.computeLuminance();
          expect(
            ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Child section tabs keep readable rendered states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: ChildSectionTabs(
            tabs: const [
              (
                id: 'open',
                label: 'Offen',
                icon: Icons.play_circle_outline_rounded,
              ),
              (id: 'done', label: 'Erledigt', icon: Icons.task_alt_rounded),
            ],
            selected: 'open',
            onSelected: (_) {},
          ),
        ),
      ),
    );
    for (final label in ['Offen', 'Erledigt']) {
      final control = tester.widget<OutlinedButton>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(OutlinedButton),
            )
            .first,
      );
      final background = control.style!.backgroundColor!.resolve({})!;
      final foreground = DefaultTextStyle.of(tester.element(find.text(label)))
          .style
          .color!;
      final brighter =
          background.computeLuminance() > foreground.computeLuminance()
          ? background
          : foreground;
      final darker = brighter == background ? foreground : background;
      expect(
        (brighter.computeLuminance() + .05) / (darker.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(OutlinedButton),
                  )
                  .first,
            )
            .height,
        greaterThanOrEqualTo(52),
      );
    }
  });
}
