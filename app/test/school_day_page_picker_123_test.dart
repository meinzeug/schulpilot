import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/ui.dart';

import 'school_day_background_test.dart' as day;

const picker = ValueKey('school-day-page-picker');

class Pages extends day.PreparationServer {
  Pages()
    : super(
        stage: 'review',
        pages: List.generate(
          19,
          (i) => {
            ...day.source(i + 1, confirmed: i < 2),
            'revision': 1,
            'synthetic': false,
            'has_image': true,
            'uncertainties': <String>[],
          },
        ),
        preparation: {'status': 'needs_review', 'phase': 'review'},
      ) {
    realUploads = true;
  }
  final images = <String>[];
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 24, height: 32)),
  );
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/image')) {
      requests.add('${request.method} ${request.url.path}');
      images.add(request.url.pathSegments[2]);
      return http.Response.bytes(
        bytes,
        200,
        headers: {'content-type': 'image/png'},
      );
    }
    return super.handle(request);
  }
}

Future<(Pages, AppState)> open(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final server = Pages(), state = server.state();
  state.api.token = 'synthetic-session';
  final router = day.router(state);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    state.inbox.dispose();
    state.familyCalls.dispose();
    state.dispose();
  });
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
  return (server, state);
}

Future<void> choose(WidgetTester tester) async {
  final button = find.byKey(picker);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.text('Seite auswählen'), findsOneWidget);
}

Finder choice(int number) =>
    find.byKey(ValueKey('school-day-page-choice:page$number'));
void onlyReads(Pages server) {
  expect(server.requests.every((r) => r.startsWith('GET ')), isTrue);
  expect(server.pages.where((p) => p['confirmed'] == true), hasLength(2));
  expect(server.submissions, 0);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    for (final name in ['Nunito', 'SpaceGrotesk']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/$name.ttf'))).load();
    }
  });
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '19 pages leave photo visible and select with GET only at $width/$scale',
        (tester) async {
          final (server, _) = await open(tester, width: width, scale: scale);
          expect(find.text('Seite 3 prüfen'), findsOneWidget);
          expect(find.text('2 von 19 geprüft'), findsOneWidget);
          expect(find.byKey(picker).hitTestable(), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is ListTile &&
                  w.key.toString().contains('school-day-page-choice'),
            ),
            findsNothing,
          );
          final photo = find.byWidgetPredicate(
            (w) => w is Image && w.image is MemoryImage,
          );
          expect(photo, findsOneWidget);
          final bounds = tester.getRect(photo);
          expect(bounds.top, lessThan(844 * .75));
          expect(bounds.bottom, lessThanOrEqualTo(844));
          final target = tester.getSize(find.byKey(picker));
          expect(target.height, greaterThanOrEqualTo(48));
          expect(target.height, lessThan(220));
          await choose(tester);
          expect(tester.widget<ListTile>(choice(1)).enabled, isFalse);
          expect(tester.widget<ListTile>(choice(3)).selected, isTrue);
          final scroll = find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Scrollable),
              )
              .last;
          await tester.scrollUntilVisible(choice(19), 320, scrollable: scroll);
          await tester.pumpAndSettle();
          expect(tester.getSize(choice(19)).height, greaterThanOrEqualTo(48));
          await tester.tap(choice(19));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.text('Seite 19 prüfen'), findsOneWidget);
          expect(server.images.toSet(), {'page3', 'page19'});
          onlyReads(server);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('cancel retains exact review widget and page without writes', (
    tester,
  ) async {
    final (server, _) = await open(tester);
    final review = tester.state(find.byType(MaterialReview));
    await choose(tester);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(MaterialReview)), same(review));
    expect(find.text('Seite 3 prüfen'), findsOneWidget);
    expect(server.images.toSet(), {'page3'});
    onlyReads(server);
  });
  for (final change in ['token', 'account', 'background']) {
    testWidgets('$change invalidates an old page callback', (tester) async {
      final (server, state) = await open(tester);
      await choose(tester);
      final old = tester.widget<ListTile>(choice(4)).onTap!;
      if (change == 'token') {
        state.api.token = 'new-session';
        state.notifyListeners();
      } else if (change == 'account') {
        state.user = {
          ...state.user!,
          'id': 'another-child',
          'child_id': 'other',
        };
        state.notifyListeners();
      } else {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      await tester.pump();
      old();
      await tester.pump();
      if (change == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpAndSettle();
      expect(server.images.contains('page4'), isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      onlyReads(server);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('a changed source snapshot rejects an old selection', (
    tester,
  ) async {
    final (server, state) = await open(tester);
    final read = Completer<http.Response>();
    server.delayedRead = read;
    state.notifyListeners();
    await tester.pump();
    await choose(tester);
    final old = tester.widget<ListTile>(choice(4)).onTap!;
    server.pages[3]['revision'] = 2;
    read.complete(day.response({'day': server.day}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    old();
    await tester.pump();
    expect(server.images.contains('page4'), isFalse);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Seite 3 prüfen'), findsOneWidget);
    onlyReads(server);
  });
  testWidgets('foreign modal blocks old selection and remains open', (
    tester,
  ) async {
    final (server, _) = await open(tester);
    await choose(tester);
    final old = tester.widget<ListTile>(choice(4)).onTap!;
    final dialog = tester.element(find.byType(AlertDialog));
    unawaited(
      showDialog<void>(
        context: dialog,
        builder: (context) => AlertDialog(
          title: const Text('Andere Ansicht'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zurück'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    old();
    await tester.pumpAndSettle();
    expect(find.text('Andere Ansicht'), findsOneWidget);
    expect(server.images.contains('page4'), isFalse);
    await tester.tap(find.text('Zurück'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Seite 3 prüfen'), findsOneWidget);
    onlyReads(server);
  });
}
