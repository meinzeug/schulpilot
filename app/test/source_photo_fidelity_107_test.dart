import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:schulpilot/material_screen.dart';

Uint8List crop(Uint8List bytes, {int turns = 0}) => encodeMaterialCrop({
  'bytes': bytes,
  'turns': turns,
  'left': 0.0,
  'top': 0.0,
  'right': 1.0,
  'bottom': 1.0,
});

void main() {
  test('new large photo retains3200px rather than1600px without metadata', () {
    final source = img.Image(width: 4000, height: 2000);
    img.fill(source, color: img.ColorRgb8(100, 30, 140));
    final encoded = Uint8List.fromList(img.encodeJpg(source));
    final output = img.decodeJpg(crop(encoded))!;
    expect([output.width, output.height], [3200, 1600]);
    expect(output.exif.isEmpty, isTrue);
  });

  test('existing small images are never enlarged to invent source detail', () {
    final source = img.Image(width: 240, height: 120);
    img.fill(source, color: img.ColorRgb8(30, 100, 160));
    final encoded = Uint8List.fromList(img.encodePng(source));
    final output = img.decodeJpg(crop(encoded))!;
    expect([output.width, output.height], [240, 120]);
  });

  test(
    'all four deliberate quarter turns preserve the selected photo extent',
    () {
      final source = img.Image(width: 120, height: 80);
      img.fill(source, color: img.ColorRgb8(70, 40, 150));
      final encoded = Uint8List.fromList(img.encodePng(source));
      for (final turns in [0, 1, 2, 3]) {
        final output = img.decodeJpg(crop(encoded, turns: turns))!;
        expect([
          output.width,
          output.height,
        ], turns.isEven ? [120, 80] : [80, 120]);
        expect(
          output.getPixel(output.width ~/ 2, output.height ~/ 2).b,
          greaterThan(120),
        );
      }
    },
  );
}
