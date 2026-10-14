import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/store_screens.dart';
import 'package:schulpilot/ui.dart';

void main() {
  testWidgets(
    'Checkout requires explicit acceptance, shows total and retries with the same request key',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final submissions = <Json>[];
      final state =
          AppState(
              api: Api(
                base: 'https://example.invalid/api',
                client: MockClient((request) async {
                  if (request.url.path.endsWith('/store/catalog')) {
                    return http.Response(
                      jsonEncode({
                        'enabled': true,
                        'revision': 7,
                        'tax_notice': 'Endpreis inkl. USt.',
                        'terms': 'Künstliche Vertragsfassung',
                        'plans': [
                          {
                            'id': 'start',
                            'name': 'Start',
                            'price_cents': 990,
                            'children': 1,
                            'calls': 300,
                          },
                        ],
                      }),
                      200,
                      headers: {
                        'content-type': 'application/json; charset=utf-8',
                      },
                    );
                  }
                  if (request.method == 'POST' &&
                      request.url.path.endsWith('/families/family/orders')) {
                    submissions.add(
                      Map<String, dynamic>.from(jsonDecode(request.body)),
                    );
                    return http.Response(
                      jsonEncode({
                        'detail': 'Bestellung noch nicht bestätigt.',
                      }),
                      503,
                      headers: {
                        'content-type': 'application/json; charset=utf-8',
                      },
                    );
                  }
                  throw StateError('Unexpected request');
                }),
              ),
            )
            ..user = {
              'id': 'parent',
              'role': 'parent',
              'display_name': 'Testeltern',
              'families': [
                {'id': 'family', 'name': 'Test', 'permission': 'owner'},
              ],
            }
            ..familyId = 'family';
      final router = GoRouter(
        initialLocation: '/bestellen/start',
        routes: [
          GoRoute(
            path: '/bestellen/:id',
            builder: (context, route) => CheckoutScreen(state, planId: 'start'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      final buy = find.widgetWithText(
        FilledButton,
        'Zahlungspflichtig bestellen',
      );
      expect(
        buy,
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      expect(tester.widget<FilledButton>(buy).onPressed, isNull);
      expect(find.text('Gesamtpreis: 9,90 €'), findsOneWidget);
      await tester.ensureVisible(find.byType(CheckboxListTile).first);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(buy);
      await tester.tap(buy);
      await tester.pumpAndSettle();
      expect(submissions, hasLength(1));
      expect(submissions.single['catalog_revision'], 7);
      expect(submissions.single['accept_terms'], true);
      expect(submissions.single['early_start'], false);
      expect(submissions.single.containsKey('amount_cents'), false);
      expect(find.text('Bestellung noch nicht bestätigt.'), findsOneWidget);
      await tester.ensureVisible(buy);
      await tester.tap(buy);
      await tester.pumpAndSettle();
      expect(submissions, hasLength(2));
      expect(submissions.first['request_key'], submissions.last['request_key']);
      expect(tester.takeException(), isNull);
    },
  );
}
