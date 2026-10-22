import 'dart:math' as math;

import 'package:flutter/material.dart';

enum _LearningNavSymbol {
  home,
  compass,
  book,
  flashcards,
  clipboard,
  person,
  gear,
  search,
  plus,
}

final _symbols = <IconData, _LearningNavSymbol>{
  Icons.grid_view_rounded: _LearningNavSymbol.home,
  Icons.home_outlined: _LearningNavSymbol.home,
  Icons.home_rounded: _LearningNavSymbol.home,
  Icons.school_outlined: _LearningNavSymbol.compass,
  Icons.explore_outlined: _LearningNavSymbol.compass,
  Icons.auto_stories_rounded: _LearningNavSymbol.compass,
  Icons.auto_stories_outlined: _LearningNavSymbol.compass,
  Icons.menu_book_outlined: _LearningNavSymbol.book,
  Icons.menu_book_rounded: _LearningNavSymbol.book,
  Icons.folder_open_rounded: _LearningNavSymbol.book,
  Icons.folder_open_outlined: _LearningNavSymbol.book,
  Icons.translate_rounded: _LearningNavSymbol.flashcards,
  Icons.translate: _LearningNavSymbol.flashcards,
  Icons.style_outlined: _LearningNavSymbol.flashcards,
  Icons.edit_note_rounded: _LearningNavSymbol.clipboard,
  Icons.edit_note_outlined: _LearningNavSymbol.clipboard,
  Icons.assignment_outlined: _LearningNavSymbol.clipboard,
  Icons.person_outline_rounded: _LearningNavSymbol.person,
  Icons.person_outline: _LearningNavSymbol.person,
  Icons.person_outlined: _LearningNavSymbol.person,
  Icons.settings_outlined: _LearningNavSymbol.gear,
  Icons.settings_rounded: _LearningNavSymbol.gear,
  Icons.tune_rounded: _LearningNavSymbol.gear,
  Icons.search: _LearningNavSymbol.search,
  Icons.search_rounded: _LearningNavSymbol.search,
  Icons.add: _LearningNavSymbol.plus,
  Icons.add_rounded: _LearningNavSymbol.plus,
};

/// Thin, rounded navigation drawings. The containing control supplies its label.
/// Operator destinations without a custom drawing keep their Material icon.
class LearningNavIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;

  const LearningNavIcon(this.icon, {super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    final symbol = _symbols[icon];
    final dimension = size.isFinite && size > 0 ? size : 24.0;
    final resolvedColor =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return ExcludeSemantics(
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: symbol == null
            ? Icon(icon, size: dimension, color: resolvedColor)
            : SizedBox.square(
                dimension: dimension,
                child: CustomPaint(
                  painter: _LearningNavPainter(symbol, resolvedColor),
                ),
              ),
      ),
    );
  }
}

class _LearningNavPainter extends CustomPainter {
  final _LearningNavSymbol symbol;
  final Color color;

