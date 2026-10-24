import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'math_content.dart';
import 'fraction_explorer.dart';
import 'learning_graphic_frame.dart';
import 'learning_scene_player.dart';
import 'science_graphic.dart';
import 'text_probe_player.dart';
import 'ui.dart';
import 'graphic_zoom.dart';
import 'learning_graphic_scope.dart';
import 'schulbuddy.dart';

/// Finite versioned vector diagrams. No network images, HTML or model-drawn paths.
class SubjectPresentation extends StatelessWidget {
  final Json? data;
  final Set<String>? stages;
  final AppState? state;
  const SubjectPresentation(this.data, {super.key, this.stages, this.state});
  @override
  Widget build(BuildContext context) {
    if (data?['version'] != 1) return const SizedBox.shrink();
    final blocks = (data?['blocks'] as List? ?? [])
        .where((b) => stages == null || stages!.contains(b['disclosure']))
        .toList();
    final scope = LearningGraphicScope.maybeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in blocks.indexed) ...[
          if (scope != null)
            LearningGraphicScope(
              index: entry.$1,
              phase: scope.index == entry.$1 ? scope.phase : 'initial',
              onChanged: scope.onChanged,
              buddyReferences: scope.buddyReferences,
              child: SubjectGraphic(
                Json.from(entry.$2),
                state: state,
                action: state == null
                    ? null
                    : GraphicZoom(
                        state: state!,
                        compact: true,
                        block: Json.from(entry.$2),
                        render: (value) => _ExplanationZoomGraphic(
                          block: value,
                          state: state!,
                          scope: scope,
                          index: entry.$1,
                        ),
                      ),
              ),
            ),
          if (scope == null)
            SubjectGraphic(
              Json.from(entry.$2),
              state: state,
              action: state == null
                  ? null
                  : GraphicZoom(
                      state: state!,
                      compact: true,
                      block: Json.from(entry.$2),
                      render: (value) => SubjectGraphic(value, state: state),
                    ),
            ),
        ],
      ],
    );
  }
}

class SubjectGraphic extends StatelessWidget {
  final Json block;
  final Widget? action;
  final AppState? state;
  const SubjectGraphic(this.block, {super.key, this.action, this.state});
  List<String> get labels => (block['labels'] as List? ?? []).cast<String>();
  List<num> get numbers => (block['numbers'] as List? ?? []).cast<num>();
  String number(num v) =>
      v == v.toInt() ? '${v.toInt()}' : '$v'.replaceAll('.', ',');
  List<String>? formPair(String value) {
    final separator = RegExp(r'\s*(?:→|=)\s*').firstMatch(value);
    if (separator != null) {
      return [
        value.substring(0, separator.start),
        value.substring(separator.end),
      ];
    }
    final numbered = RegExp(r'^(\d+)\s+(.+)$').firstMatch(value);
    if (numbered != null) return [numbered[1]!, numbered[2]!];
    return null;
  }

  List<(String, Color)> get colorLegend => block['variant'] == 'RYB'
      ? [
          ('Rot', Colors.red),
          ('Orange', Colors.orange),
          ('Gelb', Colors.yellow),
          ('Grün', Colors.green),
          ('Blau', Colors.blue),
          ('Violett', Colors.purple),
        ]
      : [
          ('Rot', Colors.red),
          ('Gelb', Colors.yellow),
          ('Grün', Colors.green),
          ('Cyan', Colors.cyan),
          ('Blau', Colors.blue),
          ('Pink', Colors.pink),
        ];

