import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/learning_navigation.dart';

void main() {
  test(
    'saved follow-up wins over a new review; active and mandatory stay first',
    () {
      final review = {'kind': 'review', 'id': 'old', 'status': 'not_started'};
      final ready = {'kind': 'unit', 'id': 'ready', 'status': 'not_started'};
      final active = {'kind': 'unit', 'id': 'active', 'status': 'paused'};
      final goal = {'kind': 'assignment', 'id': 'goal', 'mandatory': true};
      final data = <String, dynamic>{
        'plan': {
          'date': '2026-10-27',
          'today': <Map<String, dynamic>>[review, ready],
          'voluntary': <Map<String, dynamic>>[],
        },
      };
      expect(nextLearningItem(data)?['id'], 'ready');
      (data['plan']['today'] as List).insert(0, goal);
      expect(nextLearningItem(data)?['id'], 'goal');
      (data['plan']['voluntary'] as List).add(active);
      expect(nextLearningItem(data)?['id'], 'active');
      data['feedback_resume'] = {
        'kind': 'unit',
        'id': 'feedback',
        'pending_feedback': true,
      };
      expect(nextLearningItem(data)?['id'], 'feedback');
    },
  );
}