  const _LearningNavPainter(this.symbol, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.45
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void draw(Path path) => canvas.drawPath(path, pen);
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), pen);

    switch (symbol) {
      case _LearningNavSymbol.home:
        draw(
          Path()
            ..moveTo(2.8, 10.2)
            ..lineTo(12, 2.7)
            ..lineTo(21.2, 10.2),
        );
        draw(
          Path()
            ..moveTo(4.6, 9.2)
            ..lineTo(4.6, 20.8)
            ..lineTo(9.4, 20.8)
            ..lineTo(9.4, 14.1)
            ..lineTo(14.6, 14.1)
            ..lineTo(14.6, 20.8)
            ..lineTo(19.4, 20.8)
            ..lineTo(19.4, 9.2),
        );
      case _LearningNavSymbol.compass:
        canvas.drawCircle(const Offset(12, 12), 9.2, pen);
        draw(
          Path()
            ..moveTo(16.3, 7.7)
            ..lineTo(13.8, 13.8)
            ..lineTo(7.7, 16.3)
            ..lineTo(10.2, 10.2)
            ..close(),
        );
      case _LearningNavSymbol.book:
        draw(
          Path()
            ..moveTo(12, 6.1)
            ..cubicTo(9.3, 4.5, 6, 4.5, 2.7, 5.5)
            ..lineTo(2.7, 19.4)
            ..cubicTo(6, 18.4, 9.3, 18.4, 12, 20.1)
            ..cubicTo(14.7, 18.4, 18, 18.4, 21.3, 19.4)
            ..lineTo(21.3, 5.5)
            ..cubicTo(18, 4.5, 14.7, 4.5, 12, 6.1)
            ..lineTo(12, 20.1),
        );
      case _LearningNavSymbol.flashcards:
        draw(
          Path()
            ..moveTo(8.8, 3)
            ..lineTo(19.9, 5.2)
            ..quadraticBezierTo(21.1, 5.5, 20.8, 6.7)
            ..lineTo(18.2, 20),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3.1, 6.1, 12.6, 15),
            const Radius.circular(1.8),
          ),
          pen,
        );
        line(6.9, 11.5, 11.9, 11.5);
        line(6.9, 15.7, 10.5, 15.7);
      case _LearningNavSymbol.clipboard:
        draw(
          Path()
            ..moveTo(8.1, 5.3)
            ..lineTo(5.4, 5.3)
            ..quadraticBezierTo(3.8, 5.3, 3.8, 7)
            ..lineTo(3.8, 20)
            ..quadraticBezierTo(3.8, 21.4, 5.4, 21.4)
            ..lineTo(18.6, 21.4)
            ..quadraticBezierTo(20.2, 21.4, 20.2, 20)
            ..lineTo(20.2, 7)
            ..quadraticBezierTo(20.2, 5.3, 18.6, 5.3)
            ..lineTo(15.9, 5.3),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(8.1, 2.7, 7.8, 4.8),
            const Radius.circular(1.2),
          ),
          pen,
        );
        draw(
          Path()
            ..moveTo(7.8, 13.4)
            ..lineTo(10.6, 16.2)
            ..lineTo(16.3, 10.5),
        );
      case _LearningNavSymbol.person:
        canvas.drawCircle(const Offset(12, 7.1), 3.6, pen);
        draw(
          Path()
            ..moveTo(4.8, 21)
            ..lineTo(4.8, 19.2)
            ..cubicTo(4.8, 15.6, 8, 13.5, 12, 13.5)
            ..cubicTo(16, 13.5, 19.2, 15.6, 19.2, 19.2)
            ..lineTo(19.2, 21),
        );
      case _LearningNavSymbol.gear:
        final outline = Path();
        for (var tooth = 0; tooth < 8; tooth++) {
          final angle = tooth * math.pi / 4 - math.pi / 2;
          const offsets = [-.34, -.2, .2, .34];
          const radii = [7.7, 9.5, 9.5, 7.7];
          for (var corner = 0; corner < offsets.length; corner++) {
            final x = 12 + math.cos(angle + offsets[corner]) * radii[corner];
            final y = 12 + math.sin(angle + offsets[corner]) * radii[corner];
            if (tooth == 0 && corner == 0) {
              outline.moveTo(x, y);
            } else {
              outline.lineTo(x, y);
            }
          }
        }
        draw(outline..close());
        canvas.drawCircle(const Offset(12, 12), 3.3, pen);
      case _LearningNavSymbol.search:
        canvas.drawCircle(const Offset(10.5, 10.5), 6.8, pen);
        line(15.5, 15.5, 21, 21);
      case _LearningNavSymbol.plus:
        line(12, 4.2, 12, 19.8);
        line(4.2, 12, 19.8, 12);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LearningNavPainter oldDelegate) =>
      oldDelegate.symbol != symbol || oldDelegate.color != color;
}
