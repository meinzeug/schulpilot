import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Decorative subject identity from the fixed public cover catalog.
/// Private subject names never become paths or requests to another service.
class SubjectBadge extends StatelessWidget {
  final String? coverKey;
  final double size;
  const SubjectBadge(this.coverKey, {super.key, this.size = 46});

  static (Color, IconData) identity(String? key) => switch (key) {
    'mathematik' => (const Color(0xFFE93450), Icons.functions_rounded),
    'deutsch' || 'deutsch-als-zweitsprache' => (
      const Color(0xFFAC44ED),
      Icons.edit_note_rounded,
    ),
    'englisch' ||
    'franzoesisch' ||
    'spanisch' ||
    'latein' => (const Color(0xFF008FE5), Icons.translate_rounded),
    'informatik' => (const Color(0xFF657CEB), Icons.code_rounded),
    'wirtschaft' => (const Color(0xFF159E9C), Icons.bar_chart_rounded),
    'gemeinschaftskunde' ||
    'geschichte' => (const Color(0xFF18A75F), Icons.account_balance_outlined),
    'biologie' ||
    'sachunterricht' => (const Color(0xFF5DAD41), Icons.eco_outlined),
    'physik' => (const Color(0xFFDC9A25), Icons.bolt_rounded),
    'chemie' => (const Color(0xFFDB6C32), Icons.science_outlined),
    'geographie' => (const Color(0xFF24A58C), Icons.public_rounded),
    'musik' => (const Color(0xFFD34AA3), Icons.music_note_outlined),
    'kunst' => (const Color(0xFFDD6458), Icons.palette_outlined),
    'sport' || 'kreativitaet-und-bewegung' => (
      const Color(0xFF008BCE),
      Icons.sports_gymnastics_rounded,
    ),
    'technik' => (const Color(0xFF7994AE), Icons.settings_outlined),
    'ethik' ||
    'religion' => (const Color(0xFFB88BCA), Icons.chat_bubble_outline_rounded),
    'lern-und-arbeitstechniken' => (
      const Color(0xFFB69031),
      Icons.lightbulb_outline_rounded,
    ),
    _ => (const Color(0xFF6F8EAF), Icons.menu_book_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final (color, symbol) = identity(coverKey);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _SubjectHexagon(color),
          child: Center(
            child: Icon(symbol, color: Colors.white, size: size * .48),
          ),
        ),
      ),
    );
  }
}

class _SubjectHexagon extends CustomPainter {
  final Color color;
  const _SubjectHexagon(this.color);

  Path hexagon(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 2;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .47;
    final path = hexagon(center, radius);
    canvas.drawShadow(path, color.withValues(alpha: .4), 5, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      hexagon(center, radius * .79),
      Paint()
        ..color = Colors.white.withValues(alpha: .9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SubjectHexagon oldDelegate) =>
      oldDelegate.color != color;
}
