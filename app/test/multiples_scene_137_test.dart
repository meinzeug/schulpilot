// Public synthetic compiler output, not an OCR, provider or learning proof.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_scene_player.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/ui.dart';

import 'learning_scene_player_test.dart' as scene;

Json compiledBlock() => Json.from(
  jsonDecode(File('../testdata/multiples_common_v1.json').readAsStringSync()),
);

ThemeData measuredTheme() {
  final theme = appTheme(brightness: Brightness.dark);
  ButtonStyle measured(ButtonStyle? style) {
    final original = style ?? const ButtonStyle();
    return original.copyWith(
      textStyle: WidgetStateProperty.resolveWith(
        (states) => (original.textStyle?.resolve(states) ?? const TextStyle())
            .copyWith(fontFamily: 'Nunito'),
      ),
    );
  }

  // Flutter tests default an unqualified style fragment to Ahem. Use the
  // application's real family explicitly for this visual measurement only.
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Nunito'),
    filledButtonTheme: FilledButtonThemeData(
      style: measured(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: measured(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: measured(theme.textButtonTheme.style),
    ),
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: const TextStyle(fontFamily: 'Nunito'),
      secondaryLabelStyle: const TextStyle(fontFamily: 'Nunito'),
    ),
  );
}

Widget fixture(
  Json block,
  AppState state, {
  Set<String> stages = const {'solution'},
}) => Theme(
  data: measuredTheme(),
  child: RepaintBoundary(
    key: const ValueKey('multiples-public-proof'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Künstliches Darstellungsbeispiel'),
        const SizedBox(height: 12),
        SubjectPresentation(
          {
            'version': 1,
            'blocks': [block],
          },
          stages: stages,
          state: state,
        ),
      ],
    ),
  ),
);

Future<void> capture(WidgetTester tester, String name) async {
  // Local visual review is optional; CI checks geometry without writing files.
  final directory = Platform.environment['SCHULPILOT_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('multiples-public-proof')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in ['Nunito', 'SpaceGrotesk']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
    // Explicit TextStyle fragments use Flutter's default family. Load its real
    // SDK font and icons too, instead of measuring square Ahem test glyphs.
    final fonts =
        '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts';
    for (final (family, file) in [
      ('Roboto', 'Roboto-Regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(await File('$fonts/$file').readAsBytes()),
            ),
          ))
          .load();
    }
  });

  for (final width in [320.0, 390.0, 768.0, 1100.0]) {
    testWidgets('137 compiled multiples scene stays usable at $width', (
      tester,
    ) async {
      final calls = <http.Request>[];
      final state = scene.actor(calls);
      final viewport = Size(width, 844);
      scene.size(tester, viewport);
      final block = compiledBlock();
      final before = jsonEncode(block);
      await tester.pumpWidget(
        scene.host(
          fixture(block, state),
          size: viewport,
          scale: width == 320 ? 2 : 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LearningScenePlayer), findsOneWidget);
      for (final object in block['scene']['objects'] as List) {
        final finder = find.byKey(ValueKey('scene-node-${object['id']}'));
        expect(finder, findsOneWidget);
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(find.text(object['label']), findsWidgets);
      }
      await capture(tester, 'multiples-$width-step1');
      await scene.tapVisible(tester, find.byTooltip('Nächster Grafikschritt'));
      expect(scene.sliderValue(tester), 1);
      expect(find.text('Schritt 2 von 2'), findsOneWidget);
      await capture(tester, 'multiples-$width-step2');
      await scene.tapVisible(
        tester,
        find.byKey(const ValueKey('scene-reset-view')),
      );
      expect(scene.sliderValue(tester), 0);
      expect(jsonEncode(block), before);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  }

  testWidgets('137 compiled multiples animation can pause and reset locally', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = scene.actor(calls);
    scene.size(tester, const Size(390, 844));
    await tester.pumpWidget(scene.host(fixture(compiledBlock(), state)));
    await tester.pumpAndSettle();
    final play = find.byKey(scene.playKey);
    await tester.ensureVisible(play);
    await tester.pumpAndSettle();
    await tester.tap(play);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Pausieren'), findsOneWidget);
    expect(scene.sliderValue(tester), greaterThan(0));
    await tester.tap(play);
    await tester.pump();
    final stopped = scene.sliderValue(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(scene.sliderValue(tester), stopped);
    await scene.tapVisible(
      tester,
      find.byKey(const ValueKey('scene-reset-view')),
    );
    expect(scene.sliderValue(tester), 0);
    expect(calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('137 reduced motion retains explicit mathematical steps', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = scene.actor(calls);
    scene.size(tester, const Size(390, 844));
    await tester.pumpWidget(
      scene.host(fixture(compiledBlock(), state), reduced: true),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byKey(scene.playKey)).onPressed,
      isNull,
    );
    await scene.tapVisible(tester, find.byTooltip('Nächster Grafikschritt'));
    expect(scene.sliderValue(tester), 1);
    expect(calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('137 a solution scene is hidden until its stage is disclosed', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = scene.actor(calls);
    scene.size(tester, const Size(390, 844));
    final block = compiledBlock();
    await tester.pumpWidget(
      scene.host(fixture(block, state, stages: const {'given'})),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LearningScenePlayer), findsNothing);
    expect(find.text(block['labels'][2]), findsNothing);
    expect(calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
