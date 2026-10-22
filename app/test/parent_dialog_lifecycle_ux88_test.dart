import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/grades_screen.dart';
import 'package:schulpilot/grade_import_screen.dart';

import 'parent_cards_ux88_test.dart' as cards;
import 'parent_messages_ux88_test.dart' as messages;
import 'parent_pdf_filters_ux88_test.dart' as pdf;

void newer(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    DialogRoute<void>(
      context: context,
      builder: (_) =>
          const AlertDialog(title: Text('Unabhängige neue Ansicht')),
    ),
  );
}

void main() {
  testWidgets(
    'PP031 disposed message close callback preserves a newer dialog without ancestor lookup',
    (tester) async {
      final f = messages.Fixture();
      final context = await f.mount(tester);
      await messages.tap(tester, find.text('Künstliche Frage zu Brüchen'));
      final close = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Schließen'))
          .onPressed!;
      await messages.tap(tester, find.text('Schließen'));
      newer(context);
      await tester.pumpAndSettle();
      close();
      await tester.pumpAndSettle();
      expect(find.text('Unabhängige neue Ansicht'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP031 disposed grade close callback preserves a newer dialog without ancestor lookup',
    (tester) async {
      final f = cards.Fixture();
      await f.mount(tester, '/grades/child');
      await messages.tap(tester, find.text('Noteneintrag vollständig ansehen'));
      final close = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Schließen'))
          .onPressed!;
      await messages.tap(tester, find.text('Schließen'));
      newer(tester.element(find.byType(GradesScreen)));
      await tester.pumpAndSettle();
      close();
      await tester.pumpAndSettle();
      expect(find.text('Unabhängige neue Ansicht'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets(
    'PP031 disposed PDF comparison callback preserves a newer dialog without choosing a grade',
    (tester) async {
      final f = pdf.Fixture();
      await f.mount(tester);
      await pdf.tap(tester, find.text('Vorhandene Noten vergleichen'));
      final close = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Vergleich schließen'),
          )
          .onPressed!;
      await pdf.tap(tester, find.text('Vergleich schließen'));
      newer(tester.element(find.byType(GradePdfImport)));
      await tester.pumpAndSettle();
      close();
      await tester.pumpAndSettle();
      expect(find.text('Unabhängige neue Ansicht'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(f.requests, hasLength(1));
    },
  );
}