  String get description {
    final n = numbers, variant = block['variant'];
    return switch (block['kind']) {
      'fraction' =>
        '${number(n[0])} von ${number(n[1])} gleich großen Teilen sind markiert.',
      'triangle' =>
        'Skizze, nicht maßstabsgetreu. Dreieck: Grundseite g = ${number(n[0])} ${block['unit']}. Die gestrichelte Höhe h = ${number(n[1])} ${block['unit']} steht senkrecht auf g. Das kleine Quadrat markiert den rechten Winkel.',
      'reflection' =>
        'Waagerechter Spiegel, senkrechtes Lot. Einfallender und reflektierter Strahl liegen auf verschiedenen Seiten des Lots. Der eingezeichnete Winkel ${number(n[0])} Grad liegt zwischen Strahl und Lot.',
      'circuit' =>
        'Batterie, Leitungen, Schalter und Lampe. Der Schalter ist ${variant == 'closed' ? 'geschlossen; die Leitung ist verbunden' : 'offen; die Leitung ist unterbrochen'}.',
      'particles' =>
        'Gleich große Teilchen: ${variant == 'solid'
            ? 'eng und regelmäßig angeordnet'
            : variant == 'liquid'
            ? 'eng und unregelmäßig angeordnet'
            : 'weit voneinander entfernt'}. Modell, nicht maßstabsgetreu.',
      'keyboard' => 'Acht weiße Tasten. Schwarze Tasten in Zweier- und Dreiergruppen; keine schwarze Taste zwischen der dritten und vierten oder der siebten und achten weißen Taste.',
      'notes' =>
        'Notenköpfe von links nach rechts: ${n.map((v) => v == 4
            ? 'offen ohne Hals'
            : v == 2
            ? 'offen mit Hals'
            : 'gefüllt mit Hals').join('; ')}. Bezug: Viertelschläge.',
      'gears' =>
        'Direkt gekoppelte Zahnräder: ${[for (var i = 0; i < labels.length; i++) '${labels[i]} dreht ${(i.isEven == (variant != 'counterclockwise')) ? 'im' : 'gegen den'} Uhrzeigersinn'].join('; ')}.',
      'forces' =>
        variant == 'pull'
            ? 'Zug: Zwei Kraftpfeile zeigen vom Körper weg nach außen.'
            : 'Druck: Zwei Kraftpfeile zeigen zum Körper hin nach innen.',
      'compass' => 'Norden oben, Osten rechts, Süden unten, Westen links.',
      'food_chain' =>
        '${[for (var i = 0; i < labels.length - 1; i++) '${labels[i]} ist Nahrung für ${labels[i + 1]}'].join('. ')}.',
      'colour_wheel' =>
        variant == 'RYB'
            ? 'Farbmodell RYB: Rot, Gelb und Blau; dazwischen Orange, Grün und Violett.'
            : 'Farbmodell RGB: Rot, Grün und Blau für Lichtfarben.',
      'timeline' =>
        variant == 'centuries'
            ? 'Zeitachse von Jahr ${number(n[0])} bis ${number(n[1])}; es gibt kein Jahr null.'
            : 'Zeitachse: ${labels.join(' → ')}.',
      'plant' =>
        'Pflanzenschema von oben nach unten: ${labels.join(', ')}.${variant == 'roots' ? ' Die Wurzel liegt im Boden, nimmt Wasser auf und verankert die Pflanze. Der Pfeil zeigt Wasser zur Wurzel.' : ''}',
      'forms' =>
        variant == 'pollination'
            ? 'Erklärschritte zum Heftstoff.'
            : 'Beispiele aus der Heftseite.',
      'filtration' => 'Trichter mit Filterpapier über einem Auffanggefäß. Feste Teilchen bleiben im Filter; Flüssigkeit läuft in das Gefäß. Gelöste Stoffe können mit der Flüssigkeit durch den Filter gelangen.',
      'bar_chart' =>
        'Balkendiagramm mit Nullpunkt: ${[for (var i = 0; i < labels.length; i++) '${labels[i]}: ${number(n[i])}'].join('; ')}.',
      'place_values' =>
        'Binäre Stellenwerte von links nach rechts: ${[for (var i = 0; i < n.length; i++) '${math.pow(2, n.length - i - 1).toInt()}: ${number(n[i])}'].join('; ')}.',
      'mindmap' =>
        'Hauptthema: ${labels.first}. Äste: ${labels.skip(1).join(', ')}.',
      'layers' =>
        '1: ${labels[0]}; 2: ${labels[1]}; 3: ${labels[2]}. Schematische Bildebenen.',
      'position' =>
        'Ein Ball liegt ${variant == 'above'
            ? 'auf'
            : variant == 'below'
            ? 'unter'
            : 'neben'} dem Tisch.',
      _ => labels.join(' · '),
    };
  }

  static const vectorKinds = {
    'fraction',
    'triangle',
    'reflection',
    'circuit',
    'particles',
    'keyboard',
    'notes',
    'gears',
    'forces',
    'compass',
    'colour_wheel',
    'plant',
    'filtration',
    'bar_chart',
    'layers',
    'pattern',
    'picture_words',
    'mindmap',
    'position',
    'timeline',
  };
  String get accessibleDescription {
    if (block['kind'] != 'timeline' || block['variant'] != 'centuries') {
      return description;
    }
    final first = (numbers[0].toInt() - 1) ~/ 100 + 1;
    final last = (numbers[1].toInt() - 1) ~/ 100 + 1;
    return '$description ${[for (var century = first; century <= last; century++) '$century. Jahrhundert: ${100 * (century - 1) + 1} bis ${100 * century}'].join('; ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final kind = block['kind'];
    if (kind == 'text_probe') {
      return TextProbePlayer(block, state: state, action: action);
    }
    if (kind == 'scene') {
      return LearningScenePlayer(block, state: state, action: action);
    }
    if (ScienceGraphic.kinds.contains(kind)) {
      final processScene = processLearningScene(block);
      final graphic = ScienceGraphic(block, state: state, action: action);
      if (processScene == null) return graphic;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          graphic,
          ExpansionTile(
            key: ValueKey('process-scene-${block['title']}'),
            title: const Text('Schrittweise ansehen'),
            leading: const Icon(Icons.play_circle_outline_rounded),
            children: [LearningScenePlayer(processScene, state: state)],
          ),
        ],
      );
    }
    final text = description;
    return LearningGraphicFrame(
      title: block['title'] ?? 'Schau genau hin',
      action: action,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kind == 'fraction')
            FractionExplorer(
              numerator: numbers[0].toInt(),
              denominator: numbers[1].toInt(),
              state: state,
            )
          else if (vectorKinds.contains(kind))
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  image: true,
                  label: accessibleDescription,
                  child: ExcludeSemantics(
                    child: SizedBox(
                      height: 220,
                      child: CustomPaint(
                        painter: SubjectVectorPainter(
                          block,
                          Theme.of(context).colorScheme.onSurface,
                          MediaQuery.textScalerOf(context).scale(14) / 14,
                          Theme.of(context).textTheme.bodyMedium?.fontFamily,
                          palette: context.palette,
                        ),
                      ),
                    ),
                  ),
                ),
                if (kind == 'colour_wheel')
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final (label, colour) in colorLegend)
                        Chip(
                          avatar: CircleAvatar(backgroundColor: colour),
                          label: Text(label),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
              ],
            ),
          if (kind == 'forms' && block['variant'] == 'pollination')
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final step in labels.indexed) ...[
                  Semantics(
                    image: true,
                    label: step.$2,
                    child: ExcludeSemantics(
                      child: SizedBox(
                        height: 100,
                        child: CustomPaint(
                          painter: PollinationPainter(
                            step.$1,
                            palette: context.palette,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (step.$1 > 0)
                    const Icon(
                      Icons.arrow_downward_rounded,
                      semanticLabel: 'Danach',
                    ),
                  SurfaceInset(
                    child: Text(
                      '${step.$1 + 1}. ${step.$2}',
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ],
              ],
            )
          else if (kind == 'forms')
            labels.map(formPair).every((pair) => pair != null)
                ? Table(
                    border: TableBorder.all(
                      color: context.palette.surfaceBorder,
                    ),
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      for (final pair in labels.map(formPair))
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: MathText(pair![0]),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: MathText(pair[1]),
                            ),
                          ],
                        ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final label in labels)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: SurfaceInset(child: MathText(label)),
                        ),
                    ],
                  )
          else if (kind == 'money' || kind == 'place_values') ...[
            for (var i = 0; i < labels.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: SurfaceInset(
                  child: MathText(
                    '${labels[i]}${kind == 'money' ? '  ${number(numbers[i])} €' : ''}',
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
              ),
            if (kind == 'place_values')
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < numbers.length; i++)
                    Chip(
                      label: Text(
                        '${math.pow(2, numbers.length - i - 1).toInt()}er: ${number(numbers[i])}',
                      ),
                    ),
                ],
              ),
          ] else if (!vectorKinds.contains(kind)) ...[
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0 &&
                  {
                    'food_chain',
                    'water_cycle',
                    'flowchart',
                    'movement',
                    'seasons',
                    'timeline',
                  }.contains(kind))
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 18),
                    child: Icon(Icons.arrow_downward_rounded),
                  ),
                ),
              if (kind == 'flowchart')
                FlowNode(
                  text: labels[i],
                  role: i == 0 || i == labels.length - 1
                      ? 'boundary'
                      : i == 1 || i == labels.length - 2
                      ? 'io'
                      : 'process',
                )
              else
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.palette.panelSurface,
                    border: Border.all(color: context.palette.surfaceBorder),
                    borderRadius: BorderRadius.circular(
                      kind == 'speech' || kind == 'perspectives' ? 22 : 10,
                    ),
                  ),
                  child: MathText(
                    '${kind == 'sentence' ? '${i + 1}. ' : ''}${labels[i]}',
                    style: TextStyle(
                      fontSize: 17,
                      decoration:
                          (block['marks'] as List? ?? []).any(
                            (m) => m['index'] == i,
                          )
                          ? TextDecoration.underline
                          : null,
                    ),
                  ),
                ),
              for (final mark in block['marks'] as List? ?? [])
                if (mark['index'] == i)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      mark['role'] == 'subject'
                          ? 'Subjekt – wer oder was?'
                          : 'Prädikat – was geschieht?',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.palette.cyanInk,
                      ),
                    ),
                  ),
            ],
            if (kind == 'water_cycle' || kind == 'seasons')
              const Row(
                children: [
                  Icon(Icons.refresh_rounded),
                  SizedBox(width: 8),
                  Expanded(child: Text('Zurück zum Anfang')),
                ],
              ),
          ],
          const SizedBox(height: 8),
          if (kind == 'picture_words' || kind == 'mindmap' || kind == 'plant')
            for (var i = 0; i < labels.length; i++)
              Text('${i + 1}: ${labels[i]}'),
          if (kind != 'fraction' && vectorKinds.contains(kind))
            ExcludeSemantics(
              child: MathText(
                text,
                style: const TextStyle(fontSize: 15, height: 1.45),
              ),
            )
          else if (kind != 'fraction')
            MathText(text, style: const TextStyle(fontSize: 15, height: 1.45)),
          if (kind == 'timeline' && block['variant'] == 'centuries') ...[
            const SizedBox(height: 8),
            for (
              var c = ((numbers[0] - 1) ~/ 100) + 1;
              c <= ((numbers[1] - 1) ~/ 100) + 1 && c <= 30;
              c++
            )
              Text('$c. Jahrhundert: ${100 * (c - 1) + 1}–${100 * c}'),
          ],
          if ([
            'reflection',
            'creative',
            'self_report',
            'movement',
          ].contains(block['evidence_kind']))
            const Text(
              'Deine Idee zählt als eigener Beitrag, nicht als richtig/falsch gemessene Fähigkeit.',
            ),
        ],
      ),
    );
  }
}

