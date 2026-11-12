/// ActiveLook® GATT identifiers (API spec, section 2.3).
library;

/// Custom service exposing the ActiveLook command interface.
const String activeLookServiceUuid = '0783B03E-8535-B5A0-7140-A304D2495CB7';

/// TX characteristic: glasses → host notifications (command responses).
const String activeLookTxUuid = '0783B03E-8535-B5A0-7140-A304D2495CB8';

/// Control characteristic: flow control and command errors.
const String activeLookControlUuid = '0783B03E-8535-B5A0-7140-A304D2495CB9';

/// RX characteristic: host → glasses command writes.
const String activeLookRxUuid = '0783B03E-8535-B5A0-7140-A304D2495CBA';

/// Gesture sensor events.
const String activeLookGestureUuid = '0783B03E-8535-B5A0-7140-A304D2495CBB';

/// Capacitive touch button events.
const String activeLookTouchUuid = '0783B03E-8535-B5A0-7140-A304D2495CBC';

/// Standard Battery service / level characteristic.
const String batteryServiceUuid = '180F';
const String batteryLevelUuid = '2A19';

/// Standard Device Information service and characteristics.
const String deviceInformationServiceUuid = '180A';
const String manufacturerNameUuid = '2A29';
const String modelNumberUuid = '2A24';
const String serialNumberUuid = '2A25';
const String firmwareRevisionUuid = '2A26';
const String hardwareRevisionUuid = '2A27';

/// Control characteristic values (API spec, section 3.5).
abstract final class ActiveLookControl {
  static const int flowOn = 0x01;
  static const int flowOff = 0x02;
  static const int errorMessage = 0x03;
  static const int errorQueueOverflow = 0x04;
  static const int errorMissingConfigWrite = 0x06;

  static String describe(int value) => switch (value) {
    flowOn => 'поток: ВКЛ (можно отправлять)',
    flowOff => 'поток: ВЫКЛ (буфер заполнен на 75%)',
    errorMessage => 'ошибка: команда неполная или повреждена',
    errorQueueOverflow => 'ошибка: переполнение очереди приёма',
    errorMissingConfigWrite =>
      'ошибка: нет cfgWrite перед изменением конфигурации',
    _ =>
      'управление: неизвестное значение 0x${value.toRadixString(16).padLeft(2, '0')}',
  };
}
