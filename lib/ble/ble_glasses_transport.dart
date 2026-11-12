/// Real BLE implementation of [GlassesTransport], using `flutter_blue_plus`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/discovered_glasses.dart';
import '../protocol/active_look_protocol.dart';
import 'active_look_uuids.dart';
import 'glasses_transport.dart';

/// Talks to a pair of ActiveLook glasses over BLE.
///
/// Implements the parts of the protocol the demo relies on: service discovery,
/// notifications, flow control, frame reassembly and a serialised write queue.
class BleGlassesTransport implements GlassesTransport {
  /// `flutter_blue_plus` 2.x requires an explicit license: `nonprofit` covers
  /// personal, educational and non-profit use. Commercial use requires a paid
  /// license — see the package LICENSE before shipping this demo.
  static const License _fbpLicense = License.nonprofit;

  static const Duration _flowControlTimeout = Duration(seconds: 3);

  final StreamController<GlassesEvent> _events =
      StreamController<GlassesEvent>.broadcast();
  final ActiveLookFrameParser _parser = ActiveLookFrameParser();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<_QueuedCommand> _queue = [];

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;
  BluetoothCharacteristic? _control;
  BluetoothCharacteristic? _battery;
  GlassesInfo _info = const GlassesInfo();

  String _displayName = 'Очки ActiveLook';
  bool _connected = false;
  bool _sending = false;
  bool _paused = false;
  Completer<void>? _resume;
  bool _disposed = false;

  @override
  Stream<GlassesEvent> get events => _events.stream;

  @override
  bool get isConnected => _connected;

  @override
  String get displayName => _displayName;

  /// Latest known device information.
  @override
  GlassesInfo get info => _info;

