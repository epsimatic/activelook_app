/// Transport abstraction over the ActiveLook BLE link.
///
/// Screens and controllers only ever talk to this interface, so the demo can
/// run against real glasses ([BleGlassesTransport]) or a simulation
/// ([MockGlassesTransport]) without touching UI code.
library;

import '../models/discovered_glasses.dart';
import '../protocol/active_look_protocol.dart';

/// Information gathered from the glasses once connected.
class GlassesInfo {
  const GlassesInfo({
    this.firmwareVersion,
    this.hardwareVersion,
    this.serialNumber,
    this.modelNumber,
    this.batteryLevel,
    this.displayIsColor,
  });

  final String? firmwareVersion;
  final String? hardwareVersion;
  final String? serialNumber;
  final String? modelNumber;

  /// Battery level in percent.
  final int? batteryLevel;

  /// `MDP08` hardware has an RG color display, `MDP05` has 16 grey levels.
  final bool? displayIsColor;

  GlassesInfo copyWith({
    String? firmwareVersion,
    String? hardwareVersion,
    String? serialNumber,
    String? modelNumber,
    int? batteryLevel,
    bool? displayIsColor,
  }) => GlassesInfo(
    firmwareVersion: firmwareVersion ?? this.firmwareVersion,
    hardwareVersion: hardwareVersion ?? this.hardwareVersion,
    serialNumber: serialNumber ?? this.serialNumber,
    modelNumber: modelNumber ?? this.modelNumber,
    batteryLevel: batteryLevel ?? this.batteryLevel,
    displayIsColor: displayIsColor ?? this.displayIsColor,
  );
}

/// Events emitted by a [GlassesTransport].
sealed class GlassesEvent {
  const GlassesEvent();
}

class GlassesConnectionChanged extends GlassesEvent {
  const GlassesConnectionChanged({required this.connected, this.reason});

  final bool connected;

  /// Populated when the connection was lost or failed.
  final String? reason;
}

class GlassesInfoChanged extends GlassesEvent {
  const GlassesInfoChanged(this.info);

  final GlassesInfo info;
}

class GlassesMessageReceived extends GlassesEvent {
  const GlassesMessageReceived(this.message);

  final ActiveLookMessage message;
}

class GlassesControlReceived extends GlassesEvent {
  const GlassesControlReceived(this.value);

  final int value;
}

class GlassesLog extends GlassesEvent {
  const GlassesLog(this.text);

  final String text;
}

class GlassesError extends GlassesEvent {
  const GlassesError(this.message);

  final String message;
}

/// A connection to a pair of ActiveLook glasses.
abstract class GlassesTransport {
  /// Broadcast stream of connection, protocol and log events.
  Stream<GlassesEvent> get events;

  bool get isConnected;

  String get displayName;

  /// Last known device information (firmware, battery, display type…).
  GlassesInfo get info;

  Future<void> connect(DiscoveredGlasses device);

  Future<void> disconnect();

  /// Sends a command, honouring the glasses' flow control.
  Future<void> send(ActiveLookCommand command);

  Future<void> dispose();
}
