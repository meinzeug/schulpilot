import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/admin_workspace_ui.dart';
import 'package:schulpilot/child_section_ui.dart';
import 'package:schulpilot/parent_workspace_ui.dart';
import 'package:schulpilot/ui.dart';

import 'workspace_tools_100_test.dart' as workspace_fixture;

Future<void> surface(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '102 parent refresh is beside its actual heading at $width x $scale',
        (tester) async {
          var refreshes = 0;
          final focus = FocusNode();
          addTearDown(focus.dispose);
          const sectionKey = ValueKey('inline-parent-section');
          const nextKey = ValueKey('next-parent-content');
          await surface(
            tester,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ParentSectionHeading(
                  key: sectionKey,
                  title: 'Deine Kinder',
                  icon: Icons.diversity_1_rounded,
                  action: IconButton(
                    focusNode: focus,
                    tooltip: 'Aktualisieren',
                    onPressed: () => refreshes++,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
                const Text('Mika (Beispiel)', key: nextKey),
              ],
            ),
            width: width,
            scale: scale,
          );
          final title = tester.getRect(find.text('Deine Kinder'));
          final refresh = tester.getRect(find.byTooltip('Aktualisieren'));
          final section = tester.getRect(find.byKey(sectionKey));
          expect(refresh.top, lessThan(title.bottom));
          expect(refresh.left, greaterThanOrEqualTo(title.right));
          expect(refresh.right, lessThanOrEqualTo(section.right));
          expect(refresh.width, greaterThanOrEqualTo(48));
          expect(refresh.height, greaterThanOrEqualTo(48));
          final rowHeight = title.height > refresh.height
              ? title.height
              : refresh.height;
          expect(
            tester.getTopLeft(find.byKey(nextKey)).dy - section.top,
            closeTo(rowHeight + 12, .01),
            reason: 'Refresh shares the title row instead of adding another action row.',
          );
          expect(refreshes, 0);
          focus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(refreshes, 1);
          await tester.tap(find.byTooltip('Aktualisieren'));
          await tester.pumpAndSettle();
          expect(refreshes, 2);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      '102 long parent actions remain separate and readable at $width',
      (tester) async {
        var activations = 0;
        await surface(
          tester,
          ParentSectionHeading(
            title: 'Gespeicherte Themen',
            subtitle: 'Bestätigte Inhalte bleiben vollständig zugänglich.',
            icon: Icons.topic_outlined,
            action: OutlinedButton(
              onPressed: () => activations++,
              child: const Text(
                'Alle gespeicherten Themen ausdrücklich öffnen',
              ),
            ),
          ),
          width: width,
          scale: 2,
        );
        final action = find.byType(OutlinedButton);
        expect(
          tester.getTopLeft(action).dy,
          greaterThanOrEqualTo(
            tester
                .getBottomLeft(
                  find.text(
                    'Bestätigte Inhalte bleiben vollständig zugänglich.',
                  ),
                )
                .dy,
          ),
        );
        expect(tester.getSize(action).width, lessThanOrEqualTo(width - 32));
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        expect(activations, 0);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(activations, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('102 shared surfaces use compact readable insets at $width', (
      tester,
    ) async {
      const body = ValueKey('panel-body');
      await surface(
        tester,
        const Panel(
          child: SizedBox(key: body, height: 40, width: double.infinity),
        ),
        width: width,
      );
      final card = find.byType(Card);
      final expected = width < 720 ? 16.0 : 18.0;
      expect(
        tester.getTopLeft(find.byKey(body)).dx - tester.getTopLeft(card).dx,
        closeTo(expected, .01),
      );
      expect(
        tester.getTopLeft(find.byKey(body)).dy - tester.getTopLeft(card).dy,
        closeTo(expected, .01),
      );
      final shape =
          Theme.of(tester.element(card)).cardTheme.shape!
              as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16));
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 1280.0]) {
    testWidgets('102 action surface keeps deliberate activation at $width', (
      tester,
    ) async {
      var activations = 0;
      const body = ValueKey('action-body');
      await surface(
        tester,
        ActionPanel(
          actionLabel: 'Gespeicherten Inhalt öffnen',
          onPressed: () => activations++,
          child: const Text('Bestätigter Inhalt', key: body),
        ),
        width: width,
        scale: 2,
      );
      final card = find.byType(Card);
      expect(
        tester.getTopLeft(find.byKey(body)).dx - tester.getTopLeft(card).dx,
        closeTo(width < 720 ? 16 : 18, .01),
      );
      expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
      expect(activations, 0);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(activations, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('102 explicitly supplied panel padding remains explicit', (
    tester,
  ) async {
    const body = ValueKey('explicit-body');
    await surface(
      tester,
      const Panel(
        padding: EdgeInsets.all(24),
        child: SizedBox(key: body, width: double.infinity, height: 24),
      ),
      width: 320,
    );
    expect(
      tester.getTopLeft(find.byKey(body)).dx -
          tester.getTopLeft(find.byType(Card)).dx,
      24,
    );
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets('102 button targets grow with 200 percent text at $width', (
      tester,
    ) async {
      var activations = 0;
      await surface(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: () => activations++,
              child: const Text('Eine bewusste Aktion mit langer Beschriftung'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => activations++,
              child: const Text('Vorhandene Auswahl öffnen'),
            ),
          ],
        ),
        width: width,
        scale: 2,
      );
      for (final button in [
        find.byType(FilledButton),
        find.byType(OutlinedButton),
      ]) {
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        final label = find.descendant(of: button, matching: find.byType(Text));
        expect(
          tester.getSize(button).height,
          greaterThan(tester.getSize(label).height),
        );
      }
      expect(activations, 0);
      await tester.tap(find.byType(FilledButton));
      expect(activations, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final role in ['child', 'parent', 'admin']) {
      testWidgets('102 $role heading retains detail and actions at $width', (
        tester,
      ) async {
        var activations = 0;
        final action = FilledButton(
          onPressed: () => activations++,
          child: const Text('Bewusst fortsetzen'),
        );
        final Widget header;
        switch (role) {
          case 'child':
            header = ChildSectionHero(
              eyebrow: 'Lernbereich',
              title: 'Gespeicherte Lerninhalte',
              compactTitle: 'Lernbereich',
              description: 'Vorhandene bestätigte Inhalte bleiben erreichbar.',
              icon: Icons.auto_stories_rounded,
              action: action,
              facts: const [Text('Gespeicherter Fakt')],
            );
          case 'parent':
            header = ParentWorkspaceHero(
              eyebrow: 'Familienbereich',
              title: 'Gespeicherte Lerninhalte',
              subtitle: 'Vorhandene bestätigte Inhalte bleiben erreichbar.',
              actions: [action],
              facts: const [Text('Gespeicherter Fakt')],
            );
          default:
            header = const AdminWorkspaceHeader(
              title: 'Gespeicherte Betriebsdaten',
              subtitle: 'Vorhandene bestätigte Inhalte bleiben erreichbar.',
              currentPath: '/admin',
            );
        }
        await surface(tester, header, width: width, scale: 2);
        expect(tester.takeException(), isNull);
        {
          final info = find.byTooltip('Über diesen Bereich');
          expect(tester.getSize(info).shortestSide, greaterThanOrEqualTo(48));
          expect(
            find.text('Vorhandene bestätigte Inhalte bleiben erreichbar.'),
            findsNothing,
          );
          await tester.tap(info);
          await tester.pumpAndSettle();
        }
        expect(
          find.text('Vorhandene bestätigte Inhalte bleiben erreichbar.'),
          findsOneWidget,
        );
        if (role != 'admin') {
          expect(find.text('Gespeicherter Fakt'), findsOneWidget);
          final button = find.widgetWithText(
            FilledButton,
            'Bewusst fortsetzen',
          );
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          expect(activations, 0);
          await tester.tap(button);
          expect(activations, 1);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [720.0, 1280.0]) {
    for (final role in ['child', 'parent', 'admin']) {
      testWidgets('102 $role tools share the desktop header at $width', (
        tester,
      ) async {
        await workspace_fixture.workspace(
          tester,
          (state, router) async {
            final header = find.byKey(const ValueKey('workspace-header'));
            final content = find.byKey(const ValueKey('workspace-content'));
            final area = find.byKey(const ValueKey('workspace-area-switch'));
            final help = find.byTooltip('Tastatur & Bedienung');
            expect(find.descendant(of: header, matching: area), findsOneWidget);
            expect(find.descendant(of: content, matching: area), findsNothing);
            expect(find.descendant(of: header, matching: help), findsOneWidget);
            expect(tester.getSize(area).height, greaterThanOrEqualTo(48));
            expect(tester.getSize(help).height, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
            await tester.tap(area);
            await tester.pumpAndSettle();
            expect(find.text('Bereich wechseln'), findsOneWidget);
            state.api.token = 'another-synthetic-token';
            state.refreshState();
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(
              router.routeInformationProvider.value.uri.path,
              role == 'admin' ? '/admin' : '/app',
            );
          },
          role: role,
          initial: role == 'admin' ? '/admin' : '/app',
          width: width,
          scale: 2,
        );
      });
    }
  }

  testWidgets('102 relocated desktop tools preserve draft and keyboard help', (
    tester,
  ) async {
    await workspace_fixture.workspace(tester, (state, router) async {
      final draft = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Eigener Entwurf',
      );
      await tester.enterText(draft, 'Erhaltener künstlicher Entwurf');
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.text('Tastatur & Bedienung'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Erhaltener künstlicher Entwurf'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/app');
      expect(tester.takeException(), isNull);
    }, width: 1280);
  });
}
