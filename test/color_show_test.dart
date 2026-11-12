import 'package:activelook_flutter/models/color_show.dart';
import 'package:activelook_flutter/protocol/active_look_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pulse rings', () {
    test('shrink towards the centre and reach the screen corners', () {
      final rings = ColorShow.frame(
        ColorShowMode.pulse,
        0,
      ).cast<FilledCircleShape>();

      expect(rings, hasLength(ColorShow.pulseRadii.length));
      for (var i = 1; i < rings.length; i++) {
        expect(rings[i].radius, lessThan(rings[i - 1].radius));
      }
      expect(rings.first.x, ColorShow.displayWidth ~/ 2);
      expect(rings.first.y, ColorShow.displayHeight ~/ 2);
      // Half-diagonal of 304×256 is ~199 px, so the largest ring covers it all.
      expect(
        rings.first.radius * rings.first.radius,
        greaterThan(152 * 152 + 128 * 128),
      );
    });

    test('rotate their colors with the phase', () {
      final first = ColorShow.frame(
        ColorShowMode.pulse,
        0,
      ).cast<FilledCircleShape>();
      final second = ColorShow.frame(
        ColorShowMode.pulse,
        3,
      ).cast<FilledCircleShape>();

      for (var i = 0; i < first.length; i++) {
        expect(first[i].color, ColorShow.ramp[i % ColorShow.ramp.length]);
        expect(
          second[i].color,
          ColorShow.ramp[(i + 3) % ColorShow.ramp.length],
        );
      }
    });
  });

  test('draw commands set the color before every shape', () {
    final frame = ColorShow.frame(ColorShowMode.pulse, 2);
    final commands = ColorShow.drawCommands(frame);

    expect(commands, hasLength(frame.length * 2));
    for (var i = 0; i < frame.length; i++) {
      expect(commands[i * 2].id, ActiveLookCommandId.color);
      expect(commands[i * 2].data, [frame[i].color]);
      expect(commands[i * 2 + 1].id, ActiveLookCommandId.circf);
    }
  });

  test('non-shape modes are not part of the shape frame API', () {
    expect(() => ColorShow.frame(ColorShowMode.sweep, 0), throwsArgumentError);
    expect(
      () => ColorShow.frame(ColorShowMode.counter, 0),
      throwsArgumentError,
    );
  });

  group('low-BLE sweep', () {
    test('one arc segment per frame, joined all the way around', () {
      expect(ColorShow.sweepSteps, 30);

      final first = ColorShow.sweepSegment(0);
      final second = ColorShow.sweepSegment(1);

      expect(first.startAngle, 0);
      expect(first.endAngle, greaterThanOrEqualTo(ColorShow.sweepStepDegrees));
      expect(
        second.startAngle,
        greaterThan(first.startAngle),
        reason: 'segments must advance clockwise',
      );
      expect(first.x, ColorShow.displayWidth ~/ 2);
      expect(first.y, ColorShow.displayHeight ~/ 2);
      expect(
        ColorShow.sweepSegment(ColorShow.sweepSteps - 1).endAngle,
        360 + 2,
      );
    });

    test('costs two commands (~21 bytes) per frame', () {
      final segment = ColorShow.sweepSegment(4);
      final commands = ColorShow.drawCommands([segment]);

      expect(commands, hasLength(2));
      expect(commands.first.id, ActiveLookCommandId.color);
      expect(commands.last.id, ActiveLookCommandId.arc);

      final bytes = commands.fold<int>(
        0,
        (sum, command) => sum + command.encode().length,
      );
      expect(bytes, 21);

      // A full-screen ring frame costs an order of magnitude more.
      final rings = [
        ActiveLookCommands.hold(),
        ActiveLookCommands.clear(),
        ...ColorShow.drawCommands(ColorShow.frame(ColorShowMode.pulse, 0)),
        ActiveLookCommands.flush(),
      ];
      final ringBytes = rings.fold<int>(
        0,
        (sum, command) => sum + command.encode().length,
      );
      expect(ringBytes, greaterThan(bytes * 5));
    });
  });
}
