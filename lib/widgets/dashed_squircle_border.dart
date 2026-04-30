import 'dart:ui';

import 'package:flutter/material.dart';

class DashedSquircleBorder extends ShapeBorder {
  final BorderSide side;
  final double radius;
  final double dashLength;
  final double dashGap;

  const DashedSquircleBorder({
    this.side = BorderSide.none,
    this.radius = 24.0,
    this.dashLength = 5.0,
    this.dashGap = 3.0,
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

    path.moveTo(rect.left + effectiveRadius, rect.top);
    path.lineTo(rect.right - effectiveRadius, rect.top);
    path.cubicTo(
      rect.right - magic,
      rect.top,
      rect.right,
      rect.top + magic,
      rect.right,
      rect.top + effectiveRadius,
    );
    path.lineTo(rect.right, rect.bottom - effectiveRadius);
    path.cubicTo(
      rect.right,
      rect.bottom - magic,
      rect.right - magic,
      rect.bottom,
      rect.right - effectiveRadius,
      rect.bottom,
    );
    path.lineTo(rect.left + effectiveRadius, rect.bottom);
    path.cubicTo(
      rect.left + magic,
      rect.bottom,
      rect.left,
      rect.bottom - magic,
      rect.left,
      rect.bottom - effectiveRadius,
    );
    path.lineTo(rect.left, rect.top + effectiveRadius);
    path.cubicTo(
      rect.left,
      rect.top + magic,
      rect.left + magic,
      rect.top,
      rect.left + effectiveRadius,
      rect.top,
    );

    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style != BorderStyle.none) {
      final paint = side.toPaint();
      canvas.drawPath(
          _dashPath(getOuterPath(rect),
              dashLength: dashLength, dashGap: dashGap),
          paint);
    }
  }

  @override
  ShapeBorder scale(double t) => DashedSquircleBorder(
        side: side.scale(t),
        radius: radius * t,
      );

  Path _dashPath(Path source, {required double dashLength, required double dashGap}) {
    final Path dest = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        dest.addPath(
          metric.extractPath(distance, distance + dashLength),
          Offset.zero,
        );
        distance += dashLength + dashGap;
      }
    }
    return dest;
  }
}