import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_section_ui.dart';
import 'package:schulpilot/collection_screen.dart';
import 'package:schulpilot/notebook_cover.dart';
import 'package:schulpilot/notebook_photo.dart';
import 'package:schulpilot/notebook_screen.dart';
import 'package:schulpilot/subject_badge.dart';
import 'package:schulpilot/ui.dart';

const mathId = '11111111111111111111111111111111';
const bioId = '22222222222222222222222222222222';
http.Response jsonReply(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json subjects({bool canManage = false}) => {
  'items': [
    {
      'id': mathId,
      'title': 'Mathematik',
      'cover_key': 'mathematik',
      'page_count': 47,
      'review_count': 1,
      'selected': true,
    },
    {
      'id': bioId,
      'title': 'Biologie',
      'cover_key': 'biologie',
      'page_count': 0,
      'review_count': 0,
      'selected': true,
    },
  ],
  'unassigned_count': 2,
  'can_manage': canManage,
};

Json pages(
  http.Request request, {
  bool photos = true,
  Set<String> deleted = const {},
}) {
  final page = int.parse(request.url.queryParameters['page'] ?? '1');
  final empty = request.url.queryParameters['subject_id'] == bioId;
  final total = empty ? 0 : 47 - deleted.length;
  final first = (page - 1) * 20;
  final available = [
    for (var n = 0; n < 47; n++)
      if (!empty && !deleted.contains('page$n'))
        {
          'id': 'page$n',
          'title': 'Notiz $n',
          'topic': 'Lernstoff $n',
          'confirmed': n != 1,
          'created': 1700000000 + n,
          'revision': 1,
          'has_image': photos,
          'fixed_example': false,
          'subject_id': request.url.queryParameters['subject_id'],
        },
  ];
  return {
    'total': total,
    'pages': empty ? 1 : 3,
    'page': page,
    'page_size': 20,
    'items': available.skip(first).take(20).toList(),
  };
}

Future<(AppState, GoRouter, List<http.Request>)> open(
  WidgetTester tester, {
  bool shelf = false,
  String? initialLocation,
  Json? shelfView,
  double width = 390,
  double textScale = 1,
  bool reducedMotion = false,
  bool photos = true,
  bool parent = false,
  bool canManage = false,
  bool settle = true,
  Brightness brightness = Brightness.light,
  Future<http.Response> Function(http.Request)? respond,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final requests = <http.Request>[];
  final png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              if (respond != null) return respond(r);
              expect(r.method, 'GET');
              if (r.url.path.endsWith('/subjects')) {
                return jsonReply(subjects(canManage: canManage));
              }
              if (r.url.path.endsWith('/image')) {
                return http.Response.bytes(
                  png,
                  200,
                  headers: {'content-type': 'image/png'},
                );
              }
              return jsonReply(pages(r, photos: photos));
            }),
          ),
        )
        ..familyId = parent ? 'family' : null
        ..user = parent
            ? {
                'id': 'own-parent-user',
                'role': 'parent',
                'families': [
                  {'id': 'family', 'permission': canManage ? 'owner' : 'view'},
                ],
              }
            : {
                'id': 'own-child-user',
                'role': 'child',
                'child_id': 'child',
                'display_name': 'Beispiel',
              };
  if (shelfView != null) {
    state.collectionViews['notebook-shelf:child'] = Json.from(shelfView);
  }
  final router = GoRouter(
    initialLocation:
        initialLocation ??
        (shelf ? '/library/child' : '/library/child/subject/$mathId'),
    routes: [
      GoRoute(
        path: '/library/:id',
        builder: (_, _) => CollectionScreen(state, childId: 'child'),
      ),
      GoRoute(
        path: '/library/:id/subject/:subject',
        builder: (_, route) => NotebookScreen(
          state,
          key: ValueKey(route.pathParameters['subject']),
          childId: 'child',
          subjectId: route.pathParameters['subject']!,
        ),
      ),
      GoRoute(
        path: '/material/:id/processing/:job',
        builder: (_, route) => Scaffold(
          body: Text(
            'Neue Erkennung: ${route.pathParameters['id']} / ${route.pathParameters['job']}',
          ),
        ),
      ),
      GoRoute(
        path: '/material/:id',
        builder: (_, _) => const Scaffold(body: Text('Quelltext & Lernen')),
      ),
      GoRoute(
        path: '/after-school/:id',
        builder: (_, _) => const Scaffold(body: Text('Deine neuen Heftfotos')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(brightness: brightness),
      routerConfig: router,
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1000),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return (state, router, requests);
}

Future<void> tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await tester.ensureVisible(finder.first);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 350));
  }
  await tester.tap(finder.first);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

