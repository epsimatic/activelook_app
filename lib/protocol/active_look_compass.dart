/// Command sequence for the HUD-style compass ribbon drawn on the glasses.
///
/// The ribbon mirrors the phone-side preview: cardinal/intercardinal letters
/// every 45°, a tick every 15°, and the current heading centred under a caret.
/// Everything is plain `line`/`txt` drawing, so it works on both color
/// (`MDP08`) and grey (`MDP05`) hardware.
library;

import '../models/compass.dart';
import 'active_look_palette.dart';
import 'active_look_protocol.dart';

/// One tick of the compass ribbon, positioned in display pixels.
class CompassRibbonTick {
  const CompassRibbonTick({
    required this.degrees,
    required this.x,
    required this.isMajor,
  });

  /// Normalised heading of the tick, `0 <= degrees < 360`.
  final int degrees;

  /// Horizontal position on the 304 px wide display.
  final int x;

  /// Major ticks fall on the 45° labels and are drawn longer.
  final bool isMajor;

  /// Label for this tick, or `null` for 15° ticks between the labels.
  String? get label => isMajor ? compassLabel(degrees.toDouble()) : null;
}

/// Geometry and command building for the on-glasses compass ribbon.
abstract final class CompassRibbon {
  /// Ribbon geometry on the 304×256 display (usable area is 30..274 × 25..231).
  static const int centerX = 152;
  static const int leftX = 30;
  static const int rightX = 274;
  static const int lineY = 176;
  static const int labelTopY = 124;
  static const int readoutTopY = 190;
  static const int labelFont = 0;
  static const int readoutFont = 1;
  static const int tickStepDegrees = 15;
  static const int labelStepDegrees = 45;

  /// Visible span is 180° (±90°) unless the display is narrower.
  static const double pixelsPerDegree = (rightX - leftX) / 180;

  /// Approximate glyph width of the built-in font 0 (24 px high).
  static const int glyphWidth = 13;

  /// Ticks visible for [heading], left to right.
  static List<CompassRibbonTick> ticksFor(double heading) {
    final h = normalizeHeading(heading);
    final first = ((h - 90) / tickStepDegrees).floor() * tickStepDegrees;
    final ticks = <CompassRibbonTick>[];

    for (var step = first; step <= h + 90; step += tickStepDegrees) {
      final x = (centerX + (step - h) * pixelsPerDegree).round();
      if (x < leftX || x > rightX) continue;
      final degrees = ((step % 360) + 360) % 360;
      ticks.add(
        CompassRibbonTick(
          degrees: degrees,
          x: x,
          isMajor: degrees % labelStepDegrees == 0,
        ),
      );
    }
    return ticks;
  }

  /// A complete, held display update: hold → clear → ribbon → flush.
  ///
  /// [colorCapable] selects `color`/`txtColor` on engo3 and falls back to
  /// `grayscale`/`txt` on the older 16-grey glasses.
  static List<ActiveLookCommand> frame({
    required double heading,
    required bool colorCapable,
    int accentColor = ActiveLookColor.green,
    int readoutColor = ActiveLookColor.bright,
  }) {
    final h = normalizeHeading(heading);
    final commands = <ActiveLookCommand>[
      ActiveLookCommands.hold(),
      ActiveLookCommands.clear(),
      if (colorCapable)
        ActiveLookCommands.color(accentColor)
      else
        ActiveLookCommands.grayscale(15),
      // Baseline of the ribbon.
      ActiveLookCommands.line(x0: leftX, y0: lineY, x1: rightX, y1: lineY),
    ];

    final ticks = ticksFor(h);
    for (final tick in ticks) {
      final height = tick.isMajor ? 12 : 6;
      commands.add(
        ActiveLookCommands.line(
          x0: tick.x,
          y0: lineY,
          x1: tick.x,
          y1: lineY + height,
        ),
      );
    }

    for (final tick in ticks) {
      final label = tick.label;
      if (label == null) continue;
      final width = label.length * glyphWidth;
      // Keep edge labels fully on the panel instead of dropping them.
      final x = (tick.x - width ~/ 2).clamp(leftX, rightX - width);
      commands.add(
        colorCapable
            ? ActiveLookCommands.textColor(
                x: x,
                y: labelTopY,
                text: label,
                font: labelFont,
                color: accentColor,
              )
            : ActiveLookCommands.text(
                x: x,
                y: labelTopY,
                text: label,
                font: labelFont,
                grey: 15,
              ),
      );
    }

    // Caret above the baseline, pointing at the current heading.
    commands.addAll([
      ActiveLookCommands.line(
        x0: centerX - 6,
        y0: lineY - 24,
        x1: centerX,
        y1: lineY - 10,
      ),
      ActiveLookCommands.line(
        x0: centerX + 6,
        y0: lineY - 24,
        x1: centerX,
        y1: lineY - 10,
      ),
    ]);

    final readout = '${compassLabel(h)} ${compassDegrees(h)}';
    final readoutWidth = readout.length * glyphWidth;
    commands.add(
      colorCapable
          ? ActiveLookCommands.textColor(
              x: centerX - readoutWidth ~/ 2,
              y: readoutTopY,
              text: readout,
              font: readoutFont,
              color: readoutColor,
            )
          : ActiveLookCommands.text(
              x: centerX - readoutWidth ~/ 2,
              y: readoutTopY,
              text: readout,
              font: readoutFont,
              grey: 15,
            ),
    );

    commands.add(ActiveLookCommands.flush());
    return commands;
  }

  /// Small centred message for when the sensor has not produced a heading yet.
  static List<ActiveLookCommand> waitingFrame({
    required bool colorCapable,
    String text = 'Kompas...',
  }) => [
    ActiveLookCommands.hold(),
    ActiveLookCommands.clear(),
    if (colorCapable)
      ActiveLookCommands.textColor(
        x: centerX - text.length * glyphWidth ~/ 2,
        y: 124,
        text: text,
        font: 1,
        color: ActiveLookColor.secondary,
      )
    else
      ActiveLookCommands.text(
        x: centerX - text.length * glyphWidth ~/ 2,
        y: 124,
        text: text,
        font: 1,
        grey: 8,
      ),
    ActiveLookCommands.flush(),
  ];
}
