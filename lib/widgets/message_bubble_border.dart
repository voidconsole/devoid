import 'package:flutter/material.dart';

class MessageBubbleBorder extends ShapeBorder {
  final bool isUser;
  final BorderSide side;

  const MessageBubbleBorder({required this.isUser, this.side = BorderSide.none});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return getOuterPath(rect.deflate(side.width), textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = Path();
    final w = rect.width;
    final h = rect.height;
    final left = rect.left;
    final top = rect.top;

    if (isUser) {
      // User message - tail on right side
      // Original SVG: 274x49
      const svgW = 274.0;
      const svgH = 49.0;

      // Fixed dimensions (keep these constant)
      const leftCornerWidth = 24.0;
      const tailStartX = 244.065;
      const tailWidth = svgW - tailStartX; // ~30 units

      // Use a fixed scale factor for the design (adjust this to match your design size)
      const designScale = 1.0; // You can adjust this to make shapes bigger/smaller

      final fixedLeftCorner = leftCornerWidth * designScale;
      final fixedTailWidth = tailWidth * designScale;

      // Middle section stretches to fill remaining width
      final middleWidth = w - fixedLeftCorner - fixedTailWidth;

      // Vertical scale factor for height-based curves
      final vScale = h / svgH;

      // Start at top-left
      path.moveTo(left + fixedLeftCorner + middleWidth, top + vScale * 0.5);
      path.lineTo(left + fixedLeftCorner, top + vScale * 0.5);

      // Top-left corner (fixed horizontal, scaled vertical)
      path.cubicTo(
          left + designScale * 18.3291, top + vScale * 0.5,
          left + designScale * 14.1261, top + vScale * 0.500764,
          left + designScale * 10.8994, top + vScale * 0.93457
      );
      path.cubicTo(
          left + designScale * 7.6871, top + vScale * 1.36646,
          left + designScale * 5.51715, top + vScale * 2.21919,
          left + designScale * 3.86816, top + vScale * 3.86816
      );
      path.cubicTo(
          left + designScale * 2.21919, top + vScale * 5.51714,
          left + designScale * 1.36645, top + vScale * 7.68709,
          left + designScale * 0.93457, top + vScale * 10.8994
      );
      path.cubicTo(
          left + designScale * 0.500764, top + vScale * 14.1261,
          left + designScale * 0.5, top + vScale * 18.3291,
          left + designScale * 0.5, top + vScale * 24
      );

      // Left edge
      path.lineTo(left + designScale * 0.5, top + vScale * 25);

      // Bottom-left corner (fixed horizontal, scaled vertical)
      path.cubicTo(
          left + designScale * 0.5, top + vScale * 30.6709,
          left + designScale * 0.500764, top + vScale * 34.8739,
          left + designScale * 0.93457, top + vScale * 38.1006
      );
      path.cubicTo(
          left + designScale * 1.36645, top + vScale * 41.3129,
          left + designScale * 2.21919, top + vScale * 43.4829,
          left + designScale * 3.86816, top + vScale * 45.1318
      );
      path.cubicTo(
          left + designScale * 5.51715, top + vScale * 46.7808,
          left + designScale * 7.6871, top + vScale * 47.6335,
          left + designScale * 10.8994, top + vScale * 48.0654
      );
      path.cubicTo(
          left + designScale * 14.1261, top + vScale * 48.4992,
          left + designScale * 18.3291, top + vScale * 48.5,
          left + designScale * 24, top + vScale * 48.5
      );

      // Bottom edge (stretchable)
      path.lineTo(left + fixedLeftCorner + middleWidth, top + vScale * 48.5);

      // Bottom-right tail (fixed size)
      final tailX = left + fixedLeftCorner + middleWidth;
      path.cubicTo(
          tailX + designScale * (252.419 - tailStartX), top + vScale * 48.5,
          tailX + designScale * (258.337 - tailStartX), top + vScale * 48.4983,
          tailX + designScale * (262.714 - tailStartX), top + vScale * 47.8525
      );
      path.cubicTo(
          tailX + designScale * (267.08 - tailStartX), top + vScale * 47.2083,
          tailX + designScale * (269.793 - tailStartX), top + vScale * 45.9387,
          tailX + designScale * (271.465 - tailStartX), top + vScale * 43.498
      );
      path.cubicTo(
          tailX + designScale * (273.136 - tailStartX), top + vScale * 41.0573,
          tailX + designScale * (273.34 - tailStartX), top + vScale * 38.0682,
          tailX + designScale * (272.362 - tailStartX), top + vScale * 33.7646
      );
      path.cubicTo(
          tailX + designScale * (271.382 - tailStartX), top + vScale * 29.4505,
          tailX + designScale * (269.243 - tailStartX), top + vScale * 23.9315,
          tailX + designScale * (266.363 - tailStartX), top + vScale * 16.5039
      );

      path.lineTo(tailX + designScale * (265.976 - tailStartX), top + vScale * 15.5039);
      path.cubicTo(
          tailX + designScale * (264.534 - tailStartX), top + vScale * 11.7854,
          tailX + designScale * (263.466 - tailStartX), top + vScale * 9.0346,
          tailX + designScale * (262.38 - tailStartX), top + vScale * 6.94824
      );
      path.cubicTo(
          tailX + designScale * (261.299 - tailStartX), top + vScale * 4.87294,
          tailX + designScale * (260.221 - tailStartX), top + vScale * 3.49814,
          tailX + designScale * (258.78 - tailStartX), top + vScale * 2.51172
      );
      path.cubicTo(
          tailX + designScale * (257.34 - tailStartX), top + vScale * 1.52533,
          tailX + designScale * (255.668 - tailStartX), top + vScale * 1.01704,
          tailX + designScale * (253.343 - tailStartX), top + vScale * 0.759766
      );
      path.cubicTo(
          tailX + designScale * (251.005 - tailStartX), top + vScale * 0.50114,
          tailX + designScale * (248.054 - tailStartX), top + vScale * 0.5,
          tailX + designScale * (244.065 - tailStartX), top + vScale * 0.5
      );

    } else {
      // Other user message - tail on left side
      // Original SVG: 289x49
      const svgW = 289.0;
      const svgH = 49.0;

      // Fixed dimensions (keep these constant)
      const tailEndX = 29.3838;
      const rightCornerStart = 264.449;
      const rightCornerWidth = svgW - rightCornerStart;

      // Use a fixed scale factor for the design
      const designScale = 1.0; // You can adjust this to make shapes bigger/smaller

      final fixedTailWidth = tailEndX * designScale;
      final fixedRightCorner = rightCornerWidth * designScale;

      // Middle section stretches to fill remaining width
      final middleWidth = w - fixedTailWidth - fixedRightCorner;

      // Vertical scale factor for height-based curves
      final vScale = h / svgH;

      // Start with left tail (fixed size)
      path.moveTo(left + fixedTailWidth, top + vScale * 0.5);

      // Top edge (stretchable)
      path.lineTo(left + fixedTailWidth + middleWidth, top + vScale * 0.5);

      // Top-right corner (fixed horizontal, scaled vertical)
      final cornerX = left + fixedTailWidth + middleWidth;
      path.cubicTo(
          cornerX + designScale * (270.12 - rightCornerStart), top + vScale * 0.5,
          cornerX + designScale * (274.323 - rightCornerStart), top + vScale * 0.500764,
          cornerX + designScale * (277.55 - rightCornerStart), top + vScale * 0.93457
      );
      path.cubicTo(
          cornerX + designScale * (280.762 - rightCornerStart), top + vScale * 1.36646,
          cornerX + designScale * (282.932 - rightCornerStart), top + vScale * 2.21919,
          cornerX + designScale * (284.581 - rightCornerStart), top + vScale * 3.86816
      );
      path.cubicTo(
          cornerX + designScale * (286.23 - rightCornerStart), top + vScale * 5.51714,
          cornerX + designScale * (287.083 - rightCornerStart), top + vScale * 7.68709,
          cornerX + designScale * (287.515 - rightCornerStart), top + vScale * 10.8994
      );
      path.cubicTo(
          cornerX + designScale * (287.948 - rightCornerStart), top + vScale * 14.1261,
          cornerX + designScale * (287.949 - rightCornerStart), top + vScale * 18.3291,
          cornerX + designScale * (287.949 - rightCornerStart), top + vScale * 24
      );

      // Right edge
      path.lineTo(cornerX + designScale * (287.949 - rightCornerStart), top + vScale * 25);

      // Bottom-right corner (fixed horizontal, scaled vertical)
      path.cubicTo(
          cornerX + designScale * (287.949 - rightCornerStart), top + vScale * 30.6709,
          cornerX + designScale * (287.948 - rightCornerStart), top + vScale * 34.8739,
          cornerX + designScale * (287.515 - rightCornerStart), top + vScale * 38.1006
      );
      path.cubicTo(
          cornerX + designScale * (287.083 - rightCornerStart), top + vScale * 41.3129,
          cornerX + designScale * (286.23 - rightCornerStart), top + vScale * 43.4829,
          cornerX + designScale * (284.581 - rightCornerStart), top + vScale * 45.1318
      );
      path.cubicTo(
          cornerX + designScale * (282.932 - rightCornerStart), top + vScale * 46.7808,
          cornerX + designScale * (280.762 - rightCornerStart), top + vScale * 47.6335,
          cornerX + designScale * (277.55 - rightCornerStart), top + vScale * 48.0654
      );
      path.cubicTo(
          cornerX + designScale * (274.323 - rightCornerStart), top + vScale * 48.4992,
          cornerX + designScale * (270.12 - rightCornerStart), top + vScale * 48.5,
          cornerX + designScale * (264.449 - rightCornerStart), top + vScale * 48.5
      );

      // Bottom edge (stretchable)
      path.lineTo(left + fixedTailWidth, top + vScale * 48.5);

      // Bottom-left tail (fixed size)
      path.cubicTo(
          left + designScale * 21.03, top + vScale * 48.5,
          left + designScale * 15.112, top + vScale * 48.4983,
          left + designScale * 10.7354, top + vScale * 47.8525
      );
      path.cubicTo(
          left + designScale * 6.36931, top + vScale * 47.2083,
          left + designScale * 3.65587, top + vScale * 45.9387,
          left + designScale * 1.98438, top + vScale * 43.498
      );
      path.cubicTo(
          left + designScale * 0.312951, top + vScale * 41.0573,
          left + designScale * 0.109219, top + vScale * 38.0682,
          left + designScale * 1.08691, top + vScale * 33.7646
      );
      path.cubicTo(
          left + designScale * 2.06707, top + vScale * 29.4505,
          left + designScale * 4.20585, top + vScale * 23.9315,
          left + designScale * 7.08594, top + vScale * 16.5039
      );

      path.lineTo(left + designScale * 7.47363, top + vScale * 15.5039);
      path.cubicTo(
          left + designScale * 8.9155, top + vScale * 11.7854,
          left + designScale * 9.983, top + vScale * 9.0346,
          left + designScale * 11.0693, top + vScale * 6.94824
      );
      path.cubicTo(
          left + designScale * 12.15, top + vScale * 4.87294,
          left + designScale * 13.2286, top + vScale * 3.49814,
          left + designScale * 14.6689, top + vScale * 2.51172
      );
      path.cubicTo(
          left + designScale * 16.1094, top + vScale * 1.52533,
          left + designScale * 17.7809, top + vScale * 1.01704,
          left + designScale * 20.1064, top + vScale * 0.759766
      );
      path.cubicTo(
          left + designScale * 21.8601, top + vScale * 0.565781,
          left + designScale * 23.9587, top + vScale * 0.516226,
          left + designScale * 26.5811, top + vScale * 0.503906
      );
      path.lineTo(left + designScale * 29.3838, top + vScale * 0.5);
    }

    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final path = getOuterPath(rect, textDirection: textDirection);
    canvas.drawPath(path, side.toPaint());
  }

  @override
  ShapeBorder scale(double t) {
    return MessageBubbleBorder(isUser: isUser, side: side.scale(t));
  }
}