void main() {
  test(
    'Only known cover keys are paths; private subjects use the generic picture',
    () {
      expect(notebookCoverPath('../private'), 'assets/folders/mein-heft.webp');
      expect(notebookCoverPath('mathematik'), 'assets/folders/mathematik.webp');
      expect(notebookCoverKeys.length, 24);
    },
  );

  for (final (width, textScale, brightness) in [
    (320.0, 1.0, Brightness.light),
    (1280.0, 1.0, Brightness.light),
    (320.0, 2.0, Brightness.light),
    (320.0, 2.0, Brightness.dark),
  ]) {
    testWidgets(
      'Subject shelf keeps filters and pure GET navigation at $width $textScale $brightness',
      (tester) async {
        final (_, _, requests) = await open(
          tester,
          shelf: true,
          width: width,
          textScale: textScale,
          brightness: brightness,
        );
        expect(find.text('Biologie'), findsNothing);
        expect(find.text('Mathematik'), findsOneWidget);
        expect(find.text('Noch zuordnen'), findsOneWidget);
        await tap(tester, find.text('Alle Fächer'));
        expect(find.text('Biologie'), findsOneWidget);
        expect(find.text('Noch keine Seiten'), findsOneWidget);
        final mathPosition = tester.getTopLeft(find.text('Mathematik'));
        final bioPosition = tester.getTopLeft(find.text('Biologie'));
        expect(
          mathPosition.dy < bioPosition.dy ||
              (mathPosition.dy == bioPosition.dy &&
                  mathPosition.dx < bioPosition.dx),
          isTrue,
        );
        expect(requests, hasLength(1));
        expect(requests.single.url.path.endsWith('/subjects'), isTrue);
        expect(find.byType(TextField), findsNothing);
        if (textScale == 1) {
          expect(
            tester
                .getSize(find.byKey(const ValueKey('notebook-toolbar')))
                .height,
            lessThanOrEqualTo(64),
          );
        }
        if (width < 720) {
          expect(
            find.byKey(const ValueKey('compact-child-heading')),
            findsOneWidget,
          );
          expect(find.text('Dein Stoff. Gut sortiert.'), findsNothing);
        } else {
          expect(find.text('Dein Stoff. Gut sortiert.'), findsOneWidget);
        }
        expect(find.byType(SubjectBadge), findsWidgets);
        expect(find.byType(NotebookCover), findsNothing);
        expect(find.byType(GridView), findsNothing);
        await tap(tester, find.byTooltip('Kacheln'));
        expect(find.byType(GridView), findsOneWidget);
        expect(find.byType(NotebookCover), findsWidgets);
        await tap(tester, find.text('Fach suchen'));
        await tester.enterText(find.byType(TextField), 'Biologie');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(find.text('Mathematik'), findsNothing);
        expect(find.byType(NotebookCover), findsOneWidget);
        expect(find.text('Biologie'), findsWidgets);
        await tap(tester, find.byTooltip('Suche schließen'));
        expect(find.byType(TextField), findsNothing);
        await tap(tester, find.text('Meine Fächer'));
        expect(find.text('Biologie'), findsNothing);
        expect(find.text('Mathematik'), findsOneWidget);
        expect(find.text('Noch zuordnen'), findsOneWidget);
        await tap(tester, find.text('Alle Fächer'));
        await tap(tester, find.byTooltip('Liste'));
        expect(find.byType(GridView), findsNothing);
        await tap(tester, find.byTooltip('Kacheln'));
        expect(find.byType(GridView), findsOneWidget);
        expect(requests, hasLength(1));
        await tap(tester, find.text('Alle Seiten'));
        expect(requests.every((r) => r.method == 'GET'), isTrue);
        expect(requests.last.url.path.endsWith('/materials'), isTrue);
        expect(requests.last.url.queryParameters['subject_id'], isNull);
        await tap(tester, find.text('Alle Fächer'));
        expect(find.text('Biologie'), findsOneWidget);
        await tap(tester, find.text('Biologie'));
        expect(
          requests
              .where((r) => r.url.path.endsWith('/materials'))
              .last
              .url
              .queryParameters['subject_id'],
          bioId,
        );
        expect(
          find.text('Hier sind noch keine Heftseiten vorhanden.'),
          findsOneWidget,
        );
        await tap(tester, find.text('Erstes Heftfoto hinzufügen'));
        expect(find.text('Deine neuen Heftfotos'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'Album, jump, cross-batch paging, overview and zoom at $width',
      (tester) async {
        final (state, _, requests) = await open(tester, width: width);
        expect(find.text('1 von 47'), findsWidgets);
        expect(
          requests.where((r) => r.url.path.endsWith('/image')),
          hasLength(1),
        );
        await tap(tester, find.byTooltip('Nächste Seite'));
        expect(find.text('2 von 47'), findsWidgets);
        expect(find.text('Seite prüfen'), findsOneWidget);
        await tap(tester, find.text('2 von 47'));
        await tester.enterText(
          find.widgetWithText(TextField, 'Seite 1 bis 47'),
          '25',
        );
        await tap(tester, find.text('Seite öffnen'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.text('25 von 47'), findsWidgets);
        expect(
          requests
              .where((r) => r.url.path.endsWith('/materials'))
              .last
              .url
              .queryParameters['page'],
          '2',
        );
        await tap(tester, find.text('Vergrößern'));
        expect(find.byType(InteractiveViewer), findsOneWidget);
        await tap(tester, find.byTooltip('Schließen'));
        await tap(tester, find.text('Kacheln'));
        expect(find.text('21–40 von 47'), findsWidgets);
        final photos = requests
            .where((r) => r.url.path.endsWith('/image'))
            .length;
        expect(
          photos,
          lessThan(25),
        ); // bounded window, never all47 full-size photos
        await tap(tester, find.text('Liste'));
        expect(find.byType(ListView), findsOneWidget);
        await tap(tester, find.byTooltip('Nächste Übersicht'));
        expect(find.text('41–47 von 47'), findsWidgets);
        expect(
          state.collectionViews['notebook:child:$mathId']!['view'],
          'list',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Child shelf restores an explicit grid or list choice after leaving',
    (tester) async {
      final (state, router, requests) = await open(tester, shelf: true);
      expect(find.byType(SubjectBadge), findsWidgets);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(NotebookCover), findsNothing);

      Future<void> leaveAndReturn() async {
        router.go('/library/child/subject/$bioId');
        await tester.pumpAndSettle();
        expect(
          find.text('Hier sind noch keine Heftseiten vorhanden.'),
          findsOneWidget,
        );
        router.go('/library/child');
        await tester.pumpAndSettle();
      }

      await tap(tester, find.byTooltip('Kacheln'));
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(NotebookCover), findsWidgets);
      expect(state.collectionViews['notebook-shelf:child']!['list'], isFalse);
      await leaveAndReturn();
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(NotebookCover), findsWidgets);
      expect(find.byTooltip('Liste'), findsOneWidget);

      await tap(tester, find.byTooltip('Liste'));
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(NotebookCover), findsNothing);
      expect(find.byType(SubjectBadge), findsWidgets);
      expect(state.collectionViews['notebook-shelf:child']!['list'], isTrue);
      await leaveAndReturn();
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(NotebookCover), findsNothing);
      expect(find.byType(SubjectBadge), findsWidgets);
      expect(find.byTooltip('Kacheln'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final list in [false, true]) {
    testWidgets(
      'Home search overrides all-pages while preserving shelf filters and list=$list',
      (tester) async {
        final (_, router, requests) = await open(
          tester,
          shelf: true,
          initialLocation: '/library/child?search=1',
          shelfView: {
            'all_pages': true,
            'list': list,
            'own_only': false,
            'q': 'Biologie',
          },
        );
        expect(router.routeInformationProvider.value.uri.query, 'search=1');
        expect(find.byType(TextField), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Biologie',
        );
        expect(find.text('Biologie'), findsWidgets);
        expect(find.text('Mathematik'), findsNothing);
        expect(
          tester
              .widget<ChildSectionTabs>(find.byType(ChildSectionTabs))
              .selected,
          'all',
        );
        expect(find.byType(GridView), list ? findsNothing : findsOneWidget);
        expect(
          find.byType(NotebookCover),
          list ? findsNothing : findsOneWidget,
        );
        expect(find.byType(SubjectBadge), list ? findsOneWidget : findsNothing);
        expect(requests, hasLength(1));
        expect(requests.single.method, 'GET');
        expect(requests.single.url.path, '/api/children/child/subjects');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Parent shelf keeps its default cover grid', (tester) async {
    final (_, _, requests) = await open(tester, shelf: true, parent: true);
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(NotebookCover), findsWidgets);
    expect(find.byTooltip('Liste'), findsOneWidget);
    expect(requests.every((request) => request.method == 'GET'), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Confirmed page deletion and KI actions are visible in album, tiles and list',
    (tester) async {
      final deleted = <String>{};
      final requests = <http.Request>[];
      await open(
        tester,
        respond: (request) async {
          requests.add(request);
          if (request.url.path.endsWith('/materials/delete-preview')) {
            expect(request.method, 'POST');
            expect(jsonDecode(request.body), {
              'ids': ['page0'],
            });
            return jsonReply({'count': 1, 'selection_token': 'own-selection'});
          }
          if (request.url.path.endsWith('/materials/bulk-delete')) {
            expect(request.method, 'POST');
            expect(jsonDecode(request.body), {
              'selection_token': 'own-selection',
              'delete_linked_units': true,
            });
            deleted.add('page0');
            return jsonReply({'deleted_count': 1});
          }
          if (request.url.path.endsWith('/subjects')) {
            return jsonReply(subjects());
          }
          if (request.url.path.endsWith('/image')) {
            return http.Response.bytes(
              Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4))),
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          return jsonReply(pages(request, deleted: deleted));
        },
      );
      expect(find.byTooltip('Heftseite löschen'), findsOneWidget);
      expect(find.byTooltip('Mit KI neu lesen'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byTooltip('Heftseite löschen')).dy,
        lessThan(tester.getTopLeft(find.byType(NotebookPhoto).first).dy),
      );
      expect(
        tester.getSize(find.byTooltip('Heftseite löschen')).shortestSide,
        greaterThanOrEqualTo(48),
      );
      await tap(tester, find.text('Kacheln'));
      expect(find.byTooltip('Heftseite löschen'), findsWidgets);
      expect(find.byTooltip('Mit KI neu lesen'), findsWidgets);
      await tap(tester, find.text('Liste'));
      expect(find.byTooltip('Heftseite löschen'), findsWidgets);
      expect(find.byTooltip('Mit KI neu lesen'), findsWidgets);
      await tap(
        tester,
        find.byTooltip('Heftseite löschen').first,
        settle: false,
      );
      expect(find.text('Heftseite löschen?'), findsOneWidget);
      expect(
        find.textContaining('Das kannst du nicht rückgängig machen'),
        findsOneWidget,
      );
      await tap(tester, find.text('Heftseite löschen'), settle: false);
      await tester.pumpAndSettle();
      expect(deleted, {'page0'});
      expect(find.text('1–20 von 46'), findsWidgets);
      expect(requests.where((request) => request.method == 'DELETE'), isEmpty);
      expect(
        requests.where((request) => request.method == 'POST'),
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'KI reread needs one explicit confirmation and opens persisted job',
    (tester) async {
      final writes = <http.Request>[];
      await open(
        tester,
        respond: (request) async {
          if (request.method == 'POST') {
            writes.add(request);
            expect(request.url.path, '/api/materials/page0/reprocess');
            expect(jsonDecode(request.body), {'revision': 1});
            expect(
              request.headers['Idempotency-Key'] ??
                  request.headers['idempotency-key'],
              isNotEmpty,
            );
            return jsonReply({
              'id': 'new-job',
              'status': 'queued',
              'material_id': 'new-page',
            });
          }
          if (request.url.path.endsWith('/subjects')) {
            return jsonReply(subjects());
          }
          if (request.url.path.endsWith('/image')) {
            return http.Response.bytes(
              img.encodePng(img.Image(width: 4, height: 4)),
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          return jsonReply(pages(request));
        },
      );
      expect(writes, isEmpty);
      await tap(tester, find.byTooltip('Mit KI neu lesen'), settle: false);
      expect(find.text('Seite neu einlesen?'), findsOneWidget);
      expect(writes, isEmpty);
      await tap(tester, find.text('Mit KI neu einlesen'), settle: false);
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(find.text('Neue Erkennung: new-page / new-job'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'All matching pages can be selected across pagination and deleted after preview',
    (tester) async {
      var removed = false;
      final writes = <http.Request>[];
      await open(
        tester,
        photos: false,
        respond: (request) async {
          if (request.method == 'POST') {
            writes.add(request);
            if (request.url.path.endsWith('/delete-preview')) {
              expect(jsonDecode(request.body), {
                'all_matching': true,
                'filters': {'subject_id': mathId, 'q': '', 'status': 'all'},
              });
              return jsonReply({
                'count': 47,
                'selection_token': 'all-own-math',
              });
            }
            expect(request.url.path.endsWith('/bulk-delete'), isTrue);
            expect(jsonDecode(request.body), {
              'selection_token': 'all-own-math',
              'delete_linked_units': true,
            });
            removed = true;
            return jsonReply({'deleted_count': 47});
          }
          if (request.url.path.endsWith('/subjects')) {
            return jsonReply(subjects());
          }
          return jsonReply(
            pages(
              request,
              photos: false,
              deleted: removed ? {for (var i = 0; i < 47; i++) 'page$i'} : {},
            ),
          );
        },
      );
      await tap(tester, find.text('Liste'));
      await tap(tester, find.text('Seiten auswählen'));
      await tap(tester, find.text('Alle auswählen'));
      expect(find.text('Auswahl löschen (47)'), findsOneWidget);
      await tap(tester, find.byTooltip('Nächste Übersicht'));
      expect(find.text('21–40 von 47'), findsWidgets);
      expect(find.text('Auswahl löschen (47)'), findsOneWidget);
      expect(writes, isEmpty);
      await tap(tester, find.text('Auswahl löschen (47)'), settle: false);
      expect(find.text('47 Heftseiten löschen?'), findsOneWidget);
      expect(writes, hasLength(1)); // confirmation is still pending
      await tap(tester, find.text('47 Heftseiten löschen'), settle: false);
      await tester.pumpAndSettle();
      expect(writes, hasLength(2));
      expect(
        find.text('Hier sind noch keine Heftseiten vorhanden.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Specific selections survive a page change without selecting other pages',
    (tester) async {
      final writes = <http.Request>[];
      await open(
        tester,
        photos: false,
        respond: (request) async {
          if (request.method == 'POST') {
            writes.add(request);
            expect(request.url.path.endsWith('/delete-preview'), isTrue);
            expect(jsonDecode(request.body), {
              'ids': ['page0', 'page20'],
            });
            return jsonReply({'count': 2, 'selection_token': 'two-pages'});
          }
          if (request.url.path.endsWith('/subjects')) {
            return jsonReply(subjects());
          }
          return jsonReply(pages(request, photos: false));
        },
      );
      await tap(tester, find.text('Liste'));
      await tap(tester, find.text('Seiten auswählen'));
      await tap(tester, find.byType(Checkbox).first);
      expect(find.text('Auswahl löschen (1)'), findsOneWidget);
      await tap(tester, find.byTooltip('Nächste Übersicht'));
      await tap(tester, find.byType(Checkbox).first);
      expect(find.text('Auswahl löschen (2)'), findsOneWidget);
      await tap(tester, find.text('Auswahl löschen (2)'), settle: false);
      expect(find.text('2 Heftseiten löschen?'), findsOneWidget);
      await tap(tester, find.text('Abbrechen'), settle: false);
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Fixed examples show no destructive or KI controls in any view', (
    tester,
  ) async {
    await open(
      tester,
      photos: false,
      respond: (request) async {
        expect(request.method, 'GET');
        if (request.url.path.endsWith('/subjects')) {
          return jsonReply(subjects());
        }
        final response = pages(request, photos: false);
        for (final row in response['items'] as List) {
          row['fixed_example'] = true;
        }
        return jsonReply(response);
      },
    );
    for (final view in ['Blättern', 'Kacheln', 'Liste']) {
      await tap(tester, find.text(view));
      expect(find.byTooltip('Heftseite löschen'), findsNothing);
      expect(find.byTooltip('Mit KI neu lesen'), findsNothing);
      expect(find.text('Alles löschen'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Selection resets on search and account changes, without writes',
    (tester) async {
      final (state, _, requests) = await open(tester, photos: false);
      await tap(tester, find.text('Liste'));
      await tap(tester, find.text('Seiten auswählen'));
      await tap(tester, find.text('Alle auswählen'));
      expect(find.text('Auswahl löschen (47)'), findsOneWidget);
      await tap(tester, find.byTooltip('Im Hefter suchen'));
      await tester.enterText(find.byType(TextField), 'Brüche');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Auswahl löschen (47)'), findsNothing);
      expect(find.text('Seiten auswählen'), findsOneWidget);
      await tap(tester, find.text('Seiten auswählen'));
      await tap(tester, find.text('Alle auswählen'));
      state.user = {
        'id': 'another-child',
        'role': 'child',
        'child_id': 'other',
      };
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(find.textContaining('ausgewählt'), findsNothing);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Delete-all cancellation leaves every page unchanged', (
    tester,
  ) async {
    final (_, _, requests) = await open(
      tester,
      photos: false,
      respond: (request) async {
        if (request.url.path.endsWith('/delete-preview')) {
          return jsonReply({'count': 47, 'selection_token': 'cancelled'});
        }
        expect(request.method, 'GET');
        if (request.url.path.endsWith('/subjects')) {
          return jsonReply(subjects());
        }
        return jsonReply(pages(request, photos: false));
      },
    );
    await tap(tester, find.text('Liste'));
    await tap(tester, find.text('Alles löschen'), settle: false);
    expect(find.text('47 Heftseiten löschen?'), findsOneWidget);
    await tap(tester, find.text('Abbrechen'), settle: false);
    await tester.pumpAndSettle();
    expect(find.text('1–20 von 47'), findsWidgets);
    expect(requests.where((r) => r.url.path.endsWith('/bulk-delete')), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Parents can delete managed pages; read-only parents cannot', (
    tester,
  ) async {
    await open(tester, parent: true, canManage: true);
    expect(find.byTooltip('Heftseite löschen'), findsOneWidget);
    expect(find.byTooltip('Mit KI neu lesen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await open(tester, parent: true, canManage: false);
    expect(find.byTooltip('Heftseite löschen'), findsNothing);
    expect(find.byTooltip('Mit KI neu lesen'), findsNothing);
    await tap(tester, find.text('Liste'));
    expect(find.text('Seiten auswählen'), findsNothing);
    expect(find.text('Alles löschen'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Large text and reduced motion keep controls usable at320px', (
    tester,
  ) async {
    await open(
      tester,
      width: 320,
      textScale: 2,
      reducedMotion: true,
      photos: false,
    );
    await tap(tester, find.text('Liste'));
    await tap(tester, find.text('Seiten auswählen'));
    await tap(tester, find.text('Alle auswählen'));
    expect(find.text('Auswahl löschen (47)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('Auswahl aufheben'));
    await tap(tester, find.text('Kacheln'));
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('Blättern'));
    expect(
      find
          .byType(AnimatedSwitcher)
          .evaluate()
          .map((e) => (e.widget as AnimatedSwitcher).duration),
      contains(Duration.zero),
    );
    expect(find.text('Diese Seite enthält Text, kein Foto.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Keyboard and a slow swipe turn pages; source opening starts no learning',
    (tester) async {
      final (_, _, requests) = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('2 von 47'), findsWidgets);
      final gesture = find
          .byWidgetPredicate(
            (w) => w is GestureDetector && w.onHorizontalDragEnd != null,
          )
          .first;
      await tester.ensureVisible(gesture);
      await tester.timedDrag(
        gesture,
        const Offset(-110, 0),
        const Duration(milliseconds: 1000),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 von 47'), findsWidgets);
      await tap(tester, find.text('Text & Lernen'));
      expect(find.text('Quelltext & Lernen'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Search opens by action and clearing it restores the unfiltered album',
    (tester) async {
      final (_, _, requests) = await open(tester);
      expect(find.byType(TextField), findsNothing);
      await tap(tester, find.byTooltip('Im Hefter suchen'));
      await tester.enterText(find.byType(TextField), 'Brüche');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        requests
            .where((r) => r.url.path.endsWith('/materials'))
            .last
            .url
            .queryParameters['q'],
        'Brüche',
      );
      await tap(tester, find.byTooltip('Suchfeld einklappen'));
      expect(find.byType(TextField), findsNothing);
      expect(
        requests
            .where((r) => r.url.path.endsWith('/materials'))
            .last
            .url
            .queryParameters['q'],
        'Brüche',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'An older backend that ignores subject filtering cannot mislabel pages',
    (tester) async {
      await open(
        tester,
        respond: (r) async {
          if (r.url.path.endsWith('/subjects')) return jsonReply(subjects());
          final result = pages(r);
          for (final item in result['items'] as List) {
            item.remove('has_image');
            item.remove('subject_id');
          }
          return jsonReply(result);
        },
      );
      expect(
        find.text(
          'Dieser Hefter kann gerade nicht geöffnet werden. Bitte später erneut laden.',
        ),
        findsOneWidget,
      );
      expect(find.text('Lernstoff 0'), findsNothing);
      expect(find.byType(NotebookPhoto), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Logout discards a photo still downloading and hides the previous album',
    (tester) async {
      final pending = Completer<http.Response>();
      final (state, _, _) = await open(
        tester,
        settle: false,
        respond: (r) async {
          if (r.url.path.endsWith('/subjects')) return jsonReply(subjects());
          if (r.url.path.endsWith('/image')) return pending.future;
          return jsonReply(pages(r));
        },
      );
      state.user = null;
      state.notifyListeners();
      await tester.pump();
      pending.complete(
        http.Response.bytes(img.encodePng(img.Image(width: 2, height: 2)), 200),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotebookPhoto), findsNothing);
      expect(find.text('Lernstoff 0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1280.0]) {
      testWidgets(
        'Child notebook uses shared heading and accessible view controls at $width $brightness',
        (tester) async {
          final (_, _, requests) = await open(
            tester,
            width: width,
            brightness: brightness,
            textScale: width == 320 ? 2 : 1,
            photos: false,
          );
          expect(find.byType(ChildSectionHero), findsOneWidget);
          expect(find.byType(ChildSectionTabs), findsOneWidget);
          expect(find.byType(ChoiceChip), findsNothing);
          final photoButton = find.descendant(
            of: find.byType(ChildSectionHero),
            matching: find.byType(FilledButton),
          );
          expect(tester.getSize(photoButton).height, greaterThanOrEqualTo(54));
          expect(find.text('Alle Hefter'), findsOneWidget);
          expect(find.text('Themen entdecken'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tap(tester, find.text('Liste'));
          expect(
            tester
                .widget<ChildSectionTabs>(find.byType(ChildSectionTabs))
                .selected,
            'list',
          );
          expect(find.byType(ListView), findsOneWidget);
          await tap(tester, find.text('Filter'));
          expect(find.text('Seitenstatus'), findsOneWidget);
          if (width == 1280) {
            await tap(tester, find.text('Zeitraum wählen'));
            expect(
              Theme.of(tester.element(find.byType(DateRangePickerDialog)))
                  .brightness,
              brightness,
            );
            await tap(tester, find.byType(CloseButton));
          }
          await tap(tester, find.text('Anzeigen'));
          expect(tester.takeException(), isNull);
          expect(requests.every((request) => request.method == 'GET'), isTrue);

          await tap(tester, find.text('Heftfoto hinzufügen'));
          expect(find.text('Deine neuen Heftfotos'), findsOneWidget);
          expect(requests.every((request) => request.method == 'GET'), isTrue);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('Parent notebook retains existing heading and view controls', (
    tester,
  ) async {
    final (_, _, requests) = await open(tester, parent: true, canManage: true);
    expect(find.byType(ChildSectionHero), findsNothing);
    expect(find.byType(ChildSectionTabs), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(3));
    expect(find.byTooltip('Heftfoto hinzufügen'), findsOneWidget);
    expect(find.byTooltip('Alle Hefter'), findsOneWidget);
    await tap(tester, find.text('Liste'));
    expect(find.byType(ListView), findsOneWidget);
    expect(requests.every((request) => request.method == 'GET'), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
