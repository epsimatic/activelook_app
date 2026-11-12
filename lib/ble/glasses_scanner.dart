/// BLE scanning for ActiveLook glasses.
library;

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/discovered_glasses.dart';
import '../protocol/active_look_advertisement.dart';

/// Scans for nearby BLE devices and reports them as [DiscoveredGlasses].
abstract class GlassesScanner {
  Stream<bool> get scanning;

  /// Every device seen, ActiveLook or not; filtering is up to the caller.
  Stream<DiscoveredGlasses> get results;

  /// Human readable, recoverable scan failures (adapter off, no permission…).
  Stream<String> get errors;

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}

/// [GlassesScanner] backed by `flutter_blue_plus`.
class BleGlassesScanner implements GlassesScanner {
  final StreamController<DiscoveredGlasses> _results =
      StreamController<DiscoveredGlasses>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  StreamSubscription<List<ScanResult>>? _subscription;

  @override
  Stream<bool> get scanning => FlutterBluePlus.isScanning;

  @override
  Stream<DiscoveredGlasses> get results => _results.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> start() async {
    if (FlutterBluePlus.isScanningNow) return;

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _errors.add(_adapterMessage(adapterState));
      return;
    }

    _subscription ??= FlutterBluePlus.scanResults.listen((scanResults) {
      for (final result in scanResults) {
        final advertisement = result.advertisementData;
        _results.add(
          DiscoveredGlasses(
            id: result.device.remoteId.str,
            name: advertisement.advName,
            rssi: result.rssi,
            isActiveLook: isActiveLookAdvertisement(
              name: advertisement.advName,
              manufacturerData: advertisement.msd,
            ),
          ),
        );
      }
    }, onError: (Object error) => _errors.add('Ошибка поиска: $error'));

    try {
      // No service filter: ActiveLook glasses do not advertise the command
      // service UUID, so filtering happens on manufacturer data instead.
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));
    } catch (error) {
      _errors.add('Не удалось запустить поиск: $error');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await FlutterBluePlus.stopScan();
    } finally {
      await _subscription?.cancel();
      _subscription = null;
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _results.close();
    await _errors.close();
  }

  String _adapterMessage(BluetoothAdapterState state) => switch (state) {
    BluetoothAdapterState.on => '',
    BluetoothAdapterState.off =>
      'Bluetooth выключен. Включите его и запустите поиск снова.',
    BluetoothAdapterState.unauthorized => 'Доступ к Bluetooth запрещён. Разрешите Bluetooth для этого приложения в настройках системы.',
    BluetoothAdapterState.unavailable =>
      'Bluetooth недоступен на этом устройстве.',
    BluetoothAdapterState.turningOn =>
      'Bluetooth включается, попробуйте через мгновение.',
    BluetoothAdapterState.turningOff =>
      'Bluetooth выключается, попробуйте через мгновение.',
    BluetoothAdapterState.unknown =>
      'Состояние Bluetooth неизвестно, попробуйте снова.',
  };
}
