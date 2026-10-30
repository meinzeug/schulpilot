import 'package:flutter_test/flutter_test.dart';

import 'qa100_graphics_test.dart' as fixture;

void main() {
  testWidgets('Legacy empty calendar shows a clear fallback on mobile', (
    t,
  ) async {
    final h = fixture.Harness();
    await h.mount(
      t,
      h.words({
        'kind': 'timeline',
        'variant': 'calendar',
        'title': 'Zeitfolge',
        'labels': [],
        'numbers': [],
      }),
    );
    expect(
      find.text('Diese Grafik kann gerade nicht angezeigt werden.'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('Calendar entries remain visible and ordered on mobile', (
    t,
  ) async {
    final h = fixture.Harness();
    await h.mount(
      t,
      h.words({
        'kind': 'timeline',
        'variant': 'calendar',
        'title': 'Zeitfolge',
        'labels': ['Gestern', 'Heute'],
        'numbers': [],
      }),
    );
    expect(find.text('Gestern'), findsOneWidget);
    expect(find.text('Heute'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('Gestern')).dy,
      lessThan(t.getTopLeft(find.text('Heute')).dy),
    );
    expect(t.takeException(), isNull);
  });
}
