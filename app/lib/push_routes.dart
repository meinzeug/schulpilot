/// Only server-generated local destinations supported by the current app.
/// Access is always checked again by the destination's authenticated API.
String? safePushRoute(Object? value) {
  if (value is! String || value.length > 240) return null;
  if (value == '/app') return value;
  final match = RegExp(
    r'^(?:/exams/[a-f0-9]{32}\?exam=[a-f0-9]{32}(?:&session=[a-f0-9]{32})?(?:&tab=review)?|/unit/[a-f0-9]{32}|/after-school/[a-f0-9]{32}\?day=[a-f0-9]{32})',
  ).matchAsPrefix(value);
  return match?.end == value.length ? value : null;
}

String? pushMessageRoute(Map<String, dynamic> data) =>
    safePushRoute(data['exam_path']) ?? safePushRoute(data['route']);
