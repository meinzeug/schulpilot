import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/notebook_photo.dart';
import 'package:schulpilot/ui.dart';

import 'notebook_test.dart' as n;

const _height = 844.0;
const _longTitle =
    'Mathematik und angewandte Naturwissenschaften: gemeinsam untersuchte Zusammenhänge';
final _heading = find.byKey(const ValueKey('notebook-compact-heading'));
final _frame = find.byKey(const ValueKey('notebook-photo-frame'));

Finder _icon(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

Finder _headerIcon(String tooltip) =>
    find.descendant(of: _heading, matching: _icon(tooltip));

void _minimumTarget(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(48));
  expect(size.height, greaterThanOrEqualTo(48));
}

void _noGlobalChrome() {
  expect(find.byType(AppBar), findsNothing);
  expect(find.byType(NavigationBar), findsNothing);
  expect(find.byType(BottomNavigationBar), findsNothing);
  for (final key in [
    'workspace-brand-home',
    'workspace-header',
    'workspace-home-breadcrumb',
    'workspace-context-return',
  ]) {
    expect(find.byKey(ValueKey(key)), findsNothing);
  }
  expect(find.text('SCHULPILOT'), findsNothing);
}

void _onlyReadRequests(List<http.Request> calls) {
  expect(calls.every((request) => request.method == 'GET'), isTrue);
  expect(
    calls.where(
      (request) =>
          request.url.path.startsWith('/api/materials/') &&
          !request.url.path.endsWith('/image'),
    ),
    isEmpty,
    reason: 'Blättern und Ansicht öffnen laden keine Quelltextdetails vorab.',
  );
}

Future<(AppState, GoRouter, List<http.Request>)> _open(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  bool longTitle = false,
  bool parent = false,
}) async {
  final png = Uint8List.fromList(
    img.encodePng(img.Image(width: 24, height: 32)),
  );
  final result = await n.open(
    tester,
    height: _height,
    width: width,
    textScale: scale,
    parent: parent,
    canManage: parent,
    photos: true,
    respond: longTitle
        ? (request) async {
            expect(request.method, 'GET');
            if (request.url.path.endsWith('/subjects')) {
              final data = n.subjects();
              data['items'][0]['title'] = _longTitle;
              return n.jsonReply(data);
            }
            if (request.url.path.endsWith('/image')) {
              return http.Response.bytes(
                png,
                200,
                headers: {'content-type': 'image/png'},
              );
            }
            return n.jsonReply(n.pages(request));
          }
        : null,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    result.$1.inbox.dispose();
    result.$1.familyCalls.dispose();
    result.$1.dispose();
  });
  return result;
}

