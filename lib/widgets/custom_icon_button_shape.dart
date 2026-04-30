import 'package:flutter/material.dart';

class CustomIconButtonShape extends ShapeBorder {
  final BorderSide side;

  const CustomIconButtonShape({this.side = BorderSide.none});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return getOuterPath(rect.deflate(side.width), textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final width = rect.width;
    final height = rect.height;

    // Original SVG dimensions for ratio calculations
    const originalWidth = 53.0;
    const originalHeight = 49.0;

    // Scale factors
    final scaleX = width / originalWidth;
    final scaleY = height / originalHeight;

    final path = Path();

    // Starting point (scaled from M43.7062 39.7077)
    path.moveTo(43.7062 * scaleX + rect.left, 39.7077 * scaleY + rect.top);

    // Curve to bottom right point
    path.cubicTo(
      40.1676 * scaleX + rect.left, 44.2706 * scaleY + rect.top,
      38.3984 * scaleX + rect.left, 46.5521 * scaleY + rect.top,
      35.9003 * scaleX + rect.left, 47.776 * scaleY + rect.top,
    );

    path.cubicTo(
      33.4023 * scaleX + rect.left, 49 * scaleY + rect.top,
      30.5152 * scaleX + rect.left, 49 * scaleY + rect.top,
      24.741 * scaleX + rect.left, 49 * scaleY + rect.top,
    );

    // Line to bottom left
    path.lineTo(24 * scaleX + rect.left, 49 * scaleY + rect.top);

    // Line along bottom (implicitly to around x=12.6863)
    path.cubicTo(
      12.6863 * scaleX + rect.left, 49 * scaleY + rect.top,
      7.02944 * scaleX + rect.left, 49 * scaleY + rect.top,
      3.51472 * scaleX + rect.left, 45.4853 * scaleY + rect.top,
    );

    // Curve to left side
    path.cubicTo(
      0 * scaleX + rect.left, 41.9705 * scaleY + rect.top,
      0 * scaleX + rect.left, 36.3137 * scaleY + rect.top,
      0 * scaleX + rect.left, 25 * scaleY + rect.top,
    );

    // Continue along left side
    path.lineTo(0 * scaleX + rect.left, 24.5 * scaleY + rect.top);
    path.lineTo(0 * scaleX + rect.left, 24 * scaleY + rect.top);

    // Curve up left side
    path.cubicTo(
      0 * scaleX + rect.left, 12.6863 * scaleY + rect.top,
      0 * scaleX + rect.left, 7.02943 * scaleY + rect.top,
      3.51471 * scaleX + rect.left, 3.51471 * scaleY + rect.top,
    );

    // Curve to top
    path.cubicTo(
      7.02943 * scaleX + rect.left, 0 * scaleY + rect.top,
      12.6863 * scaleX + rect.left, 0 * scaleY + rect.top,
      24 * scaleX + rect.left, 0 * scaleY + rect.top,
    );

    // Continue along top
    path.lineTo(24.7409 * scaleX + rect.left, 0 * scaleY + rect.top );

    path.cubicTo(
      30.5152 * scaleX + rect.left, 0 * scaleY + rect.top,
      33.4023 * scaleX + rect.left, 0 * scaleY + rect.top,
      35.9003 * scaleX + rect.left, 1.22392 * scaleY + rect.top,
    );

    // Curve to top right point
    path.cubicTo(
      38.3984 * scaleX + rect.left, 2.44787 * scaleY + rect.top,
      40.1677 * scaleX + rect.left, 4.72931 * scaleY + rect.top,
      43.7062 * scaleX + rect.left, 9.29221 * scaleY + rect.top,
    );

    // Point details
    path.lineTo(44.094 * scaleX + rect.left, 9.79219 * scaleY + rect.top);

    // Curve to middle right point
    path.cubicTo(
      49.5742 * scaleX + rect.left, 16.8588 * scaleY + rect.top,
      52.3144 * scaleX + rect.left, 20.3921 * scaleY + rect.top,
      52.3144 * scaleX + rect.left, 24.5 * scaleY + rect.top,
    );

    // Curve back down
    path.cubicTo(
      52.3144 * scaleX + rect.left, 28.6078 * scaleY + rect.top,
      49.5742 * scaleX + rect.left, 32.1411 * scaleY + rect.top,
      44.094 * scaleX + rect.left, 39.2077 * scaleY + rect.top,
    );

    // Close at starting point
    path.lineTo(43.7062 * scaleX + rect.left, 39.7077 * scaleY + rect.top);

    path.close();

    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style != BorderStyle.none) {
      final paint = side.toPaint();
      canvas.drawPath(getOuterPath(rect, textDirection: textDirection), paint);
    }
  }

  @override
  ShapeBorder scale(double t) => CustomIconButtonShape(side: side.scale(t));
}
