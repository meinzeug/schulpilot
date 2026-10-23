import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/settings_reading_tools.dart';
import 'package:schulpilot/ui.dart';

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '092 finder only searches supplied sections and resets with scope',
    (tester) async {
      final selected = <String>[];
      bool current = true;
      Widget finder(Object scope) => SettingsSectionFinder(
        sections: const [
          ('account', 'Mein Konto', Icons.person),
          ('devices', 'Angemeldete Geräte', Icons.devices),
        ],
        onSelected: selected.add,
        bindingKey: scope,
        isCurrent: () => current,
      );
      await mount(tester, finder('owner-a'));
      await tester.tap(find.text('Einstellungen finden'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Geräte');
      await tester.pumpAndSettle();
      expect(find.text('Mein Konto'), findsNothing);
      await tester.tap(find.text('Angemeldete Geräte'));
      await tester.pumpAndSettle();
      expect(selected, ['devices']);
      await tester.tap(find.text('Einstellungen finden'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'private');
      await tester.pumpAndSettle();
      expect(find.textContaining('Kein passender Abschnitt'), findsOneWidget);
      current = false;
      await mount(tester, finder('owner-b'));
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Einstellungen finden'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets('093 current other and unknown sessions remain distinct', (
    tester,
  ) async {
    await mount(
      tester,
      DeviceSessionGroups(
        sessions: const [
          {'device': 'A', 'current': true},
          {'device': 'B', 'current': false},
          {'device': 'C'},
        ],
        rowBuilder: (s) => Text(s['device']),
      ),
    );
    for (final label in [
      'Aktuelles Gerät (1)',
      'Weitere Geräte (1)',
      'Nicht zugeordnete Anmeldungen (1)',
      'A',
      'B',
      'C',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });
  testWidgets(
    '094 rights matrix distinguishes owner manager reader and unknown',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(
        tester,
        const FamilyRightsMatrix([
          {
            'display_name': 'Eigener Zugang',
            'permission': 'owner',
            'self': true,
          },
          {'display_name': 'Verwalter', 'permission': 'manage'},
          {'display_name': 'Leser', 'permission': 'view'},
          {'display_name': 'Unbekannt', 'permission': 'future'},
        ]),
      );
      expect(find.text('Eigener Zugang'), findsNothing);
      await tester.tap(find.text('Rechte im Vergleich'));
      await tester.pumpAndSettle();
      expect(find.text('Dein Zugang'), findsOneWidget);
      expect(find.text('Die Berechtigung ist nicht bekannt.'), findsOneWidget);
      expect(find.bySemanticsLabel('Einladen: erlaubt'), findsOneWidget);
      expect(find.bySemanticsLabel('Verwalten: erlaubt'), findsNWidgets(2));
      expect(find.bySemanticsLabel('Verwalten: nicht erlaubt'), findsOneWidget);
      semantics.dispose();
    },
  );
  testWidgets(
    '095 requirements reflect actual length and equality without submitting',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final password = TextEditingController(),
          repeated = TextEditingController();
      addTearDown(password.dispose);
      addTearDown(repeated.dispose);
      await mount(
        tester,
        PasswordRequirements(password: password, repeated: repeated),
      );
      expect(
        find.bySemanticsLabel('Mindestens 12 Zeichen: noch offen'),
        findsOneWidget,
      );
      password.text = 'synthetic-123';
      repeated.text = 'synthetic-123';
      await tester.pump();
      expect(
        find.bySemanticsLabel('Mindestens 12 Zeichen: erfüllt'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Passwörter stimmen überein: erfüllt'),
        findsOneWidget,
      );
      password.text = List.filled(129, 'x').join();
      await tester.pump();
      expect(
        find.bySemanticsLabel('Höchstens 128 Zeichen: noch offen'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Passwörter stimmen überein: noch offen'),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );
  testWidgets('096 completed action notice can be dismissed locally', (
    tester,
  ) async {
    bool dismissed = false;
    await mount(
      tester,
      ConfirmedSettingNotice(
        message: 'Die Anmeldung wurde beendet.',
        onClose: () => dismissed = true,
      ),
    );
    expect(find.text('Die Anmeldung wurde beendet.'), findsOneWidget);
    await tester.tap(find.byTooltip('Bestätigung schließen'));
    expect(dismissed, isTrue);
  });
  testWidgets('092–096 tools remain readable at 320px with 200% text', (
    tester,
  ) async {
    final password = TextEditingController(),
        repeated = TextEditingController();
    addTearDown(password.dispose);
    addTearDown(repeated.dispose);
    await mount(
      tester,
      Column(
        children: [
          PasswordRequirements(password: password, repeated: repeated),
          DeviceSessionGroups(
            sessions: const [
              {'device': 'Künstliches Gerät', 'current': true},
            ],
            rowBuilder: (s) => Text(s['device']),
          ),
          ConfirmedSettingNotice(
            message: 'Die bestätigte Aktion wurde abgeschlossen.',
            onClose: () {},
          ),
        ],
      ),
      scale: 2,
    );
    await tester.ensureVisible(find.byTooltip('Bestätigung schließen'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
