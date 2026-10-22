import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'parent_workflows_ux90_test.dart' as workflows;
import 'parent_messages_ux88_test.dart' show tap;

Future<void> reveal(WidgetTester t, Finder target) async {
  if (target.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      target,
      160,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 50,
    );
  }
  await t.ensureVisible(target);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'PK021 grade keyboard Next advances actual focus without saving',
    (t) async {
      final f = workflows.EditorFixture();
      await f.open(t);
      await t.enterText(workflows.field('Fach'), 'Mathematik');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pumpAndSettle();
      final editable = t.widget<EditableText>(
        find.descendant(
          of: workflows.field('Thema (optional)'),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PK041 removing one actual filter chip preserves the other applied grade filter',
    (t) async {
      final f = workflows.collection();
      f.state.collectionViews['parent-grades:child'] = {
        'q': 'Brüche',
        'source': 'pdf',
      };
      await f.mount(t, '/grades/child');
      await reveal(t, find.byTooltip('Filter „Suche: Brüche“ entfernen'));
      await tap(t, find.byTooltip('Filter „Suche: Brüche“ entfernen'));
      expect(f.requests.last.url.queryParameters.containsKey('q'), isFalse);
      expect(f.requests.last.url.queryParameters['source'], 'pdf');
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'PK018 confirmed grade deletion sends exactly the displayed revision',
    (t) async {
      final f = workflows.collection();
      f.gradeData['can_manage'] = true;
      f.gradeData['items'][0]['revision'] = 7;
      await f.mount(t, '/grades/child');
      await reveal(t, find.byTooltip('Note verwalten'));
      await tap(t, find.byTooltip('Note verwalten'));
      await tap(t, find.text('Entfernen'));
      await tap(t, find.widgetWithText(FilledButton, 'Entfernen'));
      await t.pumpAndSettle();
      final requests = f.requests.where((r) => r.method == 'DELETE').toList();
      expect(requests, hasLength(1));
      expect(requests.single.url.queryParameters['revision'], '7');
    },
  );
  testWidgets(
    'PK019 confirmed grade derived goal keeps the reviewed revision and no automatic generation',
    (t) async {
      final f = workflows.collection();
      f.gradeData['can_manage'] = true;
      f.gradeData['items'][0]['revision'] = 7;
      await f.mount(t, '/grades/child');
      await reveal(t, find.text('Passendes Lernziel anlegen'));
      await tap(t, find.text('Passendes Lernziel anlegen'));
      await tap(t, find.text('Lernziel anlegen'));
      await t.pumpAndSettle();
      final posts = f.requests.where((r) => r.method == 'POST').toList();
      expect(posts, hasLength(1));
      expect(posts.single.url.path, '/api/children/child/grades/grade/goal');
      expect(jsonDecode(posts.single.body), {'mandatory': true, 'revision': 7});
    },
  );
}
