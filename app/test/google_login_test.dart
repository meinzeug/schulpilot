import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/google_login.dart';

void main() {
  test('only the own completion route is accepted at native cold start', () {
    const flow = 'aabbccddeeff00112233445566778899';
    expect(
      nativeInitialLocation(
        'https://schulpilot.dorfspy.de/auth/google/complete#flow=$flow',
      ),
      '/auth/google/complete#flow=$flow',
    );
    expect(
      nativeInitialLocation('/auth/google/complete#flow=$flow'),
      '/auth/google/complete#flow=$flow',
    );
    for (final path in [
      'https://evil.example.org/auth/google/complete#flow=$flow',
      'http://schulpilot.dorfspy.de/auth/google/complete#flow=$flow',
      '/admin',
      '/settings',
      '/auth/google/start#request=untrusted',
    ]) {
      expect(nativeInitialLocation(path), '/app');
    }
  });
  test('flow fragment handles malformed, missing and hostile identifiers', () {
    expect(
      googleFlowId(
        Uri.parse(
          '/auth/google/complete#flow=aabbccddeeff00112233445566778899',
        ),
      ),
      'aabbccddeeff00112233445566778899',
    );
    for (final fragment in [
      'flow=../admin',
      'flow=short',
      'error=invalid',
      'flow=%ZZ',
      '',
    ]) {
      expect(
        googleFlowId(Uri(path: '/auth/google/complete', fragment: fragment)),
        isNull,
      );
    }
  });
}
