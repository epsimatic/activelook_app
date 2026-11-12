import 'dart:async';

import 'package:activelook_flutter/ble/mock_glasses.dart';
import 'package:activelook_flutter/features/compass/compass_source.dart';
import 'package:activelook_flutter/features/glasses/glasses_controller.dart';
import 'package:activelook_flutter/models/compass.dart';
import 'package:activelook_flutter/models/discovered_glasses.dart';
import 'package:activelook_flutter/protocol/active_look_compass.dart';
import 'package:activelook_flutter/protocol/active_look_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compass labels', () {
    test('normalizeHeading wraps into 0..<360', () {
      expect(normalizeHeading(0), 0);
      expect(normalizeHeading(360), 0);
      expect(normalizeHeading(-90), 270);
      expect(normalizeHeading(725), 5);
    });

    test('labels use the nearest 45° sector', () {
      expect(compassLabel(0), 'N');
      expect(compassLabel(22.4), 'N');
      expect(compassLabel(22.5), 'NE');
      expect(compassLabel(45), 'NE');
      expect(compassLabel(90), 'E');
      expect(compassLabel(135), 'SE');
      expect(compassLabel(180), 'S');
      expect(compassLabel(225), 'SW');
      expect(compassLabel(270), 'W');
      expect(compassLabel(315), 'NW');
      expect(compassLabel(337.5), 'N');
      expect(compassLabel(359.9), 'N');
      expect(compassLabel(-45), 'NW');
    });

    test('degrees are rounded and wrapped', () {
      expect(compassDegrees(0), 0);
      expect(compassDegrees(359.6), 0);
      expect(compassDegrees(359.4), 359);
      expect(compassDegrees(-0.4), 0);
    });
  });

  group('on-glasses ribbon', () {
    test('ticks span the usable width and labels every 45°', () {
      final ticks = CompassRibbon.ticksFor(0);

      expect(ticks.first.x, greaterThanOrEqualTo(CompassRibbon.leftX));
      expect(ticks.last.x, lessThanOrEqualTo(CompassRibbon.rightX));
      expect(ticks.map((tick) => tick.label).whereType<String>(), [
        'W',
        'NW',
        'N',
        'NE',
        'E',
      ]);
      expect(ticks.where((tick) => tick.isMajor), hasLength(5));
      expect(ticks, hasLength(13));
    });

    test('ticks wrap around north', () {
      final labels = CompassRibbon.ticksFor(359)
          .map((tick) => tick.label)
          .whereType<String>();
      expect(labels, ['W', 'NW', 'N', 'NE']);
    });

    test('color glasses get a held color frame', () {
      final commands = CompassRibbon.frame(heading: 45, colorCapable: true);

      expect(commands.first.id, ActiveLookCommandId.holdFlush);
      expect(commands[1].id, ActiveLookCommandId.clear);
      expect(commands[2].id, ActiveLookCommandId.color);
      expect(commands.last.id, ActiveLookCommandId.holdFlush);
      expect(commands.last.data, [1]);

      // Every element fits the 304×256 panel.
      for (final command in commands) {
        expect(command.data.length, lessThanOrEqualTo(512));
      }

      final texts = commands
          .where((command) => command.id == ActiveLookCommandId.textColor)
          .map(_decodeText)
          .toList();
      expect(texts, containsAll(['NW', 'N', 'NE', 'E', 'SE']));
      expect(texts, contains('NE 45')); // centre readout
    });

    test('grey glasses use grayscale and txt instead of color', () {
      final commands = CompassRibbon.frame(heading: 180, colorCapable: false);

      expect(commands[2].id, ActiveLookCommandId.grayscale);
      expect(
        commands.every((command) => command.id != ActiveLookCommandId.color),
        isTrue,
      );
      expect(
        commands.every(
          (command) => command.id != ActiveLookCommandId.textColor,
        ),
        isTrue,
      );
      final texts = commands
          .where((command) => command.id == ActiveLookCommandId.text)
          .map(_decodeText);
      expect(texts, contains('S 180'));
    });

    test('waiting frame is a single held text update', () {
      final commands = CompassRibbon.waitingFrame(colorCapable: true);
      expect(commands.first.id, ActiveLookCommandId.holdFlush);
      expect(commands.last.id, ActiveLookCommandId.holdFlush);
      expect(commands.last.data, [1]);
    });
  });

  group('controller compass', () {
    test('follows the sensor and mirrors the ribbon on the glasses', () async {
      final source = _FakeCompassSource();
      final controller = GlassesController(
        transport: MockGlassesTransport(),
        compass: source,
      );
      addTearDown(controller.dispose);

      await controller.connect(
        const DiscoveredGlasses(
          id: 'SIMULATED-0001',
          name: 'A.Look DEMO01',
          rssi: -42,
          isActiveLook: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.compassSupported, isTrue);

      source.emit(91.2);
      await Future<void>.delayed(Duration.zero);
      expect(controller.compassHeading, closeTo(91.2, 0.001));

      await controller.startCompass();
      expect(controller.compassActive, isTrue);
      expect(controller.compassDisplayHeading, closeTo(91.2, 0.001));

      final frames = controller.log
          .where((line) => line.startsWith('→'))
          .toList();
      expect(frames, contains('→ FF 39 00 06 00 AA')); // hold
      expect(frames, contains('→ FF 01 00 05 AA')); // clear
      expect(frames.any((line) => line.startsWith('→ FF 3E')), isTrue);

      await controller.stopCompass();
      expect(controller.compassActive, isFalse);
      expect(controller.compassDisplayHeading, isNull);
    });

    test('ignores compass updates before connecting', () async {
      final source = _FakeCompassSource();
      final controller = GlassesController(
        transport: MockGlassesTransport(),
        compass: source,
      );
      addTearDown(controller.dispose);

      source.emit(120);
      await Future<void>.delayed(Duration.zero);
      expect(controller.compassHeading, isNull);
    });

    test('stops the compass when other content is shown', () async {
      final source = _FakeCompassSource();
      final controller = GlassesController(
        transport: MockGlassesTransport(),
        compass: source,
      );
      addTearDown(controller.dispose);

      await controller.connect(
        const DiscoveredGlasses(
          id: 'SIMULATED-0001',
          name: 'A.Look DEMO01',
          rssi: -42,
          isActiveLook: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      source.emit(200);
      await Future<void>.delayed(Duration.zero);
      await controller.startCompass();
      expect(controller.compassActive, isTrue);

      await controller.showText('Hi');
      expect(controller.compassActive, isFalse);
      expect(controller.lastRenderedText, 'Hi');
    });

    test('desktop-like platforms report no compass', () {
      final controller = GlassesController(
        transport: MockGlassesTransport(),
        compass: _UnsupportedCompassSource(),
      );
      addTearDown(controller.dispose);

      expect(controller.compassSupported, isFalse);
    });
  });
}

String _decodeText(ActiveLookCommand command) {
  // txt/txtColor: x, y, rotation, font, color|grey, then a NUL-terminated
  // string.
  final bytes = command.data.sublist(7);
  final end = bytes.indexOf(0);
  return String.fromCharCodes(end < 0 ? bytes : bytes.sublist(0, end));
}

class _FakeCompassSource implements CompassSource {
  final StreamController<double?> _headings =
      StreamController<double?>.broadcast();

  void emit(double? heading) => _headings.add(heading);

  @override
  bool get isSupported => true;

  @override
  Stream<double?> get headings => _headings.stream;

  @override
  Future<void> dispose() async {
    await _headings.close();
  }
}

class _UnsupportedCompassSource implements CompassSource {
  @override
  bool get isSupported => false;

  @override
  Stream<double?> get headings => const Stream<double?>.empty();

  @override
  Future<void> dispose() async {}
}
