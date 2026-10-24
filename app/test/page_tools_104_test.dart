import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/admin_workspace_ui.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_section_ui.dart';
import 'package:schulpilot/page_tools.dart';
import 'package:schulpilot/parent_workspace_ui.dart';
import 'package:schulpilot/ui.dart';

import 'page_tools_104_test_helpers.dart';

const _body = ValueKey('page-tools-body:filters');
const _field = ValueKey('synthetic-tool-draft');
const _open = ValueKey('page-tools-open:filters');
const _close = ValueKey('page-tools-close:filters');

class _Fixture {
  final AppState state;
  final GoRouter router;
  final GlobalKey<_TestPageState> page;
  final List<String> requests;
  _Fixture(this.state, this.router, this.page, this.requests);
}

Future<void> _surface(
  WidgetTester tester,
  Future<void> Function(_Fixture fixture) run, {
  double width = 390,
  double scale = 1,
  String header = 'plain',
  bool showGroup = true,
  bool active = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  final requests = <String>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add('${request.method} ${request.url.path}');
              expect(request.method, 'GET');
              return http.Response(
                jsonEncode({'available': false}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-owner-a',
          'role': header == 'admin'
              ? 'admin'
              : header == 'parent'
              ? 'parent'
              : 'child',
          'child_id': 'synthetic-child',
          'display_name': 'Kunstkonto',
          'real_data_enabled': true,
          'families': [
            {'id': 'synthetic-family-a', 'permission': 'owner'},
          ],
        }
        ..familyId = 'synthetic-family-a';
  state.api.token = 'synthetic-session-a';
  final page = GlobalKey<_TestPageState>();
  final router = GoRouter(
    initialLocation: '/page',
    routes: [
      GoRoute(
        path: '/page',
        builder: (context, _) => _TestPage(
          key: page,
          state: state,
          header: header,
          showGroup: showGroup,
          active: active,
        ),
      ),
      GoRoute(
        path: '/cover',
        builder: (context, _) => const Scaffold(
          body: Center(child: Text('Andere Seite', key: ValueKey('cover'))),
        ),
      ),
    ],
  );
  try {
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await run(_Fixture(state, router, page, requests));
    expect(tester.takeException(), isNull);
  } finally {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    router.dispose();
    state.inbox.dispose();
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

class _TestPage extends StatefulWidget {
  final AppState state;
  final String header;
  final bool showGroup, active;
  const _TestPage({
    super.key,
    required this.state,
    required this.header,
    required this.showGroup,
    required this.active,
  });
  @override
  State<_TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<_TestPage> {
  final controller = TextEditingController();
  final group = GlobalKey();
  late bool showGroup = widget.showGroup;
  bool allowed = true;
  Object scope = 'synthetic-source-a';
  void change(VoidCallback callback) => setState(callback);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget heading;
    switch (widget.header) {
      case 'child':
        heading = const ChildSectionHero(
          eyebrow: 'Lernen',
          title: 'Gespeicherte Lerninhalte',
          description: 'Künstliche Inhalte für diesen lokalen Test.',
          icon: Icons.menu_book_outlined,
        );
      case 'parent':
        heading = const ParentWorkspaceHero(
          eyebrow: 'Eltern',
          title: 'Lernübersicht',
          subtitle: 'Künstliche Inhalte für diesen lokalen Test.',
        );
      case 'admin':
        heading = const AdminWorkspaceHeader(
          title: 'Betriebsübersicht',
          subtitle: 'Künstliche Inhalte für diesen lokalen Test.',
          currentPath: '/admin',
        );
      default:
        heading = const Row(
          children: [
            Expanded(child: Text('Künstlicher Bereich')),
            PageToolsButton(),
          ],
        );
    }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header != 'default') heading,
        const Text('Hauptinhalt bleibt zuerst sichtbar'),
        if (showGroup)
          PageToolsGroup(
            key: group,
            id: 'filters',
            title: 'Suche und Filter',
            summary: 'Lokale Beispielwerkzeuge',
            active: widget.active,
            scope: scope,
            isCurrent: () =>
                mounted &&
                allowed &&
                ModalRoute.of(context)?.isCurrent != false,
            child: _ToolForm(controller: controller),
          ),
      ],
    );
    if (widget.header == 'plain') {
      return PageToolsHost(
        state: widget.state,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: content,
          ),
        ),
      );
    }
    return PageFrame(
      state: widget.state,
      title: 'Künstlicher Bereich',
      showTitle: widget.header == 'default',
      // A hidden default title must not add a second menu for supplied actions.
      actions: [
        IconButton(
          tooltip: 'Künstliche Hauptaktion',
          onPressed: () {},
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: content,
    );
  }
}

class _ToolForm extends StatefulWidget {
  final TextEditingController controller;
  const _ToolForm({required this.controller});
  @override
  State<_ToolForm> createState() => _ToolFormState();
}

class _ToolFormState extends State<_ToolForm> {
  final focus = FocusNode();
  String selected = 'all';
  DateTime? date;
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: _field,
        focusNode: focus,
        controller: widget.controller,
        decoration: const InputDecoration(labelText: 'Privater Entwurf'),
      ),
      DropdownButtonFormField<String>(
        key: const ValueKey('synthetic-tool-dropdown'),
        initialValue: selected,
        isExpanded: true,
        items: const [
          DropdownMenuItem(value: 'all', child: Text('Alle Einträge')),
          DropdownMenuItem(value: 'saved', child: Text('Gespeichert')),
        ],
        onChanged: (value) {
          if (value != null) setState(() => selected = value);
        },
      ),
      TextButton(
        key: const ValueKey('synthetic-tool-date'),
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime(2026, 10, 24),
            firstDate: DateTime(2026),
            lastDate: DateTime(2027),
          );
          if (mounted && picked != null) setState(() => date = picked);
        },
        child: Text(date == null ? 'Datum wählen' : 'Datum ausgewählt'),
      ),
    ],
  );
}