void main() {
  setUpAll(() async {
    for (final font in ['Nunito', 'SpaceGrotesk', 'Roboto']) {
      await (FontLoader(font)..addFont(
            rootBundle.load(
              'assets/fonts/${font == 'Roboto' ? 'Nunito' : font}.ttf',
            ),
          ))
          .load();
    }
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('mobile notebook reaches the complete photo at $width x 844', (
      tester,
    ) async {
      final (_, _, calls) = await _open(tester, width: width);
      expect(_heading, findsOneWidget);
      expect(find.byType(NotebookPhoto), findsOneWidget);
      _noGlobalChrome();
      final frame = tester.getRect(_frame);
      expect(frame.top, greaterThanOrEqualTo(0));
      expect(frame.top, lessThan(_height * 0.30));
      expect(frame.bottom, lessThanOrEqualTo(_height));
      expect(frame.left, greaterThanOrEqualTo(0));
      expect(frame.right, lessThanOrEqualTo(width));
      for (final label in [
        'Alle Hefter',
        'Heftfoto hinzufügen',
        'Themen entdecken',
      ]) {
        final target = _headerIcon(label);
        _minimumTarget(tester, target);
        expect(target.hitTestable(), findsOneWidget);
      }
      for (final label in ['Blättern', 'Kacheln', 'Liste']) {
        _minimumTarget(tester, find.widgetWithText(OutlinedButton, label));
      }
      for (final label in [
        'Im Hefter suchen',
        'Filter',
        'Seiten aktualisieren',
      ]) {
        _minimumTarget(tester, _icon(label));
        expect(_icon(label).hitTestable(), findsOneWidget);
      }
      expect(
        calls.where((request) => request.url.path.endsWith('/image')),
        hasLength(1),
      );
      _onlyReadRequests(calls);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'long mobile notebook title remains readable at $width / 200%',
      (tester) async {
        final (_, _, calls) = await _open(
          tester,
          width: width,
          scale: 2,
          longTitle: true,
        );
        _noGlobalChrome();
        final title = find.descendant(
          of: _heading,
          matching: find.text(_longTitle),
        );
        expect(title, findsOneWidget);
        final text = tester.widget<Text>(title);
        expect(text.maxLines, isNull);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        final bounds = tester.getRect(title);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(width));
        for (final label in [
          'Alle Hefter',
          'Heftfoto hinzufügen',
          'Themen entdecken',
        ]) {
          _minimumTarget(tester, _headerIcon(label));
        }
        for (final label in ['Blättern', 'Kacheln', 'Liste']) {
          _minimumTarget(tester, find.widgetWithText(OutlinedButton, label));
        }
        await n.tap(tester, _icon('Filter'));
        expect(find.text('Seiten auswählen'), findsOneWidget);
        await n.tap(tester, find.text('Abbrechen'));
        await tester.ensureVisible(_frame);
        await tester.pumpAndSettle();
        expect(_frame.hitTestable(), findsOneWidget);
        _onlyReadRequests(calls);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('focused photo keeps swipe, keyboard, batch pager and zoom', (
    tester,
  ) async {
    final (_, _, calls) = await _open(tester, width: 320);
    final metadataBefore = calls
        .where((request) => request.url.path.endsWith('/materials'))
        .length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2 von 47'), findsWidgets);
    final swipe = find.ancestor(
      of: _frame,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector && widget.onHorizontalDragEnd != null,
      ),
    );
    await tester.timedDrag(
      swipe,
      const Offset(-110, 0),
      const Duration(milliseconds: 1000),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 von 47'), findsWidgets);
    expect(
      calls.where((request) => request.url.path.endsWith('/materials')),
      hasLength(metadataBefore),
    );
    await n.tap(tester, find.text('3 von 47'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Seite 1 bis 47'),
      '25',
    );
    await n.tap(tester, find.text('Seite öffnen'));
    expect(find.text('25 von 47'), findsWidgets);
    expect(
      calls
          .lastWhere((request) => request.url.path.endsWith('/materials'))
          .url
          .queryParameters['page'],
      '2',
    );
    await n.tap(tester, find.byType(NotebookPhoto));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Heftfoto'), findsOneWidget);
    await n.tap(tester, find.byTooltip('Foto vergrößern'));
    expect(find.text('200 %'), findsOneWidget);
    await n.tap(tester, find.byTooltip('Schließen'));
    expect(find.byType(InteractiveViewer), findsNothing);
    _noGlobalChrome();
    _onlyReadRequests(calls);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focused notebook view tools and photo entry remain deliberate', (
    tester,
  ) async {
    final (_, _, calls) = await _open(tester);
    final before = calls.length;
    await n.tap(tester, _icon('Im Hefter suchen'));
    expect(
      find.widgetWithText(TextField, 'In diesem Hefter suchen'),
      findsOneWidget,
    );
    await n.tap(tester, _icon('Suchfeld einklappen'));
    await n.tap(tester, _icon('Filter'));
    await n.tap(tester, find.text('Abbrechen'));
    expect(calls.length, before);
    await n.tap(tester, find.text('Kacheln'));
    expect(find.text('1–20 von 47'), findsWidgets);
    await n.tap(tester, find.text('Liste'));
    expect(find.byType(ListView), findsOneWidget);
    await n.tap(tester, find.text('Blättern'));
    expect(find.text('1 von 47'), findsWidgets);
    await n.tap(tester, _headerIcon('Heftfoto hinzufügen'));
    expect(find.text('Deine neuen Heftfotos'), findsOneWidget);
    _onlyReadRequests(calls);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page management remains below the photo with explicit actions', (
    tester,
  ) async {
    final (_, _, calls) = await _open(tester, width: 320);
    for (final label in [
      'Foto zum Vergleich vormerken',
      'Mit KI neu lesen',
      'Heftseite löschen',
    ]) {
      final action = _icon(label);
      _minimumTarget(tester, action);
      expect(
        tester.getTopLeft(action).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(_frame).dy),
      );
      expect(tester.widget<IconButton>(action).onPressed, isNotNull);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
    }
    await n.tap(tester, _icon('Foto zum Vergleich vormerken'));
    expect(find.text('1 von 2 Fotos vorgemerkt'), findsOneWidget);
    await n.tap(tester, _icon('Foto aus Vergleich nehmen'));
    await n.tap(tester, _icon('Mit KI neu lesen'));
    expect(find.text('Seite neu einlesen?'), findsOneWidget);
    expect(
      find.textContaining('Das verbraucht einen KI-Aufruf.'),
      findsOneWidget,
    );
    await n.tap(tester, find.text('Abbrechen'));
    expect(find.text('Seite neu einlesen?'), findsNothing);
    _onlyReadRequests(calls);
    expect(tester.takeException(), isNull);
  });

  for (final label in [
    'Alle Hefter',
    'Heftfoto hinzufügen',
    'Themen entdecken',
  ]) {
    testWidgets(
      'old focused header action $label is inert after account change',
      (tester) async {
        final (state, router, calls) = await _open(tester);
        final oldAction = tester
            .widget<IconButton>(_headerIcon(label))
            .onPressed!;
        state.user = {...state.user!};
        state.notifyListeners();
        await tester.pumpAndSettle();
        final before = calls.length;
        final location = router.routeInformationProvider.value.uri;
        oldAction();
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri, location);
        expect(calls.length, before);
        expect(_heading, findsOneWidget);
        expect(find.text('Deine neuen Heftfotos'), findsNothing);
        _onlyReadRequests(calls);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('wide child notebook starts with its photo and local controls', (
    tester,
  ) async {
    final (_, _, calls) = await _open(tester, width: 1280);
    expect(_heading, findsOneWidget);
    _noGlobalChrome();
    expect(find.byType(NotebookPhoto), findsOneWidget);
    final frame = tester.getRect(_frame);
    expect(frame.top, greaterThanOrEqualTo(0));
    expect(frame.top, lessThan(_height * 0.30));
    expect(frame.bottom, lessThanOrEqualTo(_height));
    for (final label in [
      'Alle Hefter',
      'Heftfoto hinzufügen',
      'Themen entdecken',
    ]) {
      _minimumTarget(tester, _headerIcon(label));
      expect(_headerIcon(label).hitTestable(), findsOneWidget);
    }
    for (final label in [
      'Foto zum Vergleich vormerken',
      'Mit KI neu lesen',
      'Heftseite löschen',
    ]) {
      final action = _icon(label);
      _minimumTarget(tester, action);
      expect(
        tester.getTopLeft(action).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(_frame).dy),
      );
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
    }
    _onlyReadRequests(calls);
    expect(tester.takeException(), isNull);
  });

  testWidgets('browser focus retains the 80px rail and its account action', (
    tester,
  ) async {
    // PageFrame uses kIsWeb, which is false in VM widget tests. Exercise its
    // browser shell separately instead of nesting artificial workspace shells.
    tester.view.physicalSize = const Size(1280, _height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <http.Request>[];
    final state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient((request) async {
                calls.add(request);
                expect(request.method, 'GET');
                return n.jsonReply({'available': false});
              }),
            ),
          )
          ..user = {
            'id': 'synthetic-browser-child',
            'role': 'child',
            'child_id': 'child',
            'display_name': 'Beispiel',
          };
    final router = GoRouter(
      initialLocation: '/library/child/subject/${n.mathId}',
      routes: [
        GoRoute(
          path: '/library/:child/subject/:subject',
          builder: (_, _) => WorkspaceShell(
            state: state,
            browser: true,
            focusContent: true,
            showTitle: false,
            title: 'Mathematik',
            child: const Text('Eigener fokussierter Heftinhalt'),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: Text('Kontoeinstellungen')),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      state.inbox.dispose();
      state.familyCalls.dispose();
      state.dispose();
    });
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
    expect(sidebar, findsOneWidget);
    final railFace = find
        .descendant(of: sidebar, matching: find.byType(DecoratedBox))
        .first;
    expect(tester.getSize(railFace).width, 80);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-brand-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-header')), findsNothing);
    expect(
      find.byKey(const ValueKey('workspace-home-breadcrumb')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workspace-context-return')),
      findsNothing,
    );
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    final account = find.byTooltip('Konto');
    _minimumTarget(tester, account);
    expect(account.hitTestable(), findsOneWidget);
    await tester.tap(account);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(find.text('Kontoeinstellungen'), findsOneWidget);
    _onlyReadRequests(calls);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parent notebook keeps its complete workspace at 390px', (
    tester,
  ) async {
    final (_, _, calls) = await _open(tester, width: 390, parent: true);
    expect(_heading, findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NotebookPhoto), findsOneWidget);
    _onlyReadRequests(calls);
    expect(tester.takeException(), isNull);
  });
}
