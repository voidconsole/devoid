import 'package:flutter/material.dart';

class SquircleBorder extends ShapeBorder {
  final BorderSide side;
  final double radius;

  const SquircleBorder({
    this.side = BorderSide.none,
    this.radius = 24.0,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return getOuterPath(rect.deflate(side.width), textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = Path();
    final effectiveRadius = radius.clamp(0.0, rect.shortestSide / 2);
    final magic = effectiveRadius * 0.1;

    // Top edge
    path.moveTo(rect.left + effectiveRadius, rect.top);
    path.lineTo(rect.right - effectiveRadius, rect.top);

    // Top-right corner (squircle)
    path.cubicTo(
      rect.right - magic, rect.top,
      rect.right, rect.top + magic,
      rect.right, rect.top + effectiveRadius,
    );

    // Right edge
    path.lineTo(rect.right, rect.bottom - effectiveRadius);

    // Bottom-right corner (squircle)
    path.cubicTo(
      rect.right, rect.bottom - magic,
      rect.right - magic, rect.bottom,
      rect.right - effectiveRadius, rect.bottom,
    );

    // Bottom edge
    path.lineTo(rect.left + effectiveRadius, rect.bottom);

    // Bottom-left corner (squircle)
    path.cubicTo(
      rect.left + magic, rect.bottom,
      rect.left, rect.bottom - magic,
      rect.left, rect.bottom - effectiveRadius,
    );

    // Left edge
    path.lineTo(rect.left, rect.top + effectiveRadius);

    // Top-left corner (squircle)
    path.cubicTo(
      rect.left, rect.top + magic,
      rect.left + magic, rect.top,
      rect.left + effectiveRadius, rect.top,
    );

    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style != BorderStyle.none) {
      final paint = side.toPaint();
      canvas.drawPath(getOuterPath(rect), paint);
    }
  }

  @override
  ShapeBorder scale(double t) => SquircleBorder(
    side: side.scale(t),
    radius: radius * t,
  );
}
