import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/main.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/ui.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Appearance changes preserve a form and its fragment without sending it',
    (tester) async {
      final requests = <String>[];
      final api = Api(
        base: 'https://example.invalid/api',
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          return http.Response(jsonEncode({'required': true}), 200);
        }),
      );
      final state = AppState(api: api);
      const code = 'synthetic_email_code_12345678901234567890';
      await tester.pumpWidget(
        SchulpilotApp(state, initialLocation: '/invite#token=$code'),
      );
      await tester.pumpAndSettle();
      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      await tester.enterText(field('Dein Anzeigename'), 'Künstlicher Entwurf');
      // The public invitation form has no account menu; its appearance action
      // remains directly in the authentication app bar.
      await tester.tap(find.byTooltip('Helles Design'));
      await tester.pumpAndSettle();
      expect(state.darkAppearance, isFalse);
      expect(
        Theme.of(tester.element(field('Dein Anzeigename'))).brightness,
        Brightness.light,
      );
      expect(
        tester.widget<TextField>(field('Dein Anzeigename')).controller!.text,
        'Künstlicher Entwurf',
      );
      expect(
        tester.widget<TextField>(field('Sicherer Link-Code')).controller!.text,
        code,
      );
      expect(requests, isEmpty);
      final restored = AppState(api: api);
      await restored.restore();
      expect(restored.darkAppearance, isFalse);
      expect(requests, ['GET /api/setup/status']);
      await state.setAppearance(true);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(field('Dein Anzeigename'))).brightness,
        Brightness.dark,
      );
      final restoredAgain = AppState(api: api);
      await restoredAgain.restore();
      expect(restoredAgain.darkAppearance, isTrue);
      expect(requests.every((r) => r == 'GET /api/setup/status'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'Fraction legend describes both portions and retains readable contrast in $brightness',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness: brightness),
            home: const Scaffold(body: FractionSumDiagram(prompt: '1/3 + 1/6')),
          ),
        );
        await tester.tap(find.text('Gleich einteilen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Anteile zusammenlegen'));
        await tester.pumpAndSettle();
        final legend = find.textContaining('A steht für 1/3, B für 1/6');
        expect(legend, findsOneWidget);
        // Letters no longer sit inside tiny colored cells. Check the actual
        // replacement legend against the inset on which it is rendered.
        final element = tester.element(legend);
        final text = tester.widget<Text>(legend);
        final color = DefaultTextStyle.of(element).style
            .merge(text.style)
            .color!;
        final inset = find
            .ancestor(of: legend, matching: find.byType(SurfaceInset))
            .first;
        final surface = tester.widget<Material>(
          find.descendant(of: inset, matching: find.byType(Material)).first,
        );
        final x = color.computeLuminance(),
            y = surface.color!.computeLuminance();
        expect(
          x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label ==
                    'A + B: 3/6: 3 von 6 gleich großen Teilen markiert.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'Semantic surfaces and secondary text are legible in $brightness',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness: brightness),
            home: Scaffold(
              body: Column(
                children: [
                  heading('Einordnung', subtitle: 'Ein eigener Nachweis'),
                  const Notice('Deine Antwort bleibt gespeichert.'),
                  const Tag('Vorbereitet'),
                ],
              ),
            ),
          ),
        );
        final p = AppPalette(isDark: brightness == Brightness.dark);
        final secondary = tester
            .widget<Text>(find.text('Ein eigener Nachweis'))
            .style!
            .color!;
        expect(secondary, p.muted);
        final notice = tester
            .widget<Text>(find.text('Deine Antwort bleibt gespeichert.'))
            .style!
            .color!;
        expect(notice, p.ink);
        double ratio(Color a, Color b) {
          final x = a.computeLuminance(), y = b.computeLuminance();
          return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
        }

        for (final bg in [p.cream, p.panelSurface, p.surfaceLow, p.mint]) {
          expect(ratio(p.muted, bg), greaterThanOrEqualTo(4.5));
          expect(ratio(p.teal, bg), greaterThanOrEqualTo(4.5));
          expect(ratio(p.controlBorder, bg), greaterThanOrEqualTo(3));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
