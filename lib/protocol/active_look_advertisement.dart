/// Detection of ActiveLook® glasses from BLE advertising data.
library;

/// ActiveLook advertises manufacturer specific data whose last two bytes are
/// the reserved value `0x08F2` (the two bytes before it are the customer
/// manufacturer ID, `0xDAFA` by default).
const int activeLookManufacturerMarker = 0x08F2;

/// Advertised names start with `A.Look`/`A.LooK` and are padded to 16 chars.
const List<String> activeLookNamePrefixes = ['A.Look', 'A.LooK', 'ALook'];

/// Returns true when the advertised name or manufacturer data identifies an
/// ActiveLook device.
///
/// [manufacturerData] is the list of raw manufacturer specific data payloads
/// (company ID included, little-endian), as provided by most BLE plugins.
bool isActiveLookAdvertisement({
  required String name,
  Iterable<List<int>> manufacturerData = const [],
}) {
  if (activeLookNamePrefixes.any(name.startsWith)) return true;

  for (final payload in manufacturerData) {
    // Payload layout: [companyIdLo, companyIdHi, ...data].
    for (var i = 0; i + 1 < payload.length; i++) {
      if (payload[i] == 0x08 && payload[i + 1] == 0xF2) return true;
      // Some platforms keep the full AD structure; accept the reverse order too.
      if (payload[i] == 0xF2 && payload[i + 1] == 0x08) return true;
    }
  }
  return false;
}