class SubjectVectorPainter extends CustomPainter {
  final Json data;
  final Color ink;
  final double textScale;
  final String? fontFamily;
  final AppPalette palette;
  SubjectVectorPainter(
    this.data,
    this.ink,
    this.textScale,
    this.fontFamily, {
    this.palette = const AppPalette(isDark: false),
  });
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()
      ..color = ink
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = palette.cyanSurface
      ..style = PaintingStyle.fill;
    final accent = Paint()
      ..color = palette.teal
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final ns = (data['numbers'] as List).cast<num>();
    final labels = (data['labels'] as List).cast<String>();
    final variant = data['variant'];
    void line(Offset a, Offset b, [Paint? paint]) =>
        canvas.drawLine(a, b, paint ?? p);
    void text(String value, Offset at, {Color? color}) {
      final tp = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontSize: 14 * textScale,
            color: color ?? ink,
            fontWeight: FontWeight.w700,
            fontFamily: fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(20, w - at.dx));
      tp.paint(canvas, at);
    }

    void arrow(Offset a, Offset b, [Paint? paint]) {
      final pen = paint ?? accent;
      line(a, b, pen);
      final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
      line(
        b,
        b - Offset(math.cos(angle - 0.5), math.sin(angle - 0.5)) * 10,
        pen,
      );
      line(
        b,
        b - Offset(math.cos(angle + 0.5), math.sin(angle + 0.5)) * 10,
        pen,
      );
    }

    switch (data['kind']) {
      case 'fraction':
        final count = ns[1].toInt(), marked = ns[0].toInt();
        for (var i = 0; i < count; i++) {
          final rect = Rect.fromLTWH(i * w / count, 65, w / count, 70);
          if (i < marked) {
            canvas.drawRect(rect, fill..color = palette.mint);
          }
          canvas.drawRect(rect, p);
        }
        break;
      case 'timeline':
        final firstYear = ns[0].toInt();
        final lastYear = ns[1].toInt();
        final firstCentury = ((firstYear - 1) ~/ 100) + 1;
        final lastCentury = ((lastYear - 1) ~/ 100) + 1;
        final count = lastCentury - firstCentury + 1;
        final xStart = 34.0, xEnd = w - 34.0, axisY = 112.0;
        arrow(Offset(xStart, axisY), Offset(xEnd, axisY));
        for (var century = firstCentury; century <= lastCentury; century++) {
          final x = xStart + (xEnd - xStart) * (century - firstCentury) / count;
          line(Offset(x, axisY - 24), Offset(x, axisY + 24), accent);
          canvas.drawCircle(Offset(x, axisY), 4, fill..color = palette.mint);
          canvas.drawCircle(Offset(x, axisY), 4, p);
          text('$century.', Offset(x - 8, 58));
        }
        text('$firstYear', Offset(xStart, 150));
        text('$lastYear', Offset(xEnd - 28, 150));
        break;
      case 'triangle':
        final left = Offset(20, h - 42),
            right = Offset(w - 20, h - 42),
            top = Offset(w * 0.54, 22),
            foot = Offset(w * 0.54, h - 42);
        if (data['disclosure'] != 'given') {
          final r = Rect.fromLTRB(left.dx, top.dy, right.dx, left.dy);
          canvas.drawRect(r, fill);
          canvas.drawRect(r, p);
        }
        canvas.drawPath(
          Path()
            ..moveTo(left.dx, left.dy)
            ..lineTo(top.dx, top.dy)
            ..lineTo(right.dx, right.dy)
            ..close(),
          p,
        );
        for (double y = top.dy; y < foot.dy; y += 12) {
          line(
            Offset(foot.dx, y),
            Offset(foot.dx, math.min(y + 7, foot.dy)),
            accent,
          );
        }
        line(foot - const Offset(0, 10), foot + const Offset(10, -10), accent);
        line(foot + const Offset(10, -10), foot + const Offset(10, 0), accent);
        text('g', Offset(w * 0.25, h - 36));
        text('h', Offset(w * 0.54 + 10, h * 0.40));
        break;
      case 'reflection':
        final origin = Offset(w * 0.5, h - 35);
        line(Offset(10, origin.dy), Offset(w - 10, origin.dy));
        for (double y = 15; y < origin.dy; y += 12) {
          line(
            Offset(origin.dx, y),
            Offset(origin.dx, math.min(y + 6, origin.dy)),
            accent,
          );
        }
        final angle = ns.first.toDouble() * math.pi / 180,
            length = math.min(
              w * 0.43 / math.max(0.1, math.sin(angle)),
              h * 0.70,
            );
        final delta = Offset(
          math.sin(angle) * length,
          -math.cos(angle) * length,
        );
        arrow(origin + Offset(-delta.dx, delta.dy), origin);
        arrow(origin, origin + delta);
        canvas.drawArc(
          Rect.fromCircle(center: origin, radius: 36),
          -math.pi / 2 - angle,
          angle,
          false,
          accent,
        );
        text('${ns.first}°', Offset(8, 10));
        text('Lot', Offset(origin.dx + 7, 4));
        break;
      case 'circuit':
        final l = w * 0.14,
            r = w * 0.86,
            t = 45.0,
            b = h - 35,
            center = Offset(w * 0.67, b);
        line(Offset(l, t), Offset(w * 0.40, t));
        line(Offset(w * 0.60, t), Offset(r, t));
        line(Offset(r, t), Offset(r, b));
        line(Offset(l, t), Offset(l, h * 0.42));
        line(Offset(l, h * 0.58), Offset(l, b));
        line(Offset(l - 12, h * 0.42), Offset(l + 12, h * 0.42));
        line(Offset(l - 7, h * 0.58), Offset(l + 7, h * 0.58));
        line(Offset(l, b), center - const Offset(18, 0));
        line(center + const Offset(18, 0), Offset(r, b));
        canvas.drawCircle(center, 18, p);
        line(center - const Offset(12, 12), center + const Offset(12, 12));
        line(center + const Offset(12, -12), center + const Offset(-12, 12));
        canvas.drawCircle(Offset(w * 0.40, t), 3, p);
        canvas.drawCircle(Offset(w * 0.60, t), 3, p);
        line(
          Offset(w * 0.40, t),
          Offset(w * 0.60, variant == 'closed' ? t : t - 28),
        );
        text(variant == 'closed' ? 'zu' : 'offen', Offset(w * 0.38, t + 12));
        break;
      case 'particles':
        canvas.drawRect(Rect.fromLTWH(8, 8, w - 16, h - 16), p);
        final positions = (variant == 'gas')
            ? <Offset>[
                const Offset(0.17, 0.20),
                const Offset(0.78, 0.16),
                const Offset(0.46, 0.46),
                const Offset(0.18, 0.75),
                const Offset(0.83, 0.77),
                const Offset(0.60, 0.87),
              ]
            : <Offset>[
                for (var i = 0; i < 16; i++)
                  Offset(
                    0.30 +
                        (i % 4) * 0.11 +
                        (variant == 'liquid' ? (i.isEven ? 0.018 : -0.02) : 0),
                    0.40 +
                        (i ~/ 4) * 0.12 +
                        (variant == 'liquid' ? (i % 3) * 0.015 : 0),
                  ),
              ];
        for (final pos in positions) {
          canvas.drawCircle(
            Offset(pos.dx * w, pos.dy * h),
            7,
            fill..color = palette.mint,
          );
          canvas.drawCircle(Offset(pos.dx * w, pos.dy * h), 7, p);
        }
        break;
      case 'compass':
        final c = Offset(w / 2, h / 2);
        arrow(c, c - const Offset(0, 70));
        arrow(c, c + const Offset(70, 0));
        arrow(c, c + const Offset(0, 70));
        arrow(c, c - const Offset(70, 0));
        text('N', Offset(w / 2 - 8, 0));
        text('O', Offset(w / 2 + 74, h / 2 - 10));
        text('S', Offset(w / 2 - 8, h - 34));
        text('W', Offset(math.max(0, w / 2 - 103), h / 2 - 10));
        break;
      case 'keyboard':
        final keyWidth = w / 8;
        final keyOutline = Paint()
          ..color = Colors.black
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        for (var i = 0; i < 8; i++) {
          final key = Rect.fromLTWH(i * keyWidth, 15, keyWidth, h - 30);
          canvas.drawRect(key, Paint()..color = Colors.white);
          canvas.drawRect(key, keyOutline);
          if (labels.isNotEmpty) {
            text(
              labels[i],
              Offset(i * keyWidth + 3, h - 50),
              color: Colors.black,
            );
          }
        }
        for (final i in [0, 1, 3, 4, 5]) {
          canvas.drawRect(
            Rect.fromLTWH(
              (i + 1) * keyWidth - keyWidth * 0.26,
              15,
              keyWidth * 0.52,
              h * 0.50,
            ),
            Paint()..color = Colors.black,
          );
        }
        break;
      case 'notes':
        for (var j = 0; j < 5; j++) {
          line(Offset(5, 60 + j * 20), Offset(w - 5, 60 + j * 20));
        }
        for (var i = 0; i < ns.length; i++) {
          final x = w * (i + 1) / (ns.length + 1), y = 120.0;
          final rect = Rect.fromCenter(
            center: Offset(x, y),
            width: 23,
            height: 16,
          );
          canvas.drawOval(rect, ns[i] == 1 ? (Paint()..color = ink) : p);
          if (ns[i] != 4) line(Offset(x + 11, y), Offset(x + 11, 50));
        }
        break;
      case 'forces':
        final rect = Rect.fromLTWH(w * 0.35, h * 0.34, w * 0.30, h * 0.30);
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, p);
        if (variant == 'pull') {
          arrow(Offset(rect.left, h * 0.49), Offset(8, h * 0.49));
          arrow(Offset(rect.right, h * 0.49), Offset(w - 8, h * 0.49));
        } else {
          arrow(Offset(8, h * 0.49), Offset(rect.left, h * 0.49));
          arrow(Offset(w - 8, h * 0.49), Offset(rect.right, h * 0.49));
        }
        break;
      case 'gears':
        final radius = math.min(37.0, (w - 20) / (labels.length * 2));
        for (var i = 0; i < labels.length; i++) {
          final c = Offset(10 + radius + 2 * radius * i, h * 0.5);
          canvas.drawCircle(c, radius * 0.80, p);
          for (var j = 0; j < 12; j++) {
            final a = j * math.pi / 6;
            line(
              c + Offset(math.cos(a), math.sin(a)) * radius * 0.80,
              c + Offset(math.cos(a), math.sin(a)) * radius,
            );
          }
          final dir = (i.isEven == (variant != 'counterclockwise'))
              ? 1.0
              : -1.0;
          canvas.drawArc(
            Rect.fromCircle(center: c, radius: radius * 0.48),
            -2.4,
            dir * 2,
            false,
            accent,
          );
          final end = -2.4 + dir * 2;
          final point =
              c + Offset(math.cos(end), math.sin(end)) * radius * 0.48;
          final tangent = Offset(-math.sin(end) * dir, math.cos(end) * dir);
          arrow(point - tangent * 7, point);
          text(labels[i], Offset(c.dx - 10, h * 0.78));
        }
        break;
      case 'colour_wheel':
        final colors = variant == 'RYB'
            ? [
                Colors.red,
                Colors.orange,
                Colors.yellow,
                Colors.green,
                Colors.blue,
                Colors.purple,
              ]
            : [
                Colors.red,
                Colors.yellow,
                Colors.green,
                Colors.cyan,
                Colors.blue,
                Colors.pink,
              ];
        final rect = Rect.fromCircle(center: Offset(w / 2, h / 2), radius: 85);
        for (var i = 0; i < 6; i++) {
          canvas.drawArc(
            rect,
            i * math.pi / 3,
            math.pi / 3,
            true,
            Paint()..color = colors[i],
          );
          canvas.drawArc(rect, i * math.pi / 3, math.pi / 3, true, p);
        }
        break;
      case 'plant':
        final c = Offset(w * 0.5, h * 0.35);
        line(c, Offset(c.dx, h * 0.76), accent);
        canvas.drawOval(
          Rect.fromCenter(
            center: c + const Offset(-27, 35),
            width: 55,
            height: 22,
          ),
          p,
        );
        for (var i = 0; i < 5; i++) {
          canvas.drawCircle(
            c +
                Offset(
                      math.cos(i * math.pi * 0.4),
                      math.sin(i * math.pi * 0.4),
                    ) *
                    19,
            12,
            fill..color = palette.mint,
          );
          canvas.drawCircle(
            c +
                Offset(
                      math.cos(i * math.pi * 0.4),
                      math.sin(i * math.pi * 0.4),
                    ) *
                    19,
            12,
            p,
          );
        }
        canvas.drawCircle(c, 9, p);
        for (var i = -2; i <= 2; i++) {
          line(
            Offset(c.dx, h * 0.76),
            Offset(c.dx + i * 18, h * 0.96),
            data['variant'] == 'roots' ? accent : p,
          );
        }
        if (data['variant'] == 'roots') {
          line(Offset(4, h * .74), Offset(w - 4, h * .74));
          text('Boden', Offset(4, h * .74 - 18 * textScale - 4));
          arrow(Offset(8, h * .89), Offset(c.dx - 35, h * .89), accent);
        }
        for (var i = 0; i < 4; i++) {
          final y = [c.dy, h * 0.48, h * 0.65, h * 0.88][i];
          line(Offset(c.dx + 18, y), Offset(w - 30, y));
          text('${i + 1}', Offset(w - 25, y - 14));
        }
        break;
      case 'filtration':
        final top = Offset(w * 0.5, 30), bottom = Offset(w * 0.5, h * 0.60);
        canvas.drawPath(
          Path()
            ..moveTo(top.dx - 60, top.dy)
            ..lineTo(top.dx + 60, top.dy)
            ..lineTo(bottom.dx + 5, bottom.dy)
            ..lineTo(bottom.dx + 5, bottom.dy + 16)
            ..lineTo(bottom.dx - 5, bottom.dy + 16)
            ..lineTo(bottom.dx - 5, bottom.dy)
            ..close(),
          p,
        );
        line(
          Offset(top.dx - 50, top.dy + 12),
          Offset(top.dx + 50, top.dy + 12),
          accent,
        );
        for (var i = 0; i < 5; i++) {
          canvas.drawCircle(
            Offset(top.dx - 30 + i * 15, top.dy + 22 + (i % 2) * 10),
            3,
            p,
          );
        }
        canvas.drawPath(
          Path()
            ..moveTo(top.dx - 40, h * 0.70)
            ..lineTo(top.dx - 40, h * 0.96)
            ..lineTo(top.dx + 40, h * 0.96)
            ..lineTo(top.dx + 40, h * 0.70),
          p,
        );
        arrow(Offset(bottom.dx, bottom.dy + 18), Offset(bottom.dx, h * 0.90));
        break;
      case 'bar_chart':
        final maxValue = math.max(1, ns.reduce(math.max).toDouble()),
            row = h / ns.length;
        line(const Offset(20, 4), Offset(20, h));
        text('0', const Offset(0, 2));
        for (var i = 0; i < ns.length; i++) {
          final rect = Rect.fromLTWH(
            22,
            i * row + 8,
            (w - 65) * ns[i] / maxValue,
            math.max(10, row - 26),
          );
          canvas.drawRect(rect, fill..color = palette.mint);
          canvas.drawRect(rect, p);
          text('${labels[i]}: ${ns[i]}', Offset(26, i * row + 10));
        }
        break;
      case 'layers':
        for (var i = 0; i < 3; i++) {
          final rect = Rect.fromLTWH(
            15 + i * 15,
            15 + i * 60,
            w - 30 - i * 30,
            50,
          );
          canvas.drawRect(
            rect,
            fill
              ..color = [
                palette.cyanSurface,
                palette.mint,
                palette.successSurface,
              ][i],
          );
          canvas.drawRect(rect, p);
          text('${3 - i}', Offset(rect.left + 8, rect.top + 10));
        }
        break;
      case 'pattern':
        final count = labels.length.clamp(1, 10), space = w / count;
        for (var i = 0; i < count; i++) {
          final c = Offset(space * (i + 0.5), h * 0.5),
              r = math.min(20.0, space * 0.36);
          if (labels[i].toLowerCase().contains('kreis')) {
            canvas.drawCircle(c, r, p);
          } else if (labels[i].toLowerCase() == 'quadrat') {
            canvas.drawRect(
              Rect.fromCenter(center: c, width: r * 2, height: r * 2),
              p,
            );
          } else {
            canvas.drawPath(
              Path()
                ..moveTo(c.dx, c.dy - r)
                ..lineTo(c.dx - r, c.dy + r)
                ..lineTo(c.dx + r, c.dy + r)
                ..close(),
              p,
            );
          }
        }
        break;
      case 'picture_words':
        for (var i = 0; i < labels.length.clamp(0, 5); i++) {
          final x = (i + 0.5) * w / labels.length;
          final label = labels[i].toLowerCase().replaceFirst(
            RegExp(r'^(?:el|la|un|une|der|die|das)\s+'),
            '',
          );
          final colours = <String, Color>{
            'rouge': Colors.red,
            'rot': Colors.red,
            'bleu': Colors.blue,
            'blau': Colors.blue,
            'vert': Colors.green,
            'grün': Colors.green,
            'jaune': Colors.yellow,
            'gelb': Colors.yellow,
          };
          if (colours.containsKey(label)) {
            canvas.drawCircle(
              Offset(x, 100),
              20,
              Paint()..color = colours[label]!,
            );
            canvas.drawCircle(Offset(x, 100), 20, p);
          } else if ({'sonne', 'sol', 'soleil', 'sun'}.contains(label)) {
            canvas.drawCircle(Offset(x, 90), 16, p);
            for (var j = 0; j < 8; j++) {
              final d = Offset(
                math.cos(j * math.pi / 4),
                math.sin(j * math.pi / 4),
              );
              line(Offset(x, 90) + d * 22, Offset(x, 90) + d * 28);
            }
          } else if ({'mond', 'moon', 'luna', 'lune'}.contains(label)) {
            canvas.drawPath(
              Path()
                ..moveTo(x + 12, 62)
                ..cubicTo(x - 30, 60, x - 30, 125, x + 12, 123)
                ..cubicTo(x - 10, 115, x - 10, 70, x + 12, 62)
                ..close(),
              p,
            );
          } else if ({'haus', 'house', 'maison', 'casa'}.contains(label)) {
            canvas.drawRect(Rect.fromLTWH(x - 17, 90, 34, 35), p);
            canvas.drawPath(
              Path()
                ..moveTo(x - 23, 90)
                ..lineTo(x, 67)
                ..lineTo(x + 23, 90),
              p,
            );
          } else if ({'tisch', 'table', 'mesa'}.contains(label)) {
            line(Offset(x - 20, 92), Offset(x + 20, 92));
            line(Offset(x - 15, 92), Offset(x - 12, 125));
            line(Offset(x + 15, 92), Offset(x + 12, 125));
          } else if ({'buch', 'book', 'livre', 'libro'}.contains(label)) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(x - 18, 75, 36, 50),
                const Radius.circular(5),
              ),
              p,
            );
            line(Offset(x - 12, 75), Offset(x - 12, 125));
          } else if ({'katze', 'cat', 'chat', 'gato'}.contains(label)) {
            canvas.drawCircle(Offset(x, 100), 20, p);
            canvas.drawPath(
              Path()
                ..moveTo(x - 19, 93)
                ..lineTo(x - 17, 72)
                ..lineTo(x - 3, 81)
                ..moveTo(x + 3, 81)
                ..lineTo(x + 17, 72)
                ..lineTo(x + 19, 93),
              p,
            );
            canvas.drawCircle(Offset(x - 7, 96), 2, Paint()..color = ink);
            canvas.drawCircle(Offset(x + 7, 96), 2, Paint()..color = ink);
            line(Offset(x - 12, 109), Offset(x + 12, 109));
          } else {
            // A neutral numbered word card, never a fabricated object image.
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(x - 18, 75, 36, 50),
                const Radius.circular(10),
              ),
              p,
            );
            text('…', Offset(x - 8, 85));
          }
          text('${i + 1}', Offset(x - 5, 155));
        }
        break;
      case 'mindmap':
        final centre = Offset(w / 2, h / 2), radius = math.min(w, h) * 0.35;
        final points = [
          centre,
          for (var i = 1; i < labels.length; i++)
            centre +
                Offset(
                      math.cos(
                        -math.pi / 2 +
                            (i - 1) * 2 * math.pi / (labels.length - 1),
                      ),
                      math.sin(
                        -math.pi / 2 +
                            (i - 1) * 2 * math.pi / (labels.length - 1),
                      ),
                    ) *
                    radius,
        ];
        for (final edge in data['connections'] as List) {
          line(points[edge['start']], points[edge['end']], accent);
        }
        for (var i = 0; i < points.length; i++) {
          canvas.drawCircle(
            points[i],
            18,
            Paint()..color = palette.panelSurface,
          );
          canvas.drawCircle(points[i], 18, p);
          text('${i + 1}', points[i] - const Offset(7, 10));
        }
        break;
      case 'position':
        final left = w * 0.34,
            right = w * 0.72,
            top = h * 0.46,
            bottom = h * 0.85;
        line(Offset(left, top), Offset(right, top));
        line(Offset(left + 7, top), Offset(left + 7, bottom));
        line(Offset(right - 7, top), Offset(right - 7, bottom));
        final ball = variant == 'above'
            ? Offset((left + right) / 2, top - 18)
            : variant == 'below'
            ? Offset((left + right) / 2, bottom - 16)
            : Offset(left - 35, bottom - 16);
        canvas.drawCircle(ball, 15, fill..color = palette.mint);
        canvas.drawCircle(ball, 15, p);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant SubjectVectorPainter old) =>
      old.data != data ||
      old.ink != ink ||
      old.textScale != textScale ||
      old.fontFamily != fontFamily ||
      old.palette.isDark != palette.isDark;
}

