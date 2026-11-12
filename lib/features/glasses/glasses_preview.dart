import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/color_show.dart';
import '../../protocol/active_look_palette.dart';
import '../compass/compass_ribbon.dart';

/// Faithful-ish preview of the glasses framebuffer (304×256).
///
/// The panel is a memory display: black is transparent, so the preview is black
/// with the content drawn in palette colors. The faint rectangle is the
/// recommended usable area (30 px horizontal / 25 px vertical margins).
///
/// Text and [shapes] are mutually exclusive in practice: the demo text is shown
/// when [shapes] is empty, the animated color demo otherwise.
class GlassesPreview extends StatelessWidget {
  const GlassesPreview({
    super.key,
    required this.text,
    this.textColor = ActiveLookColor.bright,
    this.shapes = const [],
    this.showUsableArea = true,
    this.highlight = false,
    this.compassHeading,
    this.compassColor = ActiveLookColor.green,
  });

  static const int displayWidth = 304;
  static const int displayHeight = 256;

  /// Anchor used by the demo text; centred rather than top-left, matching the
  /// API spec example for rotation 4.
  static const int textAnchorX = 152;
  static const int textAnchorY = 128;

  /// Height of the built-in font 3, in pixels (the largest of the four).
  static const int fontSizePx = 49;

  final String text;
  final int textColor;

  /// Shapes of the current animation frame, back to front.
  final List<GlassesShape> shapes;

  final bool showUsableArea;

  /// Draws a bright, glowing border — used to flash the preview on tap.
  final bool highlight;

  /// Heading of the compass ribbon currently on the glasses, if any.
  ///
  /// When set, the preview mirrors the on-glasses HUD ribbon instead of the
  /// demo text/shapes.
  final double? compassHeading;

  /// Palette value used for the ribbon accent (green on color glasses).
  final int compassColor;

  @override
  Widget build(BuildContext context) {
    final color = Color(paletteColor(textColor));
    final hasShapes = shapes.isNotEmpty;
    final showCompass = compassHeading != null;
    final highlightColor = Theme.of(context).colorScheme.primary;

    return AspectRatio(
      aspectRatio: displayWidth / displayHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / displayWidth;
          final alignment = Alignment(
            2 * textAnchorX / displayWidth - 1,
            2 * textAnchorY / displayHeight - 1,
          );

          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: highlight ? highlightColor : const Color(0xFF2A2A2E),
                width: highlight ? 2 : 1,
              ),
              boxShadow: highlight
                  ? [
                      BoxShadow(
                        color: highlightColor.withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                if (hasShapes)
                  Positioned.fill(
                    child: CustomPaint(painter: _GlassesShapesPainter(shapes)),
                  ),
                if (showCompass)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: CompassRibbonPainter(
                        heading: compassHeading,
                        tickColor: const Color(0xFF4A4A4E),
                        labelColor: const Color(0xFF9A9A9F),
                        accentColor: Color(paletteColor(compassColor)),
                        emptyColor: const Color(0xFF5A5A5F),
                      ),
                    ),
                  ),
                if (showUsableArea && !hasShapes && !showCompass)
                  Positioned(
                    left: 30 * scale,
                    top: 25 * scale,
                    width: 244 * scale,
                    height: 206 * scale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF232326)),
                      ),
                    ),
                  ),
                if (!hasShapes && !showCompass && text.trim().isEmpty)
                  Center(
                    child: Text(
                      'экран чист',
                      style: TextStyle(
                        color: const Color(0xFF3A3A3E),
                        fontSize: 12 * scale.clamp(1, 1.6),
                      ),
                    ),
                  )
                else if (!hasShapes && !showCompass)
                  Align(
                    alignment: alignment,
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: color,
                        fontSize: fontSizePx * scale,
                        height: 1.1,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Paints a demo frame with the exact palette colors the glasses were sent.
class _GlassesShapesPainter extends CustomPainter {
  const _GlassesShapesPainter(this.shapes);

  final List<GlassesShape> shapes;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / GlassesPreview.displayWidth;
    final paint = Paint()..isAntiAlias = false;

    for (final shape in shapes) {
      paint.color = Color(paletteColor(shape.color));
      switch (shape) {
        case FilledRectShape(:final x0, :final y0, :final x1, :final y1):
          canvas.drawRect(
            Rect.fromLTRB(
              x0 * scale,
              y0 * scale,
              (x1 + 1) * scale,
              (y1 + 1) * scale,
            ),
            paint,
          );
        case FilledCircleShape(:final x, :final y, :final radius):
          canvas.drawCircle(
            Offset(x * scale, y * scale),
            radius * scale,
            paint,
          );
        case ArcShape(
          :final x,
          :final y,
          :final radius,
          :final startAngle,
          :final endAngle,
          :final thickness,
        ):
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, thickness * scale)
            ..isAntiAlias = true;
          canvas.drawArc(
            Rect.fromCircle(
              center: Offset(x * scale, y * scale),
              radius: radius * scale,
            ),
            startAngle * math.pi / 180,
            (endAngle - startAngle) * math.pi / 180,
            false,
            paint,
          );
          paint
            ..style = PaintingStyle.fill
            ..isAntiAlias = false;
      }
    }
  }

  @override
  bool shouldRepaint(_GlassesShapesPainter oldDelegate) =>
      oldDelegate.shapes != shapes;
}
