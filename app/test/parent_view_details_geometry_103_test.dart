import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/parent_view_details.dart';

import 'parent_saved_tools_ux90_test.dart' as saved;

const _title = 'Suche & Themenfilter';
const _subtitle = 'Geladene Themen';
const _draftKey = ValueKey('optional-parent-draft');
Future<void> _toggle(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final title = find.text(_title);
  await tester.ensureVisible(title);
  await tester.pumpAndSettle();
  expect(title.hitTestable(), findsOneWidget);
  await tester.tap(title);
  await tester.pumpAndSettle();
}

Finder _draft({bool hidden = false}) =>
    find.byKey(_draftKey, skipOffstage: !hidden);
Finder _editable({bool hidden = false}) => find.descendant(
  of: _draft(hidden: hidden),
  matching: find.byType(EditableText, skipOffstage: !hidden),
  skipOffstage: !hidden,
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
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
      testWidgets(
        '103 parent two-line tools remain compact and preserve draft/focus at $width/$scale',
        (tester) async {
          final f = saved.Fixture();
          final controller = TextEditingController();
          try {
            await f.mount(
              tester,
              (_) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ParentViewDetails(
                  title: _title,
                  subtitle: _subtitle,
                  scope: (
                    ObjectKey(f.state.user),
                    f.state.familyId,
                    'synthetic-child',
                  ),
                  isCurrent: () => f.state.isParent,
                  children: [
                    TextField(
                      key: _draftKey,
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Lokaler Entwurf',
                      ),
                    ),
                  ],
                ),
              ),
              width: width,
              scale: scale,
            );
            final tile = find.byType(ExpansionTile);
            final rect = tester.getRect(tile);
            expect(rect.height, greaterThanOrEqualTo(48));
            if (scale == 1) {
              expect(rect.height, lessThanOrEqualTo(56));
            } else {
              expect(rect.height, greaterThan(56));
            }
            final title = tester.widget<Text>(find.text(_title));
            final subtitle = tester.widget<Text>(find.text(_subtitle));
            expect(title.style!.fontSize, 16);
            expect(subtitle.style!.fontSize, 14);
            expect(title.style!.height, 1.2);
            expect(subtitle.style!.height, 1.2);
            expect(title.maxLines, isNull);
            expect(subtitle.maxLines, isNull);
            for (final text in [find.text(_title), find.text(_subtitle)]) {
              final textRect = tester.getRect(text);
              expect(textRect.top, greaterThanOrEqualTo(rect.top));
              expect(textRect.bottom, lessThanOrEqualTo(rect.bottom));
              expect(textRect.left, greaterThanOrEqualTo(rect.left));
              expect(textRect.right, lessThanOrEqualTo(rect.right));
            }
            expect(_draft(), findsNothing);
            expect(tester.widget<ExpansionTile>(tile).maintainState, isTrue);
            await _toggle(tester);
            final element = tester.element(_draft());
            await tester.enterText(_draft(), 'Künstlicher Suchentwurf');
            await _toggle(tester);
            expect(_draft(), findsNothing);
            expect(tester.element(_draft(hidden: true)), same(element));
            final hiddenEditable = tester.widget<EditableText>(
              _editable(hidden: true),
            );
            expect(hiddenEditable.focusNode.canRequestFocus, isFalse);
            expect(hiddenEditable.focusNode.hasFocus, isFalse);
            expect(controller.text, 'Künstlicher Suchentwurf');
            await _toggle(tester);
            expect(tester.element(_draft()), same(element));
            expect(
              tester
                  .widget<EditableText>(_editable())
                  .focusNode
                  .canRequestFocus,
              isTrue,
            );
            expect(controller.text, 'Künstlicher Suchentwurf');
            expect(f.requests, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
          }
        },
      );
    }
  }
  testWidgets(
    '103 stale parent tool callback cannot alter the new child but its current control works',
    (tester) async {
      final f = saved.Fixture();
      final child = ValueNotifier('synthetic-child-a');
      try {
        await f.mount(
          tester,
          (_) => SingleChildScrollView(
            child: ValueListenableBuilder<String>(
              valueListenable: child,
              builder: (_, id, _) => ParentViewDetails(
                title: _title,
                subtitle: _subtitle,
                scope: (ObjectKey(f.state.user), f.state.familyId, id),
                isCurrent: () => f.state.isParent && child.value == id,
                children: [Text('Werkzeug für $id')],
              ),
            ),
          ),
        );
        await _toggle(tester);
        final old = tester
            .widget<ExpansionTile>(find.byType(ExpansionTile))
            .onExpansionChanged!;
        child.value = 'synthetic-child-b';
        await tester.pumpAndSettle();
        old(true);
        await tester.pumpAndSettle();
        expect(find.text('Werkzeug für synthetic-child-a'), findsNothing);
        expect(find.text('Werkzeug für synthetic-child-b'), findsNothing);
        await _toggle(tester);
        expect(find.text('Werkzeug für synthetic-child-b'), findsOneWidget);
        old(false);
        await tester.pumpAndSettle();
        expect(find.text('Werkzeug für synthetic-child-b'), findsOneWidget);
        expect(f.requests, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        child.dispose();
      }
    },
  );
  testWidgets(
    '103 parent tool storage restores only its existing scope and closed fields stay unfocusable',
    (tester) async {
      final f = saved.Fixture();
      final view = ValueNotifier((true, 'synthetic-child-a'));
      final controller = TextEditingController();
      try {
        await f.mount(
          tester,
          (_) => SingleChildScrollView(
            child: ValueListenableBuilder<(bool, String)>(
              valueListenable: view,
              builder: (_, value, _) => !value.$1
                  ? const SizedBox()
                  : ParentViewDetails(
                      title: _title,
                      subtitle: _subtitle,
                      scope: (
                        ObjectKey(f.state.user),
                        f.state.familyId,
                        value.$2,
                      ),
                      isCurrent: () =>
                          f.state.isParent && view.value.$2 == value.$2,
                      children: [
                        TextField(key: _draftKey, controller: controller),
                      ],
                    ),
            ),
          ),
        );
        await _toggle(tester);
        await tester.enterText(_draft(), 'Lokaler Entwurf');
        view.value = (false, 'synthetic-child-a');
        await tester.pumpAndSettle();
        view.value = (true, 'synthetic-child-a');
        await tester.pumpAndSettle();
        expect(_draft(), findsOneWidget);
        expect(controller.text, 'Lokaler Entwurf');
        view.value = (true, 'synthetic-child-b');
        await tester.pumpAndSettle();
        expect(_draft(), findsNothing);
        expect(
          tester
              .widget<EditableText>(_editable(hidden: true))
              .focusNode
              .canRequestFocus,
          isFalse,
        );
        expect(f.requests, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        view.dispose();
        controller.dispose();
      }
    },
  );
}
