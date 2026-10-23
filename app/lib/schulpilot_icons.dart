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
  calendar,
  clock,
  timer,
  route,
  checkCircle,
  refresh,
  close,
  arrowBack,
  arrowForward,
  arrowUp,
  arrowDown,
  chevronLeft,
  chevronRight,
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
  Icons.calendar_month_outlined: _LearningNavSymbol.calendar,
  Icons.calendar_today_outlined: _LearningNavSymbol.calendar,
  Icons.event_outlined: _LearningNavSymbol.calendar,
  Icons.schedule: _LearningNavSymbol.clock,
  Icons.schedule_rounded: _LearningNavSymbol.clock,
  Icons.timer_outlined: _LearningNavSymbol.timer,
  Icons.route_outlined: _LearningNavSymbol.route,
  Icons.route_rounded: _LearningNavSymbol.route,
  Icons.check_circle_outline: _LearningNavSymbol.checkCircle,
  Icons.check_circle_outline_rounded: _LearningNavSymbol.checkCircle,
  Icons.check_circle_rounded: _LearningNavSymbol.checkCircle,
  Icons.task_alt_rounded: _LearningNavSymbol.checkCircle,
  Icons.refresh: _LearningNavSymbol.refresh,
  Icons.refresh_rounded: _LearningNavSymbol.refresh,
  Icons.close: _LearningNavSymbol.close,
  Icons.close_rounded: _LearningNavSymbol.close,
  Icons.arrow_back: _LearningNavSymbol.arrowBack,
  Icons.arrow_back_rounded: _LearningNavSymbol.arrowBack,
  Icons.arrow_forward_rounded: _LearningNavSymbol.arrowForward,
  Icons.arrow_upward: _LearningNavSymbol.arrowUp,
  Icons.arrow_upward_rounded: _LearningNavSymbol.arrowUp,
  Icons.arrow_downward: _LearningNavSymbol.arrowDown,
  Icons.arrow_downward_rounded: _LearningNavSymbol.arrowDown,
  Icons.chevron_left: _LearningNavSymbol.chevronLeft,
  Icons.chevron_left_rounded: _LearningNavSymbol.chevronLeft,
  Icons.chevron_right: _LearningNavSymbol.chevronRight,
  Icons.chevron_right_rounded: _LearningNavSymbol.chevronRight,
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
      case _LearningNavSymbol.calendar:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3.2, 5, 17.6, 16.2),
            const Radius.circular(2.2),
          ),
          pen,
        );
        line(3.2, 9.5, 20.8, 9.5);
        line(7.5, 2.8, 7.5, 6.8);
        line(16.5, 2.8, 16.5, 6.8);
        for (final point in const [
          Offset(7.4, 13.4),
          Offset(12, 13.4),
          Offset(16.6, 13.4),
          Offset(7.4, 17.4),
          Offset(12, 17.4),
        ]) {
          canvas.drawCircle(point, .45, pen);
        }
      case _LearningNavSymbol.clock:
        canvas.drawCircle(const Offset(12, 12), 9, pen);
        draw(
          Path()
            ..moveTo(12, 6.6)
            ..lineTo(12, 12)
            ..lineTo(15.8, 14.2),
        );
      case _LearningNavSymbol.timer:
        canvas.drawCircle(const Offset(12, 13.3), 7.7, pen);
        line(9.2, 2.6, 14.8, 2.6);
        line(12, 2.6, 12, 5.6);
        line(17.5, 7.8, 19.4, 5.9);
        line(12, 8.8, 12, 13.3);
        line(12, 13.3, 15.1, 15.1);
      case _LearningNavSymbol.route:
        canvas.drawCircle(const Offset(5, 4.4), 1.8, pen);
        canvas.drawCircle(const Offset(5, 19.6), 1.8, pen);
        draw(
          Path()
            ..moveTo(5, 6.2)
            ..lineTo(5, 7.2)
            ..quadraticBezierTo(5, 11.3, 9.3, 11.3)
            ..lineTo(14.6, 11.3)
            ..quadraticBezierTo(19, 11.3, 19, 15.5)
            ..quadraticBezierTo(19, 19.6, 14.6, 19.6)
            ..lineTo(6.8, 19.6),
        );
      case _LearningNavSymbol.checkCircle:
        canvas.drawCircle(const Offset(12, 12), 9, pen);
        draw(
          Path()
            ..moveTo(7.5, 12.1)
            ..lineTo(10.5, 15.1)
            ..lineTo(16.7, 8.8),
        );
      case _LearningNavSymbol.refresh:
        draw(
          Path()
            ..moveTo(19.5, 7.8)
            ..cubicTo(16.6, 2.6, 9.5, 2.3, 5.6, 6.3)
            ..cubicTo(1.7, 10.4, 3.5, 17.4, 8.8, 19.7)
            ..cubicTo(12.8, 21.4, 17.2, 19.6, 19.2, 16.1),
        );
        draw(
          Path()
            ..moveTo(19.5, 3.5)
            ..lineTo(19.5, 7.8)
            ..lineTo(15.2, 7.8),
        );
      case _LearningNavSymbol.close:
        line(5.3, 5.3, 18.7, 18.7);
        line(18.7, 5.3, 5.3, 18.7);
      case _LearningNavSymbol.arrowBack:
        line(20, 12, 4, 12);
        draw(
          Path()
            ..moveTo(10, 6)
            ..lineTo(4, 12)
            ..lineTo(10, 18),
        );
      case _LearningNavSymbol.arrowForward:
        line(4, 12, 20, 12);
        draw(
          Path()
            ..moveTo(14, 6)
            ..lineTo(20, 12)
            ..lineTo(14, 18),
        );
      case _LearningNavSymbol.arrowUp:
        line(12, 20, 12, 4);
        draw(
          Path()
            ..moveTo(6, 10)
            ..lineTo(12, 4)
            ..lineTo(18, 10),
        );
      case _LearningNavSymbol.arrowDown:
        line(12, 4, 12, 20);
        draw(
          Path()
            ..moveTo(6, 14)
            ..lineTo(12, 20)
            ..lineTo(18, 14),
        );
      case _LearningNavSymbol.chevronLeft:
        draw(
          Path()
            ..moveTo(14.8, 5.8)
            ..lineTo(8.6, 12)
            ..lineTo(14.8, 18.2),
        );
      case _LearningNavSymbol.chevronRight:
        draw(
          Path()
            ..moveTo(9.2, 5.8)
            ..lineTo(15.4, 12)
            ..lineTo(9.2, 18.2),
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LearningNavPainter oldDelegate) =>
      oldDelegate.symbol != symbol || oldDelegate.color != color;
}