bool _hidden(WidgetTester tester) =>
    tester.widget<Offstage>(find.byKey(_body, skipOffstage: false)).offstage;

void main() {
  testWidgets('104 no registered groups means no reserved menu or toolbar', (
    tester,
  ) async {
    await _surface(tester, (fixture) async {
      expect(find.byKey(const ValueKey('page-tools-button')), findsNothing);
      expect(find.text('Hauptinhalt bleibt zuerst sichtbar'), findsOneWidget);
      expect(fixture.requests, isEmpty);
    }, showGroup: false);
  });

  for (final header in ['default', 'child', 'parent', 'admin']) {
    testWidgets(
      '104 $header has exactly one tools entry at 320px and 200 percent',
      (tester) async {
        await _surface(
          tester,
          (fixture) async {
            final button = find.byKey(const ValueKey('page-tools-button'));
            expect(button, findsOneWidget);
            expect(
              tester.getSize(button).shortestSide,
              greaterThanOrEqualTo(48),
            );
            expect(_hidden(tester), isTrue);
            expect(find.byType(ExpansionTile), findsNothing);
            final before = List<String>.from(fixture.requests);
            await openPageTool104(tester, 'filters');
            expect(_hidden(tester), isFalse);
            expect(fixture.requests, before);
            await closePageTool104(tester, 'filters');
            expect(_hidden(tester), isTrue);
            expect(fixture.requests, before);
          },
          header: header,
          width: 320,
          scale: 2,
        );
      },
    );
  }

  testWidgets(
    '104 body state draft focus semantics survive a deliberate collapse',
    (tester) async {
      await _surface(tester, (fixture) async {
        final semantics = tester.ensureSemantics();
        try {
          final original = tester.state<_ToolFormState>(
            find.byType(_ToolForm, skipOffstage: false),
          );
          expect(find.byKey(_field), findsNothing);
          expect(find.bySemanticsLabel('Privater Entwurf'), findsNothing);
          await openPageTool104(tester, 'filters');
          await tester.enterText(find.byKey(_field), 'Nur lokaler Entwurf');
          original.focus.requestFocus();
          await tester.pump();
          expect(original.focus.hasFocus, isTrue);
          await closePageTool104(tester, 'filters');
          expect(original.focus.hasFocus, isFalse);
          expect(find.bySemanticsLabel('Privater Entwurf'), findsNothing);
          expect(
            tester.state<_ToolFormState>(
              find.byType(_ToolForm, skipOffstage: false),
            ),
            same(original),
          );
          expect(
            fixture.page.currentState!.controller.text,
            'Nur lokaler Entwurf',
          );
          await openPageTool104(tester, 'filters');
          expect(
            tester.widget<TextField>(find.byKey(_field)).controller!.text,
            'Nur lokaler Entwurf',
          );
          expect(fixture.requests, isEmpty);
        } finally {
          semantics.dispose();
        }
      });
    },
  );

  testWidgets('104 same-scope data reload restores only explicit open state', (
    tester,
  ) async {
    await _surface(tester, (fixture) async {
      await openPageTool104(tester, 'filters');
      await tester.enterText(find.byKey(_field), 'Entwurf des Seitenowners');
      fixture.page.currentState!.change(
        () => fixture.page.currentState!.showGroup = false,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-tools-button')), findsNothing);
      fixture.page.currentState!.change(
        () => fixture.page.currentState!.showGroup = true,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_open), findsOneWidget);
      expect(_hidden(tester), isFalse);
      expect(
        tester.widget<TextField>(find.byKey(_field)).controller!.text,
        'Entwurf des Seitenowners',
      );
      await closePageTool104(tester, 'filters');
      fixture.page.currentState!.change(
        () => fixture.page.currentState!.showGroup = false,
      );
      await tester.pumpAndSettle();
      fixture.page.currentState!.change(
        () => fixture.page.currentState!.showGroup = true,
      );
      await tester.pumpAndSettle();
      expect(_hidden(tester), isTrue);
      expect(fixture.requests, isEmpty);
    });
  });

  testWidgets(
    '104 actual dropdown and date picker return retain the open form',
    (tester) async {
      await _surface(tester, (fixture) async {
        await openPageTool104(tester, 'filters');
        final form = tester.state<_ToolFormState>(find.byType(_ToolForm));
        await tester.enterText(find.byKey(_field), 'Bleibt beim Datumsdialog');
        await tester.tap(find.byKey(const ValueKey('synthetic-tool-dropdown')));
        await tester.pumpAndSettle();
        expect(
          PageToolsHost.isMenuCovering(
            fixture.state,
            ModalRoute.of(fixture.page.currentContext!),
          ),
          isFalse,
        );
        await tester.tap(find.text('Gespeichert').last);
        await tester.pumpAndSettle();
        expect(find.byKey(_open), findsOneWidget);
        expect(form.selected, 'saved');
        expect(
          tester.state<_ToolFormState>(find.byType(_ToolForm)),
          same(form),
        );
        final cancel = MaterialLocalizations.of(form.context).cancelButtonLabel;
        await tester.tap(find.byKey(const ValueKey('synthetic-tool-date')));
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        expect(
          PageToolsHost.isMenuCovering(
            fixture.state,
            ModalRoute.of(fixture.page.currentContext!),
          ),
          isFalse,
        );
        await tester.tap(find.widgetWithText(TextButton, cancel));
        await tester.pumpAndSettle();
        expect(find.byKey(_open), findsOneWidget);
        expect(form.date, isNull);
        expect(form.widget.controller.text, 'Bleibt beim Datumsdialog');
        expect(fixture.requests, isEmpty);
      });
    },
  );

  testWidgets(
    '104 programmatic open requires a current registered descendant context',
    (tester) async {
      await _surface(tester, (fixture) async {
        final page = fixture.page.currentState!;
        expect(PageToolsHost.open(page.context, 'filters'), isFalse);
        expect(
          PageToolsHost.open(page.group.currentContext!, 'missing'),
          isFalse,
        );
        expect(
          PageToolsHost.open(page.group.currentContext!, 'filters'),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(_hidden(tester), isFalse);
        page.change(() => page.allowed = false);
        await tester.pumpAndSettle();
        expect(_hidden(tester), isTrue);
        expect(
          PageToolsHost.open(page.group.currentContext!, 'filters'),
          isFalse,
        );
        expect(fixture.requests, isEmpty);
      });
    },
  );

  testWidgets('104 active filter metadata does not auto-open its form', (
    tester,
  ) async {
    await _surface(tester, (fixture) async {
      expect(_hidden(tester), isTrue);
      await tester.tap(find.byKey(const ValueKey('page-tools-button')));
      await tester.pumpAndSettle();
      expect(find.text('Lokale Beispielwerkzeuge'), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt_rounded), findsOneWidget);
      final hostRoute = ModalRoute.of(fixture.page.currentContext!);
      expect(PageToolsHost.isMenuCovering(fixture.state, hostRoute), isTrue);
      expect(PageToolsHost.isMenuCovering(fixture.state, null), isFalse);
      await tester.tap(find.byTooltip('Seitenoptionen schließen'));
      await tester.pumpAndSettle();
      expect(PageToolsHost.isMenuCovering(fixture.state, hostRoute), isFalse);
      expect(_hidden(tester), isTrue);
      expect(fixture.requests, isEmpty);
    }, active: true);
  });

  for (final change in ['account', 'token', 'family', 'revision', 'source']) {
    testWidgets('104 saved menu callback is rejected after $change changes', (
      tester,
    ) async {
      await _surface(tester, (fixture) async {
        await tester.tap(find.byKey(const ValueKey('page-tools-button')));
        await tester.pumpAndSettle();
        final old = tester
            .widget<ListTile>(
              find.byKey(const ValueKey('page-tools-choice:filters')),
            )
            .onTap!;
        switch (change) {
          case 'account':
            fixture.state.user = {
              ...fixture.state.user!,
              'id': 'synthetic-owner-b',
            };
            fixture.state.refreshState();
          case 'token':
            fixture.state.api.token = 'synthetic-session-b';
            fixture.state.refreshState();
          case 'family':
            fixture.state.familyId = 'synthetic-family-b';
            fixture.state.refreshState();
          case 'revision':
            fixture.state.refreshState();
          case 'source':
            fixture.page.currentState!.change(
              () => fixture.page.currentState!.scope = 'synthetic-source-b',
            );
        }
        await tester.pumpAndSettle();
        old();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('page-tools-menu')), findsNothing);
        expect(_hidden(tester), isTrue);
        expect(fixture.requests, isEmpty);
      });
    });
  }

  testWidgets('104 stale close cannot close a new opening after scope change', (
    tester,
  ) async {
    await _surface(tester, (fixture) async {
      await openPageTool104(tester, 'filters');
      final old = tester.widget<IconButton>(find.byKey(_close)).onPressed!;
      final page = fixture.page.currentState!;
      page.change(() => page.scope = 'synthetic-source-b');
      await tester.pumpAndSettle();
      expect(_hidden(tester), isTrue);
      await openPageTool104(tester, 'filters');
      old();
      await tester.pumpAndSettle();
      expect(_hidden(tester), isFalse);
      await closePageTool104(tester, 'filters');
      expect(_hidden(tester), isTrue);
    });
  });

  testWidgets(
    '104 foreign route invalidates commands but retains local form state',
    (tester) async {
      await _surface(tester, (fixture) async {
        await openPageTool104(tester, 'filters');
        final oldClose = tester
            .widget<IconButton>(find.byKey(_close))
            .onPressed!;
        final form = tester.state<_ToolFormState>(find.byType(_ToolForm));
        await tester.enterText(find.byKey(_field), 'Seitenentwurf');
        fixture.router.push('/cover');
        await tester.pumpAndSettle();
        oldClose();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('cover')), findsOneWidget);
        expect(
          PageToolsHost.isMenuCovering(
            fixture.state,
            ModalRoute.of(fixture.page.currentContext!),
          ),
          isFalse,
        );
        fixture.router.pop();
        await tester.pumpAndSettle();
        expect(_hidden(tester), isFalse);
        expect(
          tester.state<_ToolFormState>(find.byType(_ToolForm)),
          same(form),
        );
        oldClose();
        await tester.pumpAndSettle();
        expect(_hidden(tester), isFalse);
        await closePageTool104(tester, 'filters');
        expect(_hidden(tester), isTrue);
        expect(form.widget.controller.text, 'Seitenentwurf');
        expect(fixture.requests, isEmpty);
      });
    },
  );

  testWidgets('104 lifecycle change during menu exit prevents late opening', (
    tester,
  ) async {
    await _surface(tester, (fixture) async {
      await tester.tap(find.byKey(const ValueKey('page-tools-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('page-tools-choice:filters')));
      await tester.pump(const Duration(milliseconds: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(_hidden(tester), isTrue);
      expect(find.byKey(const ValueKey('page-tools-menu')), findsNothing);
      expect(fixture.requests, isEmpty);
    });
  });

  testWidgets(
    '104 standalone fallback preserves draft and invalidates old scope callbacks',
    (tester) async {
      final controller = TextEditingController();
      final allowed = ValueNotifier(true);
      addTearDown(controller.dispose);
      addTearDown(allowed.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: allowed,
              builder: (context, value, _) => PageToolsGroup(
                id: 'filters',
                title: 'Suche und Filter',
                scope: value,
                isCurrent: () => allowed.value,
                child: TextField(key: _field, controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-tools-button')), findsNothing);
      final fallback = find.byKey(
        const ValueKey('page-tools-fallback:filters'),
      );
      await tester.tap(fallback);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_field), 'Lokaler Fallbackentwurf');
      final old = tester.widget<ExpansionTile>(fallback).onExpansionChanged!;
      allowed.value = false;
      await tester.pumpAndSettle();
      old(true);
      await tester.pumpAndSettle();
      expect(_hidden(tester), isTrue);
      expect(controller.text, 'Lokaler Fallbackentwurf');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
