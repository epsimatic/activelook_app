/// Simulated glasses, so the demo can be run without hardware.
library;

import 'dart:async';

import '../models/discovered_glasses.dart';
import '../protocol/active_look_protocol.dart';
import 'glasses_scanner.dart';
import 'glasses_transport.dart';

/// A scanner that always finds one virtual pair of glasses.
class MockGlassesScanner implements GlassesScanner {
  final StreamController<bool> _scanning = StreamController<bool>.broadcast();
  final StreamController<DiscoveredGlasses> _results =
      StreamController<DiscoveredGlasses>.broadcast();

  @override
  Stream<bool> get scanning => _scanning.stream;

  @override
  Stream<DiscoveredGlasses> get results => _results.stream;

  @override
  Stream<String> get errors => const Stream<String>.empty();

  @override
  Future<void> start() async {
    _scanning.add(true);
    _results.add(
      const DiscoveredGlasses(
        id: 'SIMULATED-0001',
        name: 'A.Look DEMO01',
        rssi: -42,
        isActiveLook: true,
      ),
    );
  }

  @override
  Future<void> stop() async => _scanning.add(false);

  @override
  Future<void> dispose() async {
    await _results.close();
    await _scanning.close();
  }
}

/// A [GlassesTransport] that pretends to be a pair of glasses.
///
/// It accepts every command, logs it as hex, and reports plausible device
/// information. Useful for UI work and for demoing without glasses.
class MockGlassesTransport implements GlassesTransport {
  final StreamController<GlassesEvent> _events =
      StreamController<GlassesEvent>.broadcast();

  GlassesInfo _info = const GlassesInfo();
  bool _connected = false;
  String _displayName = 'Имитация очков';

  @override
  Stream<GlassesEvent> get events => _events.stream;

  @override
  bool get isConnected => _connected;

  @override
  String get displayName => _displayName;

  @override
  GlassesInfo get info => _info;

  @override
  Future<void> connect(DiscoveredGlasses device) async {
    _displayName = device.displayName;
    _emit(GlassesLog('Подключение к $_displayName (имитация)…'));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    _connected = true;
    _emit(const GlassesConnectionChanged(connected: true));
    _emit(const GlassesLog('Подключено (имитация, без BLE)'));
    _info = const GlassesInfo(
      firmwareVersion: '4.14.2b',
      hardwareVersion: 'ALK03-MDP08ACRG',
      serialNumber: '000128',
      modelNumber: 'A.LooK',
      batteryLevel: 82,
      displayIsColor: true,
    );
    _emit(GlassesInfoChanged(_info));
    _emit(const GlassesLog('← имитация: версия 4.14.2b, заряд 82%'));
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    _connected = false;
    _emit(const GlassesConnectionChanged(connected: false));
  }

  @override
  Future<void> send(ActiveLookCommand command) async {
    final frame = command.encode();
    _emit(GlassesLog('→ ${hex(frame)}'));

    if (command.id == ActiveLookCommandId.text ||
        command.id == ActiveLookCommandId.textColor) {
      final text = _decodeText(command.data);
      _emit(GlassesLog('Имитация экрана показывает «${text ?? '?'}»'));
    } else if (command.id == ActiveLookCommandId.clear) {
      _emit(const GlassesLog('Имитация экрана очищена'));
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }

  String? _decodeText(List<int> data) {
    if (data.length < 8) return null;
    final bytes = data.sublist(7);
    final end = bytes.indexOf(0);
    final textBytes = end < 0 ? bytes : bytes.sublist(0, end);
    return String.fromCharCodes(textBytes);
  }

  void _emit(GlassesEvent event) => _events.add(event);
}
