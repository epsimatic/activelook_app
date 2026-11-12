/// A pair of glasses seen during a BLE scan.
class DiscoveredGlasses {
  const DiscoveredGlasses({
    required this.id,
    required this.name,
    required this.rssi,
    required this.isActiveLook,
  });

  /// Platform specific identifier (MAC address on Android, UUID on Apple).
  final String id;

  /// Advertised name, empty when the device does not advertise one.
  final String name;
  final int rssi;

  /// True when the advertisement matched the ActiveLook signature.
  final bool isActiveLook;

  String get displayName => name.trim().isEmpty ? id : name.trim();
}
