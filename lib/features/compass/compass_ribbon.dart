import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/compass.dart';

/// HUD-style compass ribbon, as used in games: a horizontal scale that slides
/// under a fixed caret, with `N`/`NE`/`E`… letters every 45° and ticks every
/// 15°.
///
/// The same painter is used for the card on the phone and for the simulated
/// 304×256 framebuffer preview, so both match what the glasses draw.
class CompassRibbon extends StatelessWidget {
  const CompassRibbon({
    super.key,
    required this.heading,
    this.height = 176,
    this.showSurface = true,
  });

  /// Current heading in degrees clockwise from north, or `null` while the
  /// sensor has no fix.
  final double? heading;

  final double height;

  /// Draws the rounded dark surface behind the ribbon. The framebuffer preview
  /// already has a black background and passes `false`.
  final bool showSurface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final painter = CompassRibbonPainter(
      heading: heading,
      tickColor: colorScheme.outlineVariant,
      labelColor: colorScheme.onSurfaceVariant,
      accentColor: colorScheme.primary,
      emptyColor: colorScheme.onSurfaceVariant,
    );

    final ribbon = RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: painter),
      ),
    );

    return Semantics(
      label: heading == null
          ? 'Компас ожидает датчик устройства'
          : 'Компас ${compassLabel(heading!)} ${compassDegrees(heading!)} градусов',
      child: showSurface
          ? Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A2E)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ribbon,
            )
          : ribbon,
    );
  }
}

/// Paints the ribbon in normalised display coordinates: the layout fractions
/// mirror the command positions used by `CompassRibbon` on the glasses.
class CompassRibbonPainter extends CustomPainter {
  const CompassRibbonPainter({
    required this.heading,
    required this.tickColor,
    required this.labelColor,
    required this.accentColor,
    required this.emptyColor,
  });

  final double? heading;
  final Color tickColor;
  final Color labelColor;
  final Color accentColor;
  final Color emptyColor;

  /// Fractions of the 304×256 framebuffer used by the glasses renderer.
  static const double _labelTop = 124 / 256;
  static const double _lineY = 176 / 256;
  static const double _readoutTop = 190 / 256;
  static const double _left = 30 / 304;
  static const double _right = 274 / 304;

  /// ±90° are visible across the usable width.
  static const double _visibleDegrees = 180;

  @override
  void paint(Canvas canvas, Size size) {
    final value = heading;
    if (value == null) {
      _paintText(
        canvas,
        'Ожидание датчика…',
        fontSize: size.height * 0.085,
        color: emptyColor,
        centerX: size.width / 2,
        top: size.height * 0.55,
      );
      return;
    }

    final h = normalizeHeading(value);
    final left = size.width * _left;
    final right = size.width * _right;
    final width = right - left;
    final pixelsPerDegree = width / _visibleDegrees;
    final lineY = size.height * _lineY;

    final tickPaint = Paint()
      ..color = tickColor
      ..strokeWidth = math.max(1, size.height * 0.006)
      ..isAntiAlias = true;

    // Baseline.
    canvas.drawLine(Offset(left, lineY), Offset(right, lineY), tickPaint);

    final labelSize = size.height * 0.075;
    final first = ((h - 90) / 15).floor() * 15;
    for (var step = first; step <= h + 90; step += 15) {
      final x = size.width / 2 + (step - h) * pixelsPerDegree;
      if (x < left || x > right) continue;
      final degrees = ((step % 360) + 360) % 360;
      final isMajor = degrees % 45 == 0;
      final height = isMajor ? 0.045 : 0.022;
      canvas.drawLine(
        Offset(x, lineY),
        Offset(x, lineY + size.height * height),
        tickPaint,
      );

      if (!isMajor) continue;
      final label = compassLabel(degrees.toDouble());
      final isCurrent = compassLabelIndex(h) == degrees ~/ 45;
      _paintText(
        canvas,
        label,
        fontSize: labelSize,
        color: isCurrent ? accentColor : labelColor,
        centerX: x,
        top: size.height * _labelTop,
        bold: isCurrent,
      );
    }

    // Fixed caret pointing at the current heading.
    final caret = Path()
      ..moveTo(size.width / 2 - size.width * 0.02, lineY - size.height * 0.11)
      ..lineTo(size.width / 2, lineY - size.height * 0.045)
      ..lineTo(size.width / 2 + size.width * 0.02, lineY - size.height * 0.11)
      ..close();
    canvas.drawPath(caret, Paint()..color = accentColor);

    _paintText(
      canvas,
      '${compassLabel(h)} ${compassDegrees(h)}°',
      fontSize: size.height * 0.095,
      color: accentColor,
      centerX: size.width / 2,
      top: size.height * _readoutTop,
      bold: true,
    );
  }

  void _paintText(
    Canvas canvas,
    String text, {
    required double fontSize,
    required Color color,
    required double centerX,
    required double top,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          letterSpacing: fontSize * 0.04,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(canvas, Offset(centerX - painter.width / 2, top));
  }

  @override
  bool shouldRepaint(CompassRibbonPainter oldDelegate) =>
      oldDelegate.heading != heading ||
      oldDelegate.tickColor != tickColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.emptyColor != emptyColor;
}
