import 'dart:convert';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/schulbuddy.dart';
import 'package:schulpilot/ui.dart';

const _bodyKey = ValueKey('heading-test-content');
const _subtitle = 'Nur bereits gespeicherte Übungsbelege.';
Finder _heading() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_WorkspaceHeading',
);
Finder _insideHeading(Finder target) =>
    find.descendant(of: _heading(), matching: target);

Future<void> _workspace(
  WidgetTester tester, {
  required String title,
  required List<Widget> actions,
  required double width,
  required double scale,
  bool focusContent = false,
  bool throughPageFrame = false,
  bool showTitle = true,
  bool demo = false,
  bool realDataEnabled = true,
  EdgeInsets? safePadding,
  WidgetBuilder? contentBuilder,
  required Future<void> Function(List<http.Request>) check,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  final requests = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              return http.Response(
                jsonEncode({
                  'items': [],
                  'unread_count': 0,
                  'available': false,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-heading-child',
          'role': 'child',
          'child_id': 'child',
          'display_name': 'Beispiel',
          'real_data_enabled': realDataEnabled,
          'synthetic': demo,
        };
  final router = GoRouter(
    initialLocation: '/progress/child',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) =>
            const Scaffold(body: Text('Kontoeinstellungen geöffnet')),
      ),
      GoRoute(
        path: '/library/child',
        builder: (_, _) => const Scaffold(body: Text('Fachsammlung geöffnet')),
      ),
      GoRoute(
        path: '/progress/:id',
        builder: (context, _) {
          final content =
              contentBuilder?.call(context) ??
              const SizedBox(key: _bodyKey, height: 24);
          return throughPageFrame
              ? PageFrame(
                  state: state,
                  title: title,
                  subtitle: _subtitle,
                  actions: actions,
                  focusContent: focusContent,
                  showTitle: showTitle,
                  child: content,
                )
              : WorkspaceShell(
                  state: state,
                  title: title,
                  subtitle: _subtitle,
                  actions: actions,
                  browser: true,
                  focusContent: focusContent,
                  showTitle: showTitle,
                  child: content,
                );
        },
      ),
    ],
  );
  try {
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: safePadding,
            viewPadding: safePadding,
          ),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await check(requests);
  } finally {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    state.inbox.dispose();
    state.familyCalls.dispose();
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in ['Nunito', 'Roboto']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
    }
  });
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final title in [
        'Übungsbelege',
        'Gespeicherte Übungsbelege aus deinen bisherigen Lernrunden',
      ]) {
        testWidgets(
          '103 single icon shares the heading at $width/$scale/$title',
          (tester) async {
            final semantics = tester.ensureSemantics();
            final focus = FocusNode();
            var refreshes = 0;
            try {
              await _workspace(
                tester,
                title: title,
                width: width,
                scale: scale,
                actions: [
                  IconButton(
                    focusNode: focus,
                    tooltip: 'Übungsbelege aktualisieren',
                    onPressed: () => refreshes++,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
                check: (requests) async {
                  final titleFinder = _insideHeading(find.text(title));
                  final action = _insideHeading(
                    find.byTooltip('Übungsbelege aktualisieren'),
                  );
                  final headerRect = tester.getRect(_heading());
                  final titleRect = tester.getRect(titleFinder);
                  final actionRect = tester.getRect(action);
                  final subtitleRect = tester.getRect(
                    _insideHeading(find.text(_subtitle)),
                  );
                  expect(actionRect.top, closeTo(titleRect.top, .01));
                  expect(
                    actionRect.left,
                    greaterThanOrEqualTo(titleRect.right + 8 - .01),
                  );
                  expect(actionRect.right, lessThanOrEqualTo(headerRect.right));
                  expect(actionRect.width, greaterThanOrEqualTo(48));
                  expect(actionRect.height, greaterThanOrEqualTo(48));
                  expect(
                    tester.getTopLeft(find.byKey(_bodyKey)).dy,
                    closeTo(headerRect.bottom + 16, .01),
                  );
                  expect(
                    headerRect.bottom,
                    closeTo(
                      subtitleRect.bottom > actionRect.bottom
                          ? subtitleRect.bottom
                          : actionRect.bottom,
                      .01,
                    ),
                  );
                  expect(
                    tester
                        .getSemantics(titleFinder)
                        .getSemanticsData()
                        .flagsCollection
                        .isHeader,
                    isTrue,
                  );
                  final semanticAction = find.semantics.byPredicate((node) {
                    final data = node.getSemanticsData();
                    return data.flagsCollection.isButton &&
                        data.hasAction(SemanticsAction.tap) &&
                        '${data.label} ${data.tooltip}'.contains(
                          'Übungsbelege aktualisieren',
                        );
                  });
                  expect(semanticAction, findsOneWidget);
                  final data = semanticAction
                      .evaluate()
                      .single
                      .getSemanticsData();
                  expect(data.flagsCollection.isButton, isTrue);
                  expect(
                    '${data.label} ${data.tooltip}',
                    contains('Übungsbelege aktualisieren'),
                  );
                  expect(data.hasAction(SemanticsAction.tap), isTrue);
                  expect(action.hitTestable(), findsOneWidget);
                  expect(refreshes, 0);
                  await tester.tap(action);
                  await tester.pumpAndSettle();
                  expect(refreshes, 1);
                  focus.requestFocus();
                  await tester.pump();
                  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
                  await tester.pumpAndSettle();
                  expect(refreshes, 2);
                  tester.semantics.tap(semanticAction);
                  await tester.pumpAndSettle();
                  expect(refreshes, 3);
                  expect(
                    requests.every((request) => request.method == 'GET'),
                    isTrue,
                  );
                  expect(tester.takeException(), isNull);
                },
              );
            } finally {
              focus.dispose();
              semantics.dispose();
            }
          },
        );
      }
    }
  }
  for (final multiple in [false, true]) {
    testWidgets(
      '103 ${multiple ? 'multiple icon' : 'text'} actions retain their mobile row',
      (tester) async {
        var activations = 0;
        await _workspace(
          tester,
          title: 'Gespeicherte Übungsbelege',
          width: 320,
          scale: 2,
          actions: multiple
              ? [
                  IconButton(
                    tooltip: 'Aktualisieren',
                    onPressed: () => activations++,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Weitere Werkzeuge',
                    onPressed: () {},
                    icon: const Icon(Icons.more_horiz),
                  ),
                ]
              : [
                  OutlinedButton(
                    onPressed: () => activations++,
                    child: const Text('Auswahl bewusst öffnen'),
                  ),
                ],
          check: (requests) async {
            final action = _insideHeading(
              multiple
                  ? find.byTooltip('Aktualisieren')
                  : find.byType(OutlinedButton),
            );
            expect(
              tester.getTopLeft(action).dy,
              greaterThanOrEqualTo(
                tester.getBottomLeft(_insideHeading(find.text(_subtitle))).dy +
                    12,
              ),
            );
            expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(action.hitTestable(), findsOneWidget);
            await tester.tap(action);
            await tester.pumpAndSettle();
            expect(activations, 1);
            expect(
              requests.every((request) => request.method == 'GET'),
              isTrue,
            );
            expect(tester.takeException(), isNull);
          },
        );
      },
    );
  }
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '103 focused PageFrame keeps mobile child content and back at $width/$scale',
        (tester) async {
          var actions = 0;
          const safe = EdgeInsets.fromLTRB(6, 24, 7, 20);
          await _workspace(
            tester,
            title: 'Beispielheft',
            width: width,
            scale: scale,
            actions: const [],
            focusContent: true,
            throughPageFrame: true,
            showTitle: false,
            demo: true,
            safePadding: safe,
            contentBuilder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Zur Fachsammlung',
                      onPressed: () => context.go('/library/child'),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const Expanded(child: Text('Beispielheft')),
                    IconButton(
                      tooltip: 'Textseite hinzufügen',
                      onPressed: () => actions++,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const Text('Gespeicherte Beispielseite'),
              ],
            ),
            check: (requests) async {
              expect(
                tester
                    .widget<WorkspaceShell>(find.byType(WorkspaceShell))
                    .focusContent,
                isTrue,
              );
              expect(find.byType(AppBar), findsNothing);
              expect(find.byType(NavigationBar), findsNothing);
              expect(
                find.byKey(const ValueKey('workspace-context-return')),
                findsNothing,
              );
              expect(find.byKey(const ValueKey('account-menu')), findsNothing);
              expect(find.byType(SchulbuddyButton), findsNothing);
              expect(find.text('Demo · nur Beispieldaten'), findsOneWidget);
              expect(
                find.text('Gespeicherte Beispielseite').hitTestable(),
                findsOneWidget,
              );
              final body = tester.widget<Scaffold>(find.byType(Scaffold)).body!;
              expect(body, isA<SafeArea>());
              final safeContent = find
                  .descendant(
                    of: find.byWidget(body),
                    matching: find.byType(Row),
                  )
                  .first;
              final safeRect = tester.getRect(safeContent);
              expect(safeRect.top, closeTo(safe.top, .01));
              expect(safeRect.bottom, closeTo(1000 - safe.bottom, .01));
              expect(safeRect.left, closeTo(safe.left, .01));
              expect(safeRect.right, closeTo(width - safe.right, .01));
              final scroll = find.byKey(const ValueKey('workspace-scroll'));
              final scrollRect = tester.getRect(scroll);
              expect(scrollRect.top, closeTo(safeRect.top, .01));
              expect(scrollRect.bottom, lessThanOrEqualTo(safeRect.bottom));
              expect(scrollRect.left, greaterThanOrEqualTo(safeRect.left));
              expect(scrollRect.right, lessThanOrEqualTo(safeRect.right));
              final actualContent = tester.getRect(
                find.text('Gespeicherte Beispielseite'),
              );
              expect(actualContent.top, greaterThanOrEqualTo(safeRect.top));
              expect(actualContent.bottom, lessThanOrEqualTo(safeRect.bottom));
              expect(
                (tester.widget<SingleChildScrollView>(scroll).padding!
                        as EdgeInsets)
                    .top,
                8,
              );
              for (final name in ['Zur Fachsammlung', 'Textseite hinzufügen']) {
                final target = find.byTooltip(name);
                expect(target.hitTestable(), findsOneWidget);
                expect(
                  tester.getSize(target).shortestSide,
                  greaterThanOrEqualTo(48),
                );
              }
              await tester.tap(find.byTooltip('Textseite hinzufügen'));
              await tester.pumpAndSettle();
              expect(actions, 1);
              await tester.tap(find.byTooltip('Zur Fachsammlung'));
              await tester.pumpAndSettle();
              expect(find.text('Fachsammlung geöffnet'), findsOneWidget);
              expect(
                requests.every((request) => request.method == 'GET'),
                isTrue,
              );
              expect(tester.takeException(), isNull);
            },
          );
        },
      );
    }
    testWidgets('103 default mobile chrome is retained at $width', (
      tester,
    ) async {
      await _workspace(
        tester,
        title: 'Standardansicht',
        width: width,
        scale: 1,
        actions: const [],
        check: (requests) async {
          expect(
            tester
                .widget<WorkspaceShell>(find.byType(WorkspaceShell))
                .focusContent,
            isFalse,
          );
          expect(find.byType(AppBar), findsOneWidget);
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(
            find.byKey(const ValueKey('workspace-context-return')),
            findsNothing,
          );
          expect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.byTooltip('Zu Lernen'),
            ),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('account-menu')), findsOneWidget);
          expect(
            (tester
                        .widget<SingleChildScrollView>(
                          find.byKey(const ValueKey('workspace-scroll')),
                        )
                        .padding!
                    as EdgeInsets)
                .top,
            12,
          );
          expect(requests.every((request) => request.method == 'GET'), isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    });
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '103 desktop focus keeps the rail while removing duplicate chrome at $scale',
      (tester) async {
        Rect? original;
        for (final focused in [false, true]) {
          await _workspace(
            tester,
            title: 'Desktopansicht',
            width: 1280,
            scale: scale,
            focusContent: focused,
            actions: const [],
            contentBuilder: (_) =>
                const Text('Fokussierter Beispielinhalt', key: _bodyKey),
            check: (requests) async {
              expect(
                find.byKey(const ValueKey('workspace-sidebar')),
                findsOneWidget,
              );
              expect(find.byType(NavigationRail), findsOneWidget);
              expect(
                find.byKey(const ValueKey('workspace-brand-home')),
                findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('workspace-header')),
                focused ? findsNothing : findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('account-menu')),
                focused ? findsNothing : findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('workspace-context-return')),
                focused ? findsNothing : findsOneWidget,
              );
              final content = tester.getRect(find.byKey(_bodyKey));
              expect(find.byKey(_bodyKey).hitTestable(), findsOneWidget);
              if (focused) {
                expect(content.top, lessThan(original!.top));
              } else {
                original = content;
              }
              expect(
                (tester
                            .widget<SingleChildScrollView>(
                              find.byKey(const ValueKey('workspace-scroll')),
                            )
                            .padding!
                        as EdgeInsets)
                    .top,
                16,
              );
              if (focused) {
                await tester.sendKeyEvent(LogicalKeyboardKey.f1);
                await tester.pumpAndSettle();
                expect(find.text('Tastatur & Bedienung'), findsOneWidget);
                await tester.tap(find.widgetWithText(TextButton, 'Schließen'));
                await tester.pumpAndSettle();
                final account = find.descendant(
                  of: find.byKey(const ValueKey('workspace-sidebar')),
                  matching: find.byTooltip('Konto'),
                );
                expect(account.hitTestable(), findsOneWidget);
                await tester.tap(account);
                await tester.pumpAndSettle();
                expect(
                  find.text('Kontoeinstellungen geöffnet'),
                  findsOneWidget,
                );
              }
              expect(
                requests.every((request) => request.method == 'GET'),
                isTrue,
              );
              expect(tester.takeException(), isNull);
            },
          );
        }
      },
    );
  }
  testWidgets('103 focused mobile keeps the real-data test warning', (
    tester,
  ) async {
    await _workspace(
      tester,
      title: 'Testansicht',
      width: 320,
      scale: 2,
      actions: const [],
      focusContent: true,
      realDataEnabled: false,
      check: (requests) async {
        expect(
          find.text(
            'Testbetrieb · Bitte noch keine echten Kinderdaten eingeben.',
          ),
          findsOneWidget,
        );
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        expect(requests.every((request) => request.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });
  testWidgets('103 focused mobile retains keyboard help and skip to content', (
    tester,
  ) async {
    await _workspace(
      tester,
      title: 'Fokusansicht',
      width: 390,
      scale: 1,
      actions: const [],
      focusContent: true,
      check: (requests) async {
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await tester.pumpAndSettle();
        expect(find.text('Tastatur & Bedienung'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Schließen'));
        await tester.pumpAndSettle();
        final skip = find.byKey(const ValueKey('workspace-skip'));
        tester.widget<FilledButton>(skip).focusNode!.requestFocus();
        await tester.pumpAndSettle();
        expect(skip.hitTestable(), findsOneWidget);
        await tester.tap(skip);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Hauptinhalt');
        expect(requests.every((request) => request.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
