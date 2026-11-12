/// Full-screen color/animation demo shown on the glasses.
///
/// The frames are plain shape lists so the exact same data drives both the BLE
/// commands and the phone-side preview: what the preview paints is what the
/// glasses are told to paint.
///
/// Everything is drawn edge to edge on the 304×256 panel and only uses entries
/// from the 81-color red/green palette — there is no blue on engo3.
library;

import '../protocol/active_look_palette.dart';
import '../protocol/active_look_protocol.dart';

/// One filled primitive, in one palette color.
sealed class GlassesShape {
  const GlassesShape({required this.color});

  /// ActiveLook 8-bit palette value (see [activeLookPalette]).
  final int color;
}

/// Filled rectangle, coordinates inclusive like the `rectf` (0x34) command.
final class FilledRectShape extends GlassesShape {
  const FilledRectShape({
    required super.color,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
  });

  final int x0;
  final int y0;
  final int x1;
  final int y1;
}

/// Filled circle, matching the `circf` (0x36) command.
final class FilledCircleShape extends GlassesShape {
  const FilledCircleShape({
    required super.color,
    required this.x,
    required this.y,
    required this.radius,
  });

  final int x;
  final int y;
  final int radius;
}

/// Circular arc with thickness, matching the `arc` (0x3C) command.
final class ArcShape extends GlassesShape {
  const ArcShape({
    required super.color,
    required this.x,
    required this.y,
    required this.radius,
    required this.startAngle,
    required this.endAngle,
    required this.thickness,
  });

  final int x;
  final int y;
  final int radius;

  /// Degrees, 0° at 3 o'clock, increasing clockwise.
  final int startAngle;
  final int endAngle;
  final int thickness;
}

/// One animation mode of the color show.
enum ColorShowMode {
  /// Concentric, full-screen rings whose colors rotate outwards.
  pulse('Кольца'),

  /// One growing arc segment per frame: two small commands, no full-screen
  /// redraw. The lowest BLE traffic way to show smooth motion.
  sweep('Экономная заливка'),

  /// A number that increments every frame, in an alternating palette color.
  /// The cheapest readable text update: `hold → clear → txtColor → flush`.
  counter('Быстрый счётчик');

  const ColorShowMode(this.label);

  final String label;
}

/// Builds the frames of the animated color demo.
abstract final class ColorShow {
  static const int displayWidth = 304;
  static const int displayHeight = 256;

  /// Palette ramp: red → orange → yellow → green, the only hues the panel has.
  static const List<int> ramp = [
    ActiveLookColor.red,
    0x20,
    0x1C,
    0x28,
    0xDB,
    0xC3,
    ActiveLookColor.green,
    0x43,
  ];

  /// Radii of the [ColorShowMode.pulse] rings, largest first. 199 px reaches
  /// the corners of the 304×256 panel, so the first circle covers everything.
  static const List<int> pulseRadii = [199, 168, 136, 104, 72, 40, 18];

  /// Degrees added to the [ColorShowMode.sweep] ring per frame.
  static const int sweepStepDegrees = 12;
  static const int sweepRadius = 92;
  static const int sweepThickness = 20;

  /// Number of frames in one full revolution of the sweep ring.
  static int get sweepSteps => 360 ~/ sweepStepDegrees;

  /// Frame [phase] of [mode]. Frames are ordered back to front.
  ///
  /// Only full-frame shape modes are supported here; [ColorShowMode.sweep] draws
  /// one incremental segment at a time (see [sweepSegment]) and
  /// [ColorShowMode.counter] is plain text.
  static List<GlassesShape> frame(ColorShowMode mode, int phase) =>
      switch (mode) {
        ColorShowMode.pulse => _pulse(phase),
        ColorShowMode.sweep ||
        ColorShowMode.counter => throw ArgumentError.value(
          mode,
          'mode',
          'this mode is not a full-frame shape sequence',
        ),
      };

  /// One segment of the growing sweep ring, starting at step [step].
  ///
  /// The end overlaps the next segment by a couple of degrees so the joins are
  /// invisible, and the color steps through the ramp.
  static ArcShape sweepSegment(int step) {
    final start = step * sweepStepDegrees;
    return ArcShape(
      x: displayWidth ~/ 2,
      y: displayHeight ~/ 2,
      radius: sweepRadius,
      startAngle: start,
      endAngle: start + sweepStepDegrees + 2,
      thickness: sweepThickness,
      color: ramp[step % ramp.length],
    );
  }

  /// Commands that draw [frame]: `color` (0x3D) before every shape, because the
  /// color applies to the next graphical element only.
  static List<ActiveLookCommand> drawCommands(List<GlassesShape> frame) => [
    for (final shape in frame) ...[
      ActiveLookCommands.color(shape.color),
      switch (shape) {
        FilledRectShape(:final x0, :final y0, :final x1, :final y1) =>
          ActiveLookCommands.rectf(x0: x0, y0: y0, x1: x1, y1: y1),
        FilledCircleShape(:final x, :final y, :final radius) =>
          ActiveLookCommands.circf(x: x, y: y, radius: radius),
        ArcShape(
          :final x,
          :final y,
          :final radius,
          :final startAngle,
          :final endAngle,
          :final thickness,
        ) =>
          ActiveLookCommands.arc(
            x: x,
            y: y,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            thickness: thickness,
          ),
      },
    ],
  ];

  static List<GlassesShape> _pulse(int phase) {
    return [
      for (var i = 0; i < pulseRadii.length; i++)
        FilledCircleShape(
          x: displayWidth ~/ 2,
          y: displayHeight ~/ 2,
          radius: pulseRadii[i],
          color: ramp[(i + phase) % ramp.length],
        ),
    ];
  }
}
