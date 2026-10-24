import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/notebook_photo.dart';

import 'notebook_test.dart' as n;

final _options = find.byKey(const ValueKey('notebook-options-dialog'));
final _searchDialog = find.byKey(const ValueKey('notebook-search-dialog'));
final _headerOptions = find.byKey(const ValueKey('notebook-options'));

Finder _command(String label) => n.notebookOption(label);

Finder _searchField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText == 'In diesem Hefter suchen',
);

Finder _icon(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

int _metadataReads(List<http.Request> calls) =>
    calls.where((request) => request.url.path.endsWith('/materials')).length;

void _readOnly(List<http.Request> calls) {
  expect(calls.every((request) => request.method == 'GET'), isTrue);
  expect(
    calls.where(
      (request) =>
          request.url.path.startsWith('/api/materials/') &&
          !request.url.path.endsWith('/image'),
    ),
    isEmpty,
    reason: 'Menü- und Ansichtsaktionen laden keine Quelltextdetails vorab.',
  );
}

Future<(AppState, GoRouter, List<http.Request>)> _open(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  bool parent = false,
  bool photos = false,
}) async {
  final result = await n.open(
    tester,
    width: width,
    height: 844,
    textScale: scale,
    parent: parent,
    canManage: parent,
    photos: photos,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    result.$1.inbox.dispose();
    result.$1.familyCalls.dispose();
    result.$1.dispose();
  });
  return result;
}

Future<void> _openOptions(WidgetTester tester) async {
  await n.openNotebookOptions(tester);
  expect(_options, findsOneWidget);
}

