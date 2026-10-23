import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'math_content.dart';
import 'learning_graphic_frame.dart';
import 'ui.dart';

/// Finite source-validated scientific models, with no model-drawn paths.
class ScienceGraphic extends StatelessWidget {
  static const kinds = {
    'function_graph',
    'data_plot',
    'cell',
    'molecule',
    'logic_table',
    'circuit_network',
    'technical_drawing',
    'function_curve',
    'process_graph',
    'process_cycle',
  };
  final Map<String, dynamic> block;
  final Widget? action;
  const ScienceGraphic(this.block, {super.key, this.action});
  List<double> get numbers =>
      (block['numbers'] as List).map((v) => (v as num).toDouble()).toList();
  List<String> get labels => (block['labels'] as List).cast<String>();
  String get connectionsDescription => ((block['connections'] as List?) ?? [])
      .map((e) => '${labels[e['start']]} führt zu ${labels[e['end']]}')
      .join('; ');
  static String number(num value) => value == value.roundToDouble()
      ? '${value.toInt()}'
      : '$value'.replaceAll('.', ',');
  static String tickLabel(double value, double span) {
    if (value.abs() < span.abs() * 1e-12 || value == 0) {
      return '0';
    }
    final parts = value.toStringAsPrecision(3).split('e');
    if (parts[0].contains('.')) {
      parts[0] = parts[0].replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return parts.join('e').replaceAll('.', ',');
  }

  List<List<String>> get logicRows {
    final variant = block['variant'];
    if (variant == 'not_gate') {
      return [
        ['A', 'Y'],
        ['0', '1'],
        ['1', '0'],
      ];
    }
    return [
      ['A', 'B', 'Y'],
      for (var a = 0; a <= 1; a++)
        for (var b = 0; b <= 1; b++)
          ['$a', '$b', '${variant == 'and_gate' ? a & b : a | b}'],
    ];
  }

  String get description => switch (block['kind']) {
    'function_curve' =>
      'Graph der belegten Standardfunktion. ${curveNames[block['variant']]}. Sichtbarer Ausschnitt: $curveDomain.${block['variant'] == 'reciprocal' ? ' Bei x=0 bleibt die Kurve unterbrochen.' : ''}',
    'process_graph' || 'process_cycle' =>
      '${block['kind'] == 'process_cycle' ? 'Geschlossener Kreislauf' : 'Gerichtetes Ablaufschema'} aus den belegten Pfeilen. ${labels.indexed.map((v) => '${v.$1 + 1}: ${v.$2}').join('; ')}. Pfeile: $connectionsDescription.',
    'function_graph' =>
      'Funktionsgraph des belegten Polynoms: a=${number(numbers[0])}, b=${number(numbers[1])}, c=${number(numbers[2])}. Die Achsen zeigen x und y. Dargestellter Ausschnitt: x von −4 bis 4.',
    'data_plot' =>
      '${block['variant'] == 'polyline' ? 'Verbundene Messpunkte, keine zusätzliche Kurvenanpassung' : 'Einzelne Messpunkte ohne Verbindung'}. Achsen x: ${labels[0]}; y: ${labels[1]}. Punkte: ${[for (var i = 0; i < numbers.length; i += 2) '(${number(numbers[i])}; ${number(numbers[i + 1])})'].join(', ')}.',
    'cell' =>
      'Vereinfachtes ${block['variant'] == 'plant_cell' ? 'Pflanzenzellmodell' : 'Tierzellmodell'}, nicht maßstabsgetreu. Nummern: ${labels.indexed.map((v) => '${v.$1 + 1}: ${v.$2}').join('; ')}.',
    'molecule' =>
      'Bindungsschema, keine räumliche Molekülgeometrie. ${switch (block['variant']) {
        'water' => 'H–O–H: zwei Einfachbindungen.',
        'carbon_dioxide' => 'O=C=O: zwei Doppelbindungen.',
        'methane' => 'Ein C-Atom mit vier Einfachbindungen zu vier H-Atomen.',
        _ => '\\(\\mathrm{CH}_3-\\mathrm{CH}_2-\\mathrm{OH}\\): zwei C-Atome, ein O-Atom, sechs H-Atome, nur Einfachbindungen.',
      }}',
    'circuit_network' =>
      block['variant'] == 'series'
          ? 'R1 und R2 in Reihe: ein gemeinsamer Strompfad.'
          : 'R1 und R2 parallel: zwei Zweige zwischen denselben beiden Knoten.',
    'technical_drawing' =>
      'Skizze, nicht maßstabsgetreu. Rechteckige Platte: Breite ${number(numbers[0])}, Höhe ${number(numbers[1])}, mittige Bohrung mit Durchmesser ${number(numbers[2])} ${block['unit']}.',
    'logic_table' =>
      'Wahrheitstafel ${block['variant'] == 'and_gate'
          ? 'UND'
          : block['variant'] == 'or_gate'
          ? 'ODER'
          : 'NICHT'}. 0 bedeutet falsch, 1 bedeutet wahr. ${logicRows.map((r) => r.join(', ')).join('; ')}.',
    _ => '',
  };
  String get curveDomain => switch (block['variant']) {
    'logarithm' => 'x von 0,1 bis 4',
    'square_root' => 'x von 0 bis 9',
    'exponential' => 'x von −3 bis 3',
    _ => 'x von −4 bis 4',
  };
  static const curveNames = {
    'sine': r'\(f(x)=\sin(x)\)',
    'cosine': r'\(f(x)=\cos(x)\)',
    'exponential': r'\(f(x)=e^x\)',
    'logarithm': r'\(f(x)=\ln(x)\)',
    'square_root': r'\(f(x)=\sqrt{x}\)',
    'reciprocal': r'\(f(x)=\frac{1}{x}\)',
    'cubic': r'\(f(x)=x^3\)',
    'absolute': r'\(f(x)=|x|\)',
  };
  @override
  Widget build(BuildContext context) => LearningGraphicFrame(
    title: block['title'],
    action: action,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (block['kind'] == 'logic_table')
          Table(
            border: TableBorder.all(color: context.palette.surfaceBorder),
            children: [
              for (final row in logicRows.indexed)
                TableRow(
                  decoration: row.$1 == 0
                      ? BoxDecoration(color: context.palette.surfaceLow)
                      : null,
                  children: [
                    for (final cell in row.$2)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          cell,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                  ],
                ),
            ],
          )
        else
          Semantics(
            image: true,
            label: MathText.spoken(description),
            child: ExcludeSemantics(
              child: SizedBox(
                height:
                    block['kind'] == 'molecule' && block['variant'] == 'ethanol'
                    ? 280
                    : 250,
                child: CustomPaint(
                  painter: SciencePainter(
                    block,
                    Theme.of(context).colorScheme.onSurface,
                    MediaQuery.textScalerOf(context).scale(14).clamp(14, 20),
                    Theme.of(context).textTheme.bodyMedium?.fontFamily,
                    palette: context.palette,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (block['kind'] == 'logic_table')
          MathText(
            description,
            style: const TextStyle(fontSize: 15, height: 1.5),
          )
        else
          ExcludeSemantics(
            child: MathText(
              description,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
        if (block['kind'] == 'data_plot')
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (var i = 0; i < numbers.length; i += 2)
                Text('(${number(numbers[i])}; ${number(numbers[i + 1])})'),
            ],
          ),
      ],
    ),
  );
}

class SciencePainter extends CustomPainter {
  final Map<String, dynamic> block;
  final Color ink;
  final double fontSize;
  final String? family;
  final AppPalette palette;
  SciencePainter(
    this.block,
    this.ink,
    this.fontSize,
    this.family, {
    this.palette = const AppPalette(isDark: false),
  });
  List<double> get n =>
      (block['numbers'] as List).map((v) => (v as num).toDouble()).toList();
  void line(Canvas c, Offset a, Offset b, {Color? color, double width = 2}) =>
      c.drawLine(
        a,
        b,
        Paint()
          ..color = color ?? ink
          ..strokeWidth = width,
      );
  void text(
    Canvas c,
    String value,
    Offset point, {
    bool center = true,
    Color? color,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: family,
          color: color ?? ink,
          fontSize: fontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(c, point - Offset(center ? p.width / 2 : 0, p.height / 2));
  }

  void atom(Canvas c, String label, Offset p) {
    c.drawCircle(p, 14, Paint()..color = palette.panelSurface);
    text(c, label, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = ink
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final w = size.width, h = size.height;
    switch (block['kind']) {
      case 'function_graph':
      case 'function_curve':
      case 'data_plot':
        final points = <Offset>[];
        if (block['kind'] == 'function_graph') {
          for (var i = 0; i <= 160; i++) {
            final x = -4 + i / 20;
            points.add(Offset(x, n[0] * x * x + n[1] * x + n[2]));
          }
        } else if (block['kind'] == 'function_curve') {
          final variant = block['variant'];
          final min = variant == 'logarithm'
              ? .1
              : variant == 'square_root'
              ? 0.0
              : variant == 'exponential'
              ? -3.0
              : -4.0;
          final max = variant == 'square_root'
              ? 9.0
              : variant == 'exponential'
              ? 3.0
              : 4.0;
          for (var i = 0; i <= 240; i++) {
            final x = min + (max - min) * i / 240;
            if (variant == 'reciprocal' && x.abs() < .15) continue;
            final y = switch (variant) {
              'sine' => math.sin(x),
              'cosine' => math.cos(x),
              'exponential' => math.exp(x),
              'logarithm' => math.log(x),
              'square_root' => math.sqrt(x),
              'reciprocal' => 1 / x,
              'cubic' => x * x * x,
              _ => x.abs(),
            };
            points.add(Offset(x, y));
          }
        } else {
          for (var i = 0; i < n.length; i += 2) {
            points.add(Offset(n[i], n[i + 1]));
          }
        }
        var minX = math.min(0.0, points.map((p) => p.dx).reduce(math.min)),
            maxX = math.max(0.0, points.map((p) => p.dx).reduce(math.max));
        var minY = math.min(0.0, points.map((p) => p.dy).reduce(math.min)),
            maxY = math.max(0.0, points.map((p) => p.dy).reduce(math.max));
        if (maxX == minX) {
          minX -= 1;
          maxX += 1;
        }
        if (maxY == minY) {
          minY -= 1;
          maxY += 1;
        }
        final rect = Rect.fromLTRB(62, 20, w - 20, h - 38);
        Offset position(Offset p) => Offset(
          rect.left + (p.dx - minX) / (maxX - minX) * rect.width,
          rect.bottom - (p.dy - minY) / (maxY - minY) * rect.height,
        );
        final zero = position(Offset.zero);
        final ticks = w < 340 ? 2 : 4;
        for (var i = 0; i <= ticks; i++) {
          final x = minX + (maxX - minX) * i / ticks,
              y = minY + (maxY - minY) * i / ticks;
          final xp = position(Offset(x, 0)), yp = position(Offset(0, y));
          line(
            canvas,
            Offset(xp.dx, rect.top),
            Offset(xp.dx, rect.bottom),
            color: palette.surfaceBorder,
            width: 1,
          );
          line(
            canvas,
            Offset(rect.left, yp.dy),
            Offset(rect.right, yp.dy),
            color: palette.surfaceBorder,
            width: 1,
          );
          text(
            canvas,
            ScienceGraphic.tickLabel(x, maxX - minX),
            Offset(xp.dx, rect.bottom + 16),
          );
          text(
            canvas,
            ScienceGraphic.tickLabel(y, maxY - minY),
            Offset(rect.left - 28, yp.dy),
          );
        }
        line(canvas, Offset(rect.left, zero.dy), Offset(rect.right, zero.dy));
        line(canvas, Offset(zero.dx, rect.top), Offset(zero.dx, rect.bottom));
        canvas.save();
        canvas.clipRect(rect.inflate(2));
        if (block['kind'] == 'function_graph' ||
            block['kind'] == 'function_curve' ||
            block['variant'] == 'polyline') {
          final path = Path()
            ..moveTo(position(points.first).dx, position(points.first).dy);
          var previous = points.first;
          for (final p in points.skip(1)) {
            final s = position(p);
            if (block['variant'] == 'reciprocal' &&
                previous.dx < 0 &&
                p.dx > 0) {
              path.moveTo(s.dx, s.dy);
            } else {
              path.lineTo(s.dx, s.dy);
            }
            previous = p;
          }
          canvas.drawPath(
            path,
            Paint()
              ..color = palette.cyanInk
              ..strokeWidth = 3
              ..style = PaintingStyle.stroke,
          );
        }
        if (block['kind'] == 'data_plot') {
          for (final p in points) {
            canvas.drawCircle(position(p), 4, Paint()..color = palette.cyanInk);
          }
        }
        canvas.restore();
        text(canvas, 'x', Offset(w - 8, rect.bottom));
        text(canvas, 'y', Offset(rect.left, 8));
      case 'process_graph':
      case 'process_cycle':
        final labels = (block['labels'] as List).cast<String>();
        final edges = (block['connections'] as List).cast<Map>();
        final points = <Offset>[];
        if (block['kind'] == 'process_cycle') {
          for (var i = 0; i < labels.length; i++) {
            final angle = -math.pi / 2 + 2 * math.pi * i / labels.length;
            points.add(
              Offset(
                w / 2 + math.cos(angle) * (w / 2 - 28),
                h / 2 + math.sin(angle) * (h / 2 - 28),
              ),
            );
          }
        } else {
          final levels = List<int>.filled(labels.length, 0);
          for (var pass = 0; pass < labels.length; pass++) {
            for (final edge in edges) {
              final a = edge['start'] as int, b = edge['end'] as int;
              levels[b] = math.max(levels[b], levels[a] + 1);
            }
          }
          final max = levels.reduce(math.max);
          for (var i = 0; i < labels.length; i++) {
            final peers = [
              for (var j = 0; j < labels.length; j++)
                if (levels[j] == levels[i]) j,
            ];
            points.add(
              Offset(
                w * (peers.indexOf(i) + 1) / (peers.length + 1),
                24 + (h - 48) * levels[i] / math.max(1, max),
              ),
            );
          }
        }
        for (final edge in edges) {
          final a = points[edge['start'] as int],
              b = points[edge['end'] as int];
          final direction = (b - a) / (b - a).distance;
          final start = a + direction * 16, end = b - direction * 19;
          line(canvas, start, end, color: palette.cyanInk);
          final perpendicular = Offset(-direction.dy, direction.dx);
          line(
            canvas,
            end,
            end - direction * 8 + perpendicular * 4,
            color: palette.cyanInk,
          );
          line(
            canvas,
            end,
            end - direction * 8 - perpendicular * 4,
            color: palette.cyanInk,
          );
        }
        for (var i = 0; i < points.length; i++) {
          canvas.drawCircle(
            points[i],
            16,
            Paint()..color = palette.panelSurface,
          );
          canvas.drawCircle(points[i], 16, stroke);
          text(canvas, '${i + 1}', points[i]);
        }
      case 'cell':
        final plant = block['variant'] == 'plant_cell';
        final rect = Rect.fromLTRB(w * .10, 15, w * .90, h - 15);
        if (plant) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(24)),
            stroke..strokeWidth = 5,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.deflate(9), const Radius.circular(18)),
            stroke..strokeWidth = 2,
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(w * .57, h * .57),
              width: w * .33,
              height: h * .44,
            ),
            Paint()..color = palette.cyanSurface,
          );
          text(canvas, '5', Offset(w * .57, h * .57));
          for (final p in [
            Offset(w * .30, h * .73),
            Offset(w * .73, h * .28),
          ]) {
            canvas.drawOval(
              Rect.fromCenter(center: p, width: 32, height: 18),
              Paint()..color = palette.successSurface,
            );
            text(canvas, '6', p);
          }
          text(canvas, '1', Offset(w * .12, h * .23));
          text(canvas, '2', Offset(w * .21, h * .32));
          text(canvas, '4', Offset(w * .72, h * .80));
        } else {
          canvas.drawOval(rect, stroke);
          text(canvas, '1', Offset(w * .19, h * .28));
          text(canvas, '3', Offset(w * .65, h * .66));
        }
        final nucleus = Offset(w * .35, h * .40);
        canvas.drawCircle(nucleus, 24, Paint()..color = palette.mint);
        canvas.drawCircle(nucleus, 24, stroke);
        text(canvas, plant ? '3' : '2', nucleus);
      case 'molecule':
        final positions = <Offset>[];
        final edges = <(int, int, int)>[];
        switch (block['variant']) {
          case 'water':
            positions.addAll([
              Offset(w * .2, h * .7),
              Offset(w * .5, h * .45),
              Offset(w * .8, h * .7),
            ]);
            edges.addAll([(0, 1, 1), (1, 2, 1)]);
          case 'carbon_dioxide':
            positions.addAll([
              Offset(w * .15, h * .5),
              Offset(w * .5, h * .5),
              Offset(w * .85, h * .5),
            ]);
            edges.addAll([(0, 1, 2), (1, 2, 2)]);
          case 'methane':
            positions.addAll([
              Offset(w * .5, h * .5),
              Offset(w * .15, h * .5),
              Offset(w * .85, h * .5),
              Offset(w * .5, h * .18),
              Offset(w * .5, h * .82),
            ]);
            edges.addAll([(0, 1, 1), (0, 2, 1), (0, 3, 1), (0, 4, 1)]);
          case 'ethanol':
            positions.addAll([
              Offset(w * .25, h * .5),
              Offset(w * .52, h * .5),
              Offset(w * .77, h * .5),
              Offset(w * .08, h * .5),
              Offset(w * .25, h * .19),
              Offset(w * .25, h * .81),
              Offset(w * .52, h * .19),
              Offset(w * .52, h * .81),
              Offset(w * .94, h * .5),
            ]);
            edges.addAll([
              (0, 1, 1),
              (1, 2, 1),
              (0, 3, 1),
              (0, 4, 1),
              (0, 5, 1),
              (1, 6, 1),
              (1, 7, 1),
              (2, 8, 1),
            ]);
        }
        for (final e in edges) {
          final a = positions[e.$1], b = positions[e.$2];
          if (e.$3 == 2) {
            line(canvas, a + const Offset(0, -4), b + const Offset(0, -4));
            line(canvas, a + const Offset(0, 4), b + const Offset(0, 4));
          } else {
            line(canvas, a, b);
          }
        }
        final labels = (block['labels'] as List).cast<String>();
        for (var i = 0; i < positions.length; i++) {
          atom(canvas, labels[i], positions[i]);
        }
      case 'circuit_network':
        final l = Offset(w * .12, h * .5), r = Offset(w * .88, h * .5);
        void resistor(double left, double right, double y, String label) {
          line(canvas, Offset(left, y), Offset((left + right) / 2 - 20, y));
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset((left + right) / 2, y),
              width: 40,
              height: 22,
            ),
            stroke,
          );
          line(canvas, Offset((left + right) / 2 + 20, y), Offset(right, y));
          text(canvas, label, Offset((left + right) / 2, y - 27));
        }
        if (block['variant'] == 'series') {
          resistor(l.dx, w * .5, l.dy, 'R1');
          resistor(w * .5, r.dx, l.dy, 'R2');
        } else {
          line(canvas, l, Offset(l.dx, h * .3));
          line(canvas, l, Offset(l.dx, h * .7));
          line(canvas, r, Offset(r.dx, h * .3));
          line(canvas, r, Offset(r.dx, h * .7));
          resistor(l.dx, r.dx, h * .3, 'R1');
          resistor(l.dx, r.dx, h * .7, 'R2');
          canvas.drawCircle(l, 4, Paint()..color = ink);
          canvas.drawCircle(r, 4, Paint()..color = ink);
        }
        line(canvas, Offset(0, l.dy), l);
        line(canvas, r, Offset(w, r.dy));
      case 'technical_drawing':
        final rect = Rect.fromLTRB(w * .23, h * .27, w * .94, h * .73);
        canvas.drawRect(rect, stroke);
        final radius = math.min(rect.width, rect.height) * .14;
        canvas.drawCircle(rect.center, radius, stroke);
        void dimension(Offset a, Offset b) {
          final d = (b - a) / (b - a).distance, p = Offset(-d.dy, d.dx);
          line(canvas, a, b);
          for (final pair in [(a, d), (b, -d)]) {
            line(canvas, pair.$1, pair.$1 + pair.$2 * 7 + p * 3);
            line(canvas, pair.$1, pair.$1 + pair.$2 * 7 - p * 3);
          }
        }
        final y = h * .17, x = w * .12;
        line(canvas, Offset(rect.left, y - 8), Offset(rect.left, rect.top));
        line(canvas, Offset(rect.right, y - 8), Offset(rect.right, rect.top));
        dimension(Offset(rect.left, y), Offset(rect.right, y));
        text(
          canvas,
          '${ScienceGraphic.number(n[0])} ${block['unit']}',
          Offset(rect.center.dx, y - 18),
        );
        line(canvas, Offset(x - 8, rect.top), Offset(rect.left, rect.top));
        line(
          canvas,
          Offset(x - 8, rect.bottom),
          Offset(rect.left, rect.bottom),
        );
        dimension(Offset(x, rect.top), Offset(x, rect.bottom));
        canvas.save();
        canvas.translate(x - 16, rect.center.dy);
        canvas.rotate(-math.pi / 2);
        text(
          canvas,
          '${ScienceGraphic.number(n[1])} ${block['unit']}',
          Offset.zero,
        );
        canvas.restore();
        final start = rect.center + Offset(radius * .7, radius * .7),
            end = Offset(rect.center.dx + 25, h * .88);
        line(canvas, start, end);
        line(canvas, end, Offset(w * .94, end.dy));
        text(
          canvas,
          'Ø ${ScienceGraphic.number(n[2])} ${block['unit']}',
          Offset(rect.center.dx + 15, h * .95),
        );
    }
  }

  @override
  bool shouldRepaint(covariant SciencePainter oldDelegate) =>
      block != oldDelegate.block ||
      ink != oldDelegate.ink ||
      fontSize != oldDelegate.fontSize ||
      family != oldDelegate.family ||
      palette.isDark != oldDelegate.palette.isDark;
}