class FlowNode extends StatelessWidget {
  final String text, role;
  const FlowNode({super.key, required this.text, required this.role});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: CustomPaint(
      painter: _FlowOutline(
        role,
        context.palette.panelSurface,
        context.palette.controlBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: MathText(text, style: const TextStyle(fontSize: 17)),
      ),
    ),
  );
}

class _FlowOutline extends CustomPainter {
  final String role;
  final Color surface, outline;
  _FlowOutline(this.role, this.surface, this.outline);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (role == 'boundary') {
      path.addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height / 2),
        ),
      );
    } else if (role == 'io') {
      path.moveTo(16, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width - 16, size.height);
      path.lineTo(0, size.height);
      path.close();
    } else {
      path.addRect(Offset.zero & size);
    }
    canvas.drawPath(path, Paint()..color = surface);
    canvas.drawPath(
      path,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _FlowOutline old) =>
      old.role != role || old.surface != surface || old.outline != outline;
}

/// Fixed schematic: pollen to stigma, then fusion of male and female cells.
class PollinationPainter extends CustomPainter {
  final int step;
  final AppPalette palette;
  PollinationPainter(
    this.step, {
    this.palette = const AppPalette(isDark: false),
  });
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = palette.ink
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = palette.mint;
    final y = size.height / 2, left = size.width * .2, right = size.width * .8;
    if (step == 0) {
      canvas.drawCircle(Offset(left, y), 15, fill);
      canvas.drawCircle(Offset(left, y), 15, p);
      for (final offset in [
        const Offset(-5, -5),
        const Offset(6, -3),
        const Offset(0, 6),
      ]) {
        canvas.drawCircle(
          Offset(left, y) + offset,
          2,
          Paint()..color = palette.ink,
        );
      }
      canvas.drawPath(
        Path()
          ..moveTo(right - 22, y - 14)
          ..quadraticBezierTo(right, y + 12, right + 22, y - 14)
          ..moveTo(right, y)
          ..lineTo(right, y + 38),
        p,
      );
    } else {
      canvas.drawCircle(Offset(left - 16, y), 8, p);
      canvas.drawCircle(Offset(left + 18, y), 20, p);
      canvas.drawCircle(Offset(right, y), 24, fill);
      canvas.drawCircle(Offset(right, y), 24, p);
      canvas.drawCircle(Offset(right, y), 9, p);
    }
    final start = Offset(size.width * .4, y), end = Offset(size.width * .6, y);
    canvas.drawLine(start, end, p);
    canvas.drawLine(end, end + const Offset(-9, -6), p);
    canvas.drawLine(end, end + const Offset(-9, 6), p);
  }

  @override
  bool shouldRepaint(PollinationPainter oldDelegate) =>
      step != oldDelegate.step || palette.isDark != oldDelegate.palette.isDark;
}

