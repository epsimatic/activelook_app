import 'package:activelook_flutter/ble/mock_glasses.dart';
import 'package:activelook_flutter/features/glasses/glasses_controller.dart';
import 'package:activelook_flutter/models/color_show.dart';
import 'package:activelook_flutter/models/discovered_glasses.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connect reads device info and sends color text', () async {
    final transport = MockGlassesTransport();
    final controller = GlassesController(transport: transport);
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

    expect(controller.connected, isTrue);
    expect(controller.isColorCapable, isTrue);
    expect(controller.info.firmwareVersion, '4.14.2b');
    expect(controller.info.batteryLevel, 82);

    await controller.showText('Hi');
    await Future<void>.delayed(Duration.zero);

    expect(controller.lastRenderedText, 'Hi');
    expect(
      controller.log.any(
        (line) => line.contains('Имитация экрана показывает «Hi»'),
      ),
      isTrue,
      reason: 'the mock should confirm the text command',
    );
    // hold → clear → txtColor → flush, i.e. a single refresh.
    final writes = controller.log
        .where((line) => line.startsWith('→'))
        .toList();
    expect(writes, hasLength(4));
    expect(writes, contains('→ FF 39 00 06 00 AA')); // hold
    expect(writes, contains('→ FF 01 00 05 AA')); // clear
    expect(writes, contains('→ FF 39 00 06 01 AA')); // flush
    expect(
      writes.any((line) => line.startsWith('→ FF 3E')),
      isTrue,
      reason: 'MDP08 hardware must use txtColor',
    );
    expect(
      writes,
      contains('→ FF 3E 00 0F 00 98 00 80 04 03 FF 48 69 00 AA'),
      reason: 'demo text uses the largest built-in font (3, 49 px)',
    );
  });

  test('empty text is ignored', () async {
    final controller = GlassesController(transport: MockGlassesTransport());
    addTearDown(controller.dispose);

    await controller.showText('   ');
    expect(controller.lastRenderedText, isEmpty);
  });

  test('color show animates full-screen frames and stops', () async {
    final transport = MockGlassesTransport();
    final controller = GlassesController(transport: transport);
    addTearDown(controller.dispose);

    await controller.connect(
      const DiscoveredGlasses(
        id: 'SIMULATED-0001',
        name: 'A.Look DEMO01',
        rssi: -42,
        isActiveLook: true,
      ),
    );

    await controller.startColorShow(ColorShowMode.pulse);
    expect(controller.isAnimating, isTrue);
    expect(controller.colorShowMode, ColorShowMode.pulse);
    expect(controller.frameShapes, hasLength(ColorShow.pulseRadii.length));

    final writes = controller.log.where((line) => line.startsWith('→'));
    expect(writes, contains('→ FF 3D 00 06 20 AA')); // color 0x20 (phase 1)
    expect(writes.any((line) => line.startsWith('→ FF 36')), isTrue); // circf

    await controller.stopColorShow();
    expect(controller.isAnimating, isFalse);
    expect(controller.frameShapes, isEmpty);
  });

  test('low-BLE sweep sends two small commands per frame', () async {
    final transport = MockGlassesTransport();
    final controller = GlassesController(transport: transport);
    addTearDown(controller.dispose);

    await controller.connect(
      const DiscoveredGlasses(
        id: 'SIMULATED-0001',
        name: 'A.Look DEMO01',
        rssi: -42,
        isActiveLook: true,
      ),
    );

    await controller.startColorShow(ColorShowMode.sweep);
    await Future<void>.delayed(Duration.zero);
    expect(controller.frameShapes, hasLength(1));
    expect(controller.lastFrameBytes, lessThan(50));

    final writes = controller.log.where((line) => line.startsWith('→'));
    expect(writes.any((line) => line.startsWith('→ FF 3D')), isTrue); // color
    expect(writes.any((line) => line.startsWith('→ FF 3C')), isTrue); // arc

    await controller.stopColorShow();
  });

  test('fast counter sends one short text command per frame', () async {
    final transport = MockGlassesTransport();
    final controller = GlassesController(transport: transport);
    addTearDown(controller.dispose);

    await controller.connect(
      const DiscoveredGlasses(
        id: 'SIMULATED-0001',
        name: 'A.Look DEMO01',
        rssi: -42,
        isActiveLook: true,
      ),
    );

    await controller.startColorShow(ColorShowMode.counter);
    await Future<void>.delayed(Duration.zero);

    expect(controller.isAnimating, isTrue);
    expect(controller.lastRenderedText, '1');
    expect(controller.lastFrameBytes, lessThan(40));
    expect(controller.displayColor, ColorShow.ramp[1]);

    final writes = controller.log.where((line) => line.startsWith('→'));
    expect(writes, hasLength(4)); // hold, clear, txtColor, flush
    expect(
      writes,
      contains('→ FF 3E 00 0E 00 98 00 80 04 03 20 31 00 AA'),
      reason: 'counter uses the largest built-in font (3, 49 px)',
    );

    await controller.stopColorShow();
    expect(controller.isAnimating, isFalse);
  });

  test('Cyrillic text is transliterated for the ASCII glasses font', () async {
    final controller = GlassesController(transport: MockGlassesTransport());
    addTearDown(controller.dispose);

    await controller.connect(
      const DiscoveredGlasses(
        id: 'SIMULATED-0001',
        name: 'A.Look DEMO01',
        rssi: -42,
        isActiveLook: true,
      ),
    );
    await controller.showText('Привет, мир!');
    await Future<void>.delayed(Duration.zero);

    expect(controller.lastRenderedText, 'Privet, mir!');
    expect(
      controller.log.any((line) => line.contains('«Privet, mir!»')),
      isTrue,
    );
  });

  test('speed is clamped to the slider range', () {
    final controller = GlassesController(transport: MockGlassesTransport());
    addTearDown(controller.dispose);

    expect(controller.colorShowFps, GlassesController.defaultColorShowFps);
    controller.setColorShowSpeed(1);
    expect(controller.colorShowFps, GlassesController.minColorShowFps);
    controller.setColorShowSpeed(99);
    expect(controller.colorShowFps, GlassesController.maxColorShowFps);
    expect(controller.colorShowInterval, const Duration(milliseconds: 33));
  });

  test('color show does nothing while disconnected', () async {
    final controller = GlassesController(transport: MockGlassesTransport());
    addTearDown(controller.dispose);

    await controller.startColorShow(ColorShowMode.pulse);
    expect(controller.isAnimating, isFalse);
    expect(controller.frameShapes, isEmpty);
  });
}
