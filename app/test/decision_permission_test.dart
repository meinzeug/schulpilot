import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'adaptive_learning_room_test.dart'
    show GuidedRound, openWithPreparationRoute;
import 'learning_room_test.dart' as room;

class PermissionRound extends GuidedRound {
  final bool? freshPermission;
  final bool support;
  PermissionRound({this.freshPermission, this.support = false}) {
    value['supports_question_explanation'] = true;
    session['can_request_decision'] = !support;
    if (support) session['can_request_support_check'] = true;
    session['action'] = {
      'kind': 'visual_example',
      'reason_code': 'change_explanation',
      'title': 'Eine andere Erklärung hilft',
      'resources': [],
    };
  }

  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/learning-session')) {
      final flag = support
          ? 'can_request_support_check'
          : 'can_request_decision';
      if (freshPermission == null) {
        session.remove(flag);
      } else {
        session[flag] = freshPermission;
      }
    }
    return super.handle(request);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'A spent modern plan uses saved explanation without another decision',
    (tester) async {
      final server = PermissionRound(freshPermission: false);
      server.session['can_request_decision'] = false;
      server.session['instructional_plan'] = null;
      server.session['decision_preparation'] = {
        'id': 'old-plan',
        'status': 'completed',
      };
      await room.openRound(tester, server);
      expect(find.text('Passenden Lernweg finden'), findsNothing);
      expect(find.text('Erklärung ansehen'), findsOneWidget);
      expect(server.planRequests, isEmpty);
      await tester.ensureVisible(find.text('Erklärung ansehen'));
      await tester.tap(find.text('Erklärung ansehen'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Kurz erklärt'), findsOneWidget);
      expect(find.text('Erklärung einer einzelnen Aufgabe.'), findsOneWidget);
      expect(server.planRequests, isEmpty);
      expect(server.answers, 0);
      expect(
        server.calls.where((call) => call.endsWith('/explanation')).length,
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Weiter üben'));
      await tester.pumpAndSettle();
    },
  );

  for (final permission in [false, null]) {
    testWidgets(
      'Fresh ${permission == false ? 'refusal refreshes without POST' : 'legacy missing flag preserves explicit protocol'}',
      (tester) async {
        final server = PermissionRound(freshPermission: permission);
        await openWithPreparationRoute(tester, server);
        expect(find.text('Passenden Lernweg finden'), findsOneWidget);
        await room.tapText(tester, 'Passenden Lernweg finden');
        expect(server.planRequests.length, permission == false ? 0 : 1);
        if (permission == false) {
          expect(find.text('Passenden Lernweg finden'), findsNothing);
          expect(find.text('Erklärung ansehen'), findsOneWidget);
          expect(
            server.calls.where((call) => call == 'GET /api/units/unit').length,
            2,
          );
        } else {
          expect(find.text('Gespeicherte Planvorbereitung'), findsOneWidget);
        }
        expect(server.answers, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('A fresh support-check refusal also avoids a new request', (
    tester,
  ) async {
    final server = PermissionRound(freshPermission: false, support: true);
    await room.openRound(tester, server);
    await room.tapText(tester, 'Hilfe');
    await tester.ensureVisible(find.text('Mehr Hilfe'));
    await tester.tap(find.text('Mehr Hilfe'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.ensureVisible(find.text('Nach der Erklärung neu probieren'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Nach der Erklärung neu probieren'));
    await tester.pumpAndSettle();
    expect(
      server.calls.where((call) => call.endsWith('/learning-session/check')),
      isEmpty,
    );
    expect(server.session['can_request_support_check'], false);
    expect(server.planRequests, isEmpty);
    expect(server.answers, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A legacy session without a permission flag never invents a model action',
    (tester) async {
      final server = PermissionRound();
      server.session.remove('can_request_decision');
      await room.openRound(tester, server);
      expect(find.text('Passenden Lernweg finden'), findsNothing);
      await room.tapText(tester, 'Hilfe');
      expect(server.hints, 1);
      expect(server.planRequests, isEmpty);
      expect(server.answers, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