/// The enlarged graphic keeps its own current route and publishes the same
/// bounded display state. The saved lesson remains mounted underneath.
class _ExplanationZoomGraphic extends StatefulWidget {
  final Json block;
  final AppState state;
  final LearningGraphicScope scope;
  final int index;
  const _ExplanationZoomGraphic({
    required this.block,
    required this.state,
    required this.scope,
    required this.index,
  });
  @override
  State<_ExplanationZoomGraphic> createState() =>
      _ExplanationZoomGraphicState();
}

class _ExplanationZoomGraphicState extends State<_ExplanationZoomGraphic> {
  late String phase = widget.scope.index == widget.index
      ? widget.scope.phase
      : 'initial';
  @override
  Widget build(BuildContext context) {
    final refs = widget.scope.buddyReferences;
    Widget body = LearningGraphicScope(
      index: widget.index,
      phase: phase,
      buddyReferences: refs,
      onChanged: (index, value) {
        if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
        setState(() => phase = value);
        widget.scope.onChanged(index, value);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SubjectGraphic(widget.block, state: widget.state),
          if (refs?['unit_id'] != null)
            Align(
              alignment: Alignment.centerRight,
              child: SchulbuddyButton(
                unitId: refs!['unit_id'],
                questionId: refs['question_id'],
              ),
            ),
        ],
      ),
    );
    if (refs != null) {
      body = SchulbuddyPageContext(
        contextValue: SchulbuddyContext('learn', {
          ...refs,
          'graphic_index': '${widget.index}',
          'graphic_phase': phase,
        }),
        child: body,
      );
    }
    return body;
  }
}