  @override
  Future<void> connect(DiscoveredGlasses glasses) async {
    if (_connected) await disconnect();

    final device = BluetoothDevice.fromId(glasses.id);
    _device = device;
    _displayName = glasses.displayName;
    _parser.reset();
    _emit(GlassesLog('Подключение к $_displayName (${glasses.id})…'));

    try {
      await device.connect(
        license: _fbpLicense,
        timeout: const Duration(seconds: 20),
        // Request the MTU ourselves (Android only) so a rejected MTU request
        // cannot make the whole connection attempt fail.
        mtu: null,
      );
    } catch (error) {
      _emit(GlassesError('Не удалось подключиться: $error'));
      rethrow;
    }

    _subscriptions.add(
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleUnexpectedDisconnect();
        }
      }),
    );

    final services = await device.discoverServices();

    final rx = _findCharacteristic(
      services,
      activeLookServiceUuid,
      activeLookRxUuid,
    );
    if (rx == null) {
      await disconnect();
      throw StateError(
        'Это устройство не является очками ActiveLook: сервис команд '
        '($activeLookServiceUuid) не найден.',
      );
    }
    _rx = rx;
    _tx = _findCharacteristic(
      services,
      activeLookServiceUuid,
      activeLookTxUuid,
    );
    _control = _findCharacteristic(
      services,
      activeLookServiceUuid,
      activeLookControlUuid,
    );
    _battery = _findCharacteristic(
      services,
      batteryServiceUuid,
      batteryLevelUuid,
    );

    if (Platform.isAndroid) {
      try {
        await device.requestMtu(247);
      } catch (_) {
        // Non fatal: writes are chunked using the MTU we actually got.
      }
    }

    await _subscribe(_tx, _onTxData, 'TX');
    await _subscribe(_control, _onControlData, 'управление');
    await _subscribe(
      _findCharacteristic(services, activeLookServiceUuid, activeLookTouchUuid),
      (_) => _emit(const GlassesLog('Нажата кнопка касания')),
      'касание',
    );
    await _subscribe(
      _findCharacteristic(
        services,
        activeLookServiceUuid,
        activeLookGestureUuid,
      ),
      (_) => _emit(const GlassesLog('Обнаружен жест')),
      'жест',
    );
    await _subscribe(_battery, _onBatteryData, 'батарея');

    _connected = true;
    _paused = false;
    _emit(GlassesConnectionChanged(connected: true));
    _emit(GlassesLog('Подключено (MTU ${device.mtuNow})'));

    await _readDeviceInformation(services);
    await _readBattery();

    // Reset a possibly stale graphic-engine state, wake the display and ask
    // the glasses about themselves. Failures here should not abort connect:
    // the link itself is up and the UI can still use it.
    try {
      await send(ActiveLookCommands.resetAndFlush());
      await send(ActiveLookCommands.displayPower(enabled: true));
      await send(ActiveLookCommands.vers());
      await send(ActiveLookCommands.battery());
    } catch (error) {
      _emit(GlassesLog('Команда рукопожатия не удалась: $error'));
    }
  }

  @override
  Future<void> disconnect() async {
    final device = _device;
    final wasConnected = _connected;
    _connected = false;
    _paused = false;
    final resume = _resume;
    _resume = null;
    if (resume != null && !resume.isCompleted) resume.complete();

    await _cancelSubscriptions();
    _failPendingQueue('Отключено');

    try {
      await device?.disconnect();
    } catch (_) {
      // Already gone.
    }

    if (wasConnected) {
      _emit(const GlassesConnectionChanged(connected: false));
    }
  }

  @override
  Future<void> send(ActiveLookCommand command) {
    if (_rx == null) {
      return Future<void>.error(StateError('Нет подключения к очкам'));
    }
    final queued = _QueuedCommand(command.encode());
    _queue.add(queued);
    unawaited(_drainQueue());
    return queued.done.future;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _events.close();
  }

  Future<void> _drainQueue() async {
    if (_sending) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty) {
        await _waitForFlowControl();
        final queued = _queue.removeAt(0);
        try {
          await _writeFrame(queued.frame);
          queued.done.complete();
        } catch (error, stackTrace) {
          queued.done.completeError(error, stackTrace);
          _emit(GlassesError('Ошибка записи: $error'));
        }
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> _waitForFlowControl() async {
    while (_paused) {
      try {
        await (_resume ??= Completer<void>()).future.timeout(
          _flowControlTimeout,
        );
      } on TimeoutException {
        _paused = false;
        _resume = null;
        _emit(
          const GlassesLog('Тайм-аут управления потоком — возобновляем запись'),
        );
      }
    }
  }

  Future<void> _writeFrame(Uint8List frame) async {
    final rx = _rx;
    if (rx == null) throw StateError('Нет подключения к очкам');

    final mtu = _device?.mtuNow ?? 23;
    final chunkSize = (mtu - 3).clamp(20, 517);
    _emit(GlassesLog('→ ${hex(frame)}'));

    for (var offset = 0; offset < frame.length; offset += chunkSize) {
      final end = min(offset + chunkSize, frame.length);
      await rx.write(frame.sublist(offset, end), withoutResponse: false);
      if (end < frame.length) {
        // Give the glasses time to consume the chunk before the next one.
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  Future<void> _subscribe(
    BluetoothCharacteristic? characteristic,
    void Function(List<int> data) onData,
    String label,
  ) async {
    if (characteristic == null) {
      _emit(GlassesLog('Нет характеристики «$label», пропускаем'));
      return;
    }
    try {
      await characteristic.setNotifyValue(true);
      _subscriptions.add(characteristic.onValueReceived.listen(onData));
    } catch (error) {
      _emit(GlassesLog('Не удалось подписаться на «$label»: $error'));
    }
  }

  void _onTxData(List<int> data) {
    _emit(GlassesLog('← ${hex(data)}'));
    for (final message in _parser.add(data)) {
      _emit(GlassesMessageReceived(message));

      switch (message.id) {
        case ActiveLookCommandId.vers when message.data.length >= 4:
          _updateInfo(firmwareVersion: decodeFirmwareVersion(message.data));
        case ActiveLookCommandId.battery when message.data.isNotEmpty:
          _updateInfo(batteryLevel: message.data.first);
        case ActiveLookCommandId.error when message.data.length >= 2:
          _emit(
            GlassesError(
              'Очки сообщили об ошибке команды 0x'
              '${message.data[0].toRadixString(16).padLeft(2, '0')} '
              '(код ${message.data[1]})',
            ),
          );
      }
    }
  }

  void _onControlData(List<int> data) {
    if (data.isEmpty) return;
    final value = data.first;
    _emit(GlassesControlReceived(value));
    _emit(GlassesLog(ActiveLookControl.describe(value)));

    switch (value) {
      case ActiveLookControl.flowOn:
        _paused = false;
        final resume = _resume;
        _resume = null;
        if (resume != null && !resume.isCompleted) resume.complete();
      case ActiveLookControl.flowOff:
        _paused = true;
      case ActiveLookControl.errorMessage:
      case ActiveLookControl.errorQueueOverflow:
      case ActiveLookControl.errorMissingConfigWrite:
        _emit(GlassesError(ActiveLookControl.describe(value)));
    }
  }

  void _onBatteryData(List<int> data) {
    if (data.isEmpty) return;
    _updateInfo(batteryLevel: data.first);
  }

  Future<void> _readDeviceInformation(List<BluetoothService> services) async {
    final hardware = await _readString(
      _findCharacteristic(
        services,
        deviceInformationServiceUuid,
        hardwareRevisionUuid,
      ),
    );
    final firmware = await _readString(
      _findCharacteristic(
        services,
        deviceInformationServiceUuid,
        firmwareRevisionUuid,
      ),
    );
    final serial = await _readString(
      _findCharacteristic(
        services,
        deviceInformationServiceUuid,
        serialNumberUuid,
      ),
    );
    final model = await _readString(
      _findCharacteristic(
        services,
        deviceInformationServiceUuid,
        modelNumberUuid,
      ),
    );

    _updateInfo(
      firmwareVersion: firmware,
      hardwareVersion: hardware,
      serialNumber: serial,
      modelNumber: model,
      displayIsColor: hardware?.toUpperCase().contains('MDP08'),
    );
  }

  Future<void> _readBattery() async {
    final battery = _battery;
    if (battery == null) return;
    try {
      final value = await battery.read();
      if (value.isNotEmpty) _updateInfo(batteryLevel: value.first);
    } catch (error) {
      _emit(GlassesLog('Не удалось прочитать заряд: $error'));
    }
  }

  Future<String?> _readString(BluetoothCharacteristic? characteristic) async {
    if (characteristic == null) return null;
    try {
      final value = await characteristic.read();
      final text = utf8.decode(value, allowMalformed: true).trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  void _updateInfo({
    String? firmwareVersion,
    String? hardwareVersion,
    String? serialNumber,
    String? modelNumber,
    int? batteryLevel,
    bool? displayIsColor,
  }) {
    _info = _info.copyWith(
      firmwareVersion: firmwareVersion,
      hardwareVersion: hardwareVersion,
      serialNumber: serialNumber,
      modelNumber: modelNumber,
      batteryLevel: batteryLevel,
      displayIsColor: displayIsColor,
    );
    _emit(GlassesInfoChanged(_info));
  }

  void _handleUnexpectedDisconnect() {
    if (!_connected) return;
    _connected = false;
    _paused = false;
    final resume = _resume;
    _resume = null;
    if (resume != null && !resume.isCompleted) resume.complete();
    _failPendingQueue('Связь потеряна');
    unawaited(_cancelSubscriptions());
    _emit(
      const GlassesConnectionChanged(
        connected: false,
        reason: 'Связь потеряна',
      ),
    );
  }

  void _failPendingQueue(String reason) {
    for (final queued in _queue) {
      if (!queued.done.isCompleted) {
        queued.done.completeError(StateError(reason));
      }
    }
    _queue.clear();
  }

  Future<void> _cancelSubscriptions() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  BluetoothCharacteristic? _findCharacteristic(
    List<BluetoothService> services,
    String serviceUuid,
    String characteristicUuid,
  ) {
    final service = Guid(serviceUuid);
    final characteristic = Guid(characteristicUuid);
    for (final candidate in services) {
      if (candidate.serviceUuid != service) continue;
      for (final item in candidate.characteristics) {
        if (item.characteristicUuid == characteristic) return item;
      }
    }
    return null;
  }

  void _emit(GlassesEvent event) {
    if (_disposed) return;
    _events.add(event);
  }
}

class _QueuedCommand {
  _QueuedCommand(this.frame);

  final Uint8List frame;
  final Completer<void> done = Completer<void>();
}
