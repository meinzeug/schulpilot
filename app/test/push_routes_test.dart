import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/push_routes.dart';

void main() {
  const child = '11111111111111111111111111111111';
  const exam = '22222222222222222222222222222222';
  const session = '33333333333333333333333333333333';
  test('only supported local exam destinations pass the push boundary', () {
    for (final path in [
      '/app',
      '/unit/$exam',
      '/after-school/$child?day=$exam',
      '/exams/$child?exam=$exam',
      '/exams/$child?exam=$exam&session=$session',
      '/exams/$child?exam=$exam&tab=review',
    ]) {
      expect(safePushRoute(path), path);
    }
    for (final path in [
      null,
      1,
      'https://evil.invalid/app',
      '//evil.invalid/app',
      '/unit/$exam\n',
      '/exams/$child?exam=$exam\u2028',
      '/settings',
      '/after-school/$child',
      '/after-school/$child?day=$exam&next=/admin',
      '/after-school/$child?day=$exam&day=$session',
      '/after-school/$child?day=$exam\n',
      '/unit/$exam?next=evil',
      '/exams/$child',
      '/exams/$child?exam=$exam&exam=$session',
      '/exams/$child?exam=$exam&next=/admin',
      '/exams/$child?exam=$exam&tab=other',
      '/exams/$child?exam=$exam#secret',
      '/exams/$child?exam=wrong',
      '/exams/%31$child?exam=$exam',
    ]) {
      expect(safePushRoute(path), isNull, reason: '$path');
    }
    expect(
      pushMessageRoute({
        'route': '/app',
        'exam_path': '/exams/$child?exam=$exam',
      }),
      '/exams/$child?exam=$exam',
    );
    expect(
      pushMessageRoute({'route': '/app', 'exam_path': '//evil.invalid'}),
      '/app',
    );
  });
}
