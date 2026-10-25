import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/unit_sources_viewer.dart';

import 'learning_room_test.dart' as room;

const first = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const second = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
Json ref(String id, [String status = 'ready']) => {
  'material_id': id,
  'revision': status == 'legacy' ? null : 1,
  'current_revision': status == 'changed' ? 2 : 1,
  'status': status,
  'title': 'Künstliches Ferienblatt',
  'has_image': true,
};
Finder inside(Finder f) =>
    find.descendant(of: find.byType(UnitSourcesViewer), matching: f);
Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> overview(WidgetTester t) =>
    tap(t, find.byKey(const ValueKey('round-overview-open')));
Future<void> sources(WidgetTester t) =>
    tap(t, find.text('Heftquellen ansehen'));
Future<void> back(WidgetTester t) =>
    tap(t, inside(find.byTooltip('Zur Aufgabe zurück')));

// Invented local original page and answers only. Every HTTP transport is fake.
class SourceRound extends room.SavedRound {
  final requests = <http.Request>[];
  bool image = true, wrongChild = false, imageChanged = false;
  Completer<http.Response>? delayed;
  SourceRound({bool short = false, List<Json>? references})
    : super(
        questions: [
          room.question('cat', type: short ? 'short' : 'choice'),
          room.question('dog'),
        ],
      ) {
    value['sources'] = references ?? [ref(first)];
  }
  Json metadata(String id) => {
    'unit_id': 'unit',
    'child_id': wrongChild ? 'another-child' : 'child',
    'material_id': id,
    'revision': 1,
    'confirmed': true,
    'has_image': image,
    'title': 'Künstliche Originalseite',
    'content': 'Bestätigter künstlicher Originaltext.',
  };
  @override
  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    if (r.url.path.contains('/sources/')) {
      expect(r.method, 'GET');
      expect(r.url.queryParameters, {'revision': '1'});
      if (r.url.path.endsWith('/image')) {
        if (imageChanged) {
          return room.jsonReply({'detail': 'PRIVATE SERVER MESSAGE'}, 409);
        }
        return http.Response.bytes(
          Uint8List.fromList(img.encodePng(img.Image(width: 24, height: 32))),
          200,
        );
      }
      if (delayed != null) return delayed!.future;
      return room.jsonReply(metadata(r.url.path.split('/').last));
    }
    return super.handle(r);
  }

  Iterable<http.Request> get sourceGets =>
      requests.where((r) => r.url.path.contains('/sources/'));
  Iterable<http.Request> get forbidden => requests.where(
    (r) =>
        r.method != 'GET' &&
        !r.url.path.endsWith('/heartbeat') &&
        !r.url.path.endsWith('/learning-session/draft') &&
        !r.url.path.endsWith('/hint'),
  );
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Reading original sources retains the short draft and the overview filter',
    (t) async {
      final s = SourceRound(short: true);
      final h = await room.openRound(t, s);
      await t.enterText(
        find.byType(TextField).first,
        'Mein ungesendeter Entwurf',
      );
      await overview(t);
      await tap(t, find.byKey(const ValueKey('round-filter-open')));
      await sources(t);
      expect(inside(find.byType(Image)), findsOneWidget);
      expect(s.sourceGets.map((r) => r.url.path), [
        '/api/units/unit/sources/$first',
        '/api/units/unit/sources/$first/image',
      ]);
      await back(t);
      expect(
        t
            .widget<ChoiceChip>(find.byKey(const ValueKey('round-filter-open')))
            .selected,
        true,
      );
      await tap(t, find.text('Zur aktuellen Aufgabe'));
      expect(
        t.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Mein ungesendeter Entwurf',
      );
      expect(find.text('Üben · Aufgabe 1 von 2'), findsOneWidget);
      expect(s.answers, 0);
      expect(s.starts, 0);
      expect(s.forbidden, isEmpty);
      await h.close();
    },
  );

  testWidgets('An unsubmitted choice remains selected after source reading', (
    t,
  ) async {
    final s = SourceRound();
    final h = await room.openRound(t, s);
    await room.tapText(t, 'Katze');
    await overview(t);
    await sources(t);
    await back(t);
    await tap(t, find.text('Zur aktuellen Aufgabe'));
    expect(
      t.widget<RadioGroup<String>>(find.byType(RadioGroup<String>)).groupValue,
      'Katze',
    );
    expect(s.answers, 0);
    expect(s.forbidden, isEmpty);
    await h.close();
  });

  testWidgets(
    'More help opens the same source viewer without a second hint or phase advance',
    (t) async {
      final s = SourceRound();
      final h = await room.openRound(t, s);
      await room.tapText(t, 'Hilfe');
      expect(s.hints, 1);
      await t.ensureVisible(find.text('Mehr Hilfe'));
      await t.tap(find.text('Mehr Hilfe'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Was hilft dir jetzt?'), findsOneWidget);
      await t.ensureVisible(find.text('Heftquellen ansehen'));
      await t.pump();
      expect(find.text('Heftquellen ansehen').hitTestable(), findsOneWidget);
      await t.tap(find.text('Heftquellen ansehen'));
      await t.pumpAndSettle();
      expect(find.byType(UnitSourcesViewer), findsOneWidget);
      await back(t);
      expect(find.text('Eine Katze miaut.'), findsWidgets);
      expect(s.hints, 1);
      expect(s.answers, 0);
      expect(s.forbidden, isEmpty);
      await h.close();
    },
  );

  testWidgets(
    'Only the selected source loads and page switching retains one image',
    (t) async {
      final s = SourceRound(references: [ref(first), ref(second)]);
      final h = await room.openRound(t, s);
      await overview(t);
      await sources(t);
      expect(s.sourceGets, hasLength(2));
      await tap(t, inside(find.text('Seite 2')));
      expect(s.sourceGets, hasLength(4));
      expect(
        s.sourceGets.last.url.path,
        '/api/units/unit/sources/$second/image',
      );
      expect(inside(find.byType(Image)), findsOneWidget);
      expect(s.forbidden, isEmpty);
      await h.close();
    },
  );

  for (final status in ['changed', 'legacy', 'unconfirmed']) {
    testWidgets(
      '$status metadata never causes an unbound source or photo GET',
      (t) async {
        final s = SourceRound(references: [ref(first, status)]);
        final h = await room.openRound(t, s);
        await overview(t);
        await sources(t);
        expect(s.sourceGets, isEmpty);
        expect(inside(find.byType(Image)), findsNothing);
        expect(
          inside(
            find.textContaining(switch (status) {
              'legacy' => 'Quellversion',
              'unconfirmed' => 'nicht mehr bestätigt',
              _ => 'wurde geändert',
            }),
          ),
          findsOneWidget,
        );
        expect(s.forbidden, isEmpty);
        await h.close();
      },
    );
  }

  for (final invalid in ['wrong-child', 'image-revision']) {
    testWidgets('$invalid rejects private content without raw error output', (
      t,
    ) async {
      final s = SourceRound()
        ..wrongChild = invalid == 'wrong-child'
        ..imageChanged = invalid == 'image-revision';
      final h = await room.openRound(t, s);
      await overview(t);
      await sources(t);
      expect(inside(find.textContaining('wurde geändert')), findsOneWidget);
      expect(find.textContaining('PRIVATE SERVER MESSAGE'), findsNothing);
      expect(inside(find.byType(Image)), findsNothing);
      expect(
        inside(find.textContaining('Bestätigter künstlicher Originaltext.')),
        findsNothing,
      );
      expect(s.sourceGets, hasLength(invalid == 'wrong-child' ? 1 : 2));
      await h.close();
    });
  }

  testWidgets(
    'Token revocation closes the private source and stale close cannot pop another route',
    (t) async {
      final s = SourceRound();
      final h = await room.openRound(t, s);
      await overview(t);
      await sources(t);
      final oldClose = t
          .widget<IconButton>(
            inside(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Zur Aufgabe zurück',
              ),
            ),
          )
          .onPressed!;
      h.state.api.token = 'replacement-session';
      h.state.refreshState();
      await t.pumpAndSettle();
      expect(find.byType(UnitSourcesViewer), findsNothing);
      oldClose();
      await t.pumpAndSettle();
      expect(s.forbidden, isEmpty);
      expect(t.takeException(), isNull);
      await h.close();
    },
  );

  testWidgets(
    'A late source response after logout cannot fetch or display a photo',
    (t) async {
      final s = SourceRound()..delayed = Completer<http.Response>();
      final h = await room.openRound(t, s);
      await overview(t);
      await t.tap(find.text('Heftquellen ansehen'));
      await t.pump();
      h.state.user = null;
      h.state.refreshState();
      s.delayed!.complete(room.jsonReply(s.metadata(first)));
      await t.pumpAndSettle();
      expect(find.byType(UnitSourcesViewer), findsNothing);
      expect(s.sourceGets.where((r) => r.url.path.endsWith('/image')), isEmpty);
      expect(s.forbidden, isEmpty);
      await h.close();
    },
  );

  testWidgets(
    'A source viewer closes in the background and never reopens itself',
    (t) async {
      final s = SourceRound();
      final h = await room.openRound(t, s);
      await overview(t);
      await sources(t);
      final provider = t.widget<Image>(inside(find.byType(Image))).image;
      final imageKey = await provider.obtainKey(const ImageConfiguration());
      expect(PaintingBinding.instance.imageCache.containsKey(imageKey), true);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pumpAndSettle();
      // Paused bindings do not draw/dispose route widgets until resume. The
      // private decoded image must already be evicted while frames are stopped.
      expect(PaintingBinding.instance.imageCache.containsKey(imageKey), false);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.byType(UnitSourcesViewer), findsNothing);
      expect(s.sourceGets, hasLength(2));
      expect(s.forbidden, isEmpty);
      await h.close();
    },
  );

  testWidgets('An old zoom callback cannot interact behind a foreign dialog', (
    t,
  ) async {
    final s = SourceRound();
    final h = await room.openRound(t, s);
    await overview(t);
    await sources(t);
    final zoom = t
        .widget<IconButton>(
          inside(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Foto vergrößern',
            ),
          ),
        )
        .onPressed!;
    final context = t.element(find.byType(UnitSourcesViewer));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Andere Ansicht'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Zurück'),
            ),
          ],
        ),
      ),
    );
    await t.pumpAndSettle();
    zoom();
    await t.pumpAndSettle();
    expect(find.text('Andere Ansicht'), findsOneWidget);
    expect(
      t
          .widget<InteractiveViewer>(inside(find.byType(InteractiveViewer)))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      1,
    );
    expect(s.sourceGets, hasLength(2));
    expect(s.forbidden, isEmpty);
    await h.close();
  });

  testWidgets(
    'Source pages without a photo retain the complete confirmed text',
    (t) async {
      final s = SourceRound()..image = false;
      final h = await room.openRound(t, s);
      await overview(t);
      await sources(t);
      expect(
        inside(find.textContaining('Bestätigter künstlicher Originaltext.')),
        findsOneWidget,
      );
      expect(s.sourceGets, hasLength(1));
      expect(inside(find.byType(Image)), findsNothing);
      expect(s.forbidden, isEmpty);
      await h.close();
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'The real viewer fits 320px at ${scale}x with accessible finite zoom',
      (t) async {
        final s = SourceRound();
        final h = await room.openRound(t, s, textScale: scale);
        await overview(t);
        await sources(t);
        for (final tooltip in ['Foto vergrößern', 'Foto verkleinern']) {
          final button = inside(find.byTooltip(tooltip));
          expect(button.hitTestable(), findsOneWidget);
          final rect = t.getRect(button);
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
        }
        await tap(t, inside(find.byTooltip('Foto vergrößern')));
        expect(
          t
              .widget<InteractiveViewer>(inside(find.byType(InteractiveViewer)))
              .transformationController!
              .value
              .getMaxScaleOnAxis(),
          2,
        );
        await tap(t, inside(find.text('Zurücksetzen')));
        expect(
          t
              .widget<InteractiveViewer>(inside(find.byType(InteractiveViewer)))
              .transformationController!
              .value
              .getMaxScaleOnAxis(),
          1,
        );
        expect(s.forbidden, isEmpty);
        expect(t.takeException(), isNull);
        await h.close();
      },
    );
  }
}
