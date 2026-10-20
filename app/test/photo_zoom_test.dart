import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/notebook_photo.dart';
import 'package:schulpilot/ui.dart';

void main() {
  testWidgets(
    'Photo zoom buttons work at large text, remain bounded and reset for another private page',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((r) async {
            requests.add(r);
            return http.Response.bytes(
              img.encodePng(img.Image(width: 4, height: 6)),
              200,
              headers: {'content-type': 'image/png'},
            );
          }),
        ),
      )..user = {'id': 'synthetic-child', 'role': 'child'};
      Widget screen(String id) => MaterialApp(
        theme: appTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: NotebookPhoto(state, materialId: id, zoomable: true),
          ),
        ),
      );
      await tester.pumpWidget(screen('first'));
      await tester.pumpAndSettle();
      expect(find.text('100 %'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Foto vergrößern'));
        await tester.pump();
      }
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 8);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Foto vergrößern',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Foto verkleinern'));
      await tester.pump();
      expect(find.text('400 %'), findsOneWidget);
      await tester.tap(find.byTooltip('Fotoansicht zurücksetzen'));
      await tester.pump();
      expect(viewer.transformationController!.value.isIdentity(), isTrue);
      await tester.tap(find.byTooltip('Foto vergrößern'));
      await tester.pump();
      await tester.pumpWidget(screen('second'));
      await tester.pumpAndSettle();
      expect(find.text('100 %'), findsOneWidget);
      expect(requests.map((r) => r.url.path), [
        '/api/materials/first/image',
        '/api/materials/second/image',
      ]);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
