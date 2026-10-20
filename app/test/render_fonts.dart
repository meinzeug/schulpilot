import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Load the actual bundled formula fonts; Ahem cannot verify typesetting.
Future<void> loadFormulaFonts() async {
  final directory = File(Platform.resolvedExecutable).parent.parent.parent.path;
  final normal = await File('$directory/material_fonts/Roboto-Regular.ttf')
      .readAsBytes();
  await (FontLoader(
    'Roboto',
  )..addFont(Future.value(ByteData.sublistView(normal)))).load();
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  var count = 0;
  for (final entry in manifest) {
    final family = entry['family'] as String;
    if (!family.startsWith('packages/flutter_math_fork/')) {
      continue;
    }
    final loader = FontLoader(family);
    final asset = (entry['fonts'] as List).first;
    loader.addFont(rootBundle.load(asset['asset']));
    await loader.load();
    count++;
  }
  if (count < 12) {
    throw StateError(
      'Bundled KaTeX fonts missing from the actual test asset manifest.',
    );
  }
}