Future<void> _runCommand(WidgetTester tester, String label) async {
  await _openOptions(tester);
  await n.tap(tester, _command(label));
  expect(_options, findsNothing);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    for (final font in ['Nunito', 'Roboto']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
    }
  });

  for (final (width, scale, parent) in [
    (320.0, 1.0, false),
    (390.0, 2.0, false),
    (1280.0, 1.0, false),
    (390.0, 1.0, true),
    (1280.0, 2.0, true),
  ]) {
    testWidgets(
      '104 tools only open on demand at $width/$scale parent=$parent',
      (tester) async {
        final (_, _, calls) = await _open(
          tester,
          width: width,
          scale: scale,
          parent: parent,
          photos: true,
        );
        expect(_headerOptions.hitTestable(), findsOneWidget);
        expect(tester.getSize(_headerOptions).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(_headerOptions).height, greaterThanOrEqualTo(48));
        for (final label in [
          'Blättern',
          'Kacheln',
          'Liste',
          'Im Hefter suchen',
          'Filter',
          'Seiten aktualisieren',
          'Themen entdecken',
        ]) {
          expect(find.text(label), findsNothing);
        }
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(NotebookPhoto), findsOneWidget);
        expect(find.text('1 von 47'), findsWidgets);
        if (!parent && scale == 1) {
          final frame = tester.getRect(
            find.byKey(const ValueKey('notebook-photo-frame')),
          );
          // The requested persistent app header occupies one toolbar above
          // the same compact notebook controls. Measure those independently.
          final header = tester.getRect(find.byType(AppBar));
          expect(frame.top - header.bottom, lessThan(150));
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(frame.bottom, lessThanOrEqualTo(844));
        }
        final before = calls.length;
        await _openOptions(tester);
        expect(find.textContaining('47 Seiten'), findsOneWidget);
        for (final label in [
          'Blättern',
          'Kacheln',
          'Liste',
          'Im Hefter suchen',
          'Filter',
          'Seiten aktualisieren',
          'Themen entdecken',
        ]) {
          final command = _command(label);
          expect(command, findsOneWidget);
          expect(tester.getSize(command).height, greaterThanOrEqualTo(48));
          await tester.ensureVisible(command);
          await tester.pumpAndSettle();
          expect(command.hitTestable(), findsOneWidget);
        }
        expect(tester.widget<ListTile>(_command('Blättern')).selected, isTrue);
        await n.tap(tester, _icon('Hefteroptionen schließen'));
        expect(_options, findsNothing);
        expect(calls.length, before);
        _readOnly(calls);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    '104 view choices persist locally without collection or detail reads',
    (tester) async {
      final (state, _, calls) = await _open(tester, width: 320);
      final before = calls.length;
      for (final (label, value) in [
        ('Kacheln', 'grid'),
        ('Liste', 'list'),
        ('Blättern', 'album'),
      ]) {
        await _runCommand(tester, label);
        expect(
          state.collectionViews['notebook:child:${n.mathId}']?['view'],
          value,
        );
        expect(calls.length, before);
        await _openOptions(tester);
        expect(tester.widget<ListTile>(_command(label)).selected, isTrue);
        await n.tap(tester, _icon('Hefteroptionen schließen'));
      }
      _readOnly(calls);
      expect(tester.takeException(), isNull);
    },
  );

  for (final enter in [false, true]) {
    testWidgets('104 staged search commits once through enter=$enter', (
      tester,
    ) async {
      final (state, _, calls) = await _open(tester);
      await _runCommand(tester, 'Im Hefter suchen');
      expect(_searchDialog, findsOneWidget);
      final beforeDraft = calls.length;
      await tester.enterText(_searchField(), 'Nur ein Entwurf');
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls.length, beforeDraft);
      expect(state.collectionViews['notebook:child:${n.mathId}']?['q'], '');
      await n.tap(tester, find.widgetWithText(TextButton, 'Abbrechen'));
      expect(_searchDialog, findsNothing);
      expect(find.text('Suche: Nur ein Entwurf'), findsNothing);
      expect(calls.length, beforeDraft);
      await _runCommand(tester, 'Im Hefter suchen');
      expect(tester.widget<TextField>(_searchField()).controller!.text, '');
      await tester.enterText(_searchField(), ' Brüche ');
      final submit = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Suchen'))
          .onPressed!;
      final beforeCommit = _metadataReads(calls);
      if (enter) {
        await tester.testTextInput.receiveAction(TextInputAction.search);
      } else {
        await n.tap(tester, find.widgetWithText(FilledButton, 'Suchen'));
      }
      await tester.pumpAndSettle();
      submit();
      await tester.pumpAndSettle();
      expect(_searchDialog, findsNothing);
      expect(_metadataReads(calls), beforeCommit + 1);
      expect(calls.last.url.queryParameters['q'], 'Brüche');
      expect(find.text('Suche: Brüche'), findsOneWidget);
      expect(
        state.collectionViews['notebook:child:${n.mathId}']?['q'],
        'Brüche',
      );
      final beforeCancel = calls.length;
      await n.tap(tester, find.text('Suche: Brüche'));
      expect(
        tester.widget<TextField>(_searchField()).controller!.text,
        'Brüche',
      );
      await tester.enterText(_searchField(), 'Nicht übernehmen');
      await n.tap(tester, find.widgetWithText(TextButton, 'Abbrechen'));
      expect(find.text('Suche: Brüche'), findsOneWidget);
      expect(calls.length, beforeCancel);
      await n.tap(tester, find.byTooltip('Suchbegriff entfernen'));
      expect(_metadataReads(calls), beforeCommit + 2);
      expect(calls.last.url.queryParameters['q'], '');
      expect(find.text('Suche: Brüche'), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
      _readOnly(calls);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('104 120-character search remains usable at 320px and 200%', (
    tester,
  ) async {
    final (_, _, calls) = await _open(tester, width: 320, scale: 2);
    await _runCommand(tester, 'Im Hefter suchen');
    expect(tester.widget<TextField>(_searchField()).maxLength, 120);
    final before = calls.length;
    await tester.enterText(_searchField(), 'X' * 130);
    expect(
      tester.widget<TextField>(_searchField()).controller!.text.length,
      120,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls.length, before);
    final submit = find.widgetWithText(FilledButton, 'Suchen');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.getSize(submit).height, greaterThanOrEqualTo(48));
    await n.tap(tester, find.widgetWithText(TextButton, 'Abbrechen'));
    expect(calls.length, before);
    _readOnly(calls);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '104 status and search chips remain visible outside the closed menu',
    (tester) async {
      final (_, _, calls) = await _open(tester);
      await _runCommand(tester, 'Filter');
      final before = _metadataReads(calls);
      await n.tap(tester, find.byType(DropdownButtonFormField<String>).last);
      await n.tap(tester, find.text('Noch prüfen').last);
      expect(_metadataReads(calls), before);
      await n.tap(tester, find.widgetWithText(FilledButton, 'Anzeigen'));
      expect(_metadataReads(calls), before + 1);
      expect(find.byTooltip('Seitenstatus aufheben'), findsOneWidget);
      expect(_options, findsNothing);
      await _runCommand(tester, 'Im Hefter suchen');
      await tester.enterText(_searchField(), 'Wasser');
      await n.tap(tester, find.widgetWithText(FilledButton, 'Suchen'));
      expect(find.text('Suche: Wasser'), findsOneWidget);
      expect(find.byTooltip('Seitenstatus aufheben'), findsOneWidget);
      await n.tap(tester, find.byTooltip('Suchbegriff entfernen'));
      expect(find.byTooltip('Seitenstatus aufheben'), findsOneWidget);
      expect(calls.last.url.queryParameters['status'], 'review');
      expect(calls.last.url.queryParameters['q'], '');
      _readOnly(calls);
      expect(tester.takeException(), isNull);
    },
  );

  for (final changed in [
    'account',
    'token',
    'family',
    'subject',
    'revision',
    'page',
    'covered route',
    'disposed',
  ]) {
    testWidgets('104 stale menu action is inert after $changed changes', (
      tester,
    ) async {
      final (state, router, calls) = await _open(tester);
      final next = tester
          .widget<IconButton>(_icon('Nächste Seite').first)
          .onPressed!;
      await _openOptions(tester);
      final action = tester.widget<ListTile>(_command('Liste')).onTap!;
      if (changed == 'account') {
        state.user = {...state.user!};
        state.notifyListeners();
      } else if (changed == 'token') {
        state.api.token = 'replacement-session';
        state.notifyListeners();
      } else if (changed == 'family') {
        state.familyId = 'replacement-family';
        state.notifyListeners();
      } else if (changed == 'subject') {
        router.go('/library/child/subject/${n.bioId}');
      } else if (changed == 'revision') {
        state.refreshState();
      } else if (changed == 'page') {
        next();
      } else if (changed == 'covered route') {
        router.push('/material/page0');
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpAndSettle();
      final before = calls.length;
      final location = router.routeInformationProvider.value.uri;
      action();
      await tester.pumpAndSettle();
      expect(calls.length, before);
      expect(router.routeInformationProvider.value.uri, location);
      expect(
        state.collectionViews['notebook:child:${n.mathId}']?['view'],
        isNot('list'),
      );
      _readOnly(calls);
      expect(tester.takeException(), isNull);
    });
  }

  for (final changed in ['account', 'revision', 'covered route']) {
    testWidgets(
      '104 stale search confirmation is inert after $changed changes',
      (tester) async {
        final (state, router, calls) = await _open(tester);
        await _runCommand(tester, 'Im Hefter suchen');
        await tester.enterText(_searchField(), 'Alter Entwurf');
        final apply = tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Suchen'))
            .onPressed!;
        if (changed == 'account') {
          state.user = {...state.user!};
          state.notifyListeners();
        } else if (changed == 'revision') {
          state.refreshState();
        } else {
          router.push('/material/page0');
        }
        await tester.pumpAndSettle();
        final before = calls.length;
        apply();
        await tester.pumpAndSettle();
        expect(calls.length, before);
        expect(find.text('Suche: Alter Entwurf'), findsNothing);
        expect(
          state.collectionViews['notebook:child:${n.mathId}']?['q'],
          isNot('Alter Entwurf'),
        );
        _readOnly(calls);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('104 an old menu close cannot dismiss a newer dialog', (
    tester,
  ) async {
    final (_, _, calls) = await _open(tester);
    await _openOptions(tester);
    final close = tester
        .widget<IconButton>(_icon('Hefteroptionen schließen'))
        .onPressed!;
    await n.tap(tester, _icon('Hefteroptionen schließen'));
    final context = tester.element(_headerOptions);
    final newer = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(title: Text('Neue Meldung')),
    );
    await tester.pumpAndSettle();
    final before = calls.length;
    close();
    await tester.pumpAndSettle();
    expect(find.text('Neue Meldung'), findsOneWidget);
    expect(calls.length, before);
    Navigator.of(tester.element(find.text('Neue Meldung'))).pop();
    await newer;
    await tester.pumpAndSettle();
    _readOnly(calls);
    expect(tester.takeException(), isNull);
  });
}
