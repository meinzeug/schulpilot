import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'material_confirm_next_141_test.dart' as f;

void main() {
  testWidgets(
    'automatic countercheck updates the open page without a POST or navigation',
    (tester) async {
      final fixture = f.Fixture();
      fixture.pages[1]['material_review'] = {
        'mode': 'automatic',
        'status': 'checking',
      };
      await fixture.open(tester);
      expect(
        find.textContaining('Die KI gleicht Foto und Abschrift ab.'),
        findsOneWidget,
      );
      final location = fixture.location;
      fixture.pages[1] = {
        ...fixture.pages[1],
        'revision': 2,
        'confirmed': true,
        'status': 'confirmed',
        'material_review': {'mode': 'automatic', 'status': 'checked'},
      };
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Foto und Abschrift automatisch abgeglichen.'),
        findsOneWidget,
      );
      expect(fixture.location, location);
      expect(fixture.writes, isEmpty);
      final reads = fixture.calls.length;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(fixture.calls.length, reads);
      await fixture.close(tester);
    },
  );

  testWidgets('a local correction survives the arriving countercheck', (
    tester,
  ) async {
    final fixture = f.Fixture();
    fixture.pages[1]['material_review'] = {
      'mode': 'automatic',
      'status': 'checking',
    };
    fixture.pages[1]['synthetic'] = false;
    await fixture.open(tester);
    await f.tap(tester, 'Etwas verbessern');
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Text auf der Seite',
    );
    await tester.ensureVisible(field);
    await tester.enterText(
      field,
      'Meine eigene noch nicht gespeicherte Korrektur.',
    );
    fixture.pages[1] = {
      ...fixture.pages[1],
      'revision': 2,
      'confirmed': true,
      'status': 'confirmed',
      'material_review': {'mode': 'automatic', 'status': 'checked'},
    };
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Deine Korrektur bleibt hier erhalten'),
      findsOneWidget,
    );
    expect(
      find.text('Meine eigene noch nicht gespeicherte Korrektur.'),
      findsOneWidget,
    );
    expect(fixture.writes, isEmpty);
    await fixture.close(tester);
  });

  testWidgets('the status observer stops while a different route is visible', (
    tester,
  ) async {
    final fixture = f.Fixture();
    fixture.pages[1]['material_review'] = {
      'mode': 'automatic',
      'status': 'checking',
    };
    await fixture.open(tester);
    fixture.router.go('/elsewhere');
    await tester.pumpAndSettle();
    final reads = fixture.calls.length;
    await tester.pump(const Duration(seconds: 15));
    expect(fixture.calls.length, reads);
    expect(fixture.writes, isEmpty);
    await fixture.close(tester);
  });
}